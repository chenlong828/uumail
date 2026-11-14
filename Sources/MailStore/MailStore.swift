import Foundation
import GRDB
import MailDomain

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
        MailStoreMigrations.register(on: &migrator)
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

    /// The stored account as sending needs it: the address is the From header and the
    /// host is the Message-ID domain (never hardcoded by `Outbox`).
    public func account(_ id: AccountID) throws -> (displayName: String, address: String, host: String)? {
        try dbQueue.read { db in
            try Row.fetchOne(
                db,
                sql: "SELECT display_name, address, host FROM accounts WHERE id = ?",
                arguments: [id.raw]
            ).map { ($0["display_name"], $0["address"], $0["host"]) }
        }
    }

    /// Marks a provisioned account usable. Account setup calls this after folders land.
    public func markAccountReady(_ id: AccountID) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE accounts SET state = 'ready' WHERE id = ?",
                arguments: [id.raw]
            )
            guard db.changesCount == 1 else {
                throw MailStoreError.accountNotFound(id)
            }
        }
    }

    /// Drops an account that never received mail (failed setup rollback). Refuses to
    /// cascade over messages, so a half-configured account cannot delete history.
    public func discardAccount(_ id: AccountID) throws {
        try dbQueue.write { db in
            guard try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM accounts WHERE id = ?)",
                arguments: [id.raw]
            ) == true else {
                throw MailStoreError.accountNotFound(id)
            }
            let messageCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM messages WHERE account_id = ?",
                arguments: [id.raw]
            ) ?? 0
            guard messageCount == 0 else {
                throw MailStoreError.accountNotEmpty(id)
            }
            try db.execute(sql: "DELETE FROM folders WHERE account_id = ?", arguments: [id.raw])
            try db.execute(sql: "DELETE FROM sync_state WHERE account_id = ?", arguments: [id.raw])
            try db.execute(sql: "DELETE FROM accounts WHERE id = ?", arguments: [id.raw])
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
                            (account_id, folder_id, server_id, subject, sender, recipients, cc,
                             received_raw, is_read, importance, preview, deleted_at, updated_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?)
                        ON CONFLICT(account_id, folder_id, server_id) DO UPDATE SET
                            subject = excluded.subject,
                            sender = excluded.sender,
                            recipients = COALESCE(excluded.recipients, messages.recipients),
                            cc = COALESCE(excluded.cc, messages.cc),
                            received_raw = excluded.received_raw,
                            is_read = excluded.is_read,
                            importance = excluded.importance,
                            preview = COALESCE(excluded.preview, messages.preview),
                            deleted_at = NULL,
                            updated_at = excluded.updated_at
                        """,
                    arguments: [
                        id.raw, folderID, message.serverID, message.subject, message.sender,
                        message.recipients, message.cc, message.receivedRaw, message.isRead ? 1 : 0,
                        message.importance, message.bodyPreview, now,
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
                // The preview rides on the envelope upsert above: it must never land in
                // `message_bodies`, or the reading pane mistakes it for the fetched body.
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
                    SELECT m.server_id, m.folder_id, m.subject, m.sender, m.recipients, m.cc,
                           m.received_raw, m.is_read, m.preview
                    FROM messages m
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
                    recipients: row["recipients"],
                    receivedRaw: row["received_raw"],
                    isRead: (row["is_read"] as Int) == 1,
                    bodyPreview: row["preview"],
                    folderID: row["folder_id"],
                    cc: row["cc"]
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

    /// Everything the compose status line shows: rows still waiting, sending, or failed.
    public func pendingOutbox(account id: AccountID) throws -> [StoredOutboxItem] {
        try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, to_recipients, cc, subject, body, in_reply_to, refs, state,
                           attempts, last_error, next_attempt_at
                    FROM outbox
                    WHERE account_id = ?
                      AND state IN ('queued', 'sending', 'failed_retryable', 'failed_permanent')
                    ORDER BY created_at, id
                    """,
                arguments: [id.raw]
            ).map(Self.outboxItem)
        }
    }

    /// Atomically claims the oldest deliverable row for `account` and stamps the lease.
    ///
    /// Deliverable: `queued`, a `failed_retryable` row whose backoff has elapsed, or a
    /// `sending` row whose lease expired (a crashed process). The `UPDATE … RETURNING`
    /// is one statement, so two processes cannot claim the same row.
    public func claimOutbox(account id: AccountID, now: Date, lease: Duration) throws -> OutboxItem? {
        let stamp = now.timeIntervalSince1970
        let expiredBefore = stamp - Self.seconds(of: lease)
        return try dbQueue.write { db in
            try Row.fetchOne(
                db,
                sql: """
                    UPDATE outbox
                    SET state = 'sending', sending_since = ?, updated_at = ?
                    WHERE account_id = ?
                      AND id = (
                          SELECT id FROM outbox
                          WHERE account_id = ?
                            AND (
                                state = 'queued'
                                OR (state = 'failed_retryable'
                                    AND (next_attempt_at IS NULL OR next_attempt_at <= ?))
                                OR (state = 'sending'
                                    AND (sending_since IS NULL OR sending_since <= ?))
                            )
                          ORDER BY created_at, id
                          LIMIT 1
                      )
                    RETURNING id, to_recipients, cc, subject, body, in_reply_to, refs,
                              state, attempts, last_error, next_attempt_at
                    """,
                arguments: [stamp, stamp, id.raw, id.raw, stamp, expiredBefore]
            ).map(Self.outboxItem)
        }
    }

    /// A successful delivery is final: the row disappears.
    public func markOutboxSent(account id: AccountID, outboxID: OutboxID) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM outbox WHERE account_id = ? AND id = ? AND state = 'sending'",
                arguments: [id.raw, outboxID.raw]
            )
            guard db.changesCount == 1 else {
                throw MailStoreError.outboxNotClaimable(account: id, outboxID: outboxID)
            }
        }
    }

    /// Records the delivery failure. Retryable rows get `next_attempt_at`; permanent
    /// rows keep their content and error but are never claimed automatically again.
    public func markOutboxFailed(
        account id: AccountID,
        outboxID: OutboxID,
        error: String,
        retryable: Bool,
        nextAttempt: Date?
    ) throws {
        let state = retryable ? "failed_retryable" : "failed_permanent"
        let next = nextAttempt?.timeIntervalSince1970
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    UPDATE outbox
                    SET state = ?, attempts = attempts + 1, last_error = ?,
                        next_attempt_at = ?, sending_since = NULL, updated_at = ?
                    WHERE account_id = ? AND id = ? AND state = 'sending'
                    """,
                arguments: [state, error, next, Date().timeIntervalSince1970, id.raw, outboxID.raw]
            )
            guard db.changesCount == 1 else {
                throw MailStoreError.outboxNotClaimable(account: id, outboxID: outboxID)
            }
        }
    }

    /// Returns a row to the queue: after an aborted delivery, or when the user asks to
    /// retry a failed item. Failed rows become `queued` and are claimable immediately.
    public func releaseOutbox(account id: AccountID, outboxID: OutboxID) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    UPDATE outbox
                    SET state = 'queued', sending_since = NULL, next_attempt_at = NULL, updated_at = ?
                    WHERE account_id = ? AND id = ?
                      AND state IN ('sending', 'failed_retryable', 'failed_permanent')
                    """,
                arguments: [Date().timeIntervalSince1970, id.raw, outboxID.raw]
            )
            guard db.changesCount == 1 else {
                throw MailStoreError.outboxNotClaimable(account: id, outboxID: outboxID)
            }
        }
    }

    /// Cancels a row that has not been delivered. `sending` is deliberately excluded:
    /// the caller marks intent and settles after the in-flight delivery returns.
    public func cancelOutbox(account id: AccountID, outboxID: OutboxID) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    UPDATE outbox
                    SET state = 'canceled', sending_since = NULL, next_attempt_at = NULL, updated_at = ?
                    WHERE account_id = ? AND id = ?
                      AND state IN ('queued', 'failed_retryable', 'failed_permanent')
                    """,
                arguments: [Date().timeIntervalSince1970, id.raw, outboxID.raw]
            )
            guard db.changesCount == 1 else {
                throw MailStoreError.outboxNotClaimable(account: id, outboxID: outboxID)
            }
        }
    }

    public func outboxItem(account id: AccountID, id outboxID: OutboxID) throws -> OutboxItem? {
        try dbQueue.read { db in
            try Row.fetchOne(
                db,
                sql: """
                    SELECT id, to_recipients, cc, subject, body, in_reply_to, refs, state,
                           attempts, last_error, next_attempt_at
                    FROM outbox WHERE account_id = ? AND id = ?
                    """,
                arguments: [id.raw, outboxID.raw]
            ).map(Self.outboxItem)
        }
    }

    private static func outboxItem(_ row: Row) -> OutboxItem {
        let nextAttempt: Double? = row["next_attempt_at"]
        return OutboxItem(
            id: row["id"], to: row["to_recipients"], cc: row["cc"], subject: row["subject"],
            body: row["body"], inReplyTo: row["in_reply_to"], references: row["refs"],
            state: row["state"], attempts: row["attempts"], lastError: row["last_error"],
            nextAttemptAt: nextAttempt.map(Date.init(timeIntervalSince1970:))
        )
    }

    private static func seconds(of duration: Duration) -> TimeInterval {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
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
        // FTS5 trigram needs at least three characters; short CJK queries fall back to LIKE.
        if trimmed.count < 3 {
            return try dbQueue.read { db in
                try Row.fetchAll(
                    db,
                    sql: """
                        SELECT m.server_id, m.folder_id, m.subject, m.sender, m.recipients, m.cc,
                               m.received_raw, m.is_read,
                               COALESCE(NULLIF(b.text, ''), m.preview) AS preview
                        FROM messages m
                        LEFT JOIN message_bodies b
                            ON b.account_id = m.account_id AND b.folder_id = m.folder_id AND b.server_id = m.server_id
                        WHERE m.account_id = ? AND m.deleted_at IS NULL
                          AND (m.subject LIKE ? OR m.sender LIKE ? OR b.text LIKE ? OR m.preview LIKE ?)
                        ORDER BY m.received_raw DESC
                        LIMIT ?
                        """,
                    arguments: [id.raw, "%\(trimmed)%", "%\(trimmed)%", "%\(trimmed)%", "%\(trimmed)%", limit]
                ).map { row in
                    StoredMessage(
                        serverID: row["server_id"], subject: row["subject"], sender: row["sender"],
                        recipients: row["recipients"], receivedRaw: row["received_raw"],
                        isRead: (row["is_read"] as Int) == 1,
                        bodyPreview: row["preview"], folderID: row["folder_id"], cc: row["cc"]
                    )
                }
            }
        }
        return try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT m.server_id, m.folder_id, m.subject, m.sender, m.recipients, m.cc,
                           m.received_raw, m.is_read,
                           COALESCE(NULLIF(b.text, ''), m.preview) AS preview
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
                    recipients: row["recipients"], receivedRaw: row["received_raw"],
                    isRead: (row["is_read"] as Int) == 1,
                    bodyPreview: row["preview"], folderID: row["folder_id"], cc: row["cc"]
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
            sql: """
                SELECT COALESCE(NULLIF(b.text, ''), m.preview)
                FROM messages m
                LEFT JOIN message_bodies b
                    ON b.account_id = m.account_id AND b.folder_id = m.folder_id AND b.server_id = m.server_id
                WHERE m.rowid = ?
                """,
            arguments: [rowid]
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
