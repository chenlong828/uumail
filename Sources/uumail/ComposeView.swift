import Presentation
import SwiftUI

/// Reply/new-mail sheet: address fields, a format bar, an editable WebView and the
/// compose actions in the title bar (macOS Mail idiom: send at the top right). The sheet
/// width follows the reading pane (REQ-0021); the editor callbacks push captured HTML
/// back into the view model before any action.
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
            if let statusText = viewModel.statusText {
                statusRow(statusText)
            }
            Divider()
            ComposeRecipientForm(
                viewModel: viewModel,
                scale: fontSize.scaleFactor,
                sheetHeight: height
            ) {
                TextField("主题", text: $viewModel.subject)
            }
            .zIndex(10)
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
        }
        .frame(width: width, height: height)
        .interactiveDismissDisabled()
        .confirmationDialog(
            "存储草稿？",
            isPresented: $showingDiscard,
            titleVisibility: .visible
        ) {
            Button("存草稿") { saveAndClose() }
            Button("放弃", role: .destructive) { onClose() }
            Button("继续编辑", role: .cancel) {}
        } message: {
            Text("已输入的内容可以存为草稿，或直接放弃。")
        }
    }

    /// macOS Mail idiom: a red close control on the left, the mode title centred and one
    /// prominent blue Send button at the top right. Sending is the only toolbar action;
    /// closing asks whether to keep the draft.
    private var header: some View {
        ZStack {
            HStack {
                closeControl
                Spacer()
                composeButton("发送") { send() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!viewModel.canSend)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .help("发送（Return）")
            }
            Text(title)
                .scaledFont(.headline)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var closeControl: some View {
        Button {
            requestClose()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 13, height: 13)
                .background(Circle().fill(Color(nsColor: .systemRed)))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .focusable(false)
        .disabled(viewModel.isSending)
        .help("关闭（Esc）")
        .accessibilityLabel("关闭")
    }

    private func statusRow(_ text: String) -> some View {
        HStack(spacing: 4) {
            Label(text, systemImage: statusSymbol)
                .scaledFont(.caption)
                .foregroundStyle(statusColor)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
    }

    private func send() {
        Task {
            if let html = await editor.capture() {
                viewModel.setEditorHTML(html)
            }
            if await viewModel.send() { onClose() }
        }
    }

    private func saveAndClose() {
        if viewModel.saveDraft() { onClose() }
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
