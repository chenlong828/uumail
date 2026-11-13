import Foundation
import MailDomain

/// Orchestrates one account: folder hierarchy first, then the inbox window.
///
/// Two rules from the design live here, not in callers:
/// 1. `SyncKey=0` answers with a fresh key and no items, so a first sync is two
///    requests and the key is only persisted together with the window it carried.
/// 2. A batch and its key commit together (the store port enforces the transaction).
public actor SyncEngine {
    private let gateway: any MailGateway
    private let store: any SyncStore
    private let account: AccountRef
    private let window: Int
    private let maxRounds: Int
    private let filterType: Int
    private let sleeper: @Sendable (Duration) async -> Void

    private var state: SyncState = .idle
    private var consecutiveFailures = 0

    public init(
        gateway: any MailGateway,
        store: any SyncStore,
        account: AccountRef,
        window: Int = 25,
        maxRounds: Int = 5,
        filterType: Int = 5,
        sleeper: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.gateway = gateway
        self.store = store
        self.account = account
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
            let report = try await syncInbox(inbox, folderCount: folders.count)
            consecutiveFailures = 0
            state = .idle
            return report
        } catch {
            let failure = SyncState.SyncFailure(
                error: map(error),
                folder: nil,
                consecutiveFailures: consecutiveFailures + 1
            )
            consecutiveFailures += 1
            state = .failed(failure)
            throw failure.error
        }
    }

    // MARK: - Folders

    private func refreshFolders() async throws -> [FolderSummary] {
        state = .syncingFolders
        // FolderSync is asked for the full hierarchy every time: an incremental key only
        // tells us that the tree changed, not what it now contains.
        let listing = try await gateway.fetchFolders(syncKey: "0")
        try store.applyFolderSnapshot(account, folders: listing.folders, syncKey: listing.syncKey)
        return try store.folders(account)
    }

    // MARK: - Messages

    private func syncInbox(_ inbox: FolderSummary, folderCount: Int) async throws -> SyncReport {
        var added = 0
        var changed = 0
        var removed = 0
        var rounds = 0
        var key = try store.syncKey(account, collection: inbox.serverID) ?? "0"
        var rebuilt = false

        // The gateway pages through the collection in `window`-sized batches and does not
        // reliably set MoreAvailable, so a round only stops when it brought fewer items
        // than the window. Measured 2026-11-09: every call returned 25 items with
        // MoreAvailable absent while ~150 messages still queued up.
        while rounds < maxRounds {
            if key == "0" {
                // First sync of a collection: SyncKey=0 answers with a key and no items.
                let bootstrap = try await gateway.fetchMessages(
                    collectionID: inbox.serverID, syncKey: "0", window: window, filterType: filterType
                )
                key = bootstrap.syncKey
                continue
            }

            do {
                let delta = try await gateway.fetchMessages(
                    collectionID: inbox.serverID, syncKey: key, window: window, filterType: filterType
                )
                try store.applySyncBatch(account, folder: inbox.serverID, delta: delta)
                added += delta.added.count
                changed += delta.changed.count
                removed += delta.removedServerIDs.count
                rounds += 1
                key = delta.syncKey

                if delta.added.count < window && !delta.moreAvailable {
                    break
                }
            } catch MailError.syncKeyInvalid where !rebuilt {
                // Status 3/4: the server lost our cursor. Rebuild this collection from zero.
                rebuilt = true
                try store.resetCollection(account, folder: inbox.serverID)
                key = "0"
            }
        }

        return SyncReport(
            folders: folderCount, added: added, changed: changed,
            removed: removed, rounds: rounds, syncKey: key
        )
    }

    // MARK: - Errors

    private func map(_ error: Error) -> MailError {
        if let gatewayError = error as? MailError {
            return gatewayError
        }
        return .offline
    }
}
