import Foundation
import MailDomain
import Testing

@testable import SyncEngine

/// Read-only test stand-in: the real production target has no such type.
struct UnsupportedWriteGateway: MailWriteGateway {
    func markRead(collectionID: String, serverID: String, syncKey: String) async throws -> MessageDelta {
        throw MailError.unsupported
    }

    func delete(collectionID: String, serverID: String, syncKey: String) async throws -> MessageDelta {
        throw MailError.unsupported
    }
}

actor FakeGateway: MailGateway {
    enum Call: Equatable {
        case provision
        case folders(syncKey: String)
        case messages(collection: String, key: String)
    }

    private(set) var calls: [Call] = []
    private var folderListing: FolderListing
    private var deltas: [String: MessageDelta]
    private var provisionError: MailError?
    private var remainingThrottles: Int
    private var messagesGate: AsyncGate?

    func setMessagesGate(_ gate: AsyncGate?) { messagesGate = gate }

    init(
        folderListing: FolderListing,
        deltas: [String: MessageDelta],
        provisionError: MailError? = nil,
        throttles: Int = 0
    ) {
        self.folderListing = folderListing
        self.deltas = deltas
        self.provisionError = provisionError
        self.remainingThrottles = throttles
    }

    func probe() async throws -> ServerCapabilities {
        ServerCapabilities(protocolVersions: [], commands: [])
    }

    func provisionIfNeeded() async throws {
        calls.append(.provision)
        if let provisionError { throw provisionError }
    }

    func fetchFolders(syncKey: String) async throws -> FolderListing {
        calls.append(.folders(syncKey: syncKey))
        if remainingThrottles > 0 {
            remainingThrottles -= 1
            throw MailError.throttled(seconds: 2)
        }
        return folderListing
    }

    func fetchMessages(collectionID: String, syncKey: String, window: Int, filterType: Int) async throws -> MessageDelta {
        calls.append(.messages(collection: collectionID, key: syncKey))
        await messagesGate?.wait()
        guard let delta = deltas[syncKey] else {
            throw MailError.syncKeyInvalid
        }
        return delta
    }

    func fetchBody(collectionID: String, serverID: String) async throws -> FetchedBody {
        throw MailError.unsupported
    }

    func fetchAttachment(fileReference: String) async throws -> Data {
        throw MailError.unsupported
    }

    func send(mime: Data, clientID: String) async throws {
        throw MailError.unsupported
    }
}

final class FakeStore: SyncStore, @unchecked Sendable {
    private(set) var folderSnapshot: [Folder] = []
    private(set) var snapshotKey: String?
    private(set) var keys: [String: String] = [:]
    private(set) var batches: [MessageDelta] = []
    private(set) var resets: [String] = []
    private(set) var markReadCalls: [String] = []
    private(set) var commitMarkReads: [MessageDelta] = []
    private(set) var commitDeletes: [MessageDelta] = []
    var folderFailure: Error?
    var markReadResult = false
    var commitFailure: Error?

    func folders(_ account: AccountID) throws -> [Folder] {
        folderSnapshot
    }

    func applyFolderSnapshot(_ account: AccountID, folders: [Folder], syncKey: String) throws {
        if let folderFailure { throw folderFailure }
        folderSnapshot = folders
        snapshotKey = syncKey
    }

    func syncKey(_ account: AccountID, collection: String) throws -> String? {
        keys[collection]
    }

    func applySyncBatch(_ account: AccountID, folder: String, delta: MessageDelta) throws {
        batches.append(delta)
        keys[folder] = delta.syncKey
    }

    func resetCollection(_ account: AccountID, folder: String) throws {
        resets.append(folder)
        keys[folder] = nil
    }

    @discardableResult
    func markRead(_ account: AccountID, folder: String, serverID: String) throws -> Bool {
        markReadCalls.append(serverID)
        return markReadResult
    }

    func commitMarkRead(_ account: AccountID, folder: String, serverID: String, delta: MessageDelta) throws {
        if let commitFailure { throw commitFailure }
        commitMarkReads.append(delta)
        keys[folder] = delta.syncKey
    }

    func commitDelete(_ account: AccountID, folder: String, serverID: String, delta: MessageDelta) throws {
        if let commitFailure { throw commitFailure }
        commitDeletes.append(delta)
        keys[folder] = delta.syncKey
    }
}

