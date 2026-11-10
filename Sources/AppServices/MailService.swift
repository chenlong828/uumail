import EASClient
import CryptoKit
import Foundation
import MailStore
import SyncEngine

/// Composition root shared by the app and the CLI: owns the store, the client and the
/// sync engine for the single configured account.
public final class MailService: MailServiceProtocol, MailSendService, @unchecked Sendable {
    public let store: MailStore
    public let accountID: AccountID
    private let configuration: EASConfiguration
    private let client: EASClient
    private let engine: SyncEngine

    public init(
        configuration: EASConfiguration,
        databasePath: String,
        transport: (any EASHTTPTransport)? = nil,
        policyKey: String? = nil
    ) throws {
        self.configuration = configuration
        store = try MailStore(path: databasePath)
        client = EASClient(
            configuration: configuration,
            transport: transport ?? URLSessionTransport(configuration: configuration),
            policyKey: policyKey
        )
        accountID = try Self.existingOrNewAccount(store: store, configuration: configuration)
        engine = SyncEngine(
            gateway: EASGateway(client: client),
            store: StoreAdapter(store: store, account: accountID),
            account: AccountRef(accountID.raw)
        )
    }

    public func syncOnce() async throws -> SyncReport {
        try await engine.syncOnce()
    }

    public func folders() throws -> [StoredFolder] {
        try store.folders(account: accountID)
    }

    /// Returns the stored HTML body, or fetches it through the gateway and stores it.
    public func body(folderID: String, serverID: String) throws -> String? {
        try store.body(account: accountID, folder: folderID, serverID: serverID)?.text
    }

    /// Fetches one body, stores it as HTML and reports whether the gateway had to truncate it.
    public func fetchBody(folderID: String, serverID: String) async throws -> FetchedMessageBody {
        do {
            let fetched = try await client.fetchBody(collectionID: folderID, serverID: serverID)
            let html = fetched.isHTML ? fetched.payload : HTMLText.fromPlainText(fetched.payload)
            try store.applyBody(account: accountID, folder: folderID, serverID: serverID, html: html)
            return FetchedMessageBody(html: html, isTruncated: fetched.isTruncated)
        } catch {
            throw EASGateway.map(error)
        }
    }

    // MARK: - Sending

    /// `account@domain` derived from the server host, matching the probe's From header.
    public var senderAddress: String {
        if let dot = configuration.host.firstIndex(of: ".") {
            return "\(configuration.account)@\(configuration.host[configuration.host.index(after: dot)...])"
        }
        return configuration.account
    }

    /// Enqueues then attempts delivery. A failure leaves the item in `failed` for retry.
    @discardableResult
    public func send(_ draft: MailDraft) async throws -> String {
        let outboxID = try store.enqueueOutbox(account: accountID, draft: draft)
        do {
            let mime = MimeBuilder.build(
                from: senderAddress,
                draft: draft,
                messageID: "\(UUID().uuidString)@\(configuration.host)"
            )
            try await client.send(mime: mime, clientID: outboxID)
            try store.markOutboxSent(account: accountID, outboxID: outboxID)
            return outboxID
        } catch {
            try store.markOutboxFailed(account: accountID, outboxID: outboxID, error: String(describing: error))
            throw EASGateway.map(error)
        }
    }

    public func saveDraft(_ draft: MailDraft) throws -> String {
        var stored = draft
        stored.isDraft = true
        return try store.saveDraft(account: accountID, draft: stored)
    }

    public func pendingOutbox() throws -> [StoredOutboxItem] {
        try store.pendingOutbox(account: accountID)
    }

    public func attachments(folderID: String, messageID: String) throws -> [StoredAttachment] {
        try store.attachments(account: accountID, folder: folderID, messageID: messageID)
    }

    /// Downloads an attachment into the local cache (once) and returns its file URL.
    public func downloadAttachment(folderID: String, messageID: String, attachment: StoredAttachment) async throws -> URL {
        let destination = try Self.cacheURL(for: attachment)
        if let cached = attachment.cachePath, FileManager.default.fileExists(atPath: cached) {
            return URL(fileURLWithPath: cached)
        }
        let data: Data
        do {
            data = try await client.fetchAttachment(fileReference: attachment.fileReference)
        } catch {
            throw EASGateway.map(error)
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination, options: .atomic)
        _ = try? AttachmentCache.prune(directory: destination.deletingLastPathComponent())
        try store.markAttachmentCached(
            account: accountID,
            folder: folderID,
            messageID: messageID,
            fileReference: attachment.fileReference,
            cachePath: destination.path
        )
        return destination
    }

    private static func cacheURL(for attachment: StoredAttachment) throws -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("uumail/attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let digest = SHA256.hash(data: Data(attachment.fileReference.utf8))
            .map { String(format: "%02x", $0) }.joined().prefix(16)
        let safeName = attachment.displayName
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return base.appendingPathComponent("\(digest)-\(safeName)")
    }

    public func searchLocal(query: String, limit: Int = 50) throws -> [StoredMessage] {
        try store.searchLocal(account: accountID, query: query, limit: limit)
    }

    public func messages(folderID: String, limit: Int) throws -> [StoredMessage] {
        try store.messages(account: accountID, folder: folderID, limit: limit)
    }

    public static func defaultDatabasePath() -> String {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("uumail", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("mail.sqlite").path
    }

    private static func existingOrNewAccount(store: MailStore, configuration: EASConfiguration) throws -> AccountID {
        if let first = try store.accounts().first {
            return first
        }
        return try store.createAccount(
            NewAccount(
                displayName: configuration.account,
                address: "\(configuration.account)@\(configuration.host)",
                host: configuration.host
            )
        )
    }
}

/// One fetched body, already converted to HTML, with the gateway's truncation verdict.
public struct FetchedMessageBody: Equatable, Sendable {
    public var html: String
    public var isTruncated: Bool

    public init(html: String, isTruncated: Bool = false) {
        self.html = html
        self.isTruncated = isTruncated
    }
}

/// The app shell's whole view of the mail world. Tests substitute a fake.
public protocol MailServiceProtocol: AnyObject, Sendable {
    func syncOnce() async throws -> SyncReport
    func folders() throws -> [StoredFolder]
    func messages(folderID: String, limit: Int) throws -> [StoredMessage]
    func body(folderID: String, serverID: String) throws -> String?
    func fetchBody(folderID: String, serverID: String) async throws -> FetchedMessageBody
    func searchLocal(query: String, limit: Int) throws -> [StoredMessage]
    func attachments(folderID: String, messageID: String) throws -> [StoredAttachment]
    func downloadAttachment(folderID: String, messageID: String, attachment: StoredAttachment) async throws -> URL
}
