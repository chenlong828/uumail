import Foundation

/// Text → HTML helpers. Bodies reach the reading pane either as HTML or as plain text
/// (a sync preview, or a gateway that cannot produce HTML); both must render readably
/// without inventing markup the sender never wrote.
public enum HTMLText {
    /// Escapes the characters that would otherwise start markup.
    public static func escape(_ text: String) -> String {
        var out = text.replacingOccurrences(of: "&", with: "&amp;")
        out = out.replacingOccurrences(of: "<", with: "&lt;")
        out = out.replacingOccurrences(of: ">", with: "&gt;")
        out = out.replacingOccurrences(of: "\"", with: "&quot;")
        return out
    }

    /// Plain text as HTML that keeps its own line breaks and spacing. Without `pre-wrap`
    /// the browser collapses every break and the whole mail turns into one paragraph.
    public static func fromPlainText(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return "<div style=\"white-space: pre-wrap;\">\(escape(normalized))</div>"
    }
}
