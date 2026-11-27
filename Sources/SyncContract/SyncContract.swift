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

    // Drafts (REQ-0044): the Drafts folder is written with the same Sync command
    // (MS-ASEMAIL §4.4). Implementations that do not support drafts may leave the
    // defaults below, which fail as `MailError.unsupported`.
    func createDraft(
        _ payload: DraftPayload, collectionID: String, syncKey: String, clientID: String
    ) async throws -> DraftWriteResult
    func updateDraft(
        serverID: String, payload: DraftPayload, collectionID: String, syncKey: String
    ) async throws -> DraftWriteResult
    func deleteDraft(
        serverID: String, collectionID: String, syncKey: String
    ) async throws -> DraftWriteResult
}

public extension MailWriteGateway {
    func createDraft(
        _ payload: DraftPayload, collectionID: String, syncKey: String, clientID: String
    ) async throws -> DraftWriteResult {
        throw MailError.unsupported
    }

    func updateDraft(
        serverID: String, payload: DraftPayload, collectionID: String, syncKey: String
    ) async throws -> DraftWriteResult {
        throw MailError.unsupported
    }

    func deleteDraft(
        serverID: String, collectionID: String, syncKey: String
    ) async throws -> DraftWriteResult {
        throw MailError.unsupported
    }
}

/// One draft's mail fields, the payload the server draft write needs.
public struct DraftPayload: Equatable, Sendable {
    public var to: String
    public var cc: String?
    public var subject: String
    public var bodyHTML: String

    public init(to: String, cc: String?, subject: String, bodyHTML: String) {
        self.to = to
        self.cc = cc
        self.subject = subject
        self.bodyHTML = bodyHTML
    }
}

/// Result of one draft write: the new SyncKey plus, for a create, the server id.
public struct DraftWriteResult: Equatable, Sendable {
    public var serverID: String?
    public var syncKey: String

    public init(serverID: String?, syncKey: String) {
        self.serverID = serverID
        self.syncKey = syncKey
    }
}

/// Store surface the draft sync pass needs (REQ-0044). `MailStore` conforms; the pass
/// lives in `SyncEngine` so it shares the same gateway, write port and advisory gate as
/// the message sync.
public protocol DraftSyncStore: Sendable {
    func drafts(account: AccountID) throws -> [DraftRecord]
    func draft(account: AccountID, draftID: String) throws -> DraftRecord?
    func draft(account: AccountID, serverID: String) throws -> DraftRecord?
    func unboundDrafts(account: AccountID) throws -> [DraftRecord]
    func draftsNeedingUpload(account: AccountID) throws -> [DraftRecord]
    func bindDraft(account: AccountID, draftID: String, serverID: String, hash: String) throws
    func setDraftHash(account: AccountID, draftID: String, hash: String) throws
    func adoptServerDraft(
        account: AccountID, draftID: String, draft: MailDomain.Draft,
        updatedAt: Date, hash: String
    ) throws
    func insertServerDraft(
        account: AccountID, serverID: String, draft: MailDomain.Draft,
        updatedAt: Date, hash: String
    ) throws
    func duplicateDraft(account: AccountID, draftID: String) throws -> String
    func unbindDraft(account: AccountID, draftID: String) throws
    func deleteDraft(account: AccountID, draftID: String) throws
    func addDraftTombstone(account: AccountID, serverID: String) throws
    func draftTombstones(account: AccountID) throws -> [String]
    func removeDraftTombstone(account: AccountID, serverID: String) throws
    func syncKey(account: AccountID, collection: String) throws -> String?
    func setSyncKey(account: AccountID, collection: String, key: String) throws
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
