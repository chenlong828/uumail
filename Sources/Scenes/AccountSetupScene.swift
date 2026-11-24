import Foundation
import MailDomain
import MailStore
import SyncContract

/// What the setup form collects (architecture spec §4.7). The gateway itself is already
/// constructed for a configuration; the input exists so the scene can validate fields,
/// create the account row and write the credentials.
public struct AccountInput: Sendable {
    public var host: String
    public var account: String
    public var password: String
    public var domain: String
    public var deviceID: String
    public var displayName: String

    public init(
        host: String,
        account: String,
        password: String,
        domain: String,
        deviceID: String,
        displayName: String
    ) {
        self.host = host
        self.account = account
        self.password = password
        self.domain = domain
        self.deviceID = deviceID
        self.displayName = displayName
    }
}

/// The result of a successful `connect`: the usable account plus its folder snapshot.
public struct ConnectedAccount: Equatable, Sendable {
    public let accountID: AccountID
    public let address: String
    public let displayName: String
    public let folders: [Folder]

    public init(accountID: AccountID, address: String, displayName: String, folders: [Folder]) {
        self.accountID = accountID
        self.address = address
        self.displayName = displayName
        self.folders = folders
    }
}

/// Account onboarding: the only place that decides the order of the setup steps and how a
/// half-finished setup is rolled back (spec §4.7).
///
/// Order is fixed: probe/provision → (reuse or create account) → folder snapshot →
/// `markAccountReady` → credentials last. No credential is written unless the account is
/// usable, and a failure while this call created the account discards it again.
public struct AccountSetupScene: Sendable {
    private let gateway: any MailGateway
    private let store: MailStore
    private let credentials: any CredentialStore

    public init(gateway: any MailGateway, store: MailStore, credentials: any CredentialStore) {
        self.gateway = gateway
        self.store = store
        self.credentials = credentials
    }

    /// Checks the server without touching the database: probe plus provisioning.
    public func validate(_ input: AccountInput) async throws {
        _ = try Self.configuration(from: input)
        do {
            _ = try await gateway.probe()
            try await gateway.provisionIfNeeded()
        } catch {
            throw Self.classify(error)
        }
    }

    /// Runs the full setup and returns the ready account.
    public func connect(_ input: AccountInput) async throws -> ConnectedAccount {
        let configuration = try Self.configuration(from: input)
        let address = "\(configuration.account)@\(configuration.host)"

        do {
            _ = try await gateway.probe()
            try await gateway.provisionIfNeeded()
        } catch {
            throw Self.classify(error)
        }

        // `existingOrNewAccount` (moved out of MailService): one account per install, and a
        // repeat `connect` reuses the row instead of creating a second one.
        let accountID: AccountID
        let created: Bool
        do {
            if let existing = try store.accounts().first {
                accountID = existing
                created = false
            } else {
                accountID = try store.createAccount(
                    NewAccount(
                        displayName: configuration.displayName,
                        address: address,
                        host: configuration.host
                    )
                )
                created = true
            }
        } catch {
            throw Self.classify(error)
        }

        do {
            let listing = try await gateway.fetchFolders(syncKey: "0")
            try store.applyFolderSnapshot(
                account: accountID,
                folders: listing.folders,
                syncKey: listing.syncKey
            )
            let folders = try store.folders(account: accountID)
            try store.markAccountReady(accountID)
            // Credentials are the last write: everything before this point can still roll
            // back without leaving a Keychain entry behind.
            let stored = try store.account(accountID)
            try credentials.save(configuration)

            return ConnectedAccount(
                accountID: accountID,
                address: stored?.address ?? address,
                displayName: stored?.displayName ?? configuration.displayName,
                folders: folders
            )
        } catch {
            let failure = Self.classify(error)
            // Only an account created by this call is discarded: a reused account may hold
            // mail and belongs to a previous, working setup.
            if created {
                do {
                    try store.discardAccount(accountID)
                } catch {
                    throw MailError.storage(reason: "rollback failed: \(error)")
                }
            }
            throw failure
        }
    }

    // MARK: - Input

    /// Validates the form and maps it to the Keychain shape. Protocol fields keep the
    /// `ServerConfiguration` defaults, since the setup form from spec §4.7 does not ask
    /// for them.
    private static func configuration(from input: AccountInput) throws -> ServerConfiguration {
        let host = input.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = input.account.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = input.password
        let domain = input.domain.trimmingCharacters(in: .whitespacesAndNewlines)
        let deviceID = input.deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = input.displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !host.isEmpty else { throw MailError.invalidInput(reason: "host is empty") }
        guard !account.isEmpty else { throw MailError.invalidInput(reason: "account is empty") }
        guard !password.isEmpty else { throw MailError.invalidInput(reason: "password is empty") }
        guard !deviceID.isEmpty else { throw MailError.invalidInput(reason: "deviceID is empty") }

        return ServerConfiguration(
            host: host,
            account: account,
            password: password,
            domain: domain,
            deviceID: deviceID,
            displayName: displayName.isEmpty ? account : displayName
        )
    }

    /// Scenes hand `MailError` to callers only; store/Keychain failures become `storage`.
    private static func classify(_ error: Error) -> MailError {
        (error as? MailError) ?? .storage(reason: String(describing: error))
    }
}
