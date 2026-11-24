import Foundation
import GRDB
import MailDomain

/// Meeting persistence (schema v12). Kept in its own file so the `MailStore` component
/// stays inside its 1000-line budget; the table still has exactly one writer — this file,
/// called only from `applyDelta`.

/// Meeting persistence, write side (schema v12). The `meetings` table has exactly one
/// writer: `upsertMeeting`, called from `applyDelta` inside the batch transaction.
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
