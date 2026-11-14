import Foundation

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

/// Narrow write port for one-message mailbox mutations. Kept apart from `MailGateway`
/// so read-only fakes and the read contract stay untouched. Every call sends exactly one
/// EAS Sync write command and returns the server's delta plus the next collection key.
public protocol MailWriteGateway: Sendable {
    func markRead(collectionID: String, serverID: String, syncKey: String) async throws -> MessageDelta
    func delete(collectionID: String, serverID: String, syncKey: String) async throws -> MessageDelta
}

/// Store port for the sync engine. Local database work is synchronous; `MailStore`
/// conforms directly (the adapter disappears in this refactor).
public protocol SyncStore: Sendable {
    func folders(_ account: AccountID) throws -> [Folder]
    func applyFolderSnapshot(_ account: AccountID, folders: [Folder], syncKey: String) throws
    func syncKey(_ account: AccountID, collection: String) throws -> String?
    func applySyncBatch(_ account: AccountID, folder: String, delta: MessageDelta) throws
    /// Drops the local mirror of one collection so a full re-sync can rebuild it.
    func resetCollection(_ account: AccountID, folder: String) throws
}

/// Credentials: Keychain in the app, in-memory in tests.
public protocol CredentialStore: Sendable {
    func load() throws -> ServerConfiguration?
    func save(_ configuration: ServerConfiguration) throws
    func delete() throws
}

/// System notification poster. Failures degrade silently by design.
public protocol Notifier: Sendable {
    func requestAuthorization() async
    func postNewMail(count: Int) async
}

/// Attachment file cache. Implementations own the 2 GB oldest-first budget.
public protocol AttachmentFiles: Sendable {
    func cachedURL(for reference: AttachmentRef) -> URL?
    func store(_ data: Data, for reference: AttachmentRef) throws -> URL
}

/// Injectable clock so polling and leases are testable without real time.
public protocol MailClock: Sendable {
    var now: Date { get }
    func sleep(for duration: Duration) async throws
}
