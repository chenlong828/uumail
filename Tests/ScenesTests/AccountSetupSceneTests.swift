import Foundation
import MailDomain
import MailStore
import Testing

@testable import Scenes

private let folderListing = FolderListing(folders: [inboxFolder, draftsFolder], syncKey: "7")

/// Records what the store looked like at the moment credentials were written, so the test
/// can prove credentials are the last step instead of trusting call order alone.
private final class SaveProbe: @unchecked Sendable {
    var accountCount: Int?
    var folderCount: Int?
    var failure: Error?
}

@Suite("AccountSetupScene")
struct AccountSetupSceneTests {
    @Test("connect probes, provisions, snapshots folders, marks ready and saves credentials last")
    func connectOrder() async throws {
        let store = try MailStore.inMemory()
        let gateway = FakeGateway(folders: folderListing)
        let credentials = FakeCredentialStore()
        let probe = SaveProbe()
        credentials.onSave = { _ in
            do {
                let accounts = try store.accounts()
                probe.accountCount = accounts.count
                probe.folderCount = try accounts.first.map { try store.folders(account: $0).count }
            } catch {
                probe.failure = error
            }
        }
        let scene = AccountSetupScene(gateway: gateway, store: store, credentials: credentials)

        let connected = try await scene.connect(makeAccountInput())

        #expect(await gateway.calls == [.probe, .provision, .folders(syncKey: "0")])
        #expect(connected.address == "jdoe@mail.corp.test")
        #expect(connected.displayName == "J Doe")
        #expect(connected.folders.map(\.serverID) == ["13", "4"])
        #expect(try store.accounts() == [connected.accountID])
        #expect(credentials.saveCalls == 1)
        #expect(credentials.saved?.host == "mail.corp.test")
        #expect(credentials.saved?.deviceID == "device-1")
        // Credentials are written only after the folder snapshot has landed.
        #expect(probe.failure == nil)
        #expect(probe.accountCount == 1)
        #expect(probe.folderCount == 2)
    }

    @Test("an explicit email replaces the account@host From address")
    func explicitEmail() async throws {
        let store = try MailStore.inMemory()
        let existing = try store.createAccount(
            NewAccount(displayName: "J Doe", address: "jdoe@mail.corp.test", host: "mail.corp.test")
        )
        let scene = AccountSetupScene(
            gateway: FakeGateway(folders: folderListing),
            store: store,
            credentials: FakeCredentialStore()
        )

        let connected = try await scene.connect(makeAccountInput(email: "jdoe@corp.test"))

        #expect(connected.address == "jdoe@corp.test")
        #expect(try store.account(existing)?.address == "jdoe@corp.test")
    }

    @Test("validate probes and provisions without writing the database or credentials")
    func validateDoesNotWrite() async throws {
        let store = try MailStore.inMemory()
        let gateway = FakeGateway(folders: folderListing)
        let credentials = FakeCredentialStore()
        let scene = AccountSetupScene(gateway: gateway, store: store, credentials: credentials)

        try await scene.validate(makeAccountInput())

        #expect(await gateway.calls == [.probe, .provision])
        #expect(try store.accounts().isEmpty)
        #expect(credentials.saveCalls == 0)
    }

    @Test("empty required fields are rejected before any network call")
    func rejectsEmptyFields() async throws {
        let store = try MailStore.inMemory()
        let gateway = FakeGateway(folders: folderListing)
        let scene = AccountSetupScene(gateway: gateway, store: store, credentials: FakeCredentialStore())

        await expectMailError(.invalidInput(reason: "host is empty")) {
            try await scene.validate(makeAccountInput(host: " "))
        }
        #expect(await gateway.calls.isEmpty)
    }

    @Test("a folder-sync failure discards the new account and saves no credentials")
    func rollsBackOnFolderFailure() async throws {
        let store = try MailStore.inMemory()
        let gateway = FakeGateway(folders: folderListing, folderError: .offline)
        let credentials = FakeCredentialStore()
        let scene = AccountSetupScene(gateway: gateway, store: store, credentials: credentials)

        await expectMailError(.offline) {
            _ = try await scene.connect(makeAccountInput())
        }

        #expect(try store.accounts().isEmpty, "the half-configured account must be discarded")
        #expect(credentials.saveCalls == 0, "credentials are the last step, so none were written")
    }

    @Test("a repeat connect reuses the existing account row")
    func reusesExistingAccount() async throws {
        let store = try MailStore.inMemory()
        let existing = try store.createAccount(
            NewAccount(displayName: "old", address: "old@corp.test", host: "mail.corp.test")
        )
        let gateway = FakeGateway(folders: folderListing)
        let scene = AccountSetupScene(gateway: gateway, store: store, credentials: FakeCredentialStore())

        let connected = try await scene.connect(makeAccountInput())

        #expect(connected.accountID == existing)
        #expect(try store.accounts() == [existing])
        #expect(connected.address == "old@corp.test", "the stored row is reported back")
        #expect(try store.folders(account: existing).count == 2)
    }

    @Test("a failure while reusing an account keeps that account and its data")
    func keepsReusedAccountOnFailure() async throws {
        let store = try MailStore.inMemory()
        let existing = try store.createAccount(
            NewAccount(displayName: "old", address: "old@corp.test", host: "mail.corp.test")
        )
        let gateway = FakeGateway(folders: folderListing, folderError: .offline)
        let scene = AccountSetupScene(gateway: gateway, store: store, credentials: FakeCredentialStore())

        await expectMailError(.offline) {
            _ = try await scene.connect(makeAccountInput())
        }

        #expect(try store.accounts() == [existing], "rollback only discards an account this call created")
    }
}
