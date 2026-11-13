import Composition
import SwiftUI

@main
struct UumailApp: App {
    @State private var composition: AppComposition?

    init() {
        _composition = State(initialValue: AppComposition.make())
    }

    var body: some Scene {
        WindowGroup("uumail") {
            Group {
                if let composition {
                    switch composition.route {
                    case .mailbox:
                        if let viewModel = composition.mailbox {
                            MailboxView(viewModel: viewModel)
                        }
                    case .accountSetup:
                        AccountSetupView(viewModel: composition.accountSetup) {
                            await composition.connect()
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "无法打开本地数据库",
                        systemImage: "externaldrive.badge.xmark",
                        description: Text("请检查 ~/Library/Application Support/uumail 的读写权限。")
                    )
                }
            }
            .frame(minWidth: 900, minHeight: 560)
            .task { composition?.start() }
            .onDisappear { composition?.stop() }
        }
    }
}