private let inbox = Folder(serverID: "13", parentID: "0", displayName: "收件箱", type: 2)
private let draft = Folder(serverID: "4", parentID: "0", displayName: "草稿", type: 3)

private func makeDelta(
    key: String,
    added: [String],
    more: Bool = false
) -> MessageDelta {
    MessageDelta(
        added: added.map { Message(serverID: $0, subject: "s-\($0)") },
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
        let engine = SyncEngine(gateway: gateway, store: store, account: AccountID("a"), writeGateway: UnsupportedWriteGateway())

        let report = try await engine.syncOnce()

        #expect(report.folders == 2)
        #expect(report.added == 3)
        #expect(report.syncKey == "101")
        #expect(store.snapshotKey == "7")
        #expect(store.batches.count == 1, "the key-only bootstrap response must not be stored")
        #expect(store.batches.first?.added.map(\.serverID) == ["1", "2", "3"])
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
        try store.applySyncBatch(AccountID("a"), folder: "13", delta: makeDelta(key: "101", added: []))
        let engine = SyncEngine(gateway: gateway, store: store, account: AccountID("a"), writeGateway: UnsupportedWriteGateway())

        let report = try await engine.syncOnce()
        #expect(report.added == 1)
        #expect(report.syncKey == "102")
        #expect(store.resets.isEmpty)
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
        try store.applySyncBatch(AccountID("a"), folder: "13", delta: makeDelta(key: "999", added: []))
        let engine = SyncEngine(gateway: gateway, store: store, account: AccountID("a"), writeGateway: UnsupportedWriteGateway())

        // 999 is unknown to the fake gateway, so the first pull raises syncKeyInvalid.
        let report = try await engine.syncOnce()
        #expect(store.resets == ["13"])
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
        let engine = SyncEngine(gateway: gateway, store: store, account: AccountID("a"), writeGateway: UnsupportedWriteGateway())
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
        let engine = SyncEngine(gateway: gateway, store: store, account: AccountID("a"), writeGateway: UnsupportedWriteGateway())

        await #expect(throws: MailError.deviceNotRegistered) {
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
        let engine = SyncEngine(gateway: gateway, store: store, account: AccountID("a"), writeGateway: UnsupportedWriteGateway())
        await #expect(throws: MailError.unsupported) {
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
                folders: [Folder(serverID: "13", parentID: "0", displayName: "收件箱", type: 2)],
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
            account: AccountID("a"),
            writeGateway: UnsupportedWriteGateway(),
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
                added: [Message(serverID: "1")], changed: [], removedServerIDs: [],
                syncKey: "11", moreAvailable: false
            ),
        ]
    }
}


/// One-shot async gate for serialization tests: the first `wait` suspends until `open`.
actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var waitCount = 0

    func wait() async {
        waitCount += 1
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }

    func waitUntilWaiting() async {
        for _ in 0..<10_000 {
            if waitCount > 0 { return }
            await Task.yield()
        }
    }
}

actor RecordingWriteGateway: MailWriteGateway {
    enum Call: Equatable {
        case markRead(collectionID: String, serverID: String, key: String)
        case delete(collectionID: String, serverID: String, key: String)
    }

    private(set) var calls: [Call] = []
    private var delta: MessageDelta
    private var error: MailError?
    private var gate: AsyncGate?

    init(delta: MessageDelta, error: MailError? = nil) {
        self.delta = delta
        self.error = error
    }

    func setGate(_ gate: AsyncGate?) { self.gate = gate }
    func setError(_ error: MailError?) { self.error = error }

    func markRead(collectionID: String, serverID: String, syncKey: String) async throws -> MessageDelta {
        calls.append(.markRead(collectionID: collectionID, serverID: serverID, key: syncKey))
        await gate?.wait()
        if let error { throw error }
        return delta
    }

    func delete(collectionID: String, serverID: String, syncKey: String) async throws -> MessageDelta {
        calls.append(.delete(collectionID: collectionID, serverID: serverID, key: syncKey))
        await gate?.wait()
        if let error { throw error }
        return delta
    }
}

@Suite("SyncEngine write path")
struct SyncEngineWriteTests {
    private func store(key: String) throws -> FakeStore {
        let store = FakeStore()
        try store.applySyncBatch(
            AccountID("a"), folder: "13",
            delta: MessageDelta(added: [], changed: [], removedServerIDs: [], syncKey: key, moreAvailable: false)
        )
        return store
    }

