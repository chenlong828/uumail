import Foundation
import MailDomain
import HTMLSupport
import MailStore
import SyncEngine

/// Identifies one message's body: its folder and the server-side id.
public struct MessageRef: Hashable, Sendable {
    public var folderID: String
    public var serverID: String

    public init(folderID: String, serverID: String) {
        self.folderID = folderID
        self.serverID = serverID
    }
}

/// What opening a message reports. `cached` is the locally stored HTML; `loaded` carries
/// the freshly fetched body with plain text already converted to HTML (D10: the scene
/// layer owns that conversion, the presentation keeps `isTruncated`).
public enum BodyEvent: Equatable, Sendable {
    case cached(String)
    case loaded(FetchedBody)
    case failed(MailError)
}

/// The read path: local queries are network-free, opening a body is cache-first with a
/// single-flight fetch-and-store, and attachments go through the `AttachmentFiles` port.
///
/// The only mutable state is the in-flight request tables (spec §4.9/§7): the scene value
/// itself is stateless, so it stays `Sendable` and cheap to copy.
public enum WriteOutcome: Equatable, Sendable {
    case succeeded
    case failed(MailError)
}

public struct ReadScene: Sendable {
    private let store: MailStore
    private let account: AccountID
    private let gateway: any MailGateway
    private let files: any AttachmentFiles
    /// The account's single `SyncEngine`; the write methods are the only network paths.
    private let writeEngine: SyncEngine

    private let bodyFlights = FlightBoard<MessageRef, FetchedBody>()
    private let attachmentFlights = FlightBoard<String, URL>()

    public init(
        store: MailStore,
        account: AccountID,
        gateway: any MailGateway,
        files: any AttachmentFiles,
        writeEngine: SyncEngine
    ) {
        self.store = store
        self.account = account
        self.gateway = gateway
        self.files = files
        self.writeEngine = writeEngine
    }

    // MARK: - Local reads (never touch the network)

    public func folders() throws -> [Folder] {
        try store.folders(account: account)
    }

    public func messages(folderID: String, limit: Int = 200) throws -> [Message] {
        try store.messages(account: account, folder: folderID, limit: limit)
    }

    /// One message by its natural key (REQ-0031): the floating reader and the calendar
    /// entry need a message that is not necessarily on the current list page.
    public func message(_ ref: MessageRef) throws -> Message? {
        try store.message(account: account, folder: ref.folderID, serverID: ref.serverID)
    }

    /// The folder's messages received at or after `since`, newest first, no row cap
    /// (REQ-0033). The window start is computed by the presentation layer.
    public func messages(folderID: String, since: Date) throws -> [Message] {
        try store.messages(account: account, folder: folderID, since: since)
    }

    public func search(_ query: String, limit: Int = 100) throws -> [Message] {
        try store.searchLocal(account: account, query: query, limit: limit)
    }

    public func attachments(for ref: MessageRef) throws -> [Attachment] {
        try store.attachments(account: account, folder: ref.folderID, messageID: ref.serverID)
    }

    /// The stored body as HTML, or `nil` when it has never been fetched.
    public func bodyIfCached(_ ref: MessageRef) throws -> String? {
        guard let stored = try store.body(account: account, folder: ref.folderID, serverID: ref.serverID) else {
            return nil
        }
        return stored.isHTML ? stored.text : HTMLText.fromPlainText(stored.text)
    }

    // MARK: - Write path

    /// Local half of the read marker: zero network. Returns whether this was a real 0→1.
    @discardableResult
    public func markReadLocally(_ ref: MessageRef) throws -> Bool {
        try store.markRead(account: account, folder: ref.folderID, serverID: ref.serverID)
    }

    /// Best-effort server write-back. Failure never rolls the local read back and is not
    /// surfaced to the presentation layer; `.failed` exists for diagnostics/tests.
    public func writeBackMarkRead(_ ref: MessageRef) async -> WriteOutcome {
        do {
            try await writeEngine.markRead(collectionID: ref.folderID, serverID: ref.serverID)
            return .succeeded
        } catch {
            return .failed(Self.classify(error))
        }
    }

