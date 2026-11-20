import MailDomain
import Presentation
import SwiftUI
import WebKit

struct MessageBodyView: View {
    let header: MessageHeaderPresentation?
    let bodyPresentation: BodyPresentation
    /// The current body with inline `cid:` sources already rewritten to `data:` URLs. The
    /// view only swaps the display string; it never parses HTML or fetches attachments.
    let inlineImageHTML: String?
    let notice: BodyNotice?
    let attachments: [Attachment]
    /// Session-only permission owned by `MailboxViewModel`; the body view never owns it
    /// (REQ-0018 / R33). It only forwards the value to the web view's CSP.
    let allowRemoteContent: Bool
    let onRetry: () -> Void
    let onOpenAttachment: (Attachment) async -> Void

    @Environment(\.fontSizePreference) private var fontSize

    /// 175% and 225% are the levels whose uncapped metadata region would leave less than
    /// the 200pt reading floor (measured 164.5pt / 147.5pt at a conservative 480pt).
    /// 120% and 145% measure 242.5pt / 205pt, so they keep their natural height and the
    /// production nesting.
    private var isCapped: Bool {
        (fontSize == .percent175 || fontSize == .percent225) && header != nil
    }

    var body: some View {
        if isCapped {
            capped
        } else {
            natural
        }
    }

    /// 100/120/145%: the production nesting exactly — header, divider, then the body
    /// switch. The outer frame stays where it was so the 100% layout is unchanged.
    private var natural: some View {
        VStack(spacing: 0) {
            if let header {
                MessageHeaderView(header: header)
                Divider()
            }
            bodyContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// 175/225%: header + attachment strip + banner share one 220pt scrollable metadata
    /// region; the WebView gets the remaining height (259pt at the conservative 480pt
    /// content height, 339pt at 560pt).
    private var capped: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    if let header {
                        MessageHeaderView(header: header)
                    }
                    if case .loaded(_, let isTruncated) = bodyPresentation {
                        attachmentStrip
                        bannerRow(isTruncated: isTruncated)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            Divider()
            if case .loaded(let html, _) = bodyPresentation {
                MessageWebView(
                    html: inlineImageHTML ?? html,
                    allowRemoteContent: allowRemoteContent,
                    fontSize: fontSize
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                bodyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// The header stays outside the body switch so every body state shares it (R28).
    @ViewBuilder
    private var bodyContent: some View {
        if case .loaded(let html, let isTruncated) = bodyPresentation {
            VStack(spacing: 0) {
                attachmentStrip
                bannerRow(isTruncated: isTruncated)
                Divider()
                MessageWebView(
                    html: inlineImageHTML ?? html,
                    allowRemoteContent: allowRemoteContent,
                    fontSize: fontSize
                )
            }
        } else {
            bodyState
        }
    }

    @ViewBuilder
    private var bodyState: some View {
        switch bodyPresentation {
        case .none where header == nil:
            EmptyState(title: "选择一封邮件", systemImage: "envelope.open", isSelectable: true)
        case .none, .loading:
            ProgressView("正在获取正文…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            EmptyState(
                title: "正文获取失败",
                systemImage: "exclamationmark.triangle",
                description: message,
                descriptionStyle: .caption,
                actionTitle: "重试",
                action: onRetry
            )
        case .loaded:
            EmptyView()
        }
    }

    @ViewBuilder
    private var attachmentStrip: some View {
        if !attachments.isEmpty {
            HStack(spacing: 8) {
                ForEach(attachments) { attachment in
                    Button {
                        Task { await onOpenAttachment(attachment) }
                    } label: {
                        Label(attachment.displayName, systemImage: "paperclip")
                            .scaledInheritedFont(.body)
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
    }

    @ViewBuilder
    private func bannerRow(isTruncated: Bool) -> some View {
        if let banner = banner(for: isTruncated) {
            HStack(spacing: 6) {
                Image(systemName: banner.symbol)
                Text(banner.text)
                if banner.allowsRetry {
                    retryButton
                }
                Spacer()
            }
            .scaledFont(.caption)
            .foregroundStyle(banner.isProblem ? Color.orange : Color.secondary)
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
    }

    /// Keep the production string-title button at 100% (a custom label changes the
    /// button's intrinsic height by 1pt); above 100% the string title ignores the
    /// environment font, so the label is scaled explicitly.
    @ViewBuilder
    private var retryButton: some View {
        if fontSize == .percent100 {
            Button("重试", action: onRetry)
                .buttonStyle(.link)
        } else {
            Button(action: onRetry) {
                Text("重试").font(fontSize.font(for: .caption))
            }
            .buttonStyle(.link)
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
    let fontSize: FontSizePreference

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        // The reading canvas is a constant, not a theme: keep it opaque and light so
        // dark chrome never shows through and sender `prefers-color-scheme: dark`
        // rules are evaluated as light (REQ-0015 / SCN-0010).
        webView.setValue(true, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .white
        webView.appearance = NSAppearance(named: .aqua)
        // First frame already carries the preference, so the body does not render at
        // 1.0 and then jump to the selected level.
        webView.pageZoom = CGFloat(fontSize.scale)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // SwiftUI/AppKit can reset the appearance after creation; reassert it before
        // the render guard so a theme change never reloads the body (R24).
        if webView.appearance?.name != .aqua {
            webView.appearance = NSAppearance(named: .aqua)
        }
        // Font size changes only the render zoom; it must stay outside the render guard
        // so the document is never reloaded (REQ-0020 immediate effect).
        if webView.pageZoom != CGFloat(fontSize.scale) {
            webView.pageZoom = CGFloat(fontSize.scale)
        }
        guard context.coordinator.lastRender != "\(allowRemoteContent)|\(html)" else { return }
        context.coordinator.lastRender = "\(allowRemoteContent)|\(html)"
        webView.loadHTMLString(MessageBodyStyle.sanitized(html, allowRemoteContent: allowRemoteContent), baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastRender: String?
    }
}
