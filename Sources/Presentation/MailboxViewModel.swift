import Foundation
import MeetingDomain
import MailDomain
import Observation
import Scenes

/// Presentation state for the mailbox window (spec §4.11). Display state only: every
/// action is one scene call and its result mapped to view state. No store, no gateway,
/// no orchestration; the reading/refresh rules live in `ReadScene`/`SyncScene`.
@MainActor
@Observable
public final class MailboxViewModel {
    public internal(set) var folders: [Folder] = []
    public internal(set) var messages: [Message] = []
    public internal(set) var body: BodyPresentation = .none
    /// Current body with `cid:` image sources replaced by `data:` URLs. View state only:
    /// never persisted and never copied into `body`/`quotableHTML` (REQ-0025 / SCN-0019).
    public internal(set) var inlineImageHTML: String?
    public internal(set) var bodyNotice: BodyNotice?
    public internal(set) var attachments: [Attachment] = []
    public private(set) var sync = SyncPresentation()
    public internal(set) var selection = Selection()
    /// Chinese, user-visible text for the last failed attachment download. Always derived
    /// from a normalized `MailError` (`ErrorText`), never a raw store error. The setter is
    /// internal so `MailboxViewModel+Attachments.swift` can write it; the public surface is
    /// read-only (REQ-0026 / SCN-0020, G1 confirmed A).
    public internal(set) var attachmentErrorText: String?
    /// Monotonic selection epoch. Incremented only when `selectedListKey` really changes;
    /// `download` captures it to drop late results. Internal: the app target does not read it
    /// (its `AttachmentActionModel` owns a separate epoch).
    @ObservationIgnored private(set) var selectionGeneration: UInt64 = 0
    /// Composite identity for the selected row. Search results span folders, where the
    /// server id alone is not unique (R23); the list and selection use this key.
    public internal(set) var selectedListKey: String? {
        didSet {
            // A selection change is the single reset point for all per-message states.
            // Same-key reloads (sync, body refresh) must not reset them.
            guard oldValue != selectedListKey else { return }
            allowsRemoteContent = false
            markReadErrorText = nil
            attachmentErrorText = nil
            selectionGeneration &+= 1
        }
    }

    /// Whether the current message may load remote images. Session-only: reset on every
    /// selection change and never persisted (REQ-0018 / SCN-0013).
    public private(set) var allowsRemoteContent = false
    /// Chinese, user-visible text for a failed manual mark-read. Always derived from a
    /// normalized `MailError`, never from a raw store/database error (REQ-0019 / F1).
    public private(set) var markReadErrorText: String?

    /// Test seam for the local half of mark-read. Production seeds it with the scene call
    /// after `read` is assigned; it is internal and not part of the public contract.
    @ObservationIgnored var localMarkRead: (MessageRef) throws -> Bool

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
    @ObservationIgnored var inlineImageTask: Task<Void, Never>?
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
        self.localMarkRead = { try read.markReadLocally($0) }
        self.dwell = MailboxDwell(sleep: dwellSleep)
        self.deletion = MailboxDeletion(read: read)
        dwell.onElapsed = { [weak self] ref in
            _ = self?.performMarkRead(ref)
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

    /// The reading pane card for a meeting request; nil for ordinary mail
    /// (REQ-0030 / SCN-0023). Derived on read, no scene call, no network.
    public var meetingCard: MeetingCardPresentation? {
        MeetingCardPresentation.make(from: meetingInvite)
    }

    /// Meeting request for the selected message; loaded on selection because `Message`
    /// no longer carries meeting values (R77).
    public internal(set) var meetingInvite: MeetingInvite?

    func refreshSelectedMeeting() {
        guard let ref = selectedRef else {
            meetingInvite = nil
            return
        }
        meetingInvite = try? read.meeting(for: ref)
    }

    var selectedRef: MessageRef? {
        guard let message = selectedMessage else { return nil }
        return ref(for: message)
    }

    // MARK: - Remote content / manual mark-read (REQ-0018 / REQ-0019)

    /// True when the loaded body provably belongs to the selected message. The stale-body
    /// window (selection moved on, old HTML still on screen) must not inherit permission.
    public var canAllowRemoteContent: Bool {
        guard let ref = selectedRef, case .loaded = body else { return false }
        return openedBody == ref || openingRef == ref
    }

    /// Only the current, visible, unread message can be marked read.
    public var canMarkSelectedRead: Bool {
        guard let selectedMessage, selectedRef != nil else { return false }
        return !selectedMessage.isRead
    }

    /// Enables/disables remote images for the current message. Enabling is guarded by the
    /// current-body identity; disabling is always allowed so the UI can recover.
    public func setAllowsRemoteContent(_ allow: Bool) {
        if allow, !canAllowRemoteContent { return }
        allowsRemoteContent = allow
    }

    /// Toolbar action: local write first, then a conditional background server write.
    public func markSelectedRead() {
        guard canMarkSelectedRead, let ref = selectedRef else { return }
        markReadErrorText = nil
        if let error = performMarkRead(ref) {
            markReadErrorText = ErrorText.text(for: error)
        }
    }

    /// The single mark-read write path shared by the dwell timer and the manual action.
    /// Returns a normalized `MailError` on local failure; callers never see raw store errors.
    @discardableResult
    func performMarkRead(_ ref: MessageRef) -> MailError? {
        do {
            let changed = try localMarkRead(ref)
            try? reloadCurrentList(autoSelect: false)
            refreshDwell()
            markReadErrorText = nil
            // Only a real 0→1 transition starts the server write.
            if changed {
                Task { _ = await read.writeBackMarkRead(ref) }
            }
            return nil
        } catch {
            return Self.normalizeMarkReadError(error)
        }
    }

    /// Marker for the raw scene/storage error surface. The public UI only ever sees the
    /// resulting `MailError`, so `ErrorText` always produces Chinese (F1).
    static func normalizeMarkReadError(_ error: Error) -> MailError {
        (error as? MailError) ?? .storage(reason: String(describing: error))
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

    /// Refreshes the Sent Items collection only (REQ-0038). `apply` re-reads folders and
    /// the visible list; switching to Sent after a first folder sync is handled by the
    /// caller (`selectSent`).
    public func refreshSent() async {
        sync.phase = .syncing
        let outcome = await syncScene.refreshSent()
        apply(outcome)
        if let id = sentFolderID, selection.folderID != id {
            select(folderID: id)
        }
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
            // The status bar shows one problem at a time; a healthy sync retires the old one.
            deletion.clearErrorText()
            markReadErrorText = nil
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

    /// Jump from the calendar to the invite that produced a meeting: leave search mode,
    /// switch folder when needed, reload the page and select/open the message. Returns
    /// whether the message exists in the loaded page.
    @discardableResult
    public func reveal(folderID: String, serverID: String) -> Bool {
        selection.searchQuery = ""
        selection.folderID = folderID
        selection.messageID = nil
        selectedListKey = nil
        clearBody()
        do {
            try reloadCurrentList(autoSelect: false)
        } catch {
            messages = []
            sync.phase = .failed(ErrorText.text(for: error))
            return false
        }
        refreshDwell()
        select(messageID: serverID)
        return selectedListKey != nil
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

    /// Surfaces a local list reload failure from extensions in other files (the setter of
    /// `sync` is private to this file).
    func presentLocalListFailure(_ error: Error) {
        sync.phase = .failed(ErrorText.text(for: error))
    }




}
