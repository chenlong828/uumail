import Foundation
import GRDB
import MailDomain

/// The `outbox` table's physical row store (`CMP-OUTBOX-STORE`).
///
/// It shares `MailStore`'s `DatabaseQueue` and owns nothing else: the table is created by
/// `MailStoreMigrations`, the delivery state machine lives in `Outbox`. Splitting these rows
/// out keeps `MailStore` inside its 1000-line budget without a second database or a
/// cross-component transaction.
public final class OutboxStore: @unchecked Sendable {
    private let dbQueue: DatabaseQueue

    public init(queue: DatabaseQueue) {
        self.dbQueue = queue
    }

    // MARK: - Rows

    @discardableResult
    public func saveDraft(account id: AccountID, draft: MailDraft) throws -> String {
        try enqueue(account: id, draft: draft, state: draft.isDraft ? "draft" : "queued")
    }

    @discardableResult
    public func enqueueOutbox(account id: AccountID, draft: MailDraft) throws -> String {
        try enqueue(account: id, draft: draft, state: "queued")
    }

    private func enqueue(account id: AccountID, draft: MailDraft, state: String) throws -> String {
        let outboxID = UUID().uuidString
        let now = Date().timeIntervalSince1970
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO outbox (id, account_id, to_recipients, cc, subject, body,
                                        body_html, in_reply_to, refs, is_draft, state, attempts,
                                        created_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?)
                    """,
                arguments: [outboxID, id.raw, draft.to, draft.cc ?? "", draft.subject, draft.body,
                            draft.bodyHTML, draft.inReplyTo, draft.references,
                            draft.isDraft ? 1 : 0, state, now, now]
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
                    SELECT id, to_recipients, cc, subject, body, body_html, in_reply_to, refs,
                           state, attempts, last_error, next_attempt_at
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
                    RETURNING id, to_recipients, cc, subject, body, body_html, in_reply_to, refs,
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
                    SELECT id, to_recipients, cc, subject, body, body_html, in_reply_to, refs,
                           state, attempts, last_error, next_attempt_at
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
            nextAttemptAt: nextAttempt.map(Date.init(timeIntervalSince1970:)),
            bodyHTML: row["body_html"]
        )
    }

    private static func seconds(of duration: Duration) -> TimeInterval {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
