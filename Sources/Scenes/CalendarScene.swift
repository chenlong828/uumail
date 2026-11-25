import Foundation
import MailDomain
import MailStore
import MeetingDomain

/// One query's worth of calendar occurrences.
public struct CalendarEvents: Equatable, Sendable {
    public var occurrences: [MeetingOccurrence]
    public var truncated: Bool
    /// Series whose rule could not be expanded; they are skipped, the rest still render.
    public var unexpandedUIDs: [String]

    public init(occurrences: [MeetingOccurrence], truncated: Bool, unexpandedUIDs: [String]) {
        self.occurrences = occurrences
        self.truncated = truncated
        self.unexpandedUIDs = unexpandedUIDs
    }
}

public enum CalendarSceneError: Error, Equatable, Sendable {
    case meetingNotFound(uid: String)
    case invalidRange
}

/// Calendar browsing over the local store (CMP-SCN-CALENDAR).
///
/// Pure local reads: it never touches the network and never writes. The scene owns the
/// three rules — one source per UID (the store already enforces it), cancellations are
/// invisible (store filter), and recurrence expansion is bounded (`limit` plus a per-series
/// cap) — while the rule math stays in `MailDomain.MeetingInvite.occurrences`.
public struct CalendarScene: Sendable {
    private let store: MailStore
    private let account: AccountID
    /// Upper bound for one series inside one query; keeps a pathological rule from
    /// starving every other meeting in a month.
    public static let perSeriesLimit = 200
    /// A query never spans more than this many days (defensive; a month grid needs ~42).
    public static let maxRangeDays = 400

    public init(store: MailStore, account: AccountID) {
        self.store = store
        self.account = account
    }

    public func events(from: Date, to: Date, limit: Int = 500) throws -> CalendarEvents {
        guard from <= to, limit > 0 else { throw CalendarSceneError.invalidRange }
        let end = min(to, from.addingTimeInterval(TimeInterval(Self.maxRangeDays) * 86_400))
        let range = from...end

        // Ask for one extra row so a truncated page is detectable after expansion.
        let entries = try store.meetings(account: account, from: from, to: end, limit: limit + 1)
        var occurrences: [MeetingOccurrence] = []
        var unexpanded: [String] = []

        for entry in entries {
            var expanded = entry.invite.occurrences(in: range, limit: Self.perSeriesLimit)
            if expanded.isEmpty, entry.invite.recurrence != nil {
                unexpanded.append(entry.invite.uid)
            }
            for index in expanded.indices {
                expanded[index].folderID = entry.folderID
                expanded[index].serverID = entry.serverID
                if let displaySubject = entry.displaySubject, !displaySubject.isEmpty {
                    expanded[index].subject = displaySubject
                }
                expanded[index].organizer = entry.invite.organizer
            }
            occurrences.append(contentsOf: expanded)
        }

        occurrences.sort { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            return lhs.uid < rhs.uid
        }
        let truncated = occurrences.count > limit
        if truncated {
            occurrences = Array(occurrences.prefix(limit))
        }
        return CalendarEvents(occurrences: occurrences, truncated: truncated, unexpandedUIDs: unexpanded)
    }

    public func meeting(uid: String) throws -> MeetingInvite? {
        try store.meetingInvite(account: account, uid: uid)
    }

    /// Source mail for one occurrence (REQ-0040): the calendar page lists invitation
    /// emails on the left, so it needs the message envelope, not just the meeting.
    public func message(_ ref: MessageRef) throws -> Message? {
        try store.message(account: account, folder: ref.folderID, serverID: ref.serverID)
    }

    public func ics(uid: String, now: Date = Date()) throws -> String {
        guard let invite = try store.meetingInvite(account: account, uid: uid) else {
            throw CalendarSceneError.meetingNotFound(uid: uid)
        }
        return invite.ics(now: now)
    }
}
