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
            parsed.append(contentsOf: EnvelopeParser.split(raw).compactMap(EnvelopeParser.address(fromSegment:)))
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
    static func normalizedKey(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed.lowercased()
    }
}
