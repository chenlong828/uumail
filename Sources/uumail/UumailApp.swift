import AppServices
import EASClient
import SwiftUI

@main
struct UumailApp: App {
    @State private var model: MailboxModel?
    @State private var accountStore = KeychainAccountStore()

    init() {
        _model = State(initialValue: Self.restoreModel())
    }

    var body: some Scene {
        WindowGroup("uumail") {
            Group {
                if let model {
                    MailboxView(model: model)
                        .task {
                            await model.refresh()
                            // Ping is unsupported by the gateway (always Status=4), so the
                            // client polls. Five minutes keeps the session cheap.
                            while !Task.isCancelled {
                                try? await Task.sleep(for: .seconds(300))
                                await model.refresh()
                            }
                        }
                } else {
                    AccountSetupView { saved in
                        try apply(saved)
                    }
                }
            }
            .frame(minWidth: 900, minHeight: 560)
        }
    }

    private func apply(_ saved: StoredAccountConfiguration) throws {
        try accountStore.save(saved)
        let configuration = EASConfiguration(
            host: saved.host,
            account: saved.account,
            password: saved.password,
            domain: saved.domain,
            deviceID: saved.deviceID
        )
        let service = try MailService(
            configuration: configuration,
            databasePath: MailService.defaultDatabasePath()
        )
        model = MailboxModel(service: service, notifier: SystemNotificationPoster())
    }

    private static func restoreModel() -> MailboxModel? {
        #if DEBUG
        // Debug-only: start against the env supplied by the probe shell, so the UI can be
        // exercised without writing the password into the Keychain. Release builds never
        // take this path.
        if ProcessInfo.processInfo.environment["UUMAIL_DEBUG_ENV"] == "1",
           let configuration = debugConfiguration() {
            let databasePath = ProcessInfo.processInfo.environment["UUMAIL_DB_PATH"]
                ?? MailService.defaultDatabasePath()
            let service = try? MailService(
                configuration: configuration,
                databasePath: databasePath
            )
            return service.map { MailboxModel(service: $0) }
        }
        #endif
        guard let saved = try? KeychainAccountStore().load() else { return nil }
        let configuration = EASConfiguration(
            host: saved.host,
            account: saved.account,
            password: saved.password,
            domain: saved.domain,
            deviceID: saved.deviceID
        )
        guard let service = try? MailService(
            configuration: configuration,
            databasePath: MailService.defaultDatabasePath()
        ) else {
            return nil
        }
        return MailboxModel(service: service, notifier: SystemNotificationPoster())
    }

    #if DEBUG
    private static func debugConfiguration() -> EASConfiguration? {
        let env = ProcessInfo.processInfo.environment
        guard let host = env["EAS_HOST"], let account = env["EAS_USER"],
              let password = env["EAS_PASS"], let deviceID = env["EAS_DEVICE_ID"]
        else { return nil }
        return EASConfiguration(
            host: host,
            account: account,
            password: password,
            domain: env["EAS_DOMAIN"] ?? "",
            deviceID: deviceID
        )
    }
    #endif
}
