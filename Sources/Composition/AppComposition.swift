import EASAdapter
import EASClient
import Foundation
import MailDomain
import MailStore
import Observation
import Outbox
import Presentation
import Scenes
import SyncEngine

/// The app's single assembly point (spec §7): reads the configuration source, builds
/// the store/gateway/outbox/scenes/platform adapters, and routes between the setup form
/// and the mailbox. It holds no business state and makes no business decisions.
@MainActor
@Observable
public final class AppComposition {
    public enum Route: Equatable, Sendable {
        case accountSetup
        case mailbox
    }

    public private(set) var route: Route
    public private(set) var mailbox: MailboxViewModel?
    public let accountSetup: AccountSetupViewModel

    private let store: MailStore

    public static func make(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AppComposition? {
        let credentials = KeychainCredentialStore()
        let configuration = configuration(environment: environment, credentials: credentials)
        guard let store = try? MailStore(path: databasePath(environment: environment)) else {
            return nil
        }
        return AppComposition(store: store, credentials: credentials, configuration: configuration)
    }

    public init(store: MailStore, credentials: any CredentialStore, configuration: ServerConfiguration?) {
        self.store = store
        let makeScene: AccountSetupSceneFactory = { input in
            Self.makeSetupScene(store: store, credentials: credentials, input: input)
        }
        accountSetup = AccountSetupViewModel(makeScene: makeScene, configuration: configuration)

        if let configuration, let account = (try? store.accounts())?.first {
            mailbox = Self.makeMailbox(store: store, configuration: configuration, account: account)
            route = .mailbox
        } else {
            mailbox = nil
            route = .accountSetup
        }
    }

    /// Lifecycle: the mailbox view model owns the loop, the composition starts/stops it.
    public func start() {
        mailbox?.startAutoRefresh()
    }

    public func stop() {
        mailbox?.stopAutoRefresh()
    }

    /// Account-setup entry action: the scene does the work, then the mailbox is assembled
    /// for the connected account.
    @discardableResult
    public func connect() async -> Bool {
        guard await accountSetup.connect(), let connected = accountSetup.connected else {
            return false
        }
        let configuration = Self.serverConfiguration(from: accountSetup.input)
        mailbox = Self.makeMailbox(store: store, configuration: configuration, account: connected.accountID)
        route = .mailbox
        start()
        return true
    }

    // MARK: - Assembly

    private static func makeMailbox(
        store: MailStore,
        configuration: ServerConfiguration,
        account: AccountID
    ) -> MailboxViewModel {
        let easConfiguration = easConfiguration(configuration)
        let client = EASClient(
            configuration: easConfiguration,
            transport: URLSessionTransport(configuration: easConfiguration)
        )
        let gateway = EASAdapter(client: client)
        let engine = SyncEngine(gateway: gateway, store: store, account: account)
        let outbox = Outbox(store: store, gateway: gateway, clock: SystemMailClock())
        let syncScene = SyncScene(engine: engine, notifier: SystemNotifier(), clock: SystemMailClock())
        let readScene = ReadScene(
            store: store,
            account: account,
            gateway: gateway,
            files: FileAttachmentFiles(directory: AppPaths.attachmentsDirectory)
        )
        let composeScene = ComposeScene(store: store, outbox: outbox)
        return MailboxViewModel(
            read: readScene,
            sync: syncScene,
            compose: composeScene,
            account: account
        )
    }

    private nonisolated static func makeSetupScene(
        store: MailStore,
        credentials: any CredentialStore,
        input: AccountInput
    ) -> AccountSetupScene {
        let configuration = easConfiguration(serverConfiguration(from: input))
        let client = EASClient(
            configuration: configuration,
            transport: URLSessionTransport(configuration: configuration)
        )
        return AccountSetupScene(
            gateway: EASAdapter(client: client),
            store: store,
            credentials: credentials
        )
    }

    // MARK: - Configuration source (the single environment branch)

    private nonisolated static func configuration(
        environment: [String: String],
        credentials: any CredentialStore
    ) -> ServerConfiguration? {
        #if DEBUG
        // Debug-only: the probe shell supplies the configuration through the environment
        // so the UI can run without writing the password into the Keychain.
        if environment["UUMAIL_DEBUG_ENV"] == "1",
           let debug = debugConfiguration(environment) {
            return debug
        }
        #endif
        return try? credentials.load()
    }

    private nonisolated static func databasePath(environment: [String: String]) -> String {
        #if DEBUG
        if environment["UUMAIL_DEBUG_ENV"] == "1",
           let path = environment["UUMAIL_DB_PATH"] {
            return path
        }
        #endif
        return AppPaths.databasePath
    }

    #if DEBUG
    private nonisolated static func debugConfiguration(_ environment: [String: String]) -> ServerConfiguration? {
        guard let host = environment["EAS_HOST"],
              let account = environment["EAS_USER"],
              let password = environment["EAS_PASS"],
              let deviceID = environment["EAS_DEVICE_ID"]
        else { return nil }
        return ServerConfiguration(
            host: host,
            account: account,
            password: password,
            domain: environment["EAS_DOMAIN"] ?? "",
            deviceID: deviceID,
            displayName: account
        )
    }
    #endif

    private nonisolated static func serverConfiguration(from input: AccountInput) -> ServerConfiguration {
        ServerConfiguration(
            host: input.host,
            account: input.account,
            password: input.password,
            domain: input.domain,
            deviceID: input.deviceID,
            displayName: input.displayName.isEmpty ? input.account : input.displayName
        )
    }

    private nonisolated static func easConfiguration(_ configuration: ServerConfiguration) -> EASConfiguration {
        EASConfiguration(
            host: configuration.host,
            account: configuration.account,
            password: configuration.password,
            domain: configuration.domain,
            deviceID: configuration.deviceID,
            deviceType: configuration.deviceType,
            protocolVersion: configuration.protocolVersion,
            allowInsecureTLS: configuration.allowInsecureTLS
        )
    }
}
