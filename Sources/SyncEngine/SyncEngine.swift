import Foundation
import MailDomain
import SyncContract

/// Orchestrates one account: folder hierarchy first, then the inbox window.
///
/// Two rules from the design live here, not in callers:
/// 1. `SyncKey=0` answers with a fresh key and no items, so a first sync is two
///    requests and the key is only persisted together with the window it carried.
/// 2. A batch and its key commit together (the store port enforces the transaction).
///
/// A read and a write (read marker/delete) share one collection key. The explicit FIFO
/// gate, not actor reentrancy, is what keeps them serial.
public actor SyncEngine {
    let gateway: any MailGateway
    let store: any SyncStore
    let account: AccountRef
    let writeGateway: any MailWriteGateway
    /// Draft sync is opt-in: the CLI and older tests construct the engine without it.
    let draftStore: (any DraftSyncStore)?
    private let window: Int
    private let maxRounds: Int
    let filterType: Int
    private let sleeper: @Sendable (Duration) async -> Void

    var state: SyncState = .idle
    var consecutiveFailures = 0

    // FIFO gate: `busy` stays true when a waiter owns the next turn.
    private var gateBusy = false
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, Error>)] = []

    public init(
        gateway: any MailGateway,
        store: any SyncStore,
        account: AccountRef,
        writeGateway: any MailWriteGateway,
        draftStore: (any DraftSyncStore)? = nil,
        window: Int = 25,
        maxRounds: Int = 5,
        filterType: Int = 5,
        sleeper: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.gateway = gateway
        self.store = store
        self.account = account
        self.writeGateway = writeGateway
        self.draftStore = draftStore
        self.window = window
        self.maxRounds = maxRounds
        self.filterType = filterType
        self.sleeper = sleeper
    }

    public func currentState() -> SyncState { state }

    /// Folder hierarchy then inbox. Safe to call repeatedly; the first call after a
    /// fresh install performs the two-request bootstrap.
    public func syncOnce() async throws -> SyncReport {
        do {
            return try await runSync()
        } catch MailError.throttled(let retryAfter) {
            // The server asked us to slow down; wait once and retry a single time.
            let seconds = min(max(retryAfter ?? 30, 1), 300)
            await sleeper(.seconds(seconds))
            return try await runSync()
        }
    }

    private func runSync() async throws -> SyncReport {
        do {
            try await gateway.provisionIfNeeded()
            let folders = try await refreshFolders()
            let inbox = folders.first(where: \.isInbox)
            guard let inbox else {
                throw MailError.unsupported
            }

            state = .syncingMessages(folder: inbox.serverID)
            let report = try await syncFolder(inbox, folderCount: folders.count)
            consecutiveFailures = 0
            state = .idle
            return report
        } catch {
            throw recordFailure(error)
        }
    }

    /// Syncs the Sent Items collection only (REQ-0038). `SendMail` already carries
    /// `SaveInSentItems`, so the server holds the copy; this pulls it into the local store
    /// without touching the inbox window or its notification rule. Returns nil when the
    /// account has no Sent Items folder.
    public func syncSentOnce() async throws -> SyncReport? {
        do {
            try await gateway.provisionIfNeeded()
            let folders = try await refreshFolders()
            guard let sent = folders.first(where: \.isSentItems) else {
                state = .idle
                return nil
            }
            state = .syncingMessages(folder: sent.serverID)
            let report = try await syncFolder(sent, folderCount: folders.count)
            consecutiveFailures = 0
            state = .idle
            return report
        } catch {
            throw recordFailure(error)
        }
    }

    /// One failure shape for both entry points: classify, count, publish the state, and
    /// hand the normalized error back to the throw site.
    func recordFailure(_ error: Error) -> MailError {
        let failure = SyncState.SyncFailure(
            error: map(error),
            folder: nil,
            consecutiveFailures: consecutiveFailures + 1
        )
        consecutiveFailures += 1
        state = .failed(failure)
        return failure.error
    }

    // MARK: - Folders

    func refreshFolders() async throws -> [FolderSummary] {
        state = .syncingFolders
        // FolderSync is asked for the full hierarchy every time: an incremental key only
        // tells us that the tree changed, not what it now contains.
        let listing = try await gateway.fetchFolders(syncKey: "0")
        try store.applyFolderSnapshot(account, folders: listing.folders, syncKey: listing.syncKey)
        return try store.folders(account)
    }

    // MARK: - Messages

    private struct RoundResult {
        var added = 0
        var changed = 0
        var removed = 0
        var rounds = 0
        var moreAvailable = false
        var reset = false
    }

    private func syncFolder(_ folder: FolderSummary, folderCount: Int) async throws -> SyncReport {
        var added = 0
        var changed = 0
        var removed = 0
        var rounds = 0
        var key = try store.syncKey(account, collection: folder.serverID) ?? "0"
        var rebuilt = false

        // The gateway pages through the collection in `window`-sized batches and does not
        // reliably set MoreAvailable, so a round only stops when it brought fewer items
        // than the window. Measured 2026-11-09: every call returned 25 items with
        // MoreAvailable absent while ~150 messages still queued up.
        while rounds < maxRounds {
            let result = try await syncRound(
                folder, allowReset: !rebuilt, currentKey: key
            )
            if result.reset {
                // The reset round already rebuilt and committed a window under the same
                // gate hold; count it and keep the run from resetting a second time.
                rebuilt = true
            }
            added += result.added
            changed += result.changed
            removed += result.removed
            rounds += result.rounds
            key = try store.syncKey(account, collection: folder.serverID) ?? key

            if result.added < window && !result.moreAvailable {
                break
            }
        }

        return SyncReport(
            folders: folderCount, added: added, changed: changed,
            removed: removed, rounds: rounds, syncKey: key
        )
    }

    /// One gated round: re-read the key, optionally bootstrap, then one Sync and its
    /// commit. A stale key resets the collection **and rebuilds it inside the same
    /// critical section**, so a queued write can never observe the empty key between the
    /// reset and the next round.
    private func syncRound(
        _ folder: FolderSummary, allowReset: Bool, currentKey: String
    ) async throws -> RoundResult {
        try await acquire()
        defer { release() }
        if Task.isCancelled { throw CancellationError() }

        var mayReset = allowReset
        var key = currentKey
        var didReset = false
        while true {
            key = try store.syncKey(account, collection: folder.serverID) ?? key
            if key == "0" {
                // SyncKey=0 answers with a key and no items. Ask for the window immediately
                // in the same critical section so a write cannot slip in between the calls.
                let bootstrap = try await gateway.fetchMessages(
                    collectionID: folder.serverID, syncKey: "0", window: window, filterType: filterType
                )
                key = bootstrap.syncKey
                guard key != "0" else { throw MailError.unsupported }
            }

            do {
                let delta = try await gateway.fetchMessages(
                    collectionID: folder.serverID, syncKey: key, window: window, filterType: filterType
                )
                try store.applySyncBatch(account, folder: folder.serverID, delta: delta)
                return RoundResult(
                    added: delta.added.count,
                    changed: delta.changed.count,
                    removed: delta.removedServerIDs.count,
                    rounds: 1,
                    moreAvailable: delta.moreAvailable,
                    reset: didReset
                )
            } catch MailError.syncKeyInvalid where mayReset {
                try store.resetCollection(account, folder: folder.serverID)
                mayReset = false
                didReset = true
                key = "0"
            }
        }
    }

    // MARK: - Write path

    /// Marks one message read on the server. The caller already made it read locally; this
    /// pins the local fact again, sends one Sync command and commits its delta + key.
    public func markRead(collectionID: String, serverID: String) async throws {
        try await acquire()
        defer { release() }
        if Task.isCancelled { throw CancellationError() }

        _ = try store.markRead(account, folder: collectionID, serverID: serverID)
        let key = try currentKey(collectionID)
        let delta = try await writeGateway.markRead(
            collectionID: collectionID, serverID: serverID, syncKey: key
        )
        // A write response may carry a full delta page and MoreAvailable (R16 sample);
        // that is a normal paging signal, not an anomaly. Commit delta + key together and
        // let the next incremental sync consume the rest.
        try store.commitMarkRead(account, folder: collectionID, serverID: serverID, delta: delta)
    }

    /// Deletes one message on the server. Nothing is soft-deleted locally until the server
    /// has confirmed and the response delta + key commit together.
    public func deleteMessage(collectionID: String, serverID: String) async throws {
        try await acquire()
        defer { release() }
        if Task.isCancelled { throw CancellationError() }

        let key = try currentKey(collectionID)
        let delta = try await writeGateway.delete(
            collectionID: collectionID, serverID: serverID, syncKey: key
        )
        // See markRead: MoreAvailable on a write response is the gateway's normal paging
        // signal (R16 sample); the delta and key commit together.
        try store.commitDelete(account, folder: collectionID, serverID: serverID, delta: delta)
    }

    private func currentKey(_ collectionID: String) throws -> String {
        guard let key = try store.syncKey(account, collection: collectionID), key != "0" else {
            throw MailError.syncKeyInvalid
        }
        return key
    }

    // MARK: - Gate

    func acquire() async throws {
        if Task.isCancelled { throw CancellationError() }
        if !gateBusy {
            gateBusy = true
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters.append((id, continuation))
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    /// Hands the gate to the next FIFO waiter without clearing `busy`.
    func release() {
        if waiters.isEmpty {
            gateBusy = false
        } else {
            waiters.removeFirst().continuation.resume()
        }
    }

    // MARK: - Errors

    private func map(_ error: Error) -> MailError {
        if let gatewayError = error as? MailError {
            return gatewayError
        }
        return .offline
    }
}
