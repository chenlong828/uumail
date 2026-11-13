import Presentation
import SwiftUI

struct ComposeView: View {
    @Bindable var viewModel: ComposeViewModel
    let onClose: () -> Void

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
                .font(.body)
                .padding(8)
            Divider()
            HStack {
                if let statusText = viewModel.statusText {
                    Label(statusText, systemImage: statusSymbol)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                }
                Spacer()
                Button("存草稿") {
                    if viewModel.saveDraft() { onClose() }
                }
                .disabled(viewModel.isSending)
                Button("发送") {
                    Task {
                        if await viewModel.send() { onClose() }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.canSend)
            }
            .padding(12)
        }
        .frame(minWidth: 640, minHeight: 460)
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
