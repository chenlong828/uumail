import Foundation

// MARK: - Values seen by the sync engine

public struct FolderSummary: Equatable, Sendable {
    public var serverID: String
    public var parentID: String?
    public var displayName: String
    public var type: Int

    public init(serverID: String, parentID: String?, displayName: String, type: Int) {
        self.serverID = serverID
        self.parentID = parentID
        self.displayName = displayName
        self.type = type
    }

    public var isInbox: Bool { type == 2 }
}

public struct MessageSummary: Equatable, Sendable {
    public var serverID: String
    public var subject: String?
    public var sender: String?
    public var recipients: String?
    public var receivedRaw: String?
    public var isRead: Bool
    public var importance: Int?
    public var bodyPreview: String?

    public init(
        serverID: String,
        subject: String? = nil,
        sender: String? = nil,
        recipients: String? = nil,
        receivedRaw: String? = nil,
        isRead: Bool = false,
        importance: Int? = nil,
        bodyPreview: String? = nil
    ) {
        self.serverID = serverID
        self.subject = subject
        self.sender = sender
        self.recipients = recipients
        self.receivedRaw = receivedRaw
        self.isRead = isRead
        self.importance = importance
        self.bodyPreview = bodyPreview
    }
}

public struct FolderListing: Equatable, Sendable {
    public var folders: [FolderSummary]
    public var syncKey: String

    public init(folders: [FolderSummary], syncKey: String) {
        self.folders = folders
        self.syncKey = syncKey
    }
}

public struct MessageDelta: Equatable, Sendable {
    public var added: [MessageSummary]
    public var changed: [MessageSummary]
    public var removedServerIDs: [String]
    public var syncKey: String
    public var moreAvailable: Bool

    public init(
        added: [MessageSummary],
        changed: [MessageSummary],
        removedServerIDs: [String],
        syncKey: String,
        moreAvailable: Bool
    ) {
        self.added = added
        self.changed = changed
        self.removedServerIDs = removedServerIDs
        self.syncKey = syncKey
        self.moreAvailable = moreAvailable
    }
}

// MARK: - Errors crossing the port

/// The gateway port speaks domain errors only. Adapters translate whatever the
/// transport produced (EASError, URLError, ...) into these cases.
public enum MailGatewayError: Error, Equatable, Sendable {
    case authFailed
    case deviceNotRegistered
    case policyBlocked
    case syncKeyInvalid
    case throttled(retryAfterSeconds: Int?)
    case offline
    case unsupported
}

// MARK: - State

public enum SyncState: Equatable, Sendable {
    case idle
    case syncingFolders
    case syncingMessages(folder: String)
    case failed(SyncFailure)

    public struct SyncFailure: Equatable, Sendable {
        public var error: MailGatewayError
        public var folder: String?
        /// Failed calls since the last success; drives backoff in later milestones.
        public var consecutiveFailures: Int

        public init(error: MailGatewayError, folder: String?, consecutiveFailures: Int) {
            self.error = error
            self.folder = folder
            self.consecutiveFailures = consecutiveFailures
        }
    }
}

public struct SyncReport: Equatable, Sendable {
    public var folders: Int
    public var added: Int
    public var changed: Int
    public var removed: Int
    public var rounds: Int
    public var syncKey: String

    public init(folders: Int, added: Int, changed: Int, removed: Int, rounds: Int, syncKey: String) {
        self.folders = folders
        self.added = added
        self.changed = changed
        self.removed = removed
        self.rounds = rounds
        self.syncKey = syncKey
    }
}
