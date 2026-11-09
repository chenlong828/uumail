import EASClient
import CryptoKit
import Foundation
import MailStore
import SyncEngine

/// Composition root shared by the app and the CLI: owns the store, the client and the
/// sync engine for the single configured account.
public final class MailService: MailServiceProtocol, @unchecked Sendable {
    public let store: MailStore
    public let accountID: AccountID
    private let client: EASClient
    private let engine: SyncEngine

    public init(configuration: EASConfiguration, databasePath: String) throws {
        store = try MailStore(path: databasePath)
        client = EASClient(
            configuration: configuration,
            transport: URLSessionTransport(configuration: configuration)
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

    public func fetchBody(folderID: String, serverID: String) async throws -> String {
        do {
            let html = try await client.fetchBody(collectionID: folderID, serverID: serverID)
            try store.applyBody(account: accountID, folder: folderID, serverID: serverID, html: html)
            return html
        } catch {
            throw EASGateway.map(error)
        }
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

/// The app shell's whole view of the mail world. Tests substitute a fake.
public protocol MailServiceProtocol: AnyObject, Sendable {
    func syncOnce() async throws -> SyncReport
    func folders() throws -> [StoredFolder]
    func messages(folderID: String, limit: Int) throws -> [StoredMessage]
    func body(folderID: String, serverID: String) throws -> String?
    func fetchBody(folderID: String, serverID: String) async throws -> String
    func attachments(folderID: String, messageID: String) throws -> [StoredAttachment]
    func downloadAttachment(folderID: String, messageID: String, attachment: StoredAttachment) async throws -> URL
}
