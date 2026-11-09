import Foundation
import Testing

@testable import SyncEngine

actor FakeGateway: MailGateway {
    enum Call: Equatable {
        case provision
        case folders(syncKey: String)
        case messages(collection: String, key: String)
    }

    private(set) var calls: [Call] = []
    private var folderListing: FolderListing
    private var deltas: [String: MessageDelta]
    private var provisionError: MailGatewayError?
    private var remainingThrottles: Int

    init(
        folderListing: FolderListing,
        deltas: [String: MessageDelta],
        provisionError: MailGatewayError? = nil,
        throttles: Int = 0
    ) {
        self.folderListing = folderListing
        self.deltas = deltas
        self.provisionError = provisionError
        self.remainingThrottles = throttles
    }

    func provisionIfNeeded() async throws {
        calls.append(.provision)
        if let provisionError { throw provisionError }
    }

    func fetchFolders(syncKey: String) async throws -> FolderListing {
        calls.append(.folders(syncKey: syncKey))
        if remainingThrottles > 0 {
            remainingThrottles -= 1
            throw MailGatewayError.throttled(retryAfterSeconds: 2)
        }
        return folderListing
    }

    func fetchMessages(collectionID: String, syncKey: String, window: Int, filterType: Int) async throws -> MessageDelta {
        calls.append(.messages(collection: collectionID, key: syncKey))
        guard let delta = deltas[syncKey] else {
            throw MailGatewayError.syncKeyInvalid
        }
        return delta
    }
}

actor FakeStore: SyncStore {
    private(set) var folderSnapshot: [FolderSummary] = []
    private(set) var snapshotKey: String?
    private(set) var keys: [String: String] = [:]
    private(set) var batches: [MessageDelta] = []
    private(set) var resets: [String] = []
    var folderFailure: Error?

    func folders(_ account: AccountRef) async throws -> [FolderSummary] {
        folderSnapshot
    }

    func applyFolderSnapshot(_ account: AccountRef, folders: [FolderSummary], syncKey: String) async throws {
        if let folderFailure { throw folderFailure }
        folderSnapshot = folders
        snapshotKey = syncKey
    }

    func syncKey(_ account: AccountRef, collection: String) async throws -> String? {
        keys[collection]
    }

    func applySyncBatch(_ account: AccountRef, folder: String, delta: MessageDelta) async throws {
        batches.append(delta)
        keys[folder] = delta.syncKey
    }

    func resetCollection(_ account: AccountRef, folder: String) async throws {
        resets.append(folder)
        keys[folder] = nil
    }
}

private let inbox = FolderSummary(serverID: "13", parentID: "0", displayName: "收件箱", type: 2)
private let draft = FolderSummary(serverID: "4", parentID: "0", displayName: "草稿", type: 3)

private func makeDelta(
    key: String,
    added: [String],
    more: Bool = false
) -> MessageDelta {
    MessageDelta(
        added: added.map { MessageSummary(serverID: $0, subject: "s-\($0)") },
        changed: [],
        removedServerIDs: [],
        syncKey: key,
        moreAvailable: more
    )
}

@Suite("SyncEngine")
struct SyncEngineTests {
    @Test("first sync is two requests and only the window is written")
    func bootstrap() async throws {
        let gateway = FakeGateway(
            folderListing: FolderListing(folders: [inbox, draft], syncKey: "7"),
            deltas: [
                "0": makeDelta(key: "100", added: []),
                "100": makeDelta(key: "101", added: ["1", "2", "3"]),
            ]
        )
        let store = FakeStore()
        let engine = SyncEngine(gateway: gateway, store: store, account: AccountRef("a"))

        let report = try await engine.syncOnce()

        #expect(report.folders == 2)
        #expect(report.added == 3)
        #expect(report.syncKey == "101")
        #expect(await store.snapshotKey == "7")
        #expect(await store.batches.count == 1, "the key-only bootstrap response must not be stored")
        #expect(await store.batches.first?.added.map(\.serverID) == ["1", "2", "3"])
        #expect(await engine.currentState() == .idle)

        let keys = await gateway.calls.compactMap { call -> String? in
            if case .messages(_, let key) = call { return key }
            return nil
        }
        #expect(keys == ["0", "100"])
    }

