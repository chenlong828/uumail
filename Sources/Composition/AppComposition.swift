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

/// The app's single assembly point (spec §7): reads the configuration source, builds the
/// store/gateway/outbox/scenes/platform adapters, and routes between the setup form and
/// the mailbox. It holds no business state and makes no business decisions.
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
    private let configuration: ServerConfiguration?
    @ObservationIgnored private var pump: OutboxPump?
    @ObservationIgnored private var bootstrapTask: Task<Void, Never>?
    @ObservationIgnored private var bootstrapAttempted = false

    public static func make(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> AppComposition? {
        let credentials = KeychainCredentialStore()
        let configuration = ConfigurationSource.serverConfiguration(
            environment: environment,
            credentials: credentials
        )
        // The DEBUG environment source changes where the settings come from, so its setup
        // pass must not write them into the login Keychain (spec §7).
        let setupCredentials: any CredentialStore
        if let configuration, ConfigurationSource.usesDebugConfiguration(environment) {
            setupCredentials = EphemeralCredentialStore(configuration: configuration)
        } else {
            setupCredentials = credentials
        }
        guard let store = try? MailStore(path: ConfigurationSource.databasePath(environment: environment)) else {
            return nil
        }
        return AppComposition(store: store, credentials: setupCredentials, configuration: configuration)
    }

    public init(store: MailStore, credentials: any CredentialStore, configuration: ServerConfiguration?) {
        self.store = store
        self.configuration = configuration
        let makeScene: AccountSetupSceneFactory = { input in
            Self.makeSetupScene(store: store, credentials: credentials, input: input)
        }
        accountSetup = AccountSetupViewModel(makeScene: makeScene, configuration: configuration)
        route = .accountSetup

        if let configuration, let account = (try? store.accounts())?.first {
            attachMailbox(configuration: configuration, account: account)
            route = .mailbox
        }
    }

    // MARK: - Lifecycle

    /// Starts the long-lived work: the refresh cadence and the delivery pump. A database
    /// that has credentials but no account row (fresh DB after `uumailctl seed`, or the
    /// DEBUG environment) is provisioned once by the frozen setup scene, then the mailbox
    /// opens; a failure leaves the setup page showing that scene's error text.
    public func start() {
        if mailbox != nil {
            mailbox?.startAutoRefresh()
            pump?.start()
            return
        }
        guard !bootstrapAttempted, configuration != nil else { return }
        bootstrapAttempted = true
        bootstrapTask = Task { [weak self] in
            _ = await self?.connect()
            self?.bootstrapTask = nil
        }
    }

    public func stop() {
        bootstrapTask?.cancel()
        bootstrapTask = nil
        mailbox?.stopAutoRefresh()
        pump?.stop()
    }

    // MARK: - Entry routing

    /// Account-setup entry action: the scene does the work, then the mailbox is assembled
    /// for the connected account.
    @discardableResult
    public func connect() async -> Bool {
        guard await accountSetup.connect(), let connected = accountSetup.connected else {
            return false
        }
        attachMailbox(
            configuration: ConfigurationSource.serverConfiguration(from: accountSetup.input),
            account: connected.accountID
        )
        route = .mailbox
        start()
        return true
    }

    /// Constructs one mailbox object graph. The pump is attached to the view model's
    /// enqueue hook so a send is delivered without waiting for the next tick.
    private func attachMailbox(configuration: ServerConfiguration, account: AccountID) {
        let easConfiguration = ConfigurationSource.easConfiguration(configuration)
        let client = EASClient(
            configuration: easConfiguration,
            transport: URLSessionTransport(configuration: easConfiguration)
        )
        let gateway = EASAdapter(client: client)
        let engine = SyncEngine(gateway: gateway, store: store, account: account)
        let outbox = Outbox(store: store, gateway: gateway, clock: SystemMailClock())
        let pump = OutboxPump(outbox: outbox, account: account)
        mailbox = MailboxViewModel(
            read: ReadScene(
                store: store,
                account: account,
                gateway: gateway,
                files: FileAttachmentFiles(directory: AppPaths.attachmentsDirectory)
            ),
            sync: SyncScene(engine: engine, notifier: SystemNotifier(), clock: SystemMailClock()),
            compose: ComposeScene(store: store, outbox: outbox),
            account: account,
            onEnqueued: { pump.signal() }
        )
        self.pump = pump
    }

    private nonisolated static func makeSetupScene(
        store: MailStore,
        credentials: any CredentialStore,
        input: AccountInput
    ) -> AccountSetupScene {
        let configuration = ConfigurationSource.easConfiguration(
            ConfigurationSource.serverConfiguration(from: input)
        )
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
}

