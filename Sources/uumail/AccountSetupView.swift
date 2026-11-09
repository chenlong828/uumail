import AppServices
import SwiftUI

struct AccountSetupView: View {
    let onSave: (StoredAccountConfiguration) throws -> Void

    @State private var displayName = "工作"
    @State private var host = ""
    @State private var account = ""
    @State private var password = ""
    @State private var domain = ""
    @State private var deviceID = ""
    @State private var errorMessage: String?

    private var canSave: Bool {
        !host.isEmpty && !account.isEmpty && !password.isEmpty && !deviceID.isEmpty
    }

    var body: some View {
        Form {
            Section("账号") {
                TextField("显示名", text: $displayName)
                TextField("服务器地址", text: $host, prompt: Text("mail.example.com"))
                TextField("账号（不带域）", text: $account)
                SecureField("密码", text: $password)
                TextField("域", text: $domain, prompt: Text("留空则不带域"))
            }

            Section {
                TextField("设备 ID", text: $deviceID)
                Text("必须是公司网关已登记并激活的设备 ID；未登记的设备会被网关静默丢弃。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("设备身份（高级）")
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("连接") {
                    let saved = StoredAccountConfiguration(
                        host: host.trimmingCharacters(in: .whitespaces),
                        account: account.trimmingCharacters(in: .whitespaces),
                        password: password,
                        domain: domain.trimmingCharacters(in: .whitespaces),
                        deviceID: deviceID.trimmingCharacters(in: .whitespaces),
                        displayName: displayName.isEmpty ? account : displayName
                    )
                    do {
                        try onSave(saved)
                    } catch {
                        errorMessage = String(describing: error)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .formStyle(.grouped)
        .padding(24)
    }
}
