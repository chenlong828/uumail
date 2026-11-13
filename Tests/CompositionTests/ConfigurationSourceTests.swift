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
}