    private func delta(key: String, removed: [String] = [], more: Bool = false) -> MessageDelta {
        MessageDelta(
            added: [], changed: [], removedServerIDs: removed,
            syncKey: key, moreAvailable: more
        )
    }

    @Test("markRead pins the local fact, sends one command with the current key and advances once")
    func markReadWritesOnceAndAdvancesKey() async throws {
        let store = try store(key: "5")
        let gateway = FakeGateway(folderListing: FolderListing(folders: [inbox], syncKey: "1"), deltas: [:])
        let write = RecordingWriteGateway(delta: delta(key: "6"))
        let engine = SyncEngine(gateway: gateway, store: store, account: AccountID("a"), writeGateway: write)

        try await engine.markRead(collectionID: "13", serverID: "101")

        #expect(store.markReadCalls == ["101"], "the engine pins the local read before the network")
        #expect(await write.calls == [.markRead(collectionID: "13", serverID: "101", key: "5")])
        #expect(store.commitMarkReads.count == 1)
        #expect(try store.syncKey(AccountID("a"), collection: "13") == "6")
    }

    @Test("deleteMessage commits the soft delete only after the server confirms and advances the key once")
    func deleteAdvancesKeyOnce() async throws {
        let store = try store(key: "5")
        let gateway = FakeGateway(folderListing: FolderListing(folders: [inbox], syncKey: "1"), deltas: [:])
        let write = RecordingWriteGateway(delta: delta(key: "7", removed: ["101"]))
        let engine = SyncEngine(gateway: gateway, store: store, account: AccountID("a"), writeGateway: write)

        try await engine.deleteMessage(collectionID: "13", serverID: "101")

        #expect(await write.calls == [.delete(collectionID: "13", serverID: "101", key: "5")])
        #expect(store.commitDeletes.count == 1)
        #expect(store.commitDeletes.first?.removedServerIDs == ["101"])
        #expect(try store.syncKey(AccountID("a"), collection: "13") == "7")
    }

