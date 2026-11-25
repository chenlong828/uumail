import Foundation
import MailDomain
import MeetingDomain

// MARK: - Calendar projections (pure values; the view only binds to these)

public struct CalendarChip: Equatable, Sendable {
    public var title: String
    public var start: Date
    public var isAllDay: Bool
    public var occurrence: MeetingOccurrence

    public init(title: String, start: Date, isAllDay: Bool, occurrence: MeetingOccurrence) {
        self.title = title
        self.start = start
        self.isAllDay = isAllDay
        self.occurrence = occurrence
    }
}

/// One calendar invitation email in the calendar page's left list (REQ-0040). Recurring
/// meetings share one source mail, so the row carries the first visible occurrence for
/// selection while the identity stays the mail's folder + server id.
public struct CalendarMailItem: Equatable, Identifiable, Sendable {
    /// The source mail when it is still in the local store. Nil for invites whose message
    /// was deleted/moved after the meeting row was written; the row then shows the meeting
    /// metadata so the calendar list stays complete.
    public var message: Message?
    public var occurrence: MeetingOccurrence

    public init(message: Message?, occurrence: MeetingOccurrence) {
        self.message = message
        self.occurrence = occurrence
    }

    public var id: String { "\(occurrence.folderID)\u{1F}\(occurrence.serverID)" }

    public var title: String {
        message?.subject ?? occurrence.subject ?? "会议"
    }

    public var senderText: String {
        if let message { return DisplayFormat.senderName(message.sender) }
        return occurrence.organizer ?? "来源邮件不在本机"
    }
}

public struct MonthDay: Equatable, Sendable {
    public var date: Date
    public var isInMonth: Bool
    public var isToday: Bool
    public var chips: [CalendarChip]
    public var hiddenCount: Int

    public init(date: Date, isInMonth: Bool, isToday: Bool, chips: [CalendarChip], hiddenCount: Int) {
        self.date = date
        self.isInMonth = isInMonth
        self.isToday = isToday
        self.chips = chips
        self.hiddenCount = hiddenCount
    }
}

public struct MonthWeek: Equatable, Sendable {
    public var days: [MonthDay]
    public init(days: [MonthDay]) { self.days = days }
}

public struct MonthGridPresentation: Equatable, Sendable {
    public var weeks: [MonthWeek]
    public var title: String
    public var daySymbols: [String]

    public init(weeks: [MonthWeek], title: String, daySymbols: [String]) {
        self.weeks = weeks
        self.title = title
        self.daySymbols = daySymbols
    }
}

public struct WeekBlock: Equatable, Sendable {
    public var startMinute: Int
    public var endMinute: Int
    public var lane: Int
    public var title: String
    public var occurrence: MeetingOccurrence

    public init(startMinute: Int, endMinute: Int, lane: Int, title: String, occurrence: MeetingOccurrence) {
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.lane = lane
        self.title = title
        self.occurrence = occurrence
    }
}

public struct WeekColumn: Equatable, Sendable {
    public var date: Date
    public var isToday: Bool
    public var blocks: [WeekBlock]

    public init(date: Date, isToday: Bool, blocks: [WeekBlock]) {
        self.date = date
        self.isToday = isToday
        self.blocks = blocks
    }
}

public struct WeekGridPresentation: Equatable, Sendable {
    public var days: [WeekColumn]
    /// First visible hour (inclusive) and last visible hour (exclusive).
    public var startHour: Int
    public var endHour: Int
    public var allDayChips: [CalendarChip]
    public var title: String

    public init(
        days: [WeekColumn],
        startHour: Int,
        endHour: Int,
        allDayChips: [CalendarChip],
        title: String
    ) {
        self.days = days
        self.startHour = startHour
        self.endHour = endHour
        self.allDayChips = allDayChips
        self.title = title
    }
}

/// The reading pane card values; `nil` when the message is not a meeting request.
public struct MeetingCardPresentation: Equatable, Sendable {
    public var time: String
    public var location: String?
    public var organizer: String?
    public var recurrence: String?

    public init(time: String, location: String?, organizer: String?, recurrence: String?) {
        self.time = time
        self.location = location
        self.organizer = organizer
        self.recurrence = recurrence
    }
}
