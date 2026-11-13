import Presentation
import SwiftUI

struct AccountSetupView: View {
    @Bindable var viewModel: AccountSetupViewModel
    let onConnect: () async -> Void

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
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("设备身份（高级）")
            }

            if let errorText = viewModel.errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                if viewModel.isBusy {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Button("连接") {
                    Task { await onConnect() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.canConnect)
            }
        }
        .formStyle(.grouped)
        .padding(24)
    }
}
