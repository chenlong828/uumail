import AppKit
import Presentation
import SwiftUI
import WebKit

/// Commands the format bar sends into the editable page. `execCommand` is deprecated but
/// is still the only WKWebView-native editing command set; the font-size command uses the
/// selection API so the sent HTML carries a span instead of a legacy `<font>` tag.
enum ComposeFormatCommand {
    case bold
    case italic
    case underline
    case strike
    case unorderedList
    case orderedList
    case alignLeft
    case alignCenter
    case alignRight
    case clearFormat
    case fontSize(Int)

    var javaScript: String {
        switch self {
        case .bold: "document.execCommand('bold')"
        case .italic: "document.execCommand('italic')"
        case .underline: "document.execCommand('underline')"
        case .strike: "document.execCommand('strikeThrough')"
        case .unorderedList: "document.execCommand('insertUnorderedList')"
        case .orderedList: "document.execCommand('insertOrderedList')"
        case .alignLeft: "document.execCommand('justifyLeft')"
        case .alignCenter: "document.execCommand('justifyCenter')"
        case .alignRight: "document.execCommand('justifyRight')"
        case .clearFormat: "document.execCommand('removeFormat')"
        case .fontSize(let pixels):
            """
            (function () {
                var selection = window.getSelection();
                if (!selection || selection.rangeCount === 0 || selection.isCollapsed) { return; }
                var range = selection.getRangeAt(0);
                var span = document.createElement('span');
                span.style.fontSize = '\(pixels)px';
                try { range.surroundContents(span); }
                catch (error) {
                    span.appendChild(range.extractContents());
                    range.insertNode(span);
                }
                selection.removeAllRanges();
                var after = document.createRange();
                after.selectNodeContents(span);
                selection.addRange(after);
            })()
            """
        }
    }
}

/// Bridges SwiftUI to the one WKWebView the compose sheet owns. The web view keeps the
/// selection; commands are evaluated from the app, so the page itself needs no scripts.
@MainActor
final class ComposeEditorHandle {
    weak var webView: WKWebView?
    var onReady: ((String) -> Void)?

    func attach(_ webView: WKWebView) {
        self.webView = webView
    }

    func didFinish() {
        guard let webView else { return }
        webView.window?.makeFirstResponder(webView)
        // Put the caret in the empty reply slot and pin the scroll to the top: without
        // this WebKit can restore the last remembered selection and open the sheet
        // scrolled into the middle of the quoted mail.
        webView.evaluateJavaScript(
            """
            (function () {
                var start = document.getElementById('uumail-reply-start');
                if (start) {
                    var selection = window.getSelection();
                    var range = document.createRange();
                    range.setStart(start, 0);
                    range.collapse(true);
                    selection.removeAllRanges();
                    selection.addRange(range);
                }
                document.documentElement.scrollTop = 0;
                document.body.scrollTop = 0;
            })()
            """
        ) { _, _ in }
        webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] result, _ in
            guard let raw = result as? String else { return }
            let cleaned = ComposeDocument.emailHTML(fromEditorDocument: raw)
            Task { @MainActor [weak self] in self?.onReady?(cleaned) }
        }
    }

    /// Returns the mail HTML with the editor's CSP/style/contenteditable removed, or
    /// `nil` when the page has not loaded (the caller keeps the current value).
    func capture() async -> String? {
        guard let webView else { return nil }
        let raw: String? = await withCheckedContinuation { continuation in
            webView.evaluateJavaScript("document.documentElement.outerHTML") { result, _ in
                continuation.resume(returning: result as? String)
            }
        }
        guard let raw else { return nil }
        return ComposeDocument.emailHTML(fromEditorDocument: raw)
    }

    func perform(_ command: ComposeFormatCommand) {
        guard let webView else { return }
        webView.window?.makeFirstResponder(webView)
        webView.evaluateJavaScript(command.javaScript) { _, _ in }
    }
}

/// The editable mail body. It loads once per sheet; `updateNSView` only applies the font
/// zoom, so capturing the HTML back into the view model cannot reload the page and lose
/// the caret.
struct ComposeEditor: NSViewRepresentable {
    let html: String
    let allowRemoteContent: Bool
    let fontSize: FontSizePreference
    let handle: ComposeEditorHandle
    let onReady: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(handle: handle)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // The page needs no scripts of its own: sender scripts are stripped before load
        // and the CSP has no script-src. The app still evaluates editing commands.
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(true, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .white
        webView.appearance = NSAppearance(named: .aqua)
        webView.pageZoom = CGFloat(fontSize.scale)
        webView.navigationDelegate = context.coordinator
        handle.attach(webView)
        handle.onReady = onReady
        let document = ComposeDocument.editorDocument(
            emailHTML: html,
            allowRemoteContent: allowRemoteContent
        )
        webView.loadHTMLString(document, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if webView.pageZoom != CGFloat(fontSize.scale) {
            webView.pageZoom = CGFloat(fontSize.scale)
        }
        context.coordinator.handle.onReady = onReady
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        let handle: ComposeEditorHandle

        init(handle: ComposeEditorHandle) {
            self.handle = handle
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            handle.didFinish()
        }
    }
}
