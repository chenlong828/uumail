import Presentation
import SwiftUI

struct ComposeView: View {
    @Bindable var viewModel: ComposeViewModel
    let onClose: () -> Void
    @Environment(\.fontSizePreference) private var fontSize

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("收件人", text: $viewModel.to, prompt: Text("a@example.com"))
                TextField("抄送", text: $viewModel.cc)
                TextField("主题", text: $viewModel.subject)
            }
            .padding(12)
            Divider()
            TextEditor(text: $viewModel.body)
                .scaledInheritedFont(.body)
                .padding(8)
            Divider()
            HStack {
                if let statusText = viewModel.statusText {
                    Label(statusText, systemImage: statusSymbol)
                        .scaledFont(.caption)
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                }
                Spacer()
                saveDraftButton
                sendButton
            }
            .padding(12)
        }
        .frame(minWidth: 640, minHeight: 460)
    }

    /// A string-title button ignores the environment font. Keep the production string
    /// title at 100% (a custom label changes its height by 1pt) and scale the label
    /// explicitly above 100%.
    @ViewBuilder
    private var saveDraftButton: some View {
        if fontSize == .percent100 {
            Button("存草稿") {
                if viewModel.saveDraft() { onClose() }
            }
            .disabled(viewModel.isSending)
        } else {
            Button {
                if viewModel.saveDraft() { onClose() }
            } label: {
                Text("存草稿").font(fontSize.font(for: .body))
            }
            .disabled(viewModel.isSending)
        }
    }

    @ViewBuilder
    private var sendButton: some View {
        if fontSize == .percent100 {
            Button("发送") {
                Task {
                    if await viewModel.send() { onClose() }
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!viewModel.canSend)
        } else {
            Button {
                Task {
                    if await viewModel.send() { onClose() }
                }
            } label: {
                Text("发送").font(fontSize.font(for: .body))
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!viewModel.canSend)
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
