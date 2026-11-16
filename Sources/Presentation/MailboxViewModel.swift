import Foundation
import MailDomain
import Observation
import Scenes

/// Presentation state for the mailbox window (spec §4.11). Display state only: every
/// action is one scene call and its result mapped to view state. No store, no gateway,
/// no orchestration; the reading/refresh rules live in `ReadScene`/`SyncScene`.
@MainActor
@Observable
public final class MailboxViewModel {
    public private(set) var folders: [Folder] = []
    public private(set) var messages: [Message] = []
    public internal(set) var body: BodyPresentation = .none
    public internal(set) var bodyNotice: BodyNotice?
    public internal(set) var attachments: [Attachment] = []
    public private(set) var sync = SyncPresentation()
    public internal(set) var selection = Selection()
    /// Composite identity for the selected row. Search results span folders, where the
    /// server id alone is not unique (R23); the list and selection use this key.
    public internal(set) var selectedListKey: String?

    let read: ReadScene
    private let syncScene: SyncScene
    let composeScene: ComposeScene
    let account: AccountID
    /// Wakes the composition's delivery pump after an enqueue. Composition owns the loop;
    /// the view model only forwards the signal.
    let onEnqueued: (@MainActor () -> Void)?

    @ObservationIgnored let dwell: MailboxDwell
    let deletion: MailboxDeletion
    @ObservationIgnored private var isApplicationActive = true
    @ObservationIgnored var isDeleteInFlight = false
    private var autoRefreshTask: Task<Void, Never>?
    var bodyTask: Task<Void, Never>?
    var openingRef: MessageRef?
    var openedBody: MessageRef?

    public init(
        read: ReadScene,
        sync: SyncScene,
        compose: ComposeScene,
        account: AccountID,
        onEnqueued: (@MainActor () -> Void)? = nil,
        dwellSleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.read = read
        self.syncScene = sync
        self.composeScene = compose
        self.account = account
        self.onEnqueued = onEnqueued
        self.dwell = MailboxDwell(read: read, sleep: dwellSleep)
        self.deletion = MailboxDeletion(read: read)
        dwell.onMarked = { [weak self] _ in
            guard let self else { return }
            try? self.reloadCurrentList(autoSelect: false)
            self.refreshDwell()
        }
    }

    // MARK: - Derived state

    /// Composite row identity; `serverID` is only unique inside one folder.
    public nonisolated static func listKey(for message: Message) -> String {
        "\(message.folderID ?? "")\u{1F}\(message.serverID)"
    }

    /// The rows currently on screen: the local list minus the deletion hide set.
    public var visibleMessages: [Message] {
        messages.filter { message in
            guard let ref = ref(for: message) else { return true }
            return !deletion.hidden.contains(ref)
        }
    }

    public var deleteErrorText: String? { deletion.errorText }

    public var selectedMessage: Message? {
        if let key = selectedListKey,
           let message = visibleMessages.first(where: { Self.listKey(for: $0) == key }) {
            return message
        }
        // Compatibility for callers/tests that only set the public `selection.messageID`.
        // A temporarily hidden row must never be resolved: it cannot be selected or opened.
        guard let id = selection.messageID else { return nil }
        return visibleMessages.first { $0.serverID == id }
    }

    /// The envelope header for the selection. Derived on read; it owns no state and calls
    /// no scene, so the reading hot path stays network-free (REQ-0017 / SCN-0012).
    public var headerPresentation: MessageHeaderPresentation? {
        selectedMessage.map { MessageHeaderPresentation(message: $0) }
    }

    var selectedRef: MessageRef? {
        guard let message = selectedMessage else { return nil }
        return ref(for: message)
    }

    func ref(for message: Message) -> MessageRef? {
        guard let folder = message.folderID ?? selection.folderID else { return nil }
        return MessageRef(folderID: folder, serverID: message.serverID)
    }

    // MARK: - Refresh

    /// Shows the local store immediately, then starts the scene's auto-refresh cadence.
    /// The loop itself lives in `SyncScene`; this only reflects each outcome.
    public func startAutoRefresh(every: Duration = .seconds(300)) {
        guard autoRefreshTask == nil else { return }
        loadCached()
        autoRefreshTask = Task { [weak self] in
            guard let self else { return }
            let stream = await self.syncScene.startAutoRefresh(every: every)
            for await outcome in stream {
                self.apply(outcome)
                if Task.isCancelled { break }
            }
            if !Task.isCancelled {
                self.autoRefreshTask = nil
            }
        }
    }

