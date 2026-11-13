import Foundation
import MailDomain

/// Credentials that live only for this process: the CLI's settings come from the
/// environment, and the DEBUG environment source must not write the login Keychain
/// (spec §7: `UUMAIL_DEBUG_ENV` changes the configuration *source* only).
struct EphemeralCredentialStore: CredentialStore {
    let configuration: ServerConfiguration

    func load() throws -> ServerConfiguration? { configuration }
    func save(_ configuration: ServerConfiguration) throws {}
    func delete() throws {}
}
