import Foundation
import MailStore
import Observation
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

    public enum DetailState: Equatable, Sendable {
        case none
        case loading
        case loaded(String)
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

    /// The same object in the app; tests can leave it nil.
    public var sendService: (any MailSendService)? { service as? any MailSendService }
    private var loadedBodyFor: String?

    public init(service: any MailServiceProtocol) {
        self.service = service
    }

    /// Pulls new mail, then refreshes the visible lists. On failure the cached lists stay
    /// on screen and the error is surfaced separately.
    public func refresh() async {
        state = .syncing
        do {
            _ = try await service.syncOnce()
            try reloadFolders()
            try reloadMessages()
            lastSyncedAt = Date()
            state = .idle
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
        guard let messageID = selectedMessageID, let folderID = selectedFolderID else {
            throw MailGatewayError.unsupported
        }
        return try await service.downloadAttachment(
            folderID: folderID, messageID: messageID, attachment: attachment
        )
    }

    /// Shows a cached body immediately; otherwise fetches it and stores it.
    public func loadBody() async {
        if case .loading = detailState { return }
        guard let messageID = selectedMessageID, let folderID = selectedFolderID else {
            detailState = .none
            return
        }
        if loadedBodyFor == messageID, case .loaded = detailState { return }
        attachments = (try? service.attachments(folderID: folderID, messageID: messageID)) ?? []
        if let cached = try? service.body(folderID: folderID, serverID: messageID), !cached.isEmpty {
            detailState = .loaded(cached)
            loadedBodyFor = messageID
            return
        }
        detailState = .loading
        do {
            let html = try await service.fetchBody(folderID: folderID, serverID: messageID)
            detailState = .loaded(html)
            loadedBodyFor = messageID
        } catch {
            detailState = .failed(String(describing: error))
        }
    }
}
