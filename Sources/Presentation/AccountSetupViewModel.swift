import Foundation
import MailDomain
import Observation
import Scenes

/// Builds an `AccountSetupScene` for the configuration the form currently describes.
/// The composition root supplies it; the view model never sees a gateway or a store.
public typealias AccountSetupSceneFactory = @Sendable (AccountInput) -> AccountSetupScene

/// Setup form state (spec §4.11): fields, busy flag, the single error text and the
/// connected account. The scene owns validation, ordering and rollback.
@MainActor
@Observable
public final class AccountSetupViewModel {
    public var displayName: String
    /// From address; empty falls back to account@host at connect time.
    public var email: String
    public var host: String
    public var account: String
    public var password: String
    public var domain: String
    public var deviceID: String

    public private(set) var isBusy = false
    public private(set) var errorText: String?
    public private(set) var connected: ConnectedAccount?

    private let makeScene: AccountSetupSceneFactory

    /// - Parameter configuration: pre-fills the form (Keychain config that has no local
    ///   account row yet, or a re-connect after a credential change).
    public init(
        makeScene: @escaping AccountSetupSceneFactory,
        configuration: ServerConfiguration? = nil
    ) {
        self.makeScene = makeScene
        displayName = configuration?.displayName ?? "工作"
        email = configuration?.email ?? ""
        host = configuration?.host ?? ""
        account = configuration?.account ?? ""
        password = configuration?.password ?? ""
        domain = configuration?.domain ?? ""
        deviceID = configuration?.deviceID ?? ""
    }

    public var canConnect: Bool {
        !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
            && !deviceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isBusy
    }

    /// The form fields as the scene's input shape.
    public var input: AccountInput {
        let trimmedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDisplay = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return AccountInput(
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            account: trimmedAccount,
            password: password,
            domain: domain.trimmingCharacters(in: .whitespacesAndNewlines),
            deviceID: deviceID.trimmingCharacters(in: .whitespacesAndNewlines),
            displayName: trimmedDisplay.isEmpty ? trimmedAccount : trimmedDisplay,
            email: email.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    // MARK: - Actions

    /// Probes the server without writing anything; `true` when the settings are usable.
    @discardableResult
    public func validate() async -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        errorText = nil
        defer { isBusy = false }
        do {
            try await makeScene(input).validate(input)
            return true
        } catch {
            errorText = ErrorText.text(for: error)
            return false
        }
    }

    /// Runs the full setup. On success the scene has created the account, snapshot and
    /// credentials; the routing hook then builds the mailbox.
    @discardableResult
    public func connect() async -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        errorText = nil
        defer { isBusy = false }
        do {
            connected = try await makeScene(input).connect(input)
            return true
        } catch {
            connected = nil
            errorText = ErrorText.text(for: error)
            return false
        }
    }
}
