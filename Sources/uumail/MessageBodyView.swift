import MailDomain
import Presentation
import SwiftUI
import WebKit

struct MessageBodyView: View {
    let bodyPresentation: BodyPresentation
    let notice: BodyNotice?
    let attachments: [Attachment]
    let onRetry: () -> Void
    let onOpenAttachment: (Attachment) async -> Void
    @State private var allowRemoteContent = false

    var body: some View {
        switch bodyPresentation {
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
        case .loaded(let html, let isTruncated):
            VStack(spacing: 0) {
                if !attachments.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(attachments) { attachment in
                            Button {
                                Task { await onOpenAttachment(attachment) }
                            } label: {
                                Label(attachment.displayName, systemImage: "paperclip")
                                    .lineLimit(1)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                }
                HStack {
                    Toggle("加载远程图片", isOn: $allowRemoteContent)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                if let banner = banner(for: isTruncated) {
                    HStack(spacing: 6) {
                        Image(systemName: banner.symbol)
                        Text(banner.text)
                        if banner.allowsRetry {
                            Button("重试", action: onRetry)
                                .buttonStyle(.link)
                        }
                        Spacer()
                    }
                    .font(.caption)
                    .foregroundStyle(banner.isProblem ? Color.orange : Color.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                }
                Divider()
                MessageWebView(html: html, allowRemoteContent: allowRemoteContent)
            }
        }
    }

    private struct Banner {
        var text: String
        var symbol: String
        var isProblem: Bool
        var allowsRetry: Bool
    }

    /// Tells the reader what it is looking at: a preview that is still filling in, a body the
    /// gateway had to cut short, or a failed fetch that fell back to the preview.
    private func banner(for isTruncated: Bool) -> Banner? {
        switch notice {
        case .fetchingFullBody:
            return Banner(
                text: "正在获取完整正文…", symbol: "arrow.down.circle", isProblem: false, allowsRetry: false
            )
        case .previewFallback:
            return Banner(
                text: "正文获取失败，当前显示的是摘要", symbol: "exclamationmark.triangle",
                isProblem: true, allowsRetry: true
            )
        case nil:
            break
        }
        if isTruncated {
            return Banner(
                text: "正文过长，网关只返回了前面一部分", symbol: "scissors",
                isProblem: true, allowsRetry: false
            )
        }
        return nil
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

    /// Reading defaults applied only where the sender left them open: Outlook-style mail
    /// carries its own inline styles, so this must stay a floor, not a theme.
    private static let baseStyle = """
        html, body { margin: 0; padding: 0; }
        body {
            font-family: -apple-system, "PingFang SC", "Helvetica Neue", sans-serif;
            font-size: 13px; line-height: 1.55; color: #1d1d1f;
            padding: 12px 16px; word-wrap: break-word; overflow-wrap: anywhere;
        }
        img { max-width: 100%; height: auto; }
        table { max-width: 100%; }
        pre { white-space: pre-wrap; }
        """

    static func sanitized(_ html: String, allowRemoteContent: Bool) -> String {
        let policy = allowRemoteContent
            ? "default-src 'none'; img-src data: https: http:; style-src 'unsafe-inline'; font-src data: https: http:;"
            : "default-src 'none'; img-src data:; style-src 'unsafe-inline'; font-src data:;"
        let head = "<meta http-equiv=\"Content-Security-Policy\" content=\"\(policy)\">"
            + "<style>\(baseStyle)</style>"
        if let open = html.range(of: "<head>", options: .caseInsensitive) {
            var copy = html
            copy.insert(contentsOf: head, at: open.upperBound)
            return copy
        }
        return "<html><head>\(head)</head><body>\(html)</body></html>"
    }
}
