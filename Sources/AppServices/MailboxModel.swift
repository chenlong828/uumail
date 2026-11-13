import Foundation
import MailStore
import Observation
import Scenes
import SyncEngine

/// Presentation state for the mailbox window. Owns no persistence: the service does.
@MainActor
@Observable
public final class MailboxModel {
    public enum State: Equatable, Sendable {
        case idle
        case syncing
        case failed(String)
    }

    /// What the reading pane shows. `isPreview` marks the sync preview: readable right away,
    /// but only the first screenful of the message, so the pane keeps fetching behind it.
    public struct BodyContent: Equatable, Sendable {
        public var html: String
        public var isPreview: Bool
        public var isTruncated: Bool
        public var error: String?

        public init(html: String, isPreview: Bool = false, isTruncated: Bool = false, error: String? = nil) {
            self.html = html
            self.isPreview = isPreview
            self.isTruncated = isTruncated
            self.error = error
        }
    }

    public enum DetailState: Equatable, Sendable {
        case none
        case loading
        case loaded(BodyContent)
        case failed(String)
    }

    public private(set) var folders: [StoredFolder] = []
    public private(set) var messages: [StoredMessage] = []
    public private(set) var state: State = .idle
    public private(set) var lastSyncedAt: Date?
    public private(set) var attachments: [StoredAttachment] = []
    public private(set) var detailState: DetailState = .none {
        didSet { /* observation only */ }
    }

    public var searchQuery: String = "" {
        didSet { Task { await self.applySearch() } }
    }

    public var selectedMessageID: String? {
        didSet {
            guard oldValue != selectedMessageID else { return }
            loadedBodyFor = nil
            Task { await self.loadBody() }
        }
    }
    public var selectedFolderID: String? {
        didSet {
            guard oldValue != selectedFolderID else { return }
            Task { await self.loadMessages() }
        }
    }

    private let service: any MailServiceProtocol
    private let notifier: (any NotificationPosting)?

    /// The same object in the app; tests can leave it nil.
    public var sendService: (any MailSendService)? { service as? any MailSendService }
    private var loadedBodyFor: String?

    public init(service: any MailServiceProtocol, notifier: (any NotificationPosting)? = nil) {
        self.service = service
        self.notifier = notifier
    }

    /// Pulls new mail, then refreshes the visible lists. On failure the cached lists stay
    /// on screen and the error is surfaced separately.
    public func refresh() async {
        state = .syncing
        do {
            let report = try await service.syncOnce()
            try reloadFolders()
            try reloadMessages()
            lastSyncedAt = Date()
            state = .idle
            if report.added > 0 {
                await notifier?.post(
                    title: "uumail",
                    body: "\(report.added) 封新邮件"
                )
            }
        } catch {
            try? reloadFolders()
            try? reloadMessages()
            state = .failed(String(describing: error))
        }
    }

    /// Shows whatever the local store already holds, before the network answers.
    public func loadCached() {
        try? reloadFolders()
        try? reloadMessages()
    }

    public func selectInboxIfNeeded() {
        if selectedFolderID == nil {
            selectedFolderID = folders.first(where: { $0.type == 2 })?.serverID ?? folders.first?.serverID
        }
    }

    private func reloadFolders() throws {
        folders = try service.folders()
        if selectedFolderID == nil || !folders.contains(where: { $0.serverID == selectedFolderID }) {
            selectedFolderID = folders.first(where: { $0.type == 2 })?.serverID ?? folders.first?.serverID
        }
    }

    private func reloadMessages() throws {
        guard let folder = selectedFolderID else {
            messages = []
            return
        }
        messages = try service.messages(folderID: folder, limit: 200)
        if selectedMessageID == nil, let first = messages.first {
            selectedMessageID = first.serverID
        }
    }

    func applySearch() async {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try? reloadMessages()
            return
        }
        do {
            messages = try service.searchLocal(query: trimmed, limit: 100)
        } catch {
            messages = []
            state = .failed(String(describing: error))
        }
    }

    private func loadMessages() async {
        try? reloadMessages()
        // Switching folders clears the reading pane, but a refresh that keeps the same
        // selected message must not throw away its body.
        if let id = selectedMessageID, messages.contains(where: { $0.serverID == id }) {
            return
        }
        detailState = .none
        loadedBodyFor = nil
    }

    /// Downloads (or reuses) one attachment and returns the file to open.
    public func downloadAttachment(_ attachment: StoredAttachment) async throws -> URL {
        guard let messageID = selectedMessageID else {
            throw MailGatewayError.unsupported
        }
        let folder = messages.first { $0.serverID == messageID }?.folderID ?? selectedFolderID ?? ""
        return try await service.downloadAttachment(
            folderID: folder, messageID: messageID, attachment: attachment
        )
    }

    /// Shows a cached body immediately; otherwise paints the sync preview and fetches the
    /// real body behind it. The preview is not a body: it never blocks the fetch.
    public func loadBody() async {
        if case .loading = detailState { return }
        guard let messageID = selectedMessageID else {
            detailState = .none
            return
        }
        if loadedBodyFor == messageID, case .loaded = detailState { return }
        let selected = messages.first { $0.serverID == messageID }
        let folderID = selected?.folderID ?? selectedFolderID ?? ""
        attachments = (try? service.attachments(folderID: folderID, messageID: messageID)) ?? []
        if let cached = try? service.body(folderID: folderID, serverID: messageID), !cached.isEmpty {
            detailState = .loaded(BodyContent(html: cached))
            loadedBodyFor = messageID
            return
        }
        let previewHTML = Self.htmlForPreview(selected?.bodyPreview)
        if let previewHTML {
            detailState = .loaded(BodyContent(html: previewHTML, isPreview: true))
            loadedBodyFor = messageID
        } else {
            detailState = .loading
        }
        do {
            let body = try await service.fetchBody(folderID: folderID, serverID: messageID)
            detailState = .loaded(BodyContent(html: body.html, isTruncated: body.isTruncated))
            loadedBodyFor = messageID
        } catch {
            // A preview keeps the message readable when the full body cannot be fetched;
            // without one the pane falls back to the retry state.
            let message = String(describing: error)
            if let previewHTML {
                detailState = .loaded(BodyContent(html: previewHTML, isPreview: true, error: message))
            } else {
                detailState = .failed(message)
            }
        }
    }

    /// The sync preview is plain text: render it as such instead of feeding it to the
    /// HTML pane, which would collapse every line break.
    private static func htmlForPreview(_ preview: String?) -> String? {
        guard let preview else { return nil }
        let trimmed = preview.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return HTMLText.fromPlainText(trimmed)
    }
}
