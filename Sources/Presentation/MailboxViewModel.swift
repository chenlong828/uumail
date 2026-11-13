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
    public private(set) var body: BodyPresentation = .none
    public private(set) var bodyNotice: BodyNotice?
    public private(set) var attachments: [Attachment] = []
    public private(set) var sync = SyncPresentation()
    public private(set) var selection = Selection()

    private let read: ReadScene
    private let syncScene: SyncScene
    private let composeScene: ComposeScene
    private let account: AccountID
    /// Wakes the composition's delivery pump after an enqueue. Composition owns the loop;
    /// the view model only forwards the signal.
    private let onEnqueued: (@MainActor () -> Void)?

    private var autoRefreshTask: Task<Void, Never>?
    private var bodyTask: Task<Void, Never>?
    private var openingRef: MessageRef?
    private var openedBody: MessageRef?

    public init(
        read: ReadScene,
        sync: SyncScene,
        compose: ComposeScene,
        account: AccountID,
        onEnqueued: (@MainActor () -> Void)? = nil
    ) {
        self.read = read
        self.syncScene = sync
        self.composeScene = compose
        self.account = account
        self.onEnqueued = onEnqueued
    }

    // MARK: - Derived state

    public var selectedMessage: Message? {
        guard let id = selection.messageID else { return nil }
        return messages.first { $0.serverID == id }
    }

    private var selectedRef: MessageRef? {
        guard let message = selectedMessage else { return nil }
        guard let folder = message.folderID ?? selection.folderID else { return nil }
        return MessageRef(folderID: folder, serverID: message.serverID)
    }

    /// The body HTML a reply/forward may quote: never a sync preview.
    private var quotableHTML: String? {
        guard bodyNotice == nil, case .loaded(let html, _) = body else { return nil }
        return html
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
        try? reloadMessages(autoSelect: true)
    }

    private func apply(_ outcome: RefreshOutcome) {
        do {
            try reloadFolders()
            try reloadMessages(autoSelect: true)
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
    }

    // MARK: - Selection

    public func select(folderID: String) {
        guard selection.folderID != folderID else { return }
        selection.folderID = folderID
        selection.messageID = nil
        clearBody()
        do {
            try reloadMessages(autoSelect: false)
        } catch {
            messages = []
            sync.phase = .failed(ErrorText.text(for: error))
        }
    }

    public func select(messageID: String) {
        guard selection.messageID != messageID else { return }
        selection.messageID = messageID
        Task { await self.openSelected() }
    }

    // MARK: - Body

    /// Opens the selected message: cached body immediately, otherwise a preview while
    /// the scene fetches. A second call for the same message joins the in-flight open.
    public func openSelected() async {
        guard let ref = selectedRef else {
            clearBody()
            return
        }
        if openedBody == ref, case .loaded = body { return }
        if let inFlight = bodyTask, openingRef == ref {
            await inFlight.value
            return
        }

        bodyTask?.cancel()
        bodyTask = nil
        openingRef = ref
        openedBody = nil
        body = .none
        bodyNotice = nil
        attachments = (try? read.attachments(for: ref)) ?? []

        let cached: String?
        do {
            cached = try read.bodyIfCached(ref)
        } catch {
            cached = nil
        }
        if let cached, !cached.isEmpty {
            body = .loaded(html: cached, truncated: false)
            openedBody = ref
            openingRef = nil
            return
        }

        let message = messages.first { $0.serverID == ref.serverID }
        if let preview = Self.previewHTML(for: message?.bodyPreview) {
            body = .loaded(html: preview, truncated: false)
            bodyNotice = .fetchingFullBody
        } else {
            body = .loading
        }

        let stream = read.open(ref)
        let task = Task { [weak self] in
            for await event in stream {
                guard let self, !Task.isCancelled else { break }
                self.apply(event, for: ref)
            }
        }
        bodyTask = task
        await task.value
        if openingRef == ref {
            openingRef = nil
            bodyTask = nil
        }
    }

    private func apply(_ event: BodyEvent, for ref: MessageRef) {
        guard selection.messageID == ref.serverID else { return }
        switch event {
        case .cached(let html):
            body = .loaded(html: html, truncated: false)
            bodyNotice = nil
            openedBody = ref
        case .loaded(let fetched):
            body = .loaded(html: fetched.text, truncated: fetched.isTruncated)
            bodyNotice = nil
            openedBody = ref
        case .failed(let error):
            let text = ErrorText.text(for: error)
            if case .loaded(let html, let truncated) = body, bodyNotice != nil {
                // Keep the preview readable; the no-preview case falls back to retry.
                body = .loaded(html: html, truncated: truncated)
                bodyNotice = .previewFallback(text: text)
            } else {
                body = .failed(text: text)
                bodyNotice = nil
            }
        }
    }

    private func clearBody() {
        bodyTask?.cancel()
        bodyTask = nil
        openingRef = nil
        openedBody = nil
        body = .none
        bodyNotice = nil
        attachments = []
    }

    private static func previewHTML(for preview: String?) -> String? {
        guard let preview else { return nil }
        let trimmed = preview.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return HTMLText.fromPlainText(trimmed)
    }

    // MARK: - Search

    /// Local FTS search; an empty query restores the selected folder's list.
    public func search(_ query: String) async {
        selection.searchQuery = query
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            do {
                try reloadMessages(autoSelect: true)
            } catch {
                messages = []
                sync.phase = .failed(ErrorText.text(for: error))
            }
            return
        }
        do {
            messages = try read.search(trimmed, limit: 100)
        } catch {
            messages = []
            sync.phase = .failed(ErrorText.text(for: error))
        }
    }

    // MARK: - Attachments

    /// Downloads (or reuses) one attachment and returns the file to open.
    public func download(_ attachment: Attachment) async -> URL? {
        guard let ref = selectedRef else { return nil }
        return try? await read.downloadAttachment(attachment, in: ref)
    }

    // MARK: - Compose

    public func composeNew() -> ComposeViewModel {
        ComposeViewModel(mode: .new, scene: composeScene, account: account, onEnqueued: onEnqueued)
    }

    public func composeReply() -> ComposeViewModel? {
        guard let message = selectedMessage else { return nil }
        return ComposeViewModel(
            replyTo: message,
            bodyHTML: quotableHTML,
            scene: composeScene,
            account: account,
            onEnqueued: onEnqueued
        )
    }

    public func composeForward() -> ComposeViewModel? {
        guard let message = selectedMessage else { return nil }
        return ComposeViewModel(
            forwarding: message,
            bodyHTML: quotableHTML,
            scene: composeScene,
            account: account,
            onEnqueued: onEnqueued
        )
    }

    // MARK: - Local reads

    private func reloadFolders() throws {
        folders = try read.folders()
        if let current = selection.folderID, folders.contains(where: { $0.serverID == current }) {
            return
        }
        selection.folderID = folders.first(where: \.isInbox)?.serverID ?? folders.first?.serverID
    }

    private func reloadMessages(autoSelect: Bool) throws {
        guard let folder = selection.folderID else {
            messages = []
            selection.messageID = nil
            clearBody()
            return
        }
        messages = try read.messages(folderID: folder, limit: 200)
        if let selected = selection.messageID, messages.contains(where: { $0.serverID == selected }) {
            return
        }
        if autoSelect, let first = messages.first {
            selection.messageID = first.serverID
            Task { await self.openSelected() }
        } else {
            selection.messageID = nil
            clearBody()
        }
    }
}
