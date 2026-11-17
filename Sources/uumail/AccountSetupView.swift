import Presentation
import SwiftUI

struct AccountSetupView: View {
    @Bindable var viewModel: AccountSetupViewModel
    let onConnect: () async -> Void
    @Environment(\.fontSizePreference) private var fontSize

    var body: some View {
        Form {
            Section("账号") {
                TextField("显示名", text: $viewModel.displayName)
                TextField("服务器地址", text: $viewModel.host, prompt: Text("mail.example.com"))
                TextField("账号（不带域）", text: $viewModel.account)
                SecureField("密码", text: $viewModel.password)
                TextField("域", text: $viewModel.domain, prompt: Text("留空则不带域"))
            }

            Section {
                TextField("设备 ID", text: $viewModel.deviceID)
                Text("必须是公司网关已登记并激活的设备 ID；未登记的设备会被网关静默丢弃。")
                    .scaledFont(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("设备身份（高级）")
            }

            if let errorText = viewModel.errorText {
                Text(errorText)
                    .scaledFont(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                if viewModel.isBusy {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                connectButton
            }
        }
        .formStyle(.grouped)
        .padding(24)
    }

    /// The string-title button ignores the environment font; keep it at 100% and scale
    /// the label explicitly above 100%.
    @ViewBuilder
    private var connectButton: some View {
        if fontSize == .percent100 {
            Button("连接") {
                Task { await onConnect() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!viewModel.canConnect)
        } else {
            Button {
                Task { await onConnect() }
            } label: {
                Text("连接").font(fontSize.font(for: .body))
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!viewModel.canConnect)
        }
    }
}
