import Foundation

/// A normalized list of recipient addresses taken from an envelope header.
///
/// The value only splits and normalizes strings: it reads no port, expands no
/// distribution group, and does not resolve display names against a directory.
/// Addresses keep the spelling and order of their first appearance; duplicates
/// are compared case-insensitively.
public struct AddressList: Equatable, Sendable {
    public private(set) var addresses: [String]

    public init(_ raw: String?) {
        self.init([raw])
    }

    public init(_ raws: [String?]) {
        var parsed: [String] = []
        for raw in raws {
            guard let raw else { continue }
            parsed.append(contentsOf: Self.parse(raw))
        }
        self.init(normalized: parsed)
    }

    /// Builds from addresses that are already normalized: no splitting or shape
    /// filtering, only case-insensitive deduplication preserving first spelling.
    init(normalized addresses: [String]) {
        var seen: Set<String> = []
        self.addresses = addresses.filter { seen.insert($0.lowercased()).inserted }
    }

    public var isEmpty: Bool { addresses.isEmpty }

    public var text: String { addresses.joined(separator: "; ") }

    public func appending(_ other: AddressList) -> AddressList {
        AddressList(normalized: addresses + other.addresses)
    }

    public func removing(_ address: String?) -> AddressList {
        guard let key = Self.normalizedKey(address) else { return self }
        return AddressList(normalized: addresses.filter { $0.lowercased() != key })
    }

    public func subtracting(_ other: AddressList) -> AddressList {
        let keys = Set(other.addresses.map { $0.lowercased() })
        return AddressList(normalized: addresses.filter { !keys.contains($0.lowercased()) })
    }
}

private extension AddressList {
    /// Splits on top-level `;`/`,`, ignoring separators inside quotes and `<>`.
    static func split(_ raw: String) -> [String] {
        var segments: [String] = []
        var current = ""
        var inQuotes = false
        var inAngle = false

        for character in raw {
            switch character {
            case "\"":
                inQuotes.toggle()
                current.append(character)
            case "<" where !inQuotes:
                inAngle = true
                current.append(character)
            case ">" where !inQuotes:
                inAngle = false
                current.append(character)
            case ";", ",":
                if inQuotes || inAngle {
                    current.append(character)
                } else {
                    segments.append(current)
                    current = ""
                }
            default:
                current.append(character)
            }
        }
        segments.append(current)
        return segments
    }

    static func parse(_ raw: String) -> [String] {
        split(raw).compactMap(address(fromSegment:))
    }

    static func address(fromSegment segment: String) -> String? {
        let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let open = trimmed.firstIndex(of: "<") {
            guard let close = trimmed[trimmed.index(after: open)...].firstIndex(of: ">") else {
                return nil
            }
            let inner = trimmed[trimmed.index(after: open)..<close]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return inner.isEmpty ? nil : inner
        }

        let unquoted = stripWrappingQuotes(trimmed)
        guard !unquoted.isEmpty else { return nil }
        if unquoted.contains("@") { return unquoted }
        if unquoted.hasPrefix("/") { return unquoted }
        if unquoted.contains("="), !unquoted.contains(where: \.isWhitespace) {
            return unquoted
        }
        return nil
    }

    static func stripWrappingQuotes(_ value: String) -> String {
        guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else {
            return value
        }
        return String(value.dropFirst().dropLast())
    }

    static func normalizedKey(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed.lowercased()
    }
}
