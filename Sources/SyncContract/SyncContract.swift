import Foundation
import MailDomain
import MeetingDomain

/// One Sync response: what changed since `syncKey`, and the next key.
///
/// Lives in the sync contract, not in `MailDomain`, because a batch carries both mail
/// envelopes and the meeting requests parsed from the same response; only this target
/// knows both domains (2026-11-24 P1, R77).
public struct MessageDelta: Equatable, Sendable {
    public var added: [Message]
    public var changed: [Message]
    public var removedServerIDs: [String]
    public var syncKey: String
    public var moreAvailable: Bool
    /// Meeting requests parsed from the same response. They travel with the batch so the
    /// store can write messages and meetings in one transaction; `Message` itself stays
    /// free of meeting values (2026-11-24 P1, R77).
    public var meetings: [MeetingDeltaEntry]

    public init(
        added: [Message],
        changed: [Message],
        removedServerIDs: [String],
        syncKey: String,
        moreAvailable: Bool,
        meetings: [MeetingDeltaEntry] = []
    ) {
        self.added = added
        self.changed = changed
        self.removedServerIDs = removedServerIDs
        self.syncKey = syncKey
        self.moreAvailable = moreAvailable
        self.meetings = meetings
    }
}

/// One meeting carried by a sync batch, tied to the message that produced it.
public struct MeetingDeltaEntry: Equatable, Sendable {
    public var serverID: String
    /// Envelope subject, used when the invite itself has none.
    public var subject: String?
    public var invite: MeetingInvite

    public init(serverID: String, subject: String?, invite: MeetingInvite) {
        self.serverID = serverID
        self.subject = subject
        self.invite = invite
    }
}

/// L1 gateway port: server capabilities in domain concepts, never EAS types or
/// status-code strings. `EASAdapter` is the only implementation that maps errors.
public protocol MailGateway: Sendable {
    func probe() async throws -> ServerCapabilities
    func provisionIfNeeded() async throws
    func fetchFolders(syncKey: String) async throws -> FolderListing
    func fetchMessages(collectionID: String, syncKey: String, window: Int, filterType: Int) async throws -> MessageDelta
    func fetchBody(collectionID: String, serverID: String) async throws -> FetchedBody
    func fetchAttachment(fileReference: String) async throws -> Data
    func send(mime: Data, clientID: String) async throws
}

/// Narrow write port for one-message mailbox mutations. Every call sends exactly one
/// EAS Sync write command and returns the server's delta plus the next collection key.
public protocol MailWriteGateway: Sendable {
    func markRead(collectionID: String, serverID: String, syncKey: String) async throws -> MessageDelta
    func delete(collectionID: String, serverID: String, syncKey: String) async throws -> MessageDelta
}

/// Store port for the sync engine. Local database work is synchronous; `MailStore`
/// conforms directly.
public protocol SyncStore: Sendable {
    func folders(_ account: AccountID) throws -> [Folder]
    func applyFolderSnapshot(_ account: AccountID, folders: [Folder], syncKey: String) throws
    func syncKey(_ account: AccountID, collection: String) throws -> String?
    func applySyncBatch(_ account: AccountID, folder: String, delta: MessageDelta) throws
    /// Drops the local mirror of one collection so a full re-sync can rebuild it.
    func resetCollection(_ account: AccountID, folder: String) throws
    /// Local half of the read marker: only the target row, no key or network.
    @discardableResult
    func markRead(_ account: AccountID, folder: String, serverID: String) throws -> Bool
    /// Commits a server-confirmed read marker, its response delta and the new key atomically.
    func commitMarkRead(_ account: AccountID, folder: String, serverID: String, delta: MessageDelta) throws
    /// Commits a server-confirmed delete, its response delta and the new key atomically.
    func commitDelete(_ account: AccountID, folder: String, serverID: String, delta: MessageDelta) throws
}
