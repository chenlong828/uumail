import AppKit
import Composition
import Presentation
import SwiftUI

@main
struct UumailApp: App {
    @State private var composition: AppComposition?
    @State private var theme: ThemePreference
    @State private var fontSize: FontSizePreference
    private let store: ThemePreferenceStore
    private let fontStore: FontSizePreferenceStore

    init() {
        // Build the local stores first: `self` is not fully initialised yet, so the
        // preferences have to be read through local bindings.
        let store = ThemePreferenceStore()
        self.store = store
        _theme = State(initialValue: store.load())
        let fontStore = FontSizePreferenceStore()
        self.fontStore = fontStore
        _fontSize = State(initialValue: fontStore.load())
        _composition = State(initialValue: AppComposition.make())
    }

    var body: some Scene {
        WindowGroup("uumail") {
            Group {
                if let composition {
                    switch composition.route {
                    case .mailbox:
                        if let viewModel = composition.mailbox {
                            MailboxView(viewModel: viewModel, calendarModel: composition.calendar)
                        }
                    case .accountSetup:
                        AccountSetupView(viewModel: composition.accountSetup) {
                            await composition.connect()
                        }
                    }
                } else {
                    EmptyState(
                        title: "无法打开本地数据库",
                        systemImage: "externaldrive.badge.xmark",
                        description: "请检查 ~/Library/Application Support/uumail 的读写权限。"
                    )
                }
            }
            .frame(minWidth: 900, minHeight: 560)
            .environment(\.fontSizePreference, fontSize)
            // 100% installs no root font (nil resolves to the default, and a concrete
            // `.font(.body)` would shift the default two-line row 32.0 -> 31.5pt);
            // only the scaled levels install one, so default text, TextField and Form
            // inputs grow with the preference.
            .environment(\.font, fontSize == .percent100 ? nil : fontSize.font(for: .body))
            .preferredColorScheme(theme.colorScheme)
            .task { composition?.start() }
            .onDisappear { composition?.stop() }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                // The mailbox window may already be gone when the app terminates; stop the
                // refresh cadence and the delivery pump explicitly.
                composition?.stop()
            }
        }
        .commands {
            ThemeCommands(theme: $theme, store: store)
            FontSizeCommands(fontSize: $fontSize, store: fontStore)
            DeveloperCommands(canExport: composition?.hasConfiguration == true) {
                guard let composition else { return }
                do {
                    DeveloperCredentialAlert.saved(try composition.saveDevelopmentCredentials())
                } catch {
                    DeveloperCredentialAlert.failed(error)
                }
            }
        }
    }
}
