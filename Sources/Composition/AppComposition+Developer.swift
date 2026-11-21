import Foundation

extension AppComposition {
    /// Developer menu: mirror the saved credentials into `~/.uumail.env` so later launches
    /// skip the login Keychain prompt. Only the explicit menu action calls this.
    @discardableResult
    public func saveDevelopmentCredentials() throws -> URL {
        try saveDevelopmentCredentials(
            to: ConfigurationSource.dotEnvStore(environment: ProcessInfo.processInfo.environment)
        )
    }

    /// Test seam for the same export with an explicit file.
    @discardableResult
    public func saveDevelopmentCredentials(to store: DotEnvCredentialStore) throws -> URL {
        guard let configuration else { throw DevelopmentCredentialsError.noConfiguration }
        try store.save(configuration)
        return store.url
    }
}

/// Failures of the developer credential export (the "开发" menu item).
public enum DevelopmentCredentialsError: Error, Equatable, CustomStringConvertible {
    case noConfiguration

    public var description: String {
        switch self {
        case .noConfiguration: "当前还没有已保存的账号凭据"
        }
    }
}
