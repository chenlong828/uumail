import Foundation
import GRDB

/// The single writer for the local mail database (see `doc/design/components/CMP-STORE/spec.md`).
/// This slice owns accounts, device profiles, folders and sync state; message tables arrive
/// with the sync work.
public final class MailStore: @unchecked Sendable {
    private let dbQueue: DatabaseQueue

    public init(path: String) throws {
        dbQueue = try DatabaseQueue(path: path)
        try migrate()
    }

    public static func inMemory() throws -> MailStore {
        let store = try MailStore(path: ":memory:")
        return store
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_accounts_folders") { db in
            try db.execute(sql: """
                CREATE TABLE accounts (
                    id TEXT PRIMARY KEY,
                    display_name TEXT NOT NULL,
                    address TEXT NOT NULL,
                    host TEXT NOT NULL,
                    state TEXT NOT NULL,
                    created_at REAL NOT NULL
                );

                CREATE TABLE device_profiles (
                    account_id TEXT PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
                    device_id TEXT NOT NULL,
                    device_type TEXT NOT NULL,
                    protocol_version TEXT NOT NULL,
                    user_agent TEXT NOT NULL
                );

                CREATE TABLE folders (
                    account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
                    server_id TEXT NOT NULL,
                    parent_id TEXT,
                    display_name TEXT NOT NULL,
                    type INTEGER NOT NULL,
                    deleted_at REAL,
                    updated_at REAL NOT NULL,
                    PRIMARY KEY (account_id, server_id)
                );

                CREATE INDEX idx_folders_account_type ON folders(account_id, type);

                CREATE TABLE sync_state (
                    account_id TEXT NOT NULL,
                    collection TEXT NOT NULL,
                    sync_key TEXT NOT NULL,
                    last_sync_at REAL,
                    last_error TEXT,
                    PRIMARY KEY (account_id, collection)
                );
                """)
        }

        migrator.registerMigration("v2_messages") { db in
            try db.execute(sql: """
                CREATE TABLE messages (
                    account_id TEXT NOT NULL,
                    folder_id TEXT NOT NULL,
                    server_id TEXT NOT NULL,
                    subject TEXT,
                    sender TEXT,
                    recipients TEXT,
                    received_raw TEXT,
                    is_read INTEGER NOT NULL DEFAULT 0,
                    importance INTEGER,
                    deleted_at REAL,
                    updated_at REAL NOT NULL,
                    PRIMARY KEY (account_id, folder_id, server_id)
                );

                CREATE INDEX idx_messages_page
                    ON messages(account_id, folder_id, received_raw DESC);

                CREATE TABLE message_bodies (
                    account_id TEXT NOT NULL,
                    folder_id TEXT NOT NULL,
                    server_id TEXT NOT NULL,
                    text TEXT,
                    fetched_at REAL,
                    PRIMARY KEY (account_id, folder_id, server_id)
                );
                """)
        }
        migrator.registerMigration("v3_body_html") { db in
            try db.execute(sql: "ALTER TABLE message_bodies ADD COLUMN is_html INTEGER NOT NULL DEFAULT 0")
        }

        migrator.registerMigration("v6_search") { db in
            try db.execute(sql: """
                CREATE VIRTUAL TABLE messages_fts USING fts5(
                    subject, sender, body, tokenize='trigram'
                );
                """)
        }

        migrator.registerMigration("v5_outbox") { db in
            try db.execute(sql: """
                CREATE TABLE outbox (
                    id TEXT PRIMARY KEY,
                    account_id TEXT NOT NULL,
                    to_recipients TEXT NOT NULL,
                    cc TEXT,
                    subject TEXT NOT NULL,
                    body TEXT NOT NULL,
                    in_reply_to TEXT,
                    refs TEXT,
                    is_draft INTEGER NOT NULL DEFAULT 0,
                    state TEXT NOT NULL,
                    attempts INTEGER NOT NULL DEFAULT 0,
                    last_error TEXT,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL
                );
                CREATE INDEX idx_outbox_state ON outbox(account_id, state);
                """)
        }

