import AppServices
import SwiftUI
import WebKit

struct MessageBodyView: View {
    let state: MailboxModel.DetailState
    let onRetry: () -> Void
    @State private var allowRemoteContent = false

    var body: some View {
        switch state {
        case .none:
            ContentUnavailableView("选择一封邮件", systemImage: "envelope.open")
        case .loading:
            ProgressView("正在获取正文…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView {
                Label("正文获取失败", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message).font(.caption)
            } actions: {
                Button("重试", action: onRetry)
            }
        case .loaded(let html):
            VStack(spacing: 0) {
                HStack {
                    Toggle("加载远程图片", isOn: $allowRemoteContent)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                Divider()
                MessageWebView(html: html, allowRemoteContent: allowRemoteContent)
            }
        }
    }
}

/// Renders mail HTML with JavaScript off. A CSP injected into the document blocks
/// remote images unless the user flips the switch for this message (design D5/D6).
struct MessageWebView: NSViewRepresentable {
    let html: String
    let allowRemoteContent: Bool

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastRender != "\(allowRemoteContent)|\(html)" else { return }
        context.coordinator.lastRender = "\(allowRemoteContent)|\(html)"
        webView.loadHTMLString(Self.sanitized(html, allowRemoteContent: allowRemoteContent), baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastRender: String?
    }

    static func sanitized(_ html: String, allowRemoteContent: Bool) -> String {
        let policy = allowRemoteContent
            ? "default-src 'none'; img-src data: https: http:; style-src 'unsafe-inline'; font-src data: https: http:;"
            : "default-src 'none'; img-src data:; style-src 'unsafe-inline'; font-src data:;"
        let meta = "<meta http-equiv=\"Content-Security-Policy\" content=\"\(policy)\">"
        if let head = html.range(of: "<head>", options: .caseInsensitive) {
            var copy = html
            copy.insert(contentsOf: meta, at: head.upperBound)
            return copy
        }
        return "<html><head>\(meta)</head><body>\(html)</body></html>"
    }
}
