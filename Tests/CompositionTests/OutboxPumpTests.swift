import Foundation
import MailDomain
import MailStore
import Outbox
import Testing
import SyncContract

@testable import Composition

private actor PumpGateway: MailGateway {
    private(set) var clientIDs: [String] = []

    func probe() async throws -> ServerCapabilities { throw MailError.unsupported }
    func provisionIfNeeded() async throws { throw MailError.unsupported }
    func fetchFolders(syncKey: String) async throws -> FolderListing { throw MailError.unsupported }
    func fetchMessages(collectionID: String, syncKey: String, window: Int, filterType: Int) async throws -> MessageDelta {
        throw MailError.unsupported
    }
    func fetchBody(collectionID: String, serverID: String) async throws -> FetchedBody { throw MailError.unsupported }
    func fetchAttachment(fileReference: String) async throws -> Data { throw MailError.unsupported }

    func send(mime: Data, clientID: String) async throws {
        clientIDs.append(clientID)
    }
}

/// The send timeout must not fire during the test, so its sleep suspends for an hour.
private struct PumpClock: MailClock {
    var now: Date { Date(timeIntervalSince1970: 1_700_000_000) }
    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: .seconds(3600))
    }
}

@MainActor
private func waitUntil(
    timeout: Duration = .seconds(2),
    _ condition: () throws -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if try condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("condition was not met before the timeout")
}

@Suite("Outbox pump")
@MainActor
struct OutboxPumpTests {
    private func fixture() throws -> (MailStore, AccountID, PumpGateway, Outbox) {
        let store = try MailStore.inMemory()
        let account = try store.createAccount(
            NewAccount(displayName: "jdoe", address: "jdoe@corp.test", host: "mail.corp.test")
        )
        let gateway = PumpGateway()
        let outbox = Outbox(store: store, gateway: gateway, clock: PumpClock())
        return (store, account, gateway, outbox)
    }

    @Test("start delivers a row queued before the app launched")
    func flushesOnStart() async throws {
        let (store, account, gateway, outbox) = try fixture()
        _ = try await outbox.enqueue(
            Draft(to: "a@b.c", cc: nil, subject: "hi", body: "text"),
            account: account
        )

        let pump = OutboxPump(outbox: outbox, account: account, interval: .seconds(3600))
        pump.start()
        defer { pump.stop() }

        try await waitUntil { try store.outbox.pendingOutbox(account: account).isEmpty }
        #expect(await gateway.clientIDs.count == 1)
    }

    @Test("a signal after enqueue delivers without waiting for the next tick")
    func flushesOnSignal() async throws {
        let (store, account, gateway, outbox) = try fixture()
        let pump = OutboxPump(outbox: outbox, account: account, interval: .seconds(3600))
        pump.start()
        defer { pump.stop() }

        // Wait out the startup catch-up first: it drains the first row, so what follows is
        // delivered only by the signal (the interval is an hour away).
        _ = try await outbox.enqueue(
            Draft(to: "a@b.c", cc: nil, subject: "startup", body: "text"),
            account: account
        )
        try await waitUntil { try store.outbox.pendingOutbox(account: account).isEmpty }

        _ = try await outbox.enqueue(
            Draft(to: "a@b.c", cc: nil, subject: "later", body: "text"),
            account: account
        )
        #expect(try store.outbox.pendingOutbox(account: account).count == 1)

        pump.signal()

        try await waitUntil { try store.outbox.pendingOutbox(account: account).isEmpty }
        #expect(await gateway.clientIDs.count == 2)
    }

    @Test("stop ends the loop and can be restarted")
    func stopAndRestart() async throws {
        let (store, account, gateway, outbox) = try fixture()
        let pump = OutboxPump(outbox: outbox, account: account, interval: .seconds(3600))
        pump.start()
        pump.stop()
        pump.stop()

        _ = try await outbox.enqueue(
            Draft(to: "a@b.c", cc: nil, subject: "again", body: "text"),
            account: account
        )
        #expect(try store.outbox.pendingOutbox(account: account).count == 1)
        #expect(await gateway.clientIDs.isEmpty)

        pump.start()
        defer { pump.stop() }
        try await waitUntil { try store.outbox.pendingOutbox(account: account).isEmpty }
        #expect(await gateway.clientIDs.count == 1)
    }
}
