import Foundation
import MailDomain
import Testing

@testable import Composition

@Suite("Configuration source")
struct ConfigurationSourceTests {
    private let debugEnvironment = [
        "UUMAIL_DEBUG_ENV": "1",
        "EAS_HOST": "mail.corp.test",
        "EAS_USER": "jdoe",
        "EAS_PASS": "secret",
        "EAS_DEVICE_ID": "DEV",
    ]

    @Test("the DEBUG environment source is recognised only when complete")
    func debugSourceDetection() {
        #if DEBUG
        #expect(ConfigurationSource.usesDebugConfiguration(debugEnvironment))
        #expect(!ConfigurationSource.usesDebugConfiguration(["UUMAIL_DEBUG_ENV": "1"]))
        #expect(!ConfigurationSource.usesDebugConfiguration([:]))
        #else
        #expect(!ConfigurationSource.usesDebugConfiguration(debugEnvironment))
        #endif
    }

    @Test("a credential store for the DEBUG source keeps the password in the process")
    func ephemeralStoreDoesNotThrow() throws {
        let configuration = ServerConfiguration(
            host: "mail.corp.test",
            account: "jdoe",
            password: "secret",
            domain: "corp",
            deviceID: "DEV",
            displayName: "J Doe"
        )
        let store = EphemeralCredentialStore(configuration: configuration)
        #expect(try store.load() == configuration)
        try store.save(configuration)
        #expect(try store.load() == configuration, "saving is a no-op on purpose")
        try store.delete()
        #expect(try store.load() == configuration)
    }

    @Test("the setup credentials fall back to the login store when the environment is not a DEBUG source")
    func setupCredentialsUseTheLoginStoreByDefault() throws {
        let configuration = makeAssemblyConfiguration()
        let login = RecordingCredentialStore()
        let chosen = ConfigurationSource.setupCredentials(
            environment: [:],
            configuration: configuration,
            credentials: login
        )
        try chosen.save(configuration)
        #expect(login.saveCalls == 1)
        #expect(login.saved == configuration)
    }

    #if DEBUG
    @Test("the DEBUG environment credentials are kept in-process, not written to the login store")
    func debugSetupCredentialsStayInProcess() throws {
        let configuration = makeAssemblyConfiguration()
        let login = RecordingCredentialStore()
        let chosen = ConfigurationSource.setupCredentials(
            environment: debugEnvironment,
            configuration: configuration,
            credentials: login
        )
        try chosen.save(configuration)
        #expect(login.saveCalls == 0, "the login Keychain must stay untouched")
        #expect(try chosen.load() == configuration)
    }
    #endif
}
