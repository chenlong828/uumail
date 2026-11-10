import Foundation

/// WBXML 1.3 codec for Exchange ActiveSync (MS-ASWBXML).
///
/// Wire format is taken from the verified probe, not from the specification text:
/// inline strings are `STR_I (0x03) + UTF-8 + 0x00` (NUL-terminated), opaque data is
/// `0xC3 + mb_uint length + raw bytes`. The length-prefixed string form from
/// MS-ASWBXML is rejected by the gateway (request hangs ~20s, then 502).
public enum WBXMLError: Error, Equatable, Sendable {
    case tokenTableUnavailable
    case invalidTokenTable(String)
    case unknownTag(name: String, page: Int)
    case badVersion(UInt8)
    case truncated
    case unterminatedString
    case missingLength
}

public enum WBXMLValue: Equatable, Sendable {
    case empty
    case text(String)
    case opaque(Data)
    case children([WBXMLElement])
}

public struct WBXMLElement: Equatable, Sendable {
    public let name: String
    public let value: WBXMLValue

    public init(_ name: String, _ value: WBXMLValue = .empty) {
        self.name = name
        self.value = value
    }

    public static func text(_ name: String, _ text: String) -> WBXMLElement {
        WBXMLElement(name, .text(text))
    }

    public static func children(_ name: String, _ children: [WBXMLElement]) -> WBXMLElement {
        WBXMLElement(name, .children(children))
    }

    public static func opaque(_ name: String, _ data: Data) -> WBXMLElement {
        WBXMLElement(name, .opaque(data))
    }

    public static func empty(_ name: String) -> WBXMLElement {
        WBXMLElement(name, .empty)
    }
}

/// Parsed WBXML tree. `page` is kept for diagnostics; lookups are by element name.
public struct WBXMLNode: Equatable, Sendable {
    public let name: String
    public let page: Int
    public let attributes: [String: String]
    public let text: String?
    public let opaque: Data?
    public let children: [WBXMLNode]

    public init(
        name: String,
        page: Int,
        attributes: [String: String] = [:],
        text: String? = nil,
        opaque: Data? = nil,
        children: [WBXMLNode] = []
    ) {
        self.name = name
        self.page = page
        self.attributes = attributes
        self.text = text
        self.opaque = opaque
        self.children = children
    }

    public func child(_ name: String) -> WBXMLNode? {
        children.first { $0.name == name }
    }

    public func path(_ names: String...) -> WBXMLNode? {
        var node: WBXMLNode? = self
        for name in names {
            node = node?.child(name)
        }
        return node
    }

    /// Own text, or the first child that carries text — mirrors the probe helper.
    public func stringValue() -> String? {
        if let text { return text }
        return children.lazy.compactMap(\.text).first
    }
}

public struct WBXMLCodec: Sendable {
    private struct Key: Hashable {
        let page: Int
        let name: String
    }

    private let pageOfName: [String: Int]
    private let tokenForName: [Key: UInt8]
    private let nameForToken: [Int: [UInt8: String]]

    public init(tokenTableJSON: Data) throws {
        guard
            let root = try JSONSerialization.jsonObject(with: tokenTableJSON) as? [String: Any],
            !root.isEmpty
        else {
            throw WBXMLError.invalidTokenTable("top level must be an object of pages")
        }

        var pageOfName: [String: Int] = [:]
        var tokenForName: [Key: UInt8] = [:]
        var nameForToken: [Int: [UInt8: String]] = [:]

        for (pageKey, rawPage) in root {
            guard
                let page = Int(pageKey),
                let entry = rawPage as? [String: Any],
                let tags = entry["tags"] as? [String: Any]
            else {
                throw WBXMLError.invalidTokenTable("bad page \(pageKey)")
            }
            for (name, rawToken) in tags {
                guard let number = rawToken as? Int, number >= 0, number <= 0x3F else {
                    throw WBXMLError.invalidTokenTable("bad token \(name) on page \(page)")
                }
                let token = UInt8(number)
                tokenForName[Key(page: page, name: name)] = token
                nameForToken[page, default: [:]][token] = name
                // Several pages define the same tag (CollectionId lives on 0, 6 and 8). Pick the
                // lowest page deterministically: JSON dictionary order is not stable in Swift,
                // and an arbitrary pick sends ItemOperations to a page the gateway rejects.
                if let known = pageOfName[name] {
                    pageOfName[name] = min(known, page)
                } else {
                    pageOfName[name] = page
                }
            }
        }

        self.pageOfName = pageOfName
        self.tokenForName = tokenForName
        self.nameForToken = nameForToken
    }

    /// Loads the token table shipped with the target (generated from MS-ASWBXML).
    public static func standard() throws -> WBXMLCodec {
        guard
            let url = Bundle.module.url(forResource: "eas_tokens", withExtension: "json"),
            let data = try? Data(contentsOf: url)
        else {
            throw WBXMLError.tokenTableUnavailable
        }
        return try WBXMLCodec(tokenTableJSON: data)
    }
}

// MARK: - Encoding

extension WBXMLCodec {
    private enum Tag {
        static let version: UInt8 = 0x03
        static let publicID: UInt8 = 0x01
        static let charsetUTF8: UInt8 = 0x6A
        static let switchPage: UInt8 = 0x00
        static let end: UInt8 = 0x01
        static let inlineString: UInt8 = 0x03
        static let opaque: UInt8 = 0xC3
        static let hasContent: UInt8 = 0x40
    }

