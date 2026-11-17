import Presentation
import SwiftUI

/// Reply/new-mail sheet: address fields, a format bar, an editable WebView and the
/// explicit close entry. The sheet width follows the reading pane (REQ-0021); the two
/// editor callbacks push captured HTML back into the view model before any action.
struct ComposeView: View {
    @Bindable var viewModel: ComposeViewModel
    let preferredWidth: CGFloat
    let preferredHeight: CGFloat
    let allowRemoteContent: Bool
    let onClose: () -> Void

    @Environment(\.fontSizePreference) private var fontSize
    @State private var editor = ComposeEditorHandle()
    @State private var showingDiscard = false

    private var width: CGFloat {
        // The reading pane can be very narrow in a three-column split; keep the sheet
        // usable while still matching the pane at any normal window size.
        max(preferredWidth, 480)
    }

    private var height: CGFloat {
        max(460, min(preferredHeight, 820))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Form {
                TextField("收件人", text: $viewModel.to, prompt: Text("a@example.com"))
                TextField("抄送", text: $viewModel.cc)
                TextField("主题", text: $viewModel.subject)
            }
            .padding(12)
            Divider()
            ComposeFormatBar(handle: editor)
            Divider()
            ComposeEditor(
                html: viewModel.bodyHTML,
                allowRemoteContent: allowRemoteContent,
                fontSize: fontSize,
                handle: editor,
                onReady: { viewModel.editorDidLoad($0) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: width, height: height)
        .interactiveDismissDisabled()
        .confirmationDialog(
            "放弃这封邮件？",
            isPresented: $showingDiscard,
            titleVisibility: .visible
        ) {
            Button("放弃", role: .destructive) { onClose() }
            Button("继续编辑", role: .cancel) {}
        } message: {
            Text("已输入的内容不会保存。")
        }
    }

    private var header: some View {
        HStack {
            Text(title)
                .scaledFont(.headline)
            Spacer()
            Button {
                requestClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .focusable(false)
            .help("取消并关闭")
            .accessibilityLabel("取消并关闭")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            composeButton("取消") { requestClose() }
                .keyboardShortcut(.cancelAction)
                .disabled(viewModel.isSending)
            if let statusText = viewModel.statusText {
                Label(statusText, systemImage: statusSymbol)
                    .scaledFont(.caption)
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
            }
            Spacer()
            composeButton("存草稿") {
                Task {
                    if let html = await editor.capture() {
                        viewModel.setEditorHTML(html)
                    }
                    if viewModel.saveDraft() { onClose() }
                }
            }
            .disabled(viewModel.isSending)
            composeButton("发送") {
                Task {
                    if let html = await editor.capture() {
                        viewModel.setEditorHTML(html)
                    }
                    if await viewModel.send() { onClose() }
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!viewModel.canSend)
        }
        .padding(12)
    }

    /// String-title buttons ignore the environment font; 100% keeps the original title
    /// (no 1pt height drift) and above 100% scales the label explicitly.
    @ViewBuilder
    private func composeButton(_ title: String, action: @escaping () -> Void) -> some View {
        if fontSize == .percent100 {
            Button(title, action: action)
        } else {
            Button(action: action) {
                Text(title).font(fontSize.font(for: .body))
            }
        }
    }

    private func requestClose() {
        Task {
            if let html = await editor.capture() {
                viewModel.setEditorHTML(html)
            }
            if viewModel.hasEdits {
                showingDiscard = true
            } else {
                onClose()
            }
        }
    }

    private var title: String {
        switch viewModel.mode {
        case .new: "新邮件"
        case .reply: "回复"
        case .replyAll: "全部回复"
        case .forward: "转发"
        }
    }

    private var statusSymbol: String {
        switch viewModel.status {
        case .failed: "exclamationmark.triangle"
        case .queued, .saved: "checkmark.circle"
        case .sending, .editing: "arrow.up.circle"
        }
    }

    private var statusColor: Color {
        switch viewModel.status {
        case .failed: .red
        case .queued, .saved: .green
        case .sending, .editing: .secondary
        }
    }
}