    @Test("incremental sync resumes from the stored key")
    func incremental() async throws {
        let gateway = FakeGateway(
            folderListing: FolderListing(folders: [inbox], syncKey: "7"),
            deltas: ["101": makeDelta(key: "102", added: ["9"])]
        )
        let store = FakeStore()
        try await store.applySyncBatch(AccountRef("a"), folder: "13", delta: makeDelta(key: "101", added: []))
        let engine = SyncEngine(gateway: gateway, store: store, account: AccountRef("a"))

        let report = try await engine.syncOnce()
        #expect(report.added == 1)
        #expect(report.syncKey == "102")
        #expect(await store.resets.isEmpty)
    }

    @Test("an invalid key resets the collection and rebuilds it")
    func rebuildOnInvalidKey() async throws {
        let gateway = FakeGateway(
            folderListing: FolderListing(folders: [inbox], syncKey: "7"),
            deltas: [
                "0": makeDelta(key: "200", added: []),
                "200": makeDelta(key: "201", added: ["5"]),
            ]
        )
        let store = FakeStore()
        try await store.applySyncBatch(AccountRef("a"), folder: "13", delta: makeDelta(key: "999", added: []))
        let engine = SyncEngine(gateway: gateway, store: store, account: AccountRef("a"))

        // 999 is unknown to the fake gateway, so the first pull raises syncKeyInvalid.
        let report = try await engine.syncOnce()
        #expect(await store.resets == ["13"])
        #expect(report.added == 1)
        #expect(report.syncKey == "201")
    }

    @Test("MoreAvailable pulls further windows up to the round budget")
    func moreAvailable() async throws {
        let gateway = FakeGateway(
            folderListing: FolderListing(folders: [inbox], syncKey: "7"),
            deltas: [
                "0": makeDelta(key: "1", added: []),
                "1": makeDelta(key: "2", added: ["1"], more: true),
                "2": makeDelta(key: "3", added: ["2"]),
            ]
        )
        let store = FakeStore()
        let engine = SyncEngine(gateway: gateway, store: store, account: AccountRef("a"))
        let report = try await engine.syncOnce()
        #expect(report.added == 2)
        #expect(report.rounds == 2)
        #expect(report.syncKey == "3")
    }

    @Test("a device rejection stops the run and keeps the failure in the state")
    func deviceNotRegistered() async throws {
        let gateway = FakeGateway(
            folderListing: FolderListing(folders: [inbox], syncKey: "7"),
            deltas: [:],
            provisionError: .deviceNotRegistered
        )
        let store = FakeStore()
        let engine = SyncEngine(gateway: gateway, store: store, account: AccountRef("a"))

        await #expect(throws: MailGatewayError.deviceNotRegistered) {
            _ = try await engine.syncOnce()
        }
        guard case .failed(let failure) = await engine.currentState() else {
            Issue.record("expected failed state")
            return
        }
        #expect(failure.error == .deviceNotRegistered)
        #expect(failure.consecutiveFailures == 1)
    }

    @Test("no inbox means the run fails instead of silently doing nothing")
    func missingInbox() async throws {
        let gateway = FakeGateway(
            folderListing: FolderListing(folders: [draft], syncKey: "7"),
            deltas: [:]
        )
        let store = FakeStore()
        let engine = SyncEngine(gateway: gateway, store: store, account: AccountRef("a"))
        await #expect(throws: MailGatewayError.unsupported) {
            _ = try await engine.syncOnce()
        }
    }
}

private actor SleepRecorder {
    private(set) var durations: [Duration] = []
    func add(_ duration: Duration) { durations.append(duration) }
}

@Suite("SyncEngine throttle")
struct SyncEngineThrottleTests {
    @Test("a throttled run waits for Retry-After and retries once")
    func retriesAfterThrottle() async throws {
        let gateway = FakeGateway(
            folderListing: FolderListing(
                folders: [FolderSummary(serverID: "13", parentID: "0", displayName: "收件箱", type: 2)],
                syncKey: "1"
            ),
            deltas: dangerousDeltas(),
            throttles: 1
        )
        let store = FakeStore()
        let sleeps = SleepRecorder()
        let engine = SyncEngine(
            gateway: gateway,
            store: store,
            account: AccountRef("a"),
            sleeper: { duration in await sleeps.add(duration) }
        )
        let report = try await engine.syncOnce()
        #expect(report.folders == 1)
        #expect(await sleeps.durations.count == 1)
        #expect(await sleeps.durations.first == .seconds(2))
    }

    private func dangerousDeltas() -> [String: MessageDelta] {
        [
            "0": MessageDelta(added: [], changed: [], removedServerIDs: [], syncKey: "10", moreAvailable: false),
            "10": MessageDelta(
                added: [MessageSummary(serverID: "1")], changed: [], removedServerIDs: [],
                syncKey: "11", moreAvailable: false
            ),
        ]
    }
}
