import Foundation
import GRDB
import MailDomain

/// Read-only lookups added for the floating reader and the 30-day list window
/// (REQ-0031 / REQ-0033, D12). Kept out of `MailStore.swift` so that file does not keep
/// growing while `plan/risks.md` R45 (component over budget) is open.
extension MailStore {
    /// The message's fixed SELECT list: one place so every lookup projects the same columns.
    static let messageColumns = """
        m.server_id, m.folder_id, m.subject, m.sender, m.recipients, m.cc,
        m.received_raw, m.is_read, m.preview
        """

    /// One message by its natural key. `nil` when it is absent or soft-deleted;
    /// storage failures still throw.
    public func message(account id: AccountID, folder folderID: String, serverID: String) throws -> StoredMessage? {
        try dbQueue.read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT \(Self.messageColumns)
                    FROM messages m
                    WHERE m.account_id = ? AND m.folder_id = ? AND m.server_id = ? AND m.deleted_at IS NULL
                    LIMIT 1
                    """,
                arguments: [id.raw, folderID, serverID]
            )
            guard let row else { return nil }
            let message = Self.storedMessage(from: row)
            return message
        }
    }

    /// Every message received at or after `since`, newest first, **no row cap**
    /// (REQ-0033). Rows whose `received_raw` cannot be parsed are kept rather than
    /// silently hidden: the gateway string is stored verbatim and an unparseable date is
    /// a data problem, not an age signal.
    public func messages(account id: AccountID, folder folderID: String, since: Date) throws -> [StoredMessage] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT \(Self.messageColumns)
                    FROM messages m
                    WHERE m.account_id = ? AND m.folder_id = ? AND m.deleted_at IS NULL
                      AND (
                        m.received_raw IS NULL
                        OR julianday(m.received_raw) IS NULL
                        OR julianday(m.received_raw) >= julianday(?, 'unixepoch')
                      )
                    ORDER BY m.received_raw DESC, m.server_id DESC
                    """,
                arguments: [id.raw, folderID, since.timeIntervalSince1970]
            )
            return rows.map(Self.storedMessage(from:))
        }
    }

    static func storedMessage(from row: Row) -> StoredMessage {
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