    /// Server-confirmed delete. The local soft delete happens inside the engine's store
    /// commit; this method never pre-deletes. Cancellation propagates for PRES to restore.
    public func deleteMessage(_ ref: MessageRef) async throws {
        do {
            try await writeEngine.deleteMessage(collectionID: ref.folderID, serverID: ref.serverID)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Self.classify(error)
        }
    }

    // MARK: - Body

    /// Opens one body: a cached body is yielded immediately without touching the network;
    /// otherwise the body is fetched once per `MessageRef`, stored as HTML, and only then
    /// yielded as `loaded` (so a repeat open hits the cache).
    public func open(_ ref: MessageRef) -> AsyncStream<BodyEvent> {
        let (stream, continuation) = AsyncStream<BodyEvent>.makeStream()
        let flights = bodyFlights
        let task = Task { [self] in
            do {
                if let cached = try bodyIfCached(ref) {
                    continuation.yield(.cached(cached))
                    continuation.finish()
                    return
                }
                let fetched = try await fetchBody(ref)
                try Task.checkCancellation()
                continuation.yield(.loaded(fetched))
            } catch is CancellationError {
                // The consumer went away: nothing is yielded and the fetch never applies
                // its body (the check inside `fetchBody` runs before `applyBody`).
            } catch {
                continuation.yield(.failed(Self.classify(error)))
            }
            continuation.finish()
        }
        continuation.onTermination = { @Sendable _ in
            task.cancel()
            Task { await flights.cancel(ref) }
        }
        return stream
    }

    private func fetchBody(_ ref: MessageRef) async throws -> FetchedBody {
        try await bodyFlights.run(ref) { [self] in
            let fetched = try await gateway.fetchBody(
                collectionID: ref.folderID,
                serverID: ref.serverID
            )
            try Task.checkCancellation()
            let html = fetched.isHTML ? fetched.text : HTMLText.fromPlainText(fetched.text)
            try store.applyBody(
                account: account,
                folder: ref.folderID,
                serverID: ref.serverID,
                html: html
            )
            return FetchedBody(text: html, isHTML: true, isTruncated: fetched.isTruncated)
        }
    }

    // MARK: - Attachments

    /// Returns the cached file, or fetches, stores and records it. The `AttachmentFiles`
    /// port owns the on-disk budget; the scene only marks the row after the file exists.
    public func downloadAttachment(_ attachment: Attachment, in ref: MessageRef) async throws -> URL {
        let reference = AttachmentRef(
            fileReference: attachment.fileReference,
            displayName: attachment.displayName
        )
        if let cached = files.cachedURL(for: reference) {
            return cached
        }

        do {
            return try await attachmentFlights.run(attachment.fileReference) { [self] in
                // Another caller may have finished the same download while this one waited.
                if let cached = files.cachedURL(for: reference) {
                    return cached
                }
                let data = try await gateway.fetchAttachment(fileReference: attachment.fileReference)
                let url = try files.store(data, for: reference)
                try store.markAttachmentCached(
                    account: account,
                    folder: ref.folderID,
                    messageID: ref.serverID,
                    fileReference: attachment.fileReference,
                    cachePath: url.path
                )
                return url
            }
        } catch {
            throw Self.classify(error)
        }
    }

    private static func classify(_ error: Error) -> MailError {
        (error as? MailError) ?? .storage(reason: String(describing: error))
    }
}

/// Single-flight table: callers with the same key share one task and one result.
private actor FlightBoard<Key: Hashable & Sendable, Value: Sendable> {
    private var tasks: [Key: Task<Value, Error>] = [:]

    func run(_ key: Key, operation: @Sendable @escaping () async throws -> Value) async throws -> Value {
        if let task = tasks[key] {
            return try await task.value
        }
        let task = Task { try await operation() }
        tasks[key] = task
        do {
            let value = try await task.value
            tasks[key] = nil
            return value
        } catch {
            tasks[key] = nil
            throw error
        }
    }

    func cancel(_ key: Key) {
        tasks[key]?.cancel()
    }
}
