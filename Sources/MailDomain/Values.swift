import Foundation

/// Stable account identifier shared by every module.
public struct AccountID: Hashable, Sendable, CustomStringConvertible {
    public let raw: String

    public init(_ raw: String) {
        self.raw = raw
    }

    public var description: String { raw }
}

/// A mailbox folder as the domain knows it: no protocol shape, no database row.
public struct Folder: Equatable, Sendable {
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

    /// Exchange folder type `2` is the inbox.
    public var isInbox: Bool { type == 2 }
}

/// An attachment as listed on a message. `messageID` is absent until the store has
/// associated the row with a message.
public struct Attachment: Equatable, Sendable, Identifiable {
    public var messageID: String?
    public var displayName: String
    public var fileReference: String
    public var size: Int?
    public var cachePath: String?

    public var id: String { fileReference }

    public init(displayName: String, fileReference: String, size: Int? = nil) {
        self.displayName = displayName
        self.fileReference = fileReference
        self.size = size
    }

    public init(messageID: String, displayName: String, fileReference: String, size: Int?, cachePath: String?) {
        self.messageID = messageID
        self.displayName = displayName
        self.fileReference = fileReference
        self.size = size
        self.cachePath = cachePath
    }
}

/// One message: envelope fields, the locally cached preview, and its attachments.
public struct Message: Equatable, Sendable {
    public var serverID: String
    public var subject: String?
    public var sender: String?
    public var recipients: String?
    public var receivedRaw: String?
    public var isRead: Bool
    public var importance: Int?
    public var bodyPreview: String?
    public var folderID: String?
    public var attachments: [Attachment]

    public init(
        serverID: String,
        subject: String? = nil,
        sender: String? = nil,
        recipients: String? = nil,
        receivedRaw: String? = nil,
        isRead: Bool = false,
        importance: Int? = nil,
        bodyPreview: String? = nil,
        folderID: String? = nil,
        attachments: [Attachment] = []
    ) {
        self.serverID = serverID
        self.subject = subject
        self.sender = sender
        self.recipients = recipients
        self.receivedRaw = receivedRaw
        self.isRead = isRead
        self.importance = importance
        self.bodyPreview = bodyPreview
        self.folderID = folderID
        self.attachments = attachments
    }
}

/// The full folder tree as one snapshot plus the key it belongs to.
public struct FolderListing: Equatable, Sendable {
    public var folders: [Folder]
    public var syncKey: String

    public init(folders: [Folder], syncKey: String) {
        self.folders = folders
        self.syncKey = syncKey
    }
}

/// One Sync response: what changed since `syncKey`, and the next key.
public struct MessageDelta: Equatable, Sendable {
    public var added: [Message]
    public var changed: [Message]
    public var removedServerIDs: [String]
    public var syncKey: String
    public var moreAvailable: Bool

    public init(
        added: [Message],
        changed: [Message],
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

/// What the gateway advertises about itself (protocol versions and command list).
public struct ServerCapabilities: Equatable, Sendable {
    public let protocolVersions: [String]
    public let commands: [String]

    public init(protocolVersions: [String], commands: [String]) {
        self.protocolVersions = protocolVersions
        self.commands = commands
    }
}

/// One sync run's accounting, returned to the caller for status and logging.
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

/// A message being written: reply/forward seeds and drafts use the same shape.
public struct Draft: Equatable, Sendable {
    public var to: String
    public var cc: String?
    public var subject: String
    public var body: String
    public var inReplyTo: String?
    public var references: String?
    public var isDraft: Bool

    public init(
        to: String,
        cc: String?,
        subject: String,
        body: String,
        inReplyTo: String? = nil,
        references: String? = nil,
        isDraft: Bool = false
    ) {
        self.to = to
        self.cc = cc
        self.subject = subject
        self.body = body
        self.inReplyTo = inReplyTo
        self.references = references
        self.isDraft = isDraft
    }
}

/// One row of the outbox as the store keeps it (state machine owned by `Outbox`).
public struct OutboxItem: Equatable, Sendable {
    public var id: String
    public var to: String
    public var cc: String?
    public var subject: String
    public var body: String
    public var inReplyTo: String?
    public var references: String?
    public var state: String
    public var attempts: Int
    public var lastError: String?

    public init(
        id: String,
        to: String,
        cc: String?,
        subject: String,
        body: String,
        inReplyTo: String?,
        references: String?,
        state: String,
        attempts: Int,
        lastError: String?
    ) {
        self.id = id
        self.to = to
        self.cc = cc
        self.subject = subject
        self.body = body
        self.inReplyTo = inReplyTo
        self.references = references
        self.state = state
        self.attempts = attempts
        self.lastError = lastError
    }
}

/// A body fetched from the gateway. `isHTML` says whether the payload is HTML or
/// plain text (the scene layer converts), `isTruncated` says the server cut it.
public struct FetchedBody: Equatable, Sendable {
    public var text: String
    public var isHTML: Bool
    public var isTruncated: Bool

    public init(text: String, isHTML: Bool, isTruncated: Bool) {
        self.text = text
        self.isHTML = isHTML
        self.isTruncated = isTruncated
    }
}

/// Reference to a cached attachment file, used by the `AttachmentFiles` port.
/// `displayName` decides the on-disk file name suffix (the digest prefixes it).
public struct AttachmentRef: Hashable, Sendable {
    public let fileReference: String
    public let displayName: String

    public init(fileReference: String, displayName: String) {
        self.fileReference = fileReference
        self.displayName = displayName
    }
}
