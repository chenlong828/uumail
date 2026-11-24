import Foundation
import GRDB
import MailDomain

/// Meeting persistence (schema v12). Kept in its own file so the `MailStore` component
/// stays inside its 1000-line budget; the table still has exactly one writer — this file,
/// called only from `applyDelta`.
extension MailStore {
    // MARK: - Sync write path

    /// Upserts the meeting a synced message carries. Cancellations delete the series row;
    /// an exception request (`InstanceType == 3`) merges into the existing series instead.
    func upsertMeeting(
        _ db: Database,
        account id: AccountID,
        folder folderID: String,
        message: Message,
        now: Double
    ) throws {
        guard let invite = message.meeting, !invite.uid.isEmpty else { return }

        if let recurrenceID = invite.exceptionRecurrenceID {
            guard var existing = try meetingInvite(db, account: id, uid: invite.uid) else { return }
            existing.exceptions.removeAll { $0.recurrenceId == recurrenceID }
            existing.exceptions.append(MeetingException(
                recurrenceId: recurrenceID,
                start: invite.start,
                end: invite.end,
                subject: invite.subject,
                location: invite.location,
                isDeleted: invite.isCancelled
            ))
            try writeMeetingRow(
                db, account: id, folder: existing.exceptions.isEmpty ? folderID : folderID,
                serverID: message.serverID, subject: invite.subject ?? message.subject,
                invite: existing, now: now
            )
            return
        }

        if invite.isCancelled || invite.messageType == .outdated {
            try db.execute(
                sql: "DELETE FROM meetings WHERE account_id = ? AND uid = ?",
                arguments: [id.raw, invite.uid]
            )
            return
        }

        let encoded = try Self.encodeMeeting(invite)
        let dtstamp = invite.dtstamp?.timeIntervalSince1970
        try db.execute(
            sql: """
                INSERT INTO meetings
                    (account_id, uid, folder_id, server_id, subject, start_utc, end_utc,
                     is_all_day, location, organizer, reminder_minutes, response_requested,
                     busy_status, message_type, is_cancelled, dtstamp, timezone_name,
                     timezone_offset_minutes, recurrence, exceptions, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(account_id, uid) DO UPDATE SET
                    folder_id = excluded.folder_id,
                    server_id = excluded.server_id,
                    subject = excluded.subject,
                    start_utc = excluded.start_utc,
                    end_utc = excluded.end_utc,
                    is_all_day = excluded.is_all_day,
                    location = excluded.location,
                    organizer = excluded.organizer,
                    reminder_minutes = excluded.reminder_minutes,
                    response_requested = excluded.response_requested,
                    busy_status = excluded.busy_status,
                    message_type = excluded.message_type,
                    is_cancelled = excluded.is_cancelled,
                    dtstamp = excluded.dtstamp,
                    timezone_name = excluded.timezone_name,
                    timezone_offset_minutes = excluded.timezone_offset_minutes,
                    recurrence = excluded.recurrence,
                    exceptions = excluded.exceptions,
                    updated_at = excluded.updated_at
                WHERE COALESCE(excluded.dtstamp, 9e18) >= COALESCE(meetings.dtstamp, -9e18)
                """,
            arguments: [
                id.raw, invite.uid, folderID, message.serverID, invite.subject ?? message.subject,
                invite.start.timeIntervalSince1970, invite.end.timeIntervalSince1970,
                invite.isAllDay ? 1 : 0, invite.location, invite.organizer,
                invite.reminderMinutes, invite.responseRequested ? 1 : 0, invite.busyStatus,
                invite.messageType.rawValue, invite.isCancelled ? 1 : 0, dtstamp,
                invite.timeZone?.name, invite.timeZone.map { $0.offsetSeconds / 60 },
                encoded.recurrence, encoded.exceptions, now,
            ]
        )
    }

    /// A message deleted from the server removes the meeting row only if that message is
    /// the one the row points at; another invite for the same UID may still be current.
    func deleteMeetings(_ db: Database, account id: AccountID, folder folderID: String, serverIDs: [String]) throws {
        for serverID in serverIDs {
            try db.execute(
                sql: "DELETE FROM meetings WHERE account_id = ? AND folder_id = ? AND server_id = ?",
                arguments: [id.raw, folderID, serverID]
            )
        }
    }

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

    private func meetingInvite(_ db: Database, account id: AccountID, uid: String) throws -> MeetingInvite? {
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

    // MARK: - Encoding

    private struct EncodedMeeting {
        var recurrence: String?
        var exceptions: String?
    }

    private static func encodeMeeting(_ invite: MeetingInvite) throws -> EncodedMeeting {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        var recurrence: String?
        if let rule = invite.recurrence {
            recurrence = String(decoding: try encoder.encode(rule), as: UTF8.self)
        }
        var exceptions: String?
        if !invite.exceptions.isEmpty {
            exceptions = String(decoding: try encoder.encode(invite.exceptions), as: UTF8.self)
        }
        return EncodedMeeting(recurrence: recurrence, exceptions: exceptions)
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

    private func writeMeetingRow(
        _ db: Database,
        account id: AccountID,
        folder folderID: String,
        serverID: String,
        subject: String?,
        invite: MeetingInvite,
        now: Double
    ) throws {
        let encoded = try Self.encodeMeeting(invite)
        try db.execute(
            sql: """
                UPDATE meetings
                SET exceptions = ?, updated_at = ?
                WHERE account_id = ? AND uid = ?
                """,
            arguments: [encoded.exceptions, now, id.raw, invite.uid]
        )
    }
}
