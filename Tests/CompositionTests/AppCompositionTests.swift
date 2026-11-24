import EASAdapter
import Foundation
import MailDomain
import MailStore
import Presentation
import Testing

@testable import Composition

/// Assembly smoke (spec §7/§8): build the real object graph with a fake gateway, an
/// in-memory store and an in-memory credential store. Business rules stay in the
/// `ScenesTests`/`PresentationTests`; here only routing, bootstrap and lifecycle.
@Suite("App composition")
@MainActor
struct AppCompositionTests {
    @Test("an account row plus configuration routes to the mailbox without touching the gateway")
    func accountRowRoutesToMailbox() async throws {
        let store = try makeAssemblyStore(withAccountRow: true)
        let gateway = AssemblyGateway(folders: makeFolderListing(), deltas: makeSyncDeltas())
        let composition = AppComposition(
            store: store,
            credentials: RecordingCredentialStore(saved: makeAssemblyConfiguration()),
            configuration: makeAssemblyConfiguration(),
            gatewayFactory: makeGatewayFactory(gateway),
            notifier: RecordingNotifier()
        )

        let calls = await gateway.calls
        #expect(composition.route == .mailbox)
        #expect(composition.mailbox != nil)
        #expect(calls.isEmpty, "assembly must not call the gateway")
        composition.stop()
    }

    @Test("a completed setup keeps the configuration so the developer export works before a restart")
    func setupEnablesDeveloperExport() async throws {
        let store = try makeAssemblyStore()
        let gateway = AssemblyGateway(folders: makeFolderListing(), deltas: makeSyncDeltas())
        let composition = AppComposition(
            store: store,
            credentials: RecordingCredentialStore(),
            configuration: nil,
            gatewayFactory: makeGatewayFactory(gateway),
            notifier: RecordingNotifier()
        )
        composition.accountSetup.host = "mail.corp.test"
        composition.accountSetup.account = "jdoe"
        composition.accountSetup.password = "secret"
        composition.accountSetup.deviceID = "DEVICEID0000000000000000000001"
        #expect(composition.hasConfiguration == false)

        #expect(await composition.connect())

        #expect(composition.hasConfiguration == true)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("uumail-export-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(".uumail.env")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }
        let written = try composition.saveDevelopmentCredentials(to: DotEnvCredentialStore(url: url))

        #expect(written == url)
        #expect(DotEnvCredentialStore(url: url).load()?.account == "jdoe")
        #expect(DotEnvCredentialStore(url: url).load()?.deviceID == "DEVICEID0000000000000000000001")
        composition.stop()
    }

    @Test("a database without an account row starts on the setup page")
    func noAccountRowRoutesToSetup() async throws {
        let store = try makeAssemblyStore()
        let gateway = AssemblyGateway()
        let composition = AppComposition(
            store: store,
            credentials: RecordingCredentialStore(saved: makeAssemblyConfiguration()),
            configuration: makeAssemblyConfiguration(),
            gatewayFactory: makeGatewayFactory(gateway),
            notifier: RecordingNotifier()
        )

        #expect(composition.route == .accountSetup)
        #expect(composition.mailbox == nil)
        #expect(composition.accountSetup.host == "mail.corp.test", "the form is pre-filled from the stored configuration")
        let calls = await gateway.calls
        #expect(calls.isEmpty)
    }

    @Test("a fresh database with a stored configuration connects through the setup scene and opens the mailbox")
    func bootstrapFromStoredConfiguration() async throws {
        let store = try makeAssemblyStore()
        let gateway = AssemblyGateway(folders: makeFolderListing(), deltas: makeSyncDeltas())
        let configuration = makeAssemblyConfiguration()
        let credentials = RecordingCredentialStore()
        let composition = AppComposition(
            store: store,
            credentials: credentials,
            configuration: configuration,
            gatewayFactory: makeGatewayFactory(gateway),
            notifier: RecordingNotifier()
        )
        #expect(composition.route == .accountSetup)
        #expect(composition.mailbox == nil)

        composition.start()
        try await waitUntil { composition.route == .mailbox }

        #expect(composition.mailbox != nil)
        let accounts = try store.accounts()
        #expect(accounts.count == 1)
        let account = try #require(accounts.first)
        #expect(try store.account(account)?.address == "jdoe@mail.corp.test")
        #expect(credentials.saveCalls == 1)
        #expect(credentials.saved == configuration)
        let probeCalls = await gateway.probeCalls
        #expect(probeCalls == 1)

        // start/stop are idempotent: a second start must not add another pump or cadence.
        composition.start()
        composition.start()

        let compose = try #require(composition.mailbox?.composeNew())
        compose.to = "a@b.c"
        compose.subject = "hi"
        compose.body = "text"
        let enqueued = await compose.send()
        #expect(enqueued)
        try await waitUntil { try store.outbox.pendingOutbox(account: account).isEmpty }
        let sendCalls = await gateway.sendCalls
        #expect(sendCalls == 1, "the pump delivers each queued row exactly once")

        composition.stop()
        composition.stop()
        #expect(composition.route == .mailbox)
    }

    @Test("a failed bootstrap stays on the setup page and shows the scene's error text")
    func bootstrapFailureShowsSetupError() async throws {
        let store = try makeAssemblyStore()
        let gateway = AssemblyGateway(probeError: .authFailed)
        let credentials = RecordingCredentialStore()
        let composition = AppComposition(
            store: store,
            credentials: credentials,
            configuration: makeAssemblyConfiguration(),
            gatewayFactory: makeGatewayFactory(gateway),
            notifier: RecordingNotifier()
        )

        composition.start()
        try await waitUntil { composition.accountSetup.errorText != nil }

        #expect(composition.route == .accountSetup)
        #expect(composition.mailbox == nil)
        #expect(composition.accountSetup.errorText == ErrorText.text(for: .authFailed))
        #expect(try store.accounts().isEmpty, "a failed setup leaves no account row")
        #expect(credentials.saveCalls == 0, "a failed setup writes no credentials")
        let probeCalls = await gateway.probeCalls
        let provisionCalls = await gateway.provisionCalls
        #expect(probeCalls == 1)
        #expect(provisionCalls == 0)

        // The bootstrap is attempted once; a later start does not retry it.
        composition.start()
        let retriedProbeCalls = await gateway.probeCalls
        let retriedProvisionCalls = await gateway.provisionCalls
        #expect(retriedProbeCalls == 1)
        #expect(retriedProvisionCalls == 0)
        composition.stop()
    }

    @Test("production endpoints expose the same EASAdapter on read and write")
    func productionEndpointsUseAdapterForBothPorts() {
        let endpoints = PlatformGateway.make(makeAssemblyConfiguration())
        #expect(endpoints.read is EASAdapter)
        #expect(endpoints.write is EASAdapter, "the write port is non-optional and production-backed")
    }

    @Test("without a stored configuration the app stays on the setup page and makes no call")
    func missingConfigurationDoesNothing() async throws {
        let store = try makeAssemblyStore()
        let gateway = AssemblyGateway()
        let composition = AppComposition(
            store: store,
            credentials: RecordingCredentialStore(),
            configuration: nil,
            gatewayFactory: makeGatewayFactory(gateway),
            notifier: RecordingNotifier()
        )

        composition.start()
        #expect(composition.route == .accountSetup)
        #expect(composition.mailbox == nil)
        let calls = await gateway.calls
        #expect(calls.isEmpty)
        #expect(try store.accounts().isEmpty)
        composition.stop()
    }
}
