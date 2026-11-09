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

    public private(set) var folders: [StoredFolder] = []
    public private(set) var messages: [StoredMessage] = []
    public private(set) var state: State = .idle
    public private(set) var lastSyncedAt: Date?
    public var selectedFolderID: String? {
        didSet {
            guard oldValue != selectedFolderID else { return }
            Task { await self.loadMessages() }
        }
    }

    private let service: any MailServiceProtocol

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
    }

    private func loadMessages() async {
        try? reloadMessages()
    }
}
