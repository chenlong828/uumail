import AppKit
import SwiftUI

/// Developer-only escape hatch for the ad-hoc-signed local build: writing the login
/// credentials to `~/.uumail.env` keeps the Keychain ACL prompt out of every rebuild.
/// Normal users never see this file unless they pick the menu item themselves.
struct DeveloperCommands: Commands {
    let canExport: Bool
    let export: () -> Void

    var body: some Commands {
        CommandMenu("开发") {
            Button("保存凭据到 ~/.uumail.env") { export() }
                .disabled(!canExport)
        }
    }
}

@MainActor
enum DeveloperCredentialAlert {
    static func saved(_ url: URL) {
        present(
            title: "凭据已保存",
            message: "已写入 \(url.path)。下次启动将优先读取该文件，不再访问登录钥匙串。"
        )
    }

    static func failed(_ error: Error) {
        present(
            title: "保存失败",
            message: "未能写入 ~/.uumail.env：\(error)"
        )
    }

    private static func present(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
