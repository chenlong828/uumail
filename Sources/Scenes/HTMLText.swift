import Foundation

/// Text ↔ HTML helpers shared by the reading pane and the compose editor. Bodies reach
/// the reader either as HTML or as plain text; both must render readably without
/// inventing markup the sender never wrote. The compose side uses the same escaping and
/// sanitising rules so a quoted original cannot smuggle script into the editable page.
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

    // MARK: - Compose documents

    public static func emptyEmailDocument() -> String {
        """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"></head><body><div id="uumail-reply-start"><br></div></body></html>
        """
    }

    /// The reply/forward document: a date+sender header, then the original body at full
    /// width. Deliberately no `<blockquote>`, left margin or left border — the quote is
    /// part of the mail body, not an indented attachment (REQ-0021).
    public static func quotedEmail(header: String, originalHTML: String?) -> String {
        let parts = splitDocument(originalHTML ?? "")
        let styles = parts.styles.joined(separator: "\n")
        let body = sanitizedForCompose(parts.body)
        return """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8">\(styles)</head>
        <body>
        <div id="uumail-reply-start"><br></div>
        <div style="margin-top:16px;padding-top:12px;border-top:1px solid #d9d9d9;">
        <div style="font-size:12px;line-height:1.5;color:#6e6e73;margin:0 0 12px 0;">\(escape(header))</div>
        <div>\(body)</div>
        </div>
        </body></html>
        """
    }

    // MARK: - Plain-text alternative

    /// HTML → readable plain text for `text/plain` clients. Block boundaries become line
    /// breaks, list items get a bullet, tags and entities are resolved, and runs of blank
    /// lines collapse so quoted marketing mail does not become mostly whitespace.
    public static func plainText(from html: String) -> String {
        var text = html
        for tag in ["script", "style", "head", "title"] {
            text = removingElement(text, tag: tag)
        }
        for tag in ["br", "br/", "br /"] {
            text = text.replacingOccurrences(of: "<\(tag)>", with: "\n", options: .caseInsensitive)
        }
        text = text.replacingOccurrences(of: "<li", with: "\n• <li", options: .caseInsensitive)
        for tag in ["p", "div", "li", "tr", "blockquote", "h1", "h2", "h3", "h4", "h5", "h6"] {
            text = text.replacingOccurrences(of: "</\(tag)>", with: "\n", options: .caseInsensitive)
        }
        while let open = text.firstIndex(of: "<"), let close = text[open...].firstIndex(of: ">") {
            text.removeSubrange(open...close)
        }
        text = decodeEntities(text)
        text = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var lines: [String] = []
        var blankRun = 0
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.replacingOccurrences(of: "[ \\t]+$", with: "", options: .regularExpression)
            if line.isEmpty {
                blankRun += 1
                if blankRun > 2 { continue }
            } else {
                blankRun = 0
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Sanitising

    /// Removes the structural elements that could execute or navigate while the quoted
    /// original sits inside an editable page. Inline styles and images survive; the CSP
    /// injected by the editor is the second line of defence.
    public static func sanitizedForCompose(_ html: String) -> String {
        var text = html
        for tag in [
            "script", "iframe", "object", "embed", "form", "button", "input",
            "textarea", "select", "meta", "link", "base",
        ] {
            text = removingElement(text, tag: tag)
        }
        text = removingEventAttributes(text)
        text = text.replacingOccurrences(of: "javascript:", with: "#", options: .caseInsensitive)
        return text
    }

    // MARK: - Document split

    /// Extracts `<style>` blocks (kept, scoped to the sender's markup by order) and the
    /// `<body>` content from a full document or a fragment.
    static func splitDocument(_ html: String) -> (styles: [String], body: String) {
        var styles: [String] = []
        let stylePattern = try? NSRegularExpression(
            pattern: "<style\\b[^>]*>[\\s\\S]*?</style\\s*>", options: [.caseInsensitive]
        )
        if let stylePattern {
            let ns = html as NSString
            let matches = stylePattern.matches(in: html, range: NSRange(location: 0, length: ns.length))
            for match in matches {
                styles.append(ns.substring(with: match.range))
            }
            var body = html
            for style in styles {
                body = body.replacingOccurrences(of: style, with: "", options: .caseInsensitive)
            }
            return (styles, bodyFromDocument(body))
        }
        return ([], bodyFromDocument(html))
    }

    /// Body content of a document; a fragment is returned as-is.
    private static func bodyFromDocument(_ html: String) -> String {
        guard let bodyOpen = html.range(of: "<body", options: .caseInsensitive),
              let tagClose = html.range(of: ">", range: bodyOpen.upperBound..<html.endIndex)
        else {
            return stripDocumentHead(html)
        }
        let contentStart = tagClose.upperBound
        let contentEnd = html.range(of: "</body>", options: .caseInsensitive, range: contentStart..<html.endIndex)?.lowerBound
        return String(html[contentStart..<(contentEnd ?? html.endIndex)])
    }

    /// A fragment that still carries a head/body wrapper (without a `<body>` match) is
    /// reduced to its body content when possible.
    private static func stripDocumentHead(_ html: String) -> String {
        guard let headEnd = html.range(of: "</head>", options: .caseInsensitive) else {
            return html
        }
        return String(html[headEnd.upperBound...])
    }

    // MARK: - String helpers

    private static func removingElement(_ html: String, tag: String) -> String {
        let block = try? NSRegularExpression(
            pattern: "<\(tag)\\b[^>]*>[\\s\\S]*?</\(tag)\\s*>", options: [.caseInsensitive]
        )
        var text = html
        if let block {
            let ns = text as NSString
            text = block.stringByReplacingMatches(
                in: text, range: NSRange(location: 0, length: ns.length), withTemplate: ""
            )
        }
        let selfClosing = try? NSRegularExpression(
            pattern: "<\(tag)\\b[^>]*/?>", options: [.caseInsensitive]
        )
        if let selfClosing {
            let ns = text as NSString
            text = selfClosing.stringByReplacingMatches(
                in: text, range: NSRange(location: 0, length: ns.length), withTemplate: ""
            )
        }
        return text
    }

    private static func removingEventAttributes(_ html: String) -> String {
        let pattern = try? NSRegularExpression(
            pattern: "\\son[a-zA-Z]+\\s*=\\s*(?:\"[^\"]*\"|'[^']*'|[^\\s>]+)", options: [.caseInsensitive]
        )
        guard let pattern else { return html }
        let ns = html as NSString
        return pattern.stringByReplacingMatches(
            in: html, range: NSRange(location: 0, length: ns.length), withTemplate: ""
        )
    }

    private static func decodeEntities(_ text: String) -> String {
        var out = text
        let named: [String: String] = [
            "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
            "&apos;": "'", "&#39;": "'", "&mdash;": "—", "&ndash;": "–", "&hellip;": "…",
            "&middot;": "·", "&bull;": "•", "&copy;": "©", "&reg;": "®", "&trade;": "™",
            "&laquo;": "«", "&raquo;": "»", "&times;": "×", "&divide;": "÷",
        ]
        for (entity, value) in named {
            out = out.replacingOccurrences(of: entity, with: value, options: .caseInsensitive)
        }
        let numeric = try? NSRegularExpression(
            pattern: "&#(x?[0-9a-fA-F]+);", options: [.caseInsensitive]
        )
        if let numeric {
            let ns = out as NSString
            let matches = numeric.matches(in: out, range: NSRange(location: 0, length: ns.length))
            for match in matches.reversed() {
                let token = ns.substring(with: match.range(at: 1))
                let value = token.lowercased().hasPrefix("x")
                    ? UInt32(token.dropFirst(), radix: 16)
                    : UInt32(token, radix: 10)
                guard let value, let scalar = UnicodeScalar(value) else { continue }
                out = (out as NSString).replacingCharacters(in: match.range, with: String(scalar))
            }
        }
        return out
    }
}
