import Foundation
import MailDomain

/// What the reading pane shows (spec §4.11). `loaded` carries the fetched/cached HTML
/// and the gateway's truncation verdict; preview fallbacks are a separate notice so
/// the loaded payload stays exactly the body the scene produced.
public enum BodyPresentation: Equatable, Sendable {
    case none
    case loading
    case loaded(html: String, truncated: Bool)
    case failed(text: String)
}

/// Transient note above the rendered body: a sync preview is on screen while the full
/// body is still being fetched, or the fetch failed and the preview is all we have.
public enum BodyNotice: Equatable, Sendable {
    case fetchingFullBody
    case previewFallback(text: String)
}

/// Refresh state for the status bar. `lastSyncedAt` survives a failed run so the user
/// can see when the currently displayed data was last verified.
public struct SyncPresentation: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case syncing
        case failed(String)
    }

    public var phase: Phase
    public var lastSyncedAt: Date?

    public init(phase: Phase = .idle, lastSyncedAt: Date? = nil) {
        self.phase = phase
        self.lastSyncedAt = lastSyncedAt
    }
}

/// Current navigation state: the selected folder/message and the search query.
public struct Selection: Equatable, Sendable {
    public var folderID: String?
    public var messageID: String?
    public var searchQuery: String

    public init(folderID: String? = nil, messageID: String? = nil, searchQuery: String = "") {
        self.folderID = folderID
        self.messageID = messageID
        self.searchQuery = searchQuery
    }
}
