import EASClient
import Foundation
import MailDomain
import Scenes

/// The composition roots' configuration source (spec §7): the Keychain, or — in a DEBUG
/// build only — the probe shell's environment. This chooses *where* the settings come
/// from; it makes no business decision.
enum ConfigurationSource {
    static func serverConfiguration(
        environment: [String: String],
        credentials: any CredentialStore
    ) -> ServerConfiguration? {
        #if DEBUG
        if environment["UUMAIL_DEBUG_ENV"] == "1", let debug = debugConfiguration(environment) {
            return debug
        }
        #endif
        return try? credentials.load()
    }

    static func databasePath(environment: [String: String]) -> String {
        #if DEBUG
        if environment["UUMAIL_DEBUG_ENV"] == "1", let path = environment["UUMAIL_DB_PATH"] {
            return path
        }
        #endif
        return AppPaths.databasePath
    }

    /// Whether the configuration came from the DEBUG environment instead of the Keychain.
    /// That source must not write the login Keychain (spec §7).
    static func usesDebugConfiguration(_ environment: [String: String]) -> Bool {
        #if DEBUG
        environment["UUMAIL_DEBUG_ENV"] == "1" && debugConfiguration(environment) != nil
        #else
        false
        #endif
    }

    #if DEBUG
    private static func debugConfiguration(_ environment: [String: String]) -> ServerConfiguration? {
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

    /// Both sources already carry the same fields; the setup form is the only caller that
    /// still needs the `displayName` fallback.
    static func serverConfiguration(from input: AccountInput) -> ServerConfiguration {
        ServerConfiguration(
            host: input.host,
            account: input.account,
            password: input.password,
            domain: input.domain,
            deviceID: input.deviceID,
            displayName: input.displayName.isEmpty ? input.account : input.displayName
        )
    }

    /// `ServerConfiguration` is the domain's shape; the EAS client needs its own.
    static func easConfiguration(_ configuration: ServerConfiguration) -> EASConfiguration {
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