    public func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
        Task { await self.syncScene.stopAutoRefresh() }
    }

    /// Manual refresh (toolbar). The sync result is reflected in `sync`; the lists are
    /// re-read from the local store so a failure keeps whatever was on screen.
    public func refresh() async {
        sync.phase = .syncing
        let outcome = await syncScene.refresh()
        apply(outcome)
    }

    /// Paints cached folders and messages without touching the network.
    public func loadCached() {
        try? reloadFolders()
        try? reloadCurrentList(autoSelect: true)
        refreshDwell()
    }

    private func apply(_ outcome: RefreshOutcome) {
        do {
            try reloadFolders()
            try reloadCurrentList(autoSelect: true)
        } catch {
            sync.phase = .failed(ErrorText.text(for: error))
            return
        }
        if outcome.report != nil {
            sync.lastSyncedAt = outcome.at
            sync.phase = .idle
        } else if let error = outcome.error {
            sync.phase = .failed(ErrorText.text(for: error))
        } else {
            sync.phase = .idle
        }
        refreshDwell()
    }

    // MARK: - Selection

    public func select(folderID: String) {
        guard selection.folderID != folderID else { return }
        selection.folderID = folderID
        selection.searchQuery = ""
        selection.messageID = nil
        selectedListKey = nil
        clearBody()
        do {
            try reloadCurrentList(autoSelect: false)
        } catch {
            messages = []
            sync.phase = .failed(ErrorText.text(for: error))
        }
        refreshDwell()
    }

    public func select(messageID: String) {
        guard let message = messages.first(where: { $0.serverID == messageID }) else { return }
        select(listKey: Self.listKey(for: message))
    }

    /// View-facing selection by composite identity.
    public func select(listKey: String) {
        guard let message = messages.first(where: { Self.listKey(for: $0) == listKey }),
              let ref = ref(for: message),
              !deletion.hidden.contains(ref)
        else { return }
        guard selectedListKey != listKey else { return }
        selectedListKey = listKey
        selection.messageID = message.serverID
        refreshDwell()
        Task { await self.openSelected() }
    }

    /// Foreground/background forwarding from the view. The view model owns the timer rule.
    public func setApplicationActive(_ active: Bool) {
        isApplicationActive = active
        refreshDwell()
    }

    // MARK: - Search

    /// Local FTS search; an empty query restores the selected folder's list. Search mode
    /// never feeds the dwell timer, whether entering or staying in results.
    public func search(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        selection.searchQuery = trimmed
        do {
            try reloadCurrentList(autoSelect: trimmed.isEmpty)
        } catch {
            messages = []
            sync.phase = .failed(ErrorText.text(for: error))
        }
        refreshDwell()
    }

    // MARK: - Attachments

    /// Downloads (or reuses) one attachment and returns the file to open.
    public func download(_ attachment: Attachment) async -> URL? {
        guard let ref = selectedRef else { return nil }
        return try? await read.downloadAttachment(attachment, in: ref)
    }

    // MARK: - Dwell

    func refreshDwell() {
        guard let message = selectedMessage, let ref = ref(for: message) else {
            dwell.cancel()
            return
        }
        let inSearch = !selection.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        dwell.update(target: ref, isUnread: !message.isRead, isActive: isApplicationActive && !inSearch)
    }

    // MARK: - Local reads

    private func reloadFolders() throws {
        folders = try read.folders()
        if let current = selection.folderID, folders.contains(where: { $0.serverID == current }) {
            return
        }
        selection.folderID = folders.first(where: \.isInbox)?.serverID ?? folders.first?.serverID
    }

    func reloadCurrentList(autoSelect: Bool) throws {
        let query = selection.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            guard let folder = selection.folderID else {
                messages = []
                clearSelection()
                return
            }
            messages = try read.messages(folderID: folder, limit: 200)
        } else {
            messages = try read.search(query, limit: 100)
        }

        if let key = selectedListKey,
           let message = messages.first(where: { Self.listKey(for: $0) == key }),
           !isHidden(message) {
            return
        }
        if let id = selection.messageID,
           let message = messages.first(where: { $0.serverID == id }),
           !isHidden(message) {
            selectedListKey = Self.listKey(for: message)
            return
        }
        if autoSelect, let first = visibleMessages.first {
            select(first, open: true)
        } else {
            clearSelection()
        }
    }

    private func select(_ message: Message, open: Bool) {
        selectedListKey = Self.listKey(for: message)
        selection.messageID = message.serverID
        refreshDwell()
        if open {
            startBodyLoad()
        }
    }

    private func clearSelection() {
        selection.messageID = nil
        selectedListKey = nil
        clearBody()
        dwell.cancel()
    }

    func isHidden(_ message: Message) -> Bool {
        guard let ref = ref(for: message) else { return false }
        return deletion.hidden.contains(ref)
    }
}
