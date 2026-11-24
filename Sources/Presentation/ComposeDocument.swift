import Foundation
import HTMLSupport
import Scenes

/// Turns a stored mail document into the editable page and back. The editor adds a CSP
/// and an editor-only stylesheet; both are removed before the HTML becomes the outgoing
/// MIME body, so recipients never receive `contenteditable` or our reading defaults.
public enum ComposeDocument {
    /// Editor-only stylesheet id and CSP marker. Capture removes exactly these.
    static let styleID = "uumail-editor-style"
    static let cspMarker = "uumail-editor-csp"

    /// `emailHTML` is the stored draft (no CSP, no editor chrome). The returned document
    /// is what `ComposeEditor` loads. Sender markup is sanitised first: the page has
    /// JavaScript enabled so the format commands can run, and the CSP below blocks
    /// page scripts as the second line of defence.
    public static func editorDocument(emailHTML: String, allowRemoteContent: Bool) -> String {
        let base = emailHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? HTMLText.emptyEmailDocument()
            : emailHTML
        let safe = HTMLText.sanitizedForCompose(base)
        let meta = """
            <meta name="\(cspMarker)" http-equiv="Content-Security-Policy" content="\(policy(allowRemoteContent: allowRemoteContent))">
            """
        let style = "<style id=\"\(styleID)\">\(editorCSS)</style>"
        var document = insertIntoHead(meta + style, into: safe)
        document = replacingBodyTag(in: document) { tag in
            var tag = tag
            if !tag.lowercased().contains("contenteditable") {
                tag = tag.replacingOccurrences(of: ">", with: " contenteditable=\"true\" spellcheck=\"true\">")
            }
            return tag
        }
        return document
    }

    /// Removes the editor chrome and returns the mail document to store and send.
    public static func emailHTML(fromEditorDocument document: String) -> String {
        var text = document
        text = replacing(
            pattern: "<meta[^>]*name=\"\(cspMarker)\"[^>]*>",
            in: text,
            with: ""
        )
        text = replacing(
            pattern: "<style[^>]*id=\"\(styleID)\"[^>]*>[\\s\\S]*?</style\\s*>",
            in: text,
            with: ""
        )
        text = text.replacingOccurrences(of: " contenteditable=\"true\"", with: "")
        text = text.replacingOccurrences(of: " contenteditable=\"\"", with: "")
        text = text.replacingOccurrences(of: " spellcheck=\"true\"", with: "")
        return text
    }

    static func policy(allowRemoteContent: Bool) -> String {
        let sources = allowRemoteContent ? "data: https: http:" : "data:"
        return "default-src 'none'; img-src \(sources); style-src 'unsafe-inline'; font-src \(sources); media-src \(sources);"
    }

    static let editorCSS = """
        html, body { margin: 0; padding: 0; background-color: #ffffff; color-scheme: light; }
        body {
            font-family: -apple-system, "PingFang SC", "Helvetica Neue", sans-serif;
            font-size: 13px; line-height: 1.55; color: #1d1d1f;
            padding: 12px 16px; word-wrap: break-word; overflow-wrap: anywhere;
            outline: none;
        }
        img { max-width: 100%; height: auto; }
        table { max-width: 100%; }
        pre { white-space: pre-wrap; }
        a { color: #0a84ff; }
        """

    private static func insertIntoHead(_ snippet: String, into html: String) -> String {
        if let headEnd = html.range(of: "</head>", options: .caseInsensitive) {
            var copy = html
            copy.insert(contentsOf: snippet, at: headEnd.lowerBound)
            return copy
        }
        if let headOpen = html.range(of: "<head>", options: .caseInsensitive) {
            var copy = html
            copy.insert(contentsOf: snippet, at: headOpen.upperBound)
            return copy
        }
        return "<html><head>\(snippet)</head><body>\(html)</body></html>"
    }

    private static func replacingBodyTag(in html: String, _ transform: (String) -> String) -> String {
        guard let bodyOpen = html.range(of: "<body", options: .caseInsensitive),
              let tagClose = html.range(of: ">", range: bodyOpen.lowerBound..<html.endIndex)
        else {
            return html
        }
        let tag = String(html[bodyOpen.lowerBound..<tagClose.lowerBound]) + ">"
        return html.replacingCharacters(in: bodyOpen.lowerBound..<tagClose.upperBound, with: transform(tag))
    }

    private static func replacing(pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return text
        }
        let ns = text as NSString
        return regex.stringByReplacingMatches(
            in: text, range: NSRange(location: 0, length: ns.length), withTemplate: template
        )
    }
}