    public func encode(_ element: WBXMLElement) throws -> Data {
        var out = Data([Tag.version])
        out.append(mbUInt(UInt64(Tag.publicID)))
        out.append(mbUInt(UInt64(Tag.charsetUTF8)))
        out.append(0x00) // empty string table
        var page = 0
        try emit(element, page: &page, into: &out)
        return out
    }

    private func emit(_ element: WBXMLElement, page: inout Int, into out: inout Data) throws {
        if tokenForName[Key(page: page, name: element.name)] == nil {
            guard let target = pageOfName[element.name] else {
                throw WBXMLError.unknownTag(name: element.name, page: page)
            }
            out.append(Tag.switchPage)
            out.append(UInt8(target))
            page = target
        }

        guard let token = tokenForName[Key(page: page, name: element.name)] else {
            throw WBXMLError.unknownTag(name: element.name, page: page)
        }

        switch element.value {
        case .empty:
            out.append(token)
        case .text(let text):
            out.append(token | Tag.hasContent)
            out.append(Tag.inlineString)
            out.append(contentsOf: Array(text.utf8))
            out.append(0x00)
            out.append(Tag.end)
        case .opaque(let data):
            out.append(token | Tag.hasContent)
            out.append(Tag.opaque)
            out.append(mbUInt(UInt64(data.count)))
            out.append(data)
            out.append(Tag.end)
        case .children(let children):
            out.append(token | Tag.hasContent)
            for child in children {
                try emit(child, page: &page, into: &out)
            }
            out.append(Tag.end)
        }
    }

    private func mbUInt(_ value: UInt64) -> Data {
        var bytes: [UInt8] = []
        var rest = value
        repeat {
            bytes.insert(UInt8(rest & 0x7F), at: 0)
            rest >>= 7
        } while rest != 0
        for index in 0..<(bytes.count - 1) {
            bytes[index] |= 0x80
        }
        return Data(bytes)
    }
}

// MARK: - Decoding

extension WBXMLCodec {
    /// Decodes a response body into a synthetic `ROOT` node whose children are the top-level elements.
    public func decode(_ data: Data) throws -> WBXMLNode {
        guard data.count >= 4 else { throw WBXMLError.truncated }

        var position = 0
        guard data[position] == Tag.version else { throw WBXMLError.badVersion(data[position]) }
        position += 1
        _ = try readMbUInt(data, &position) // public id
        _ = try readMbUInt(data, &position) // charset
        let stringTableLength = Int(try readMbUInt(data, &position))
        position += stringTableLength

        let root = MutableNode(name: "ROOT", page: -1)
        var stack: [MutableNode] = [root]
        var pages: [Int] = [0]

        while position < data.count {
            let byte = data[position]

            switch byte {
            case Tag.end:
                position += 1
                if stack.count > 1 { stack.removeLast() }

            case Tag.switchPage:
                guard position + 1 < data.count else { throw WBXMLError.truncated }
                pages.append(Int(data[position + 1]))
                position += 2

            case Tag.inlineString:
                position += 1
                guard let nul = data[position...].firstIndex(of: 0x00) else {
                    throw WBXMLError.unterminatedString
                }
                stack[stack.count - 1].text = String(decoding: data[position..<nul], as: UTF8.self)
                position = nul + 1

            case Tag.opaque:
                position += 1
                let length = Int(try readMbUInt(data, &position))
                guard position + length <= data.count else { throw WBXMLError.truncated }
                stack[stack.count - 1].opaque = data.subdata(in: position..<(position + length))
                position += length

            default:
                let hasAttributes = byte & 0x80 != 0
                let hasContent = byte & Tag.hasContent != 0
                let token = byte & 0x3F
                let page = pages.last ?? 0
                let name = nameForToken[page]?[token] ?? "TAG_0x\(String(format: "%02X", token))_p\(page)"
                position += 1

                let node = MutableNode(name: name, page: page)

                if hasAttributes {
                    while position < data.count, data[position] != Tag.end {
                        let attributeByte = data[position]
                        position += 1
                        let attributeToken = attributeByte & 0x3F
                        let attributeName = nameForToken[page]?[attributeToken]
                            ?? "ATTR_0x\(String(format: "%02X", attributeToken))_p\(page)"
                        var attributeValue = ""
                        if position < data.count, data[position] == Tag.inlineString {
                            position += 1
                            guard let nul = data[position...].firstIndex(of: 0x00) else {
                                throw WBXMLError.unterminatedString
                            }
                            attributeValue = String(decoding: data[position..<nul], as: UTF8.self)
                            position = nul + 1
                        }
                        node.attributes[attributeName] = attributeValue
                    }
                    guard position < data.count else { throw WBXMLError.truncated }
                    position += 1 // END of attributes
                }

                stack[stack.count - 1].children.append(node)
                if hasContent {
                    stack.append(node)
                }
            }
        }

        return root.snapshot()
    }

    private func readMbUInt(_ data: Data, _ position: inout Int) throws -> UInt64 {
        var value: UInt64 = 0
        while position < data.count {
            let byte = data[position]
            value = (value << 7) | UInt64(byte & 0x7F)
            position += 1
            if byte & 0x80 == 0 {
                return value
            }
        }
        throw WBXMLError.truncated
    }
}

private final class MutableNode {
    let name: String
    let page: Int
    var attributes: [String: String] = [:]
    var text: String?
    var opaque: Data?
    var children: [MutableNode] = []

    init(name: String, page: Int) {
        self.name = name
        self.page = page
    }

    func snapshot() -> WBXMLNode {
        WBXMLNode(
            name: name,
            page: page,
            attributes: attributes,
            text: text,
            opaque: opaque,
            children: children.map { $0.snapshot() }
        )
    }
}
