import Foundation
import GRDB
import MailDomain

/// Meeting persistence (schema v12). Kept in its own file so the `MailStore` component
/// stays inside its 1000-line budget; the table still has exactly one writer — this file,
/// called only from `applyDelta`.

/// Meeting persistence, read side (schema v12). Only reads: list decoration, calendar range
/// queries and the `.ics` source lookup.
extension MailStore {
    // MARK: - Reads

    /// Meeting rows that can intersect `[from, to]`: they start before the range ends, and
    /// either end inside it or are recurring (their first instance may predate the range).
    public func meetings(
        account id: AccountID,
        from: Date,
        to: Date,
        limit: Int = 500
    ) throws -> [MeetingEntry] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT mt.*, COALESCE(m.subject, mt.subject) AS display_subject
                    FROM meetings mt
                    LEFT JOIN messages m
                        ON m.account_id = mt.account_id
                       AND m.folder_id = mt.folder_id
                       AND m.server_id = mt.server_id
                    WHERE mt.account_id = ?
                      AND mt.start_utc <= ?
                      AND (mt.recurrence IS NOT NULL OR mt.end_utc >= ?)
                      AND mt.is_cancelled = 0
                      AND mt.message_type <> 4
                    ORDER BY mt.start_utc
                    LIMIT ?
                    """,
                arguments: [id.raw, to.timeIntervalSince1970, from.timeIntervalSince1970, limit]
            )
            return rows.compactMap { row in
                guard let invite = try? Self.decodeMeeting(row) else { return nil }
                return MeetingEntry(
                    invite: invite,
                    folderID: row["folder_id"],
                    serverID: row["server_id"],
                    displaySubject: row["display_subject"]
                )
            }
        }
    }

    public func meetingInvite(account id: AccountID, uid: String) throws -> MeetingInvite? {
        try dbQueue.read { db in
            try meetingInvite(db, account: id, uid: uid)
        }
    }

    func meetingInvite(_ db: Database, account id: AccountID, uid: String) throws -> MeetingInvite? {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT * FROM meetings WHERE account_id = ? AND uid = ?",
            arguments: [id.raw, uid]
        ) else { return nil }
        return try Self.decodeMeeting(row)
    }

    /// Attaches the meeting carried by each message of a list page (one query per page).
    func attachMeetings(_ db: Database, account id: AccountID, messages: [StoredMessage]) throws -> [StoredMessage] {
        let keys: Set<String> = Set(messages.compactMap { message -> String? in
            guard let folder = message.folderID else { return nil }
            return "\(folder)\u{1F}\(message.serverID)"
        })
        guard !keys.isEmpty else { return messages }

        var byKey: [String: MeetingInvite] = [:]
        let folders: Set<String> = Set(messages.compactMap(\.folderID))
        for folder in folders {
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM meetings
                    WHERE account_id = ? AND folder_id = ? AND is_cancelled = 0 AND message_type <> 4
                    """,
                arguments: [id.raw, folder]
            )
            for row in rows {
                guard let invite = try? Self.decodeMeeting(row),
                      let folderID: String = row["folder_id"],
                      let serverID: String = row["server_id"]
                else { continue }
                byKey["\(folderID)\u{1F}\(serverID)"] = invite
            }
        }
        return messages.map { message in
            var copy = message
            if let folder = message.folderID {
                copy.meeting = byKey["\(folder)\u{1F}\(message.serverID)"]
            }
            return copy
        }
    }

    private static func decodeMeeting(_ row: Row) throws -> MeetingInvite {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        var rule: RecurrenceRule?
        if let json: String = row["recurrence"], let data = json.data(using: .utf8) {
            rule = try decoder.decode(RecurrenceRule.self, from: data)
        }
        var exceptions: [MeetingException] = []
        if let json: String = row["exceptions"], let data = json.data(using: .utf8) {
            exceptions = try decoder.decode([MeetingException].self, from: data)
        }
        let timeZoneName: String? = row["timezone_name"]
        let offsetMinutes: Int? = row["timezone_offset_minutes"]
        let messageType = MeetingMessageType(rawValue: row["message_type"]) ?? .initial
        return MeetingInvite(
            uid: row["uid"],
            subject: row["subject"],
            start: Date(timeIntervalSince1970: row["start_utc"]),
            end: Date(timeIntervalSince1970: row["end_utc"]),
            isAllDay: (row["is_all_day"] as Int) == 1,
            location: row["location"],
            organizer: row["organizer"],
            reminderMinutes: row["reminder_minutes"],
            responseRequested: (row["response_requested"] as Int) == 1,
            busyStatus: row["busy_status"],
            messageType: messageType,
            isCancelled: (row["is_cancelled"] as Int) == 1,
            dtstamp: (row["dtstamp"] as Double?).map(Date.init(timeIntervalSince1970:)),
            timeZone: offsetMinutes.map {
                MeetingTimeZone(name: timeZoneName, offsetSeconds: $0 * 60)
            },
            recurrence: rule,
            exceptions: exceptions
        )
    }
}
