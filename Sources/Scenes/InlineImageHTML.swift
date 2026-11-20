import Foundation
import MailDomain

/// Turns `cid:` image references into `data:` URLs. Pure functions only: the caller matches
/// attachments and fetches bytes; everything except the replaced `src` values stays untouched.
enum InlineImageHTML {
    struct Match {
        let source: String
        let attachment: Attachment
    }
    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "bmp", "tif", "tiff", "heic",
    ]
    /// `<img>` start tag, quote-aware through the closing `>`; attributes of any other tag or
    /// text outside a tag are never candidates.
    private static let imgTagPattern = try? NSRegularExpression(
        pattern: "(?i)<img(?=[\\s/>])(?:\"[^\"]*\"|'[^']*'|[^'\">])*>"
    )
    /// Independent `src` attribute with a single-, double- or unquoted value. Quoted values
    /// are masked before matching, so ` src=` inside another attribute value is not an
    /// attribute; the lookahead keeps a self-closing `/` out of an unquoted value.
    private static let sourcePattern = try? NSRegularExpression(
        pattern: "(?i)(?<![\\w:-])src\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s\"'=<>`]+?))(?=\\s|/?>)"
    )
    /// Original spellings of the distinct `cid:` values in document order.
    static func sources(inHTML html: String) -> [String] {
        var seen = Set<String>()
        return sourceRanges(inHTML: html).compactMap { source in
            let value = source.value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.lowercased().hasPrefix("cid:"), seen.insert(value).inserted else { return nil }
            return value
        }
    }
    /// `cid:` prefix, brackets, percent escapes and case removed. The bracket pass runs
    /// again after decoding so `cid:%3Clogo%3E` normalizes like `cid:<logo>`.
    static func normalizedCID(_ cid: String) -> String {
        var value = cid.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("cid:") { value = String(value.dropFirst(4)) }
        return normalizedToken(value)
    }
    /// One `Match` per referenced cid whose attachment match is unambiguous.
    static func matches(inHTML html: String, attachments: [Attachment]) -> [Match] {
        sources(inHTML: html).compactMap { source in
            let cid = normalizedCID(source)
            guard !cid.isEmpty else { return nil }
            let local = cid.split(separator: "@", maxSplits: 1).first.map(String.init) ?? cid
            let candidates = attachments.filter { attachment in
                let display = normalizedToken(attachment.displayName)
                if display == cid || display == local { return true }
                guard hasImageExtension(attachment.displayName) else { return false }
                let stem = (attachment.displayName as NSString).deletingPathExtension
                return normalizedToken(stem) == local
            }
            let unique = Dictionary(candidates.map { ($0.fileReference, $0) }, uniquingKeysWith: { first, _ in first })
            guard unique.count == 1, let attachment = unique.values.first else { return nil }
            return Match(source: source, attachment: attachment)
        }
    }
    /// A `data:` URL only for bytes that actually carry a supported image signature.
    static func dataURL(for data: Data) -> String? {
        guard let mime = imageMIME(for: data) else { return nil }
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }
    /// Replaces only the value ranges whose exact spelling is in `replacements`; absent keys
    /// and every other byte of the document stay untouched.
    static func replacingSources(inHTML html: String, with replacements: [String: String]) -> String {
        guard !replacements.isEmpty else { return html }
        let edits = sourceRanges(inHTML: html).compactMap { source -> (NSRange, String)? in
            guard let replacement = replacements[source.value.trimmingCharacters(in: .whitespacesAndNewlines)]
            else { return nil }
            return (source.range, replacement)
        }
        guard !edits.isEmpty else { return html }
        let result = NSMutableString(string: html)
        for (range, replacement) in edits.reversed() { result.replaceCharacters(in: range, with: replacement) }
        return result as String
    }
    /// Value ranges of `src` attributes on `<img>` tags, in document order.
    private static func sourceRanges(inHTML html: String) -> [(range: NSRange, value: String)] {
        guard let tags = imgTagPattern, let pattern = sourcePattern else { return [] }
        let ns = html as NSString
        var out: [(range: NSRange, value: String)] = []
        for tag in tags.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            var units = Array(ns.substring(with: tag.range).utf16)
            var quote: UInt16 = 0
            for index in units.indices.dropFirst().dropLast() {
                if quote == 0, units[index] == 34 || units[index] == 39 { quote = units[index] }
                else if quote != 0, units[index] == quote { quote = 0 }
                else if quote != 0 { units[index] = 32 }
            }
            let masked = String(utf16CodeUnits: units, count: units.count)
            for match in pattern.matches(in: masked, range: NSRange(location: 0, length: units.count)) {
                guard let local = valueRange(match, in: masked as NSString) else { continue }
                let range = NSRange(location: tag.range.location + local.location, length: local.length)
                out.append((range, ns.substring(with: range)))
            }
        }
        return out
    }
    private static func valueRange(_ match: NSTextCheckingResult, in ns: NSString) -> NSRange? {
        for group in 1...3 where match.range(at: group).location != NSNotFound {
            return match.range(at: group)
        }
        return nil
    }

    private static func normalizedToken(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasPrefix("<"), value.hasSuffix(">") { value = String(value.dropFirst().dropLast()) }
        value = value.removingPercentEncoding ?? value
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasPrefix("<"), value.hasSuffix(">") { value = String(value.dropFirst().dropLast()) }
        return value.lowercased()
    }

    private static func hasImageExtension(_ name: String) -> Bool {
        imageExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    private static func imageMIME(for data: Data) -> String? {
        let bytes = [UInt8](data.prefix(16))
        func starts(_ signature: [UInt8]) -> Bool { bytes.starts(with: signature) }
        if starts([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return "image/png" }
        if starts([0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if starts(Array("GIF87a".utf8)) || starts(Array("GIF89a".utf8)) { return "image/gif" }
        if starts(Array("RIFF".utf8)), bytes.count >= 12,
           Array(bytes[8..<12]) == Array("WEBP".utf8) { return "image/webp" }
        if starts(Array("BM".utf8)) { return "image/bmp" }
        if starts([0x49, 0x49, 0x2A, 0x00]) || starts([0x4D, 0x4D, 0x00, 0x2A]) { return "image/tiff" }
        if bytes.count >= 12, Array(bytes[4..<8]) == Array("ftyp".utf8),
           let brand = String(bytes: bytes[8..<12], encoding: .ascii),
           ["heic", "heix", "hevc", "heim", "heis", "hevm", "hevs", "mif1", "msf1"].contains(brand) {
            return "image/heic"
        }
        return nil
    }
}
