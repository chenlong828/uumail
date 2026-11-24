import MailDomain
import Presentation
import SwiftUI

/// Content of the floating reader window (SCN-0025 / REQ-0031). Reads only from
/// `ReaderViewModel`; every action is one call on it or on `ReaderRouter`.
struct ReaderWindowView: View {
    @Bindable var model: ReaderViewModel
    var router: ReaderRouter

    @Environment(\.fontSizePreference) private var fontSize

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                if model.isComposing, let compose = model.compose {
                    ComposeView(
                        viewModel: compose,
                        preferredWidth: proxy.size.width,
                        preferredHeight: proxy.size.height,
                        allowRemoteContent: false,
                        onClose: endCompose
                    )
                } else {
                    reading(width: proxy.size.width, height: proxy.size.height)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    // MARK: - Reading

    private func reading(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if let notice = router.blockedNotice {
                banner(notice, systemImage: "pencil.and.outline")
            }
            if let error = model.markReadErrorText {
                banner(error, systemImage: "envelope.badge")
            }
            if model.isMissing {
                EmptyState(
                    title: "找不到这封邮件",
                    systemImage: "envelope.badge.shield.half.filled",
                    description: "它可能已被删除，或尚未同步到本机。"
                )
            } else {
                messageContent
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            if router.toolbarStyle == .mail {
                Button("回复") { model.composeReply() }
                    .disabled(!model.canCompose)
                Button("全部回复") { model.composeReplyAll() }
                    .disabled(!model.canCompose)
                Button("转发") { model.composeForward() }
                    .disabled(!model.canCompose)
            } else {
                Button("转发") { model.composeForward() }
                    .disabled(!model.canCompose)
                Button("在日历中打开") { router.openInCalendar?() }
            }
            Spacer()
            if let subject = model.header?.subject {
                Text(subject)
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Button {
                NSApp.keyWindow?.performClose(nil)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help("关闭")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var messageContent: some View {
        VStack(spacing: 0) {
            if let header = model.header {
                MessageHeaderView(header: header)
                remoteContentNotice
            }
            if let card = model.meetingCard {
                MeetingCardView(card: card, onOpenInCalendar: {}, showsAction: false)
                Divider()
            }
            MessageBodyView(
                header: nil,
                bodyPresentation: model.body,
                inlineImageHTML: model.inlineImageHTML,
                notice: model.bodyNotice,
                attachments: [],
                allowRemoteContent: model.allowsRemoteContent,
                onRetry: { model.retry() },
                attachmentErrorText: nil,
                savingAttachmentID: nil,
                onOpenAttachment: { _ in },
                onSaveAttachment: { _ in },
                onCancelSave: {}
            )
        }
    }

    /// Static (non-blocking) notice: the reader loads remote images by default (D6).
    private var remoteContentNotice: some View {
        HStack(spacing: 4) {
            Image(systemName: "globe")
            Text("远程图片来自发件人服务器，已自动显示")
            Spacer()
        }
        .scaledInheritedFont(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private func banner(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(text)
            Spacer()
        }
        .scaledInheritedFont(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.yellow.opacity(0.15))
    }

    private func endCompose() {
        model.endComposing()
        router.endComposing()
    }
}
