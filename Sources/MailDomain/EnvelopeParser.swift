import Foundation

/// Shared envelope-text splitting used by `AddressList` and `ContactDirectory`.
///
/// This is the single implementation of the `;`/`,` splitting rule (quotes and `<>`
/// suspend separators). `AddressList` keeps its permissive address-shape filter;
/// `ContactDirectory` adds the SMTP-only filter and the display-name extraction on top.
enum EnvelopeParser {
    struct Segment {
        /// Display name when the segment had a non-empty `<>` prefix and the name is usable.
        let name: String?
        /// Address body: the `<>` interior, or the whole (unquoted) segment.
        let address: String
        /// Whether the segment used the `Name <address>` shape. `AddressList` treats an
        /// angled body as an address without applying its bare-segment shape filter.
        let isAngled: Bool
    }

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

    /// Parses one segment. Returns `nil` for empty segments, an unclosed `<>`, or an
    /// empty `<>` body. Malformed trailing text after `>` is ignored exactly as before.
    static func segment(from raw: String) -> Segment? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let open = trimmed.firstIndex(of: "<") {
            guard let close = trimmed[trimmed.index(after: open)...].firstIndex(of: ">") else {
                return nil
            }
            let inner = trimmed[trimmed.index(after: open)..<close]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !inner.isEmpty else { return nil }
            let rawName = trimmed[..<open]
            let name = normalizedName(String(rawName), address: inner)
            return Segment(name: name, address: inner, isAngled: true)
        }

        let unquoted = stripWrappingQuotes(trimmed)
        guard !unquoted.isEmpty else { return nil }
        return Segment(name: nil, address: unquoted, isAngled: false)
    }

    /// `AddressList`'s long-standing segment shape filter, now shared.
    static func address(fromSegment raw: String) -> String? {
        guard let parsed = segment(from: raw) else { return nil }
        if parsed.isAngled { return parsed.address }
        if parsed.address.contains("@") { return parsed.address }
        if parsed.address.hasPrefix("/") { return parsed.address }
        if parsed.address.contains("="), !parsed.address.contains(where: \.isWhitespace) {
            return parsed.address
        }
        return nil
    }

    /// A contact candidate requires a strict single-`@` SMTP address. Bare names,
    /// distribution-group names, Exchange DNs and malformed angled bodies are skipped.
    static func isSMTPAddress(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        guard !value.contains(where: \.isWhitespace) else { return false }
        guard value.filter({ $0 == "@" }).count == 1 else { return false }
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return false }
        let forbidden: Set<Character> = [";", ",", "<", ">", "\""]
        return !value.contains(where: { forbidden.contains($0) })
    }

    static func stripWrappingQuotes(_ value: String) -> String {
        guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else {
            return value
        }
        return String(value.dropFirst().dropLast())
    }

    /// Display names are unquoted, whitespace-collapsed, and dropped when empty, equal
    /// to the address, or an undecoded RFC 2047 encoded word.
    private static func normalizedName(_ raw: String, address: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let unquoted = stripWrappingQuotes(trimmed)
        let collapsed = unquoted.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        guard collapsed.lowercased() != address.lowercased() else { return nil }
        guard !(collapsed.hasPrefix("=?") && collapsed.hasSuffix("?=")) else { return nil }
        return collapsed
    }
}
