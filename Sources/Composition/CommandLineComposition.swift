import EASClient
import Foundation
import MailDomain
import MailStore
import Outbox
import Scenes
import SyncEngine

/// The CLI's assembly point (spec §7): the same object graph as `AppComposition`, with the
/// database path taken from `--db` and the configuration from the environment. It reads
/// the configuration source, builds the store/scenes, and bootstraps the account row when
/// the database has none; then it gets out of the way and the commands act on the scenes.
public struct CommandLineComposition {
    public let configuration: ServerConfiguration
    public let store: MailStore
    public let account: AccountID
    public let read: ReadScene
    public let sync: SyncScene
    public let compose: ComposeScene
    public let outbox: Outbox

    // MARK: - Configuration source

    /// The CLI's settings always come from the environment (there is no Window/Keychain
    /// setup flow in a terminal). `insecure` is the `--insecure` flag.
    public static func configuration(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        insecure: Bool = false
    ) throws -> ServerConfiguration {
        func require(_ key: String) throws -> String {
            guard let value = environment[key], !value.isEmpty else {
                throw CommandLineConfigurationError.missing(key)
            }
            return value
        }
        return ServerConfiguration(
            host: try require("EAS_HOST"),
            account: try require("EAS_USER"),
            password: try require("EAS_PASS"),
            domain: environment["EAS_DOMAIN"] ?? "",
            deviceID: try require("EAS_DEVICE_ID"),
            displayName: environment["EAS_USER"] ?? "",
            allowInsecureTLS: insecure
        )
    }

    /// The diagnostic commands build an `EASClient` directly; this is the one mechanical
    /// configuration conversion they need from the composition root.
    public static func easConfiguration(_ configuration: ServerConfiguration) -> EASConfiguration {
        ConfigurationSource.easConfiguration(configuration)
    }

    // MARK: - Assembly

    /// Builds the CLI object graph for one database. A database without an account row is
    /// bootstrapped through the setup scene (one probe/provision/folder-sync round); the
    /// environment credentials are not written to the login Keychain, which belongs to the
    /// app's setup flow. `gatewayFactory` exists for assembly tests; production omits it.
    public static func make(
        databasePath: String,
        configuration: ServerConfiguration,
        gatewayFactory: GatewayFactory? = nil
    ) async throws -> CommandLineComposition {
        let store = try MailStore(path: databasePath)
        let endpoints = (gatewayFactory ?? { PlatformGateway.make($0) })(configuration)
        let gateway = endpoints.read

        let account: AccountID
        if let existing = try store.accounts().first {
            account = existing
        } else {
            let setup = AccountSetupScene(
                gateway: gateway,
                store: store,
                credentials: EphemeralCredentialStore(configuration: configuration)
            )
            account = try await setup.connect(AccountInput(configuration: configuration)).accountID
        }

        let engine = SyncEngine(gateway: gateway, store: store, account: account)
        let outbox = Outbox(store: store, gateway: gateway, clock: SystemMailClock())
        return CommandLineComposition(
            configuration: configuration,
            store: store,
            account: account,
            read: ReadScene(
                store: store,
                account: account,
                gateway: gateway,
                files: FileAttachmentFiles(directory: AppPaths.attachmentsDirectory)
            ),
            sync: SyncScene(engine: engine, notifier: SilentNotifier(), clock: SystemMailClock()),
            compose: ComposeScene(store: store, outbox: outbox),
            outbox: outbox
        )
    }
}

/// Configuration-source failures of the CLI (the app reads the Keychain instead).
public enum CommandLineConfigurationError: Error, CustomStringConvertible, Equatable {
    case missing(String)

    public var description: String {
        switch self {
        case .missing(let key): "missing environment variable \(key)"
        }
    }
}

/// A CLI has no notification surface (`UNUserNotificationCenter` needs an app bundle);
/// the setup/sync scenes only need the port.
private struct SilentNotifier: Notifier {
    func requestAuthorization() async {}
    func postNewMail(count: Int) async {}
}

private extension AccountInput {
    init(configuration: ServerConfiguration) {
        self.init(
            host: configuration.host,
            account: configuration.account,
            password: configuration.password,
            domain: configuration.domain,
            deviceID: configuration.deviceID,
            displayName: configuration.displayName
        )
    }
}
