import Foundation
import GRDB
import MailDomain

/// Draft rows and their server binding (REQ-0043 / REQ-0044). Split from `OutboxStore.swift`
/// for the per-file budget; the two files share the same `DatabaseQueue`.
extension OutboxStore {
    // MARK: - Local drafts

    /// Locally saved drafts, newest first. Drafts are never delivered: `state = 'draft'`
    /// keeps them out of every outbox query above.
    public func drafts(account id: AccountID) throws -> [DraftRecord] {
        try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, to_recipients, cc, subject, body, body_html, in_reply_to, refs,
                           updated_at, server_id, draft_hash
                    FROM outbox
                    WHERE account_id = ? AND state = 'draft'
                    ORDER BY updated_at DESC, id DESC
                    """,
                arguments: [id.raw]
            ).map(Self.draftRecord)
        }
    }

    /// One draft row by outbox id (any state), for the sync pass.
    public func draft(account id: AccountID, draftID: String) throws -> DraftRecord? {
        try dbQueue.read { db in
            try Row.fetchOne(
                db,
                sql: """
                    SELECT id, to_recipients, cc, subject, body, body_html, in_reply_to, refs,
                           updated_at, server_id, draft_hash
                    FROM outbox WHERE account_id = ? AND id = ?
                    """,
                arguments: [id.raw, draftID]
            ).map(Self.draftRecord)
        }
    }

    /// One draft row by its server id (draft sync).
    public func draft(account id: AccountID, serverID: String) throws -> DraftRecord? {
        try dbQueue.read { db in
            try Row.fetchOne(
                db,
                sql: """
                    SELECT id, to_recipients, cc, subject, body, body_html, in_reply_to, refs,
                           updated_at, server_id, draft_hash
                    FROM outbox WHERE account_id = ? AND server_id = ? AND state = 'draft'
                    """,
                arguments: [id.raw, serverID]
            ).map(Self.draftRecord)
        }
    }

    /// Copies one draft into a new local-only row (conflict merge: the server version stays
    /// on the original row, the user's version is kept next to it for the human to delete).
    @discardableResult
    public func duplicateDraft(account id: AccountID, draftID: String) throws -> String {
        let copyID = UUID().uuidString
        let now = Date().timeIntervalSince1970
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO outbox (id, account_id, to_recipients, cc, subject, body,
                                        body_html, in_reply_to, refs, is_draft, state, attempts,
                                        created_at, updated_at, server_id, draft_hash)
                    SELECT ?, account_id, to_recipients, cc, subject, body, body_html,
                           in_reply_to, refs, 1, 'draft', 0, ?, ?, NULL, NULL
                    FROM outbox WHERE account_id = ? AND id = ? AND state = 'draft'
                    """,
                arguments: [copyID, now, now, id.raw, draftID]
            )
        }
        return copyID
    }

    /// Overwrites a draft row in place. Returns `false` when the row is gone (deleted by
    /// another window), so the caller can fall back to inserting a fresh draft.
    @discardableResult
    public func updateDraft(account id: AccountID, draftID: String, draft: MailDraft) throws -> Bool {
        let now = Date().timeIntervalSince1970
        return try dbQueue.write { db in
            try db.execute(
                sql: """
                    UPDATE outbox
                    SET to_recipients = ?, cc = ?, subject = ?, body = ?, body_html = ?,
                        in_reply_to = ?, refs = ?, updated_at = ?
                    WHERE account_id = ? AND id = ? AND state = 'draft'
                    """,
                arguments: [draft.to, draft.cc ?? "", draft.subject, draft.body,
                            draft.bodyHTML, draft.inReplyTo, draft.references, now, id.raw, draftID]
            )
            return db.changesCount == 1
        }
    }

    /// Turns an existing draft row into a deliverable one: the row keeps its id (and so its
    /// `ClientId`), `is_draft` is cleared and the state becomes `queued` in one statement,
    /// so the draft can never be both delivered and still listed. Returns `false` when the
    /// row is gone.
    @discardableResult
    public func sendDraft(account id: AccountID, draftID: String, draft: MailDraft) throws -> Bool {
        let now = Date().timeIntervalSince1970
        return try dbQueue.write { db in
            let serverID: String? = try String.fetchOne(
                db,
                sql: "SELECT server_id FROM outbox WHERE account_id = ? AND id = ? AND state = 'draft'",
                arguments: [id.raw, draftID]
            )
            try db.execute(
                sql: """
                    UPDATE outbox
                    SET to_recipients = ?, cc = ?, subject = ?, body = ?, body_html = ?,
                        in_reply_to = ?, refs = ?, is_draft = 0, state = 'queued',
                        attempts = 0, last_error = NULL, next_attempt_at = NULL, updated_at = ?
                    WHERE account_id = ? AND id = ? AND state = 'draft'
                    """,
                arguments: [draft.to, draft.cc ?? "", draft.subject, draft.body,
                            draft.bodyHTML, draft.inReplyTo, draft.references, now, id.raw, draftID]
            )
            // The sent draft must also disappear from the server's Drafts folder; the
            // tombstone is committed with the transition so an offline send still deletes it
            // on the next draft sync.
            if db.changesCount == 1, let serverID {
                try db.execute(
                    sql: """
                        INSERT OR REPLACE INTO draft_tombstones (account_id, server_id, created_at)
                        VALUES (?, ?, ?)
                        """,
                    arguments: [id.raw, serverID, now]
                )
            }
            return db.changesCount == 1
        }
    }

    /// Permanently removes a draft row (drafts only; queued mail keeps the outbox machinery).
    @discardableResult
    public func deleteDraft(account id: AccountID, draftID: String) throws -> Bool {
        try dbQueue.write { db in
            let serverID: String? = try String.fetchOne(
                db,
                sql: "SELECT server_id FROM outbox WHERE account_id = ? AND id = ? AND state = 'draft'",
                arguments: [id.raw, draftID]
            )
            try db.execute(
                sql: "DELETE FROM outbox WHERE account_id = ? AND id = ? AND state = 'draft'",
                arguments: [id.raw, draftID]
            )
            if db.changesCount == 1, let serverID {
                try db.execute(
                    sql: """
                        INSERT OR REPLACE INTO draft_tombstones (account_id, server_id, created_at)
                        VALUES (?, ?, ?)
                        """,
                    arguments: [id.raw, serverID, Date().timeIntervalSince1970]
                )
            }
            return db.changesCount == 1
        }
    }

    // MARK: - Rows

    static func draftRecord(_ row: Row) -> DraftRecord {
        DraftRecord(
            id: row["id"], to: row["to_recipients"], cc: nonEmpty(row["cc"]),
            subject: row["subject"], body: row["body"], bodyHTML: row["body_html"],
            inReplyTo: row["in_reply_to"], references: row["refs"],
            updatedAt: Date(timeIntervalSince1970: row["updated_at"]),
            serverID: nonEmpty(row["server_id"]), draftHash: row["draft_hash"]
        )
    }
}
