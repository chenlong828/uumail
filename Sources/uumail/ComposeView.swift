import AppServices
import SwiftUI

struct ComposeView: View {
    @Bindable var compose: ComposeModel
    let service: any MailSendService
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("收件人", text: $compose.to, prompt: Text("a@example.com"))
                TextField("抄送", text: $compose.cc)
                TextField("主题", text: $compose.subject)
            }
            .padding(12)
            Divider()
            TextEditor(text: $compose.body)
                .font(.body)
                .padding(8)
            Divider()
            HStack {
                if case .failed(let message) = compose.state {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
                if compose.state == .sent {
                    Label("已发送", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                Spacer()
                Button("存草稿") {
                    compose.saveDraft(using: service)
                    onClose()
                }
                .disabled(compose.state == .sending)
                Button("发送") {
                    Task {
                        await compose.send(using: service)
                        if compose.state == .sent { onClose() }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!compose.canSend)
            }
            .padding(12)
        }
        .frame(minWidth: 640, minHeight: 460)
    }
}
