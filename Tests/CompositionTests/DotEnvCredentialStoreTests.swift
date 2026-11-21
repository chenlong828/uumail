import Foundation
import MailDomain
import Testing

@testable import Composition

@Suite("DotEnv credentials")
struct DotEnvCredentialStoreTests {
    private func makeURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("uumail-dotenv-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(".uumail.env")
    }

    private func makeDirectory(for url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    private let configuration = ServerConfiguration(
        host: "mail.corp.test",
        account: "jdoe",
        password: "s3cret",
        domain: "corp",
        deviceID: "DEVICEID0000000000000000000001",
        displayName: "jdoe"
    )

    @Test("save then load round-trips the account and locks the file to the owner")
    func roundTrip() throws {
        let url = makeURL()
        try makeDirectory(for: url)
        let store = DotEnvCredentialStore(url: url)
        defer { try? FileManager.default.removeItem(at: url) }

        try store.save(configuration)

        #expect(store.load() == configuration)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("EAS_HOST=\"mail.corp.test\""))
        #expect(text.contains("EAS_DEVICE_ID=\"DEVICEID0000000000000000000001\""))
    }

    @Test("comments, export prefixes, quotes and CRLF are accepted")
    func parsesCommonDotEnvSpellings() {
        let text = """
        # leading comment

        export EAS_HOST="mail.corp.test"
        EAS_USER='jdoe'
        EAS_PASS = "s3cret"
        EAS_DOMAIN=corp
        EAS_DEVICE_ID=DEVICEID0000000000000000000001
        UNRELATED=ignored
        """

        let values = DotEnvCredentialStore.parse(text)

        #expect(values["EAS_HOST"] == "mail.corp.test")
        #expect(values["EAS_USER"] == "jdoe")
        #expect(values["EAS_PASS"] == "s3cret")
        #expect(values["EAS_DOMAIN"] == "corp")
        #expect(values["EAS_DEVICE_ID"] == "DEVICEID0000000000000000000001")
        #expect(values["UNRELATED"] == "ignored")
    }

    @Test("missing or incomplete files load as nil so the caller can fall back to the Keychain")
    func missingOrIncompleteFileIsNil() throws {
        let url = makeURL()
        try makeDirectory(for: url)
        let store = DotEnvCredentialStore(url: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(store.load() == nil)

        try Data("EAS_HOST=mail.corp.test\nEAS_USER=jdoe\n".utf8).write(to: url)
        #expect(store.load() == nil, "a password and device id are required")
    }

    @Test("password characters that need quoting survive the round trip")
    func specialCharactersRoundTrip() throws {
        let url = makeURL()
        try makeDirectory(for: url)
        let store = DotEnvCredentialStore(url: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let tricky = ServerConfiguration(
            host: "mail.corp.test",
            account: "jdoe",
            password: "p@ss \"quoted\" \\ back",
            domain: "",
            deviceID: "DEV",
            displayName: "jdoe"
        )

        try store.save(tricky)

        #expect(store.load() == tricky)
    }
}
