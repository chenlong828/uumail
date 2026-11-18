import Foundation

/// One recipient candidate: an SMTP address plus the most recent usable display name.
public struct ContactAddress: Equatable, Sendable, Identifiable {
    public let name: String?
    public let address: String

    public var id: String { address.lowercased() }

    public init(name: String?, address: String) {
        self.name = name
        self.address = address
    }
}

/// The envelope fields a message contributes to the recipient directory.
public struct ContactEnvelope: Equatable, Sendable {
    public let sender: String?
    public let recipients: String?
    public let cc: String?
    /// Raw received timestamp; used only to pick the most recent name. Lexicographic
    /// order is enough for the ISO-8601 values the sync layer stores.
    public let receivedRaw: String?

    public init(sender: String?, recipients: String?, cc: String?, receivedRaw: String?) {
        self.sender = sender
        self.recipients = recipients
        self.cc = cc
        self.receivedRaw = receivedRaw
    }
}

/// An in-memory projection of already-synced message envelopes. It is not a second
/// source of truth: it holds no port, performs no I/O, and is rebuilt per compose
/// session by `ComposeScene.recipientDirectory(account:)`.
public struct ContactDirectory: Equatable, Sendable {
    private struct Entry: Equatable, Sendable {
        let address: String
        var name: String?
        /// Timestamp of the name currently kept; empty for an unnamed first sighting.
        var nameRaw: String
        /// Most recent sighting of the address, used for stable ordering.
        var latestRaw: String
        /// Aggregate-order tie-break, so equal timestamps never reorder between queries.
        let order: Int
    }

    private let entries: [Entry]

    public init(envelopes: [ContactEnvelope], excluding: [String] = []) {
        let excluded = Set(excluding.compactMap(Self.normalizedKey))
        var byKey: [String: Entry] = [:]
        var order = 0

        for envelope in envelopes {
            for header in [envelope.sender, envelope.recipients, envelope.cc] {
                guard let header else { continue }
                let received = envelope.receivedRaw ?? ""
                for raw in EnvelopeParser.split(header) {
                    guard let parsed = EnvelopeParser.segment(from: raw) else { continue }
                    guard EnvelopeParser.isSMTPAddress(parsed.address) else { continue }
                    let key = parsed.address.lowercased()
                    guard !excluded.contains(key) else { continue }

                    if var existing = byKey[key] {
                        if received > existing.latestRaw {
                            existing.latestRaw = received
                        }
                        if let name = parsed.name {
                            // Keep the most recent non-empty name; equal timestamps keep
                            // the first sighting so adjacent keystrokes never flip names.
                            if existing.name == nil || received > existing.nameRaw {
                                existing.name = name
                                existing.nameRaw = received
                            }
                        }
                        byKey[key] = existing
                    } else {
                        byKey[key] = Entry(
                            address: parsed.address,
                            name: parsed.name,
                            nameRaw: parsed.name == nil ? "" : received,
                            latestRaw: received,
                            order: order
                        )
                    }
                    order += 1
                }
            }
        }

        self.entries = byKey.values.sorted { $0.order < $1.order }
    }

    public var isEmpty: Bool { entries.isEmpty }

    /// Case-insensitive prefix/substring match over the address and display name.
    /// Results are capped at eight and ordered by match quality, recency, address.
    public func suggestions(
        for fragment: String,
        excluding: [String] = [],
        limit: Int = 8
    ) -> [ContactAddress] {
        let needle = fragment.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }
        let capped = min(max(limit, 0), 8)
        guard capped > 0 else { return [] }

        var excluded = Set(excluding.compactMap(Self.normalizedKey))
        excluded.insert(needle)

        let ranked: [(entry: Entry, rank: Int)] = entries.compactMap { entry in
            let address = entry.address.lowercased()
            guard !excluded.contains(address) else { return nil }
            let name = entry.name?.lowercased()
            let rank: Int
            if address.hasPrefix(needle) {
                rank = 0
            } else if let name, name.hasPrefix(needle) {
                rank = 1
            } else if address.contains(needle) {
                rank = 2
            } else if let name, name.contains(needle) {
                rank = 3
            } else {
                return nil
            }
            return (entry, rank)
        }

        let sorted = ranked.sorted { left, right in
            if left.rank != right.rank { return left.rank < right.rank }
            if left.entry.latestRaw != right.entry.latestRaw {
                return left.entry.latestRaw > right.entry.latestRaw
            }
            let leftAddress = left.entry.address.lowercased()
            let rightAddress = right.entry.address.lowercased()
            if leftAddress != rightAddress { return leftAddress < rightAddress }
            return left.entry.order < right.entry.order
        }

        return sorted.prefix(capped).map {
            ContactAddress(name: $0.entry.name, address: $0.entry.address)
        }
    }

    private static func normalizedKey(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed.lowercased()
    }
}

/// Pure text helpers for the recipient field's trailing fragment. The caller decides
/// whether the caret/selection makes an insertion legal; this type only edits text.
public enum RecipientText {
    /// The text after the last top-level `;`/`,`, trimmed. Quotes and `<>` suspend
    /// separators, so a display name containing a comma is not a field boundary.
    public static func tailFragment(in text: String) -> String {
        String(text[tailStart(in: text)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Everything before the trailing fragment. The separator and any spaces after it
    /// stay in the prefix, so an insertion does not re-flow existing addresses.
    public static func prefixBeforeTail(in text: String) -> String {
        String(text[..<tailStart(in: text)])
    }

    /// Replaces the trailing fragment with `address` and appends `"; "`. An empty
    /// address returns the text unchanged. The caller must have verified the caret.
    public static func replacingTail(in text: String, with address: String) -> String {
        let clean = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return text }
        let start = tailStart(in: text)
        return String(text[..<start]) + clean + "; "
    }

    private static func tailStart(in text: String) -> String.Index {
        var lastSeparator: String.Index?
        var inQuotes = false
        var inAngle = false

        for index in text.indices {
            switch text[index] {
            case "\"":
                inQuotes.toggle()
            case "<" where !inQuotes:
                inAngle = true
            case ">" where !inQuotes:
                inAngle = false
            case ";", ",":
                if !inQuotes && !inAngle {
                    lastSeparator = index
                }
            default:
                break
            }
        }

        guard let lastSeparator else { return text.startIndex }
        // Keep the spaces after the separator in the prefix: replacing only the
        // trimmed fragment must not re-flow "a@b; zha" into "a@b;z@corp.test".
        var start = text.index(after: lastSeparator)
        while start < text.endIndex, text[start].isWhitespace {
            start = text.index(after: start)
        }
        return start
    }
}