        migrator.registerMigration("v4_attachments") { db in
            try db.execute(sql: """
                CREATE TABLE attachments (
                    account_id TEXT NOT NULL,
                    folder_id TEXT NOT NULL,
                    message_id TEXT NOT NULL,
                    file_reference TEXT NOT NULL,
                    display_name TEXT NOT NULL,
                    size INTEGER,
                    cache_path TEXT,
                    downloaded_at REAL,
                    PRIMARY KEY (account_id, folder_id, message_id, file_reference)
                );
                """)
        }
        try migrator.migrate(dbQueue)
    }

    // MARK: - Accounts

    @discardableResult
    public func createAccount(_ draft: NewAccount) throws -> AccountID {
        let id = AccountID(UUID().uuidString)
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO accounts (id, display_name, address, host, state, created_at)
                    VALUES (?, ?, ?, ?, 'draft', ?)
                    """,
                arguments: [id.raw, draft.displayName, draft.address, draft.host, Date().timeIntervalSince1970]
            )
        }
        return id
    }

    public func accounts() throws -> [AccountID] {
        try dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT id FROM accounts ORDER BY created_at")
                .map(AccountID.init)
        }
    }

    public func account(_ id: AccountID) throws -> (displayName: String, address: String)? {
        try dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT display_name, address FROM accounts WHERE id = ?", arguments: [id.raw])
                .map { ($0["display_name"], $0["address"]) }
        }
    }

    // MARK: - Folders

    public func folders(account id: AccountID) throws -> [StoredFolder] {
        try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT server_id, parent_id, display_name, type
                    FROM folders
                    WHERE account_id = ? AND deleted_at IS NULL
                    ORDER BY CASE type WHEN 2 THEN 0 WHEN 3 THEN 1 WHEN 4 THEN 2 WHEN 5 THEN 3 ELSE 9 END,
                             display_name
                    """,
                arguments: [id.raw]
            ).map { row in
                StoredFolder(
                    serverID: row["server_id"],
                    parentID: row["parent_id"],
                    displayName: row["display_name"],
                    type: row["type"]
                )
            }
        }
    }

    /// Applies a folder snapshot in one transaction: upserts, soft-deletes the given
    /// server ids, and advances the folder sync key. A throw rolls the whole batch back.
    public func applyFolderSnapshot(
        account id: AccountID,
        folders incoming: [MailFolder],
        removedServerIDs: [String] = [],
        syncKey: String
    ) throws {
        for folder in incoming where folder.serverID.isEmpty {
            throw MailStoreError.invalidFolder(reason: "empty serverID")
        }

        try dbQueue.write { db in
            guard try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM accounts WHERE id = ?)", arguments: [id.raw]) == true else {
                throw MailStoreError.accountNotFound(id)
            }

            let now = Date().timeIntervalSince1970
            for folder in incoming {
                try db.execute(
                    sql: """
                        INSERT INTO folders (account_id, server_id, parent_id, display_name, type, deleted_at, updated_at)
                        VALUES (?, ?, ?, ?, ?, NULL, ?)
                        ON CONFLICT(account_id, server_id) DO UPDATE SET
                            parent_id = excluded.parent_id,
                            display_name = excluded.display_name,
                            type = excluded.type,
                            deleted_at = NULL,
                            updated_at = excluded.updated_at
                        """,
                    arguments: [id.raw, folder.serverID, folder.parentID, folder.displayName, folder.type, now]
                )
            }

            for serverID in removedServerIDs {
                try db.execute(
                    sql: """
                        UPDATE folders SET deleted_at = ?, updated_at = ?
                        WHERE account_id = ? AND server_id = ? AND deleted_at IS NULL
                        """,
                    arguments: [now, now, id.raw, serverID]
                )
            }

            try db.execute(
                sql: """
                    INSERT INTO sync_state (account_id, collection, sync_key, last_sync_at)
                    VALUES (?, 'folders', ?, ?)
                    ON CONFLICT(account_id, collection) DO UPDATE SET
                        sync_key = excluded.sync_key,
                        last_sync_at = excluded.last_sync_at,
                        last_error = NULL
                    """,
                arguments: [id.raw, syncKey, now]
            )
        }
    }

    // MARK: - Messages

    /// Applies one Sync response: message upserts, preview storage, soft deletes and the
    /// new SyncKey all commit together. A throw leaves the old key in place.
    public func applySyncBatch(
        account id: AccountID,
        folder folderID: String,
        added: [MailMessage],
        changed: [MailMessage],
        removedServerIDs: [String],
        syncKey: String
    ) throws {
        for message in added + changed where message.serverID.isEmpty {
            throw MailStoreError.invalidFolder(reason: "empty message serverID")
        }

        try dbQueue.write { db in
            let folderExists = try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM folders WHERE account_id = ? AND server_id = ? AND deleted_at IS NULL)",
                arguments: [id.raw, folderID]
            ) == true
            guard folderExists else {
                throw MailStoreError.folderNotFound(account: id, folder: folderID)
            }

            let now = Date().timeIntervalSince1970
            for message in added + changed {
                try db.execute(
                    sql: """
                        INSERT INTO messages
                            (account_id, folder_id, server_id, subject, sender, recipients,
                             received_raw, is_read, importance, deleted_at, updated_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?)
                        ON CONFLICT(account_id, folder_id, server_id) DO UPDATE SET
                            subject = excluded.subject,
                            sender = excluded.sender,
                            recipients = excluded.recipients,
                            received_raw = excluded.received_raw,
                            is_read = excluded.is_read,
                            importance = excluded.importance,
                            deleted_at = NULL,
                            updated_at = excluded.updated_at
                        """,
                    arguments: [
                        id.raw, folderID, message.serverID, message.subject, message.sender,
                        message.recipients, message.receivedRaw, message.isRead ? 1 : 0,
                        message.importance, now,
                    ]
                )
                for attachment in message.attachments {
                    try db.execute(
                        sql: """
                            INSERT INTO attachments
                                (account_id, folder_id, message_id, file_reference, display_name, size, cache_path, downloaded_at)
                            VALUES (?, ?, ?, ?, ?, ?, NULL, NULL)
                            ON CONFLICT(account_id, folder_id, message_id, file_reference) DO UPDATE SET
                                display_name = excluded.display_name,
                                size = excluded.size
                            """,
                        arguments: [id.raw, folderID, message.serverID, attachment.fileReference, attachment.displayName, attachment.size]
                    )
                }
                if let preview = message.bodyPreview {
                    try db.execute(
                        sql: """
                            INSERT INTO message_bodies (account_id, folder_id, server_id, text, fetched_at)
                            VALUES (?, ?, ?, ?, ?)
                            ON CONFLICT(account_id, folder_id, server_id) DO UPDATE SET
                                text = excluded.text,
                                fetched_at = excluded.fetched_at
                            """,
                        arguments: [id.raw, folderID, message.serverID, preview, now]
                    )
                }
                try Self.reindexMessage(db, account: id, folder: folderID, serverID: message.serverID)
            }

            for serverID in removedServerIDs {
                try db.execute(
                    sql: """
                        UPDATE messages SET deleted_at = ?, updated_at = ?
                        WHERE account_id = ? AND folder_id = ? AND server_id = ? AND deleted_at IS NULL
                        """,
                    arguments: [now, now, id.raw, folderID, serverID]
                )
            }

            try db.execute(
                sql: """
                    INSERT INTO sync_state (account_id, collection, sync_key, last_sync_at)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(account_id, collection) DO UPDATE SET
                        sync_key = excluded.sync_key,
                        last_sync_at = excluded.last_sync_at,
                        last_error = NULL
                    """,
                arguments: [id.raw, folderID, syncKey, now]
            )
        }
    }

    public func messages(account id: AccountID, folder folderID: String, limit: Int = 50) throws -> [StoredMessage] {
        try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT m.server_id, m.folder_id, m.subject, m.sender, m.received_raw, m.is_read, b.text AS preview
                    FROM messages m
                    LEFT JOIN message_bodies b
                        ON b.account_id = m.account_id AND b.folder_id = m.folder_id AND b.server_id = m.server_id
                    WHERE m.account_id = ? AND m.folder_id = ? AND m.deleted_at IS NULL
                    ORDER BY m.received_raw DESC, m.server_id DESC
                    LIMIT ?
                    """,
                arguments: [id.raw, folderID, limit]
            ).map { row in
                StoredMessage(
                    serverID: row["server_id"],
                    subject: row["subject"],
                    sender: row["sender"],
                    receivedRaw: row["received_raw"],
                    isRead: (row["is_read"] as Int) == 1,
                    bodyPreview: row["preview"],
                    folderID: row["folder_id"]
                )
            }
        }
    }

    /// Stores a fetched body. The body table is separate from the envelope so list
    /// queries never touch it.
    public func applyBody(
        account id: AccountID,
        folder folderID: String,
        serverID: String,
        html: String
    ) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO message_bodies (account_id, folder_id, server_id, text, fetched_at, is_html)
                    VALUES (?, ?, ?, ?, ?, 1)
                    ON CONFLICT(account_id, folder_id, server_id) DO UPDATE SET
                        text = excluded.text,
                        fetched_at = excluded.fetched_at,
                        is_html = 1
                    """,
                arguments: [id.raw, folderID, serverID, html, Date().timeIntervalSince1970]
            )
            try Self.reindexMessage(db, account: id, folder: folderID, serverID: serverID)
        }
    }

    public func body(account id: AccountID, folder folderID: String, serverID: String) throws -> (text: String, isHTML: Bool)? {
        try dbQueue.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT text, is_html FROM message_bodies WHERE account_id = ? AND folder_id = ? AND server_id = ?",
                arguments: [id.raw, folderID, serverID]
            ).flatMap { row in
                guard let text: String = row["text"] else { return nil }
                return (text, (row["is_html"] as Int) == 1)
            }
        }
    }

    public func attachments(account id: AccountID, folder folderID: String, messageID: String) throws -> [StoredAttachment] {
        try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT message_id, display_name, file_reference, size, cache_path
                    FROM attachments WHERE account_id = ? AND folder_id = ? AND message_id = ?
                    ORDER BY display_name
                    """,
                arguments: [id.raw, folderID, messageID]
            ).map { row in
                StoredAttachment(
                    messageID: row["message_id"],
                    displayName: row["display_name"],
                    fileReference: row["file_reference"],
                    size: row["size"],
                    cachePath: row["cache_path"]
                )
            }
        }
    }

    public func markAttachmentCached(account id: AccountID, folder folderID: String, messageID: String, fileReference: String, cachePath: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    UPDATE attachments SET cache_path = ?, downloaded_at = ?
                    WHERE account_id = ? AND folder_id = ? AND message_id = ? AND file_reference = ?
                    """,
                arguments: [cachePath, Date().timeIntervalSince1970, id.raw, folderID, messageID, fileReference]
            )
        }
    }

    // MARK: - Outbox / drafts

    @discardableResult
    public func saveDraft(account id: AccountID, draft: MailDraft) throws -> String {
        try enqueueOutbox(account: id, draft: draft, state: draft.isDraft ? "draft" : "queued")
    }

    @discardableResult
    public func enqueueOutbox(account id: AccountID, draft: MailDraft) throws -> String {
        try enqueueOutbox(account: id, draft: draft, state: "queued")
    }

    private func enqueueOutbox(account id: AccountID, draft: MailDraft, state: String) throws -> String {
        let outboxID = UUID().uuidString
        let now = Date().timeIntervalSince1970
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO outbox (id, account_id, to_recipients, cc, subject, body,
                                        in_reply_to, refs, is_draft, state, attempts,
                                        created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?)
                    """,
                arguments: [outboxID, id.raw, draft.to, draft.cc ?? "", draft.subject, draft.body,
                            draft.inReplyTo, draft.references, draft.isDraft ? 1 : 0, state, now, now]
            )
        }
        return outboxID
    }

    public func pendingOutbox(account id: AccountID) throws -> [StoredOutboxItem] {
        try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, to_recipients, cc, subject, body, in_reply_to, refs, state, attempts, last_error
                    FROM outbox WHERE account_id = ? AND state IN ('queued', 'failed')
                    ORDER BY created_at
                    """,
                arguments: [id.raw]
            ).map(Self.outboxItem)
        }
    }

    public func markOutboxSent(account id: AccountID, outboxID: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM outbox WHERE account_id = ? AND id = ?",
                arguments: [id.raw, outboxID]
            )
        }
    }

    public func markOutboxFailed(account id: AccountID, outboxID: String, error: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    UPDATE outbox SET state = 'failed', attempts = attempts + 1, last_error = ?, updated_at = ?
                    WHERE account_id = ? AND id = ?
                    """,
                arguments: [error, Date().timeIntervalSince1970, id.raw, outboxID]
            )
        }
    }

    private static func outboxItem(_ row: Row) -> StoredOutboxItem {
        StoredOutboxItem(
            id: row["id"], to: row["to_recipients"], cc: row["cc"], subject: row["subject"],
            body: row["body"], inReplyTo: row["in_reply_to"], references: row["refs"],
            state: row["state"], attempts: row["attempts"], lastError: row["last_error"]
        )
    }

    /// Drops one collection's local mirror (messages, previews and cursor) so a full
    /// re-sync can rebuild it. Used when the server answers Sync status 3/4.
    public func resetCollection(account id: AccountID, folder: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM message_bodies WHERE account_id = ? AND folder_id = ?",
                arguments: [id.raw, folder]
            )
            try db.execute(
                sql: "DELETE FROM messages WHERE account_id = ? AND folder_id = ?",
                arguments: [id.raw, folder]
            )
            try db.execute(
                sql: "DELETE FROM sync_state WHERE account_id = ? AND collection = ?",
                arguments: [id.raw, folder]
            )
        }
    }

    public func searchLocal(account id: AccountID, query: String, limit: Int = 50) throws -> [StoredMessage] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT m.server_id, m.folder_id, m.subject, m.sender, m.received_raw, m.is_read, b.text AS preview
                    FROM messages_fts f
                    JOIN messages m ON m.rowid = f.rowid
                    LEFT JOIN message_bodies b
                        ON b.account_id = m.account_id AND b.folder_id = m.folder_id AND b.server_id = m.server_id
                    WHERE messages_fts MATCH ? AND m.account_id = ? AND m.deleted_at IS NULL
                    ORDER BY m.received_raw DESC
                    LIMIT ?
                    """,
                arguments: [trimmed, id.raw, limit]
            ).map { row in
                StoredMessage(
                    serverID: row["server_id"], subject: row["subject"], sender: row["sender"],
                    receivedRaw: row["received_raw"], isRead: (row["is_read"] as Int) == 1,
                    bodyPreview: row["preview"], folderID: row["folder_id"]
                )
            }
        }
    }

    private static func reindexMessage(_ db: Database, account id: AccountID, folder: String, serverID: String) throws {
        guard let rowid = try Int64.fetchOne(
            db,
            sql: "SELECT rowid FROM messages WHERE account_id = ? AND folder_id = ? AND server_id = ?",
            arguments: [id.raw, folder, serverID]
        ) else { return }
        let subject = try String.fetchOne(db, sql: "SELECT subject FROM messages WHERE rowid = ?", arguments: [rowid])
        let sender = try String.fetchOne(db, sql: "SELECT sender FROM messages WHERE rowid = ?", arguments: [rowid])
        let body = try String.fetchOne(
            db,
            sql: "SELECT text FROM message_bodies WHERE account_id = ? AND folder_id = ? AND server_id = ?",
            arguments: [id.raw, folder, serverID]
        )
        try db.execute(sql: "DELETE FROM messages_fts WHERE rowid = ?", arguments: [rowid])
        try db.execute(
            sql: "INSERT INTO messages_fts(rowid, subject, sender, body) VALUES (?, ?, ?, ?)",
            arguments: [rowid, subject ?? "", sender ?? "", body ?? ""]
        )
    }

    // MARK: - Sync state

    public func syncKey(account id: AccountID, collection: String) throws -> String? {
        try dbQueue.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT sync_key FROM sync_state WHERE account_id = ? AND collection = ?",
                arguments: [id.raw, collection]
            )
        }
    }
}
