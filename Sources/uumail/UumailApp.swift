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
                        .task { await model.refresh() }
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
        model = MailboxModel(service: service)
    }

    private static func restoreModel() -> MailboxModel? {
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
        return MailboxModel(service: service)
    }
}
