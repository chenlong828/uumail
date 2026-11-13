import Foundation
import MailDomain
import MailStore
import Scenes
import Testing

import Presentation

@Suite("AccountSetupViewModel")
@MainActor
struct AccountSetupViewModelTests {
    private func makeViewModel(
        gateway: PresentationFakeGateway,
        store: MailStore,
        credentials: PresentationFakeCredentialStore
    ) -> AccountSetupViewModel {
        AccountSetupViewModel(makeScene: { _ in
            AccountSetupScene(gateway: gateway, store: store, credentials: credentials)
        })
    }

    private func fill(_ viewModel: AccountSetupViewModel) {
        viewModel.host = "mail.corp.test"
        viewModel.account = "jdoe"
        viewModel.password = "secret"
        viewModel.domain = "corp"
        viewModel.deviceID = "device-1"
        viewModel.displayName = "J Doe"
    }

    @Test("connect provisions the account and does not stay busy")
    func connectSucceeds() async throws {
        let store = try MailStore.inMemory()
        let gateway = PresentationFakeGateway(
            folders: FolderListing(folders: [presentationInbox], syncKey: "7")
        )
        let credentials = PresentationFakeCredentialStore()
        let viewModel = makeViewModel(gateway: gateway, store: store, credentials: credentials)
        fill(viewModel)

        let connected = await viewModel.connect()

        #expect(connected)
        #expect(viewModel.connected != nil)
        #expect(viewModel.isBusy == false)
        #expect(viewModel.errorText == nil)
        #expect(credentials.saveCalls == 1)
        #expect(try store.accounts().count == 1)
        #expect(try store.folders(account: try #require(viewModel.connected?.accountID)).count == 1)
    }

    @Test("a failed connect shows the mapped error and leaves no account behind")
    func connectFailure() async throws {
        let store = try MailStore.inMemory()
        let gateway = PresentationFakeGateway(
            folders: FolderListing(folders: [presentationInbox], syncKey: "7")
        )
        gateway.probeError = .deviceNotRegistered
        let credentials = PresentationFakeCredentialStore()
        let viewModel = makeViewModel(gateway: gateway, store: store, credentials: credentials)
        fill(viewModel)

        let connected = await viewModel.connect()

        #expect(!connected)
        #expect(viewModel.connected == nil)
        #expect(viewModel.isBusy == false)
        #expect(viewModel.errorText == ErrorText.text(for: .deviceNotRegistered))
        #expect(try store.accounts().isEmpty)
        #expect(credentials.saveCalls == 0)
    }

    @Test("validate probes without creating an account or writing credentials")
    func validateDoesNotWrite() async throws {
        let store = try MailStore.inMemory()
        let gateway = PresentationFakeGateway(
            folders: FolderListing(folders: [presentationInbox], syncKey: "7")
        )
        let credentials = PresentationFakeCredentialStore()
        let viewModel = makeViewModel(gateway: gateway, store: store, credentials: credentials)
        fill(viewModel)

        let valid = await viewModel.validate()

        #expect(valid)
        #expect(viewModel.errorText == nil)
        #expect(try store.accounts().isEmpty)
        #expect(credentials.saveCalls == 0)
    }

    @Test("a failed validate reports the mapped error text")
    func validateFailure() async throws {
        let store = try MailStore.inMemory()
        let gateway = PresentationFakeGateway(
            folders: FolderListing(folders: [presentationInbox], syncKey: "7")
        )
        gateway.probeError = .authFailed
        let viewModel = makeViewModel(
            gateway: gateway,
            store: store,
            credentials: PresentationFakeCredentialStore()
        )
        fill(viewModel)

        let valid = await viewModel.validate()

        #expect(!valid)
        #expect(viewModel.errorText == ErrorText.text(for: .authFailed))
        #expect(viewModel.isBusy == false)
    }
}
