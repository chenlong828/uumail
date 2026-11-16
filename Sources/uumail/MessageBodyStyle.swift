import Foundation

/// Reading defaults injected around a mail body.
///
/// This is a floor, not a theme: Outlook-style mail carries its own inline styles,
/// so the white background and dark text only apply where the sender left them open.
/// The sender's explicit background/colour/table/image rules stay later in the
/// document and therefore win over this block.
enum MessageBodyStyle {
    static let baseCSS = """
        html, body {
            margin: 0; padding: 0;
            background-color: #ffffff; color-scheme: light;
        }
        body {
            font-family: -apple-system, "PingFang SC", "Helvetica Neue", sans-serif;
            font-size: 13px; line-height: 1.55; color: #1d1d1f;
            padding: 12px 16px; word-wrap: break-word; overflow-wrap: anywhere;
        }
        img { max-width: 100%; height: auto; }
        table { max-width: 100%; }
        pre { white-space: pre-wrap; }
        """

    static func contentSecurityPolicy(allowRemoteContent: Bool) -> String {
        allowRemoteContent
            ? "default-src 'none'; img-src data: https: http:; style-src 'unsafe-inline'; font-src data: https: http:;"
            : "default-src 'none'; img-src data:; style-src 'unsafe-inline'; font-src data:;"
    }

    static func sanitized(_ html: String, allowRemoteContent: Bool) -> String {
        let head = "<meta http-equiv=\"Content-Security-Policy\" content=\"\(contentSecurityPolicy(allowRemoteContent: allowRemoteContent))\">"
            + "<style>\(baseCSS)</style>"
        if let open = html.range(of: "<head>", options: .caseInsensitive) {
            var copy = html
            copy.insert(contentsOf: head, at: open.upperBound)
            return copy
        }
        return "<html><head>\(head)</head><body>\(html)</body></html>"
    }
}