    @Test("a gateway failure leaves the key and the local state untouched")
    func writeFailureDoesNotCommit() async throws {
        let store = try store(key: "5")
        let gateway = FakeGateway(folderListing: FolderListing(folders: [inbox], syncKey: "1"), deltas: [:])
        let write = RecordingWriteGateway(delta: delta(key: "6"), error: .offline)
        let engine = SyncEngine(gateway: gateway, store: store, account: AccountID("a"), writeGateway: write)

        await #expect(throws: MailError.offline) {
            try await engine.deleteMessage(collectionID: "13", serverID: "101")
        }
        #expect(try store.syncKey(AccountID("a"), collection: "13") == "5")
        #expect(store.commitDeletes.isEmpty)
    }

    @Test("a write response with MoreAvailable is refused instead of committed")
    func moreAvailableWriteIsRefused() async throws {
        let store = try store(key: "5")
        let gateway = FakeGateway(folderListing: FolderListing(folders: [inbox], syncKey: "1"), deltas: [:])
        let write = RecordingWriteGateway(delta: delta(key: "6", more: true))
        let engine = SyncEngine(gateway: gateway, store: store, account: AccountID("a"), writeGateway: write)

        await #expect(throws: MailError.unsupported) {
            try await engine.markRead(collectionID: "13", serverID: "101")
        }
        #expect(try store.syncKey(AccountID("a"), collection: "13") == "5")
        #expect(store.commitMarkReads.isEmpty)
    }

    @Test("a missing or bootstrap key fails before any write goes out")
    func missingKeySendsNothing() async throws {
        let store = FakeStore()
        let gateway = FakeGateway(folderListing: FolderListing(folders: [inbox], syncKey: "1"), deltas: [:])
        let write = RecordingWriteGateway(delta: delta(key: "6"))
        let engine = SyncEngine(gateway: gateway, store: store, account: AccountID("a"), writeGateway: write)

        await #expect(throws: MailError.syncKeyInvalid) {
            try await engine.markRead(collectionID: "13", serverID: "101")
        }
        #expect(await write.calls.isEmpty)
    }

    @Test("T-SCN-0008-03: markRead is serialized with syncOnce and starts from the new key")
    func markReadIsSerializedWithSyncOnce() async throws {
        let store = try store(key: "5")
        let gateway = FakeGateway(
            folderListing: FolderListing(folders: [inbox], syncKey: "1"),
            deltas: ["5": delta(key: "6")]
        )
        let gate = AsyncGate()
        await gateway.setMessagesGate(gate)
        let write = RecordingWriteGateway(delta: delta(key: "7"))
        let engine = SyncEngine(gateway: gateway, store: store, account: AccountID("a"), writeGateway: write)

        let syncTask = Task { try await engine.syncOnce() }
        await gate.waitUntilWaiting()
        let writeTask = Task { try await engine.markRead(collectionID: "13", serverID: "101") }
        try await Task.sleep(for: .milliseconds(20))
        #expect(await write.calls.isEmpty, "the write must not interleave with the gated sync")

        await gate.open()
        _ = try await syncTask.value
        try await writeTask.value
        #expect(await write.calls == [.markRead(collectionID: "13", serverID: "101", key: "6")])
        #expect(try store.syncKey(AccountID("a"), collection: "13") == "7")
    }

    @Test("T-SCN-0009-03: a repeated delete uses the current key and does not advance it twice")
    func deleteIsIdempotentAndAdvancesKeyOnce() async throws {
        let store = try store(key: "5")
        let gateway = FakeGateway(folderListing: FolderListing(folders: [inbox], syncKey: "1"), deltas: [:])
        let write = RecordingWriteGateway(delta: delta(key: "6", removed: ["101"]))
        let engine = SyncEngine(gateway: gateway, store: store, account: AccountID("a"), writeGateway: write)

        try await engine.deleteMessage(collectionID: "13", serverID: "101")
        try await engine.deleteMessage(collectionID: "13", serverID: "101")

        #expect(await write.calls == [
            .delete(collectionID: "13", serverID: "101", key: "5"),
            .delete(collectionID: "13", serverID: "101", key: "6"),
        ])
        #expect(try store.syncKey(AccountID("a"), collection: "13") == "6")
    }

    @Test("a sync waits for an in-flight write and reads the key it advanced")
    func syncWaitsForWrite() async throws {
        let store = try store(key: "5")
        let gateway = FakeGateway(
            folderListing: FolderListing(folders: [inbox], syncKey: "1"),
            deltas: ["6": delta(key: "7")]
        )
        let write = RecordingWriteGateway(delta: delta(key: "6"))
        let gate = AsyncGate()
        await write.setGate(gate)
        let engine = SyncEngine(gateway: gateway, store: store, account: AccountID("a"), writeGateway: write)

        let writeTask = Task { try await engine.markRead(collectionID: "13", serverID: "101") }
        await gate.waitUntilWaiting()
        let syncTask = Task { try await engine.syncOnce() }
        try await Task.sleep(for: .milliseconds(20))
        let keysBeforeRelease = await gateway.calls.compactMap { call -> String? in
            if case .messages(_, let key) = call { return key }
            return nil
        }
        #expect(keysBeforeRelease.isEmpty, "the sync must not fetch while the write owns the gate")

        await gate.open()
        try await writeTask.value
        _ = try await syncTask.value
        let keys = await gateway.calls.compactMap { call -> String? in
            if case .messages(_, let key) = call { return key }
            return nil
        }
        #expect(keys == ["6"])
        #expect(try store.syncKey(AccountID("a"), collection: "13") == "7")
    }

    @Test("a cancelled queued write never reaches the gateway")
    func cancelledWaiterSendsNothing() async throws {
        let store = try store(key: "5")
        let gateway = FakeGateway(folderListing: FolderListing(folders: [inbox], syncKey: "1"), deltas: [:])
        let gate = AsyncGate()
        let write = RecordingWriteGateway(delta: delta(key: "6"))
        await write.setGate(gate)
        let engine = SyncEngine(gateway: gateway, store: store, account: AccountID("a"), writeGateway: write)

        let first = Task { try await engine.markRead(collectionID: "13", serverID: "101") }
        await gate.waitUntilWaiting()
        let second = Task { try await engine.deleteMessage(collectionID: "13", serverID: "102") }
        try await Task.sleep(for: .milliseconds(20))
        second.cancel()
        await gate.open()
        try await first.value

        do {
            try await second.value
            Issue.record("expected CancellationError")
        } catch is CancellationError {
            // expected
        } catch {
            Issue.record("expected CancellationError, got \(error)")
        }
        #expect(await write.calls.count == 1)
    }
}
