import Foundation
import GRDB
import MailDomain

/// Draft server binding and delete tombstones (REQ-0044). Separate from
/// `OutboxStore+Drafts.swift` for the per-file budget; same `DatabaseQueue`.
extension OutboxStore {
    // MARK: - Server binding (REQ-0044)

    /// Local-only drafts that still need a `Sync Add` (never uploaded, or unbound because
    /// the server copy disappeared while the local row had changes).
    public func unboundDrafts(account id: AccountID) throws -> [DraftRecord] {
        try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, to_recipients, cc, subject, body, body_html, in_reply_to, refs,
                           updated_at, server_id, draft_hash
                    FROM outbox
                    WHERE account_id = ? AND state = 'draft' AND server_id IS NULL
                    ORDER BY updated_at, id
                    """,
                arguments: [id.raw]
            ).map(Self.draftRecord)
        }
    }

    /// Bound drafts whose content no longer matches the last-synced fingerprint, i.e. the
    /// local side changed and the server needs a `Sync Change`.
    public func draftsNeedingUpload(account id: AccountID) throws -> [DraftRecord] {
        try drafts(account: id).filter { record in
            guard let serverID = record.serverID, !serverID.isEmpty else { return false }
            return record.draftHash != record.fingerprint
        }
    }

    public func bindDraft(
        account id: AccountID, draftID: String, serverID: String, hash: String
    ) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    UPDATE outbox SET server_id = ?, draft_hash = ?
                    WHERE account_id = ? AND id = ? AND state = 'draft'
                    """,
                arguments: [serverID, hash, id.raw, draftID]
            )
        }
    }

    public func setDraftHash(account id: AccountID, draftID: String, hash: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE outbox SET draft_hash = ? WHERE account_id = ? AND id = ?",
                arguments: [hash, id.raw, draftID]
            )
        }
    }

    /// Takes the server version into an already-bound row (the local side is clean).
    public func adoptServerDraft(
        account id: AccountID, draftID: String, draft: MailDraft, updatedAt: Date, hash: String
    ) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    UPDATE outbox
                    SET to_recipients = ?, cc = ?, subject = ?, body = ?, body_html = ?,
                        in_reply_to = ?, refs = ?, updated_at = ?, draft_hash = ?
                    WHERE account_id = ? AND id = ? AND state = 'draft'
                    """,
                arguments: [draft.to, draft.cc ?? "", draft.subject, draft.body,
                            draft.bodyHTML, draft.inReplyTo, draft.references,
                            updatedAt.timeIntervalSince1970, hash, id.raw, draftID]
            )
        }
    }

    /// Inserts a draft that exists only on the server (first download).
    public func insertServerDraft(
        account id: AccountID, serverID: String, draft: MailDraft, updatedAt: Date, hash: String
    ) throws {
        let now = Date().timeIntervalSince1970
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO outbox (id, account_id, to_recipients, cc, subject, body,
                                        body_html, in_reply_to, refs, is_draft, state, attempts,
                                        created_at, updated_at, server_id, draft_hash)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1, 'draft', 0, ?, ?, ?, ?)
                    """,
                arguments: [UUID().uuidString, id.raw, draft.to, draft.cc ?? "", draft.subject,
                            draft.body, draft.bodyHTML, draft.inReplyTo, draft.references,
                            now, updatedAt.timeIntervalSince1970, serverID, hash]
            )
        }
    }

    /// The server copy disappeared while the local row had changes: keep the local text as
    /// a fresh local-only draft (it will be uploaded again on the next pass).
    public func unbindDraft(account id: AccountID, draftID: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE outbox SET server_id = NULL, draft_hash = NULL WHERE account_id = ? AND id = ?",
                arguments: [id.raw, draftID]
            )
        }
    }

    // MARK: - Delete tombstones

    public func addDraftTombstone(account id: AccountID, serverID: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO draft_tombstones (account_id, server_id, created_at)
                    VALUES (?, ?, ?)
                    """,
                arguments: [id.raw, serverID, Date().timeIntervalSince1970]
            )
        }
    }

    public func draftTombstones(account id: AccountID) throws -> [String] {
        try dbQueue.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT server_id FROM draft_tombstones WHERE account_id = ? ORDER BY created_at",
                arguments: [id.raw]
            )
        }
    }

    public func removeDraftTombstone(account id: AccountID, serverID: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM draft_tombstones WHERE account_id = ? AND server_id = ?",
                arguments: [id.raw, serverID]
            )
        }
    }
}
