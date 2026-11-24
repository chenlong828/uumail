import Foundation

// MARK: - Meeting values (REQ-0029 / REQ-0030)

/// How a meeting message relates to the series it carries.
public enum MeetingMessageType: Int, Sendable, Equatable {
    case initial = 1
    case update = 2
    case informational = 3
    /// A newer request replaced this one; it must not be shown.
    case outdated = 4
    case delegatorCopy = 5
    case delegated = 6
}

/// Bit values used by the EAS `DayOfWeek` element (1 = Sunday … 64 = Saturday).
public enum Weekday: Int, Sendable, Equatable, CaseIterable {
    case sunday = 1
    case monday = 2
    case tuesday = 4
    case wednesday = 8
    case thursday = 16
    case friday = 32
    case saturday = 64

    /// `Calendar` weekday numbers (1 = Sunday … 7 = Saturday).
    public var calendarWeekday: Int {
        switch self {
        case .sunday: 1
        case .monday: 2
        case .tuesday: 3
        case .wednesday: 4
        case .thursday: 5
        case .friday: 6
        case .saturday: 7
        }
    }

    /// The two-letter iCalendar code used in `BYDAY`.
    public var iCalendarCode: String {
        switch self {
        case .sunday: "SU"
        case .monday: "MO"
        case .tuesday: "TU"
        case .wednesday: "WE"
        case .thursday: "TH"
        case .friday: "FR"
        case .saturday: "SA"
        }
    }

    /// Maps the EAS `FirstDayOfWeek` value (0 = Sunday … 6 = Saturday).
    public static func calendarWeekday(_ value: Int?) -> Weekday {
        switch value {
        case 0: .sunday
        case 2: .tuesday
        case 3: .wednesday
        case 4: .thursday
        case 5: .friday
        case 6: .saturday
        default: .monday
        }
    }

    /// Expands an EAS bit mask; `127` is the "last day of month" marker, not a set.
    public static func set(fromMask mask: Int) -> Set<Weekday> {
        guard mask != 127 else { return [] }
        return Set(allCases.filter { mask & $0.rawValue != 0 })
    }
}

/// The organizer's fixed zone: name for display, offset for wall-clock expansion.
public struct MeetingTimeZone: Equatable, Sendable {
    public var name: String?
    /// Seconds east of UTC (`Asia/Shanghai` = 28800).
    public var offsetSeconds: Int

    public init(name: String? = nil, offsetSeconds: Int) {
        self.name = name
        self.offsetSeconds = offsetSeconds
    }
}

/// A meeting series rule, normalized from the EAS `Recurrence` element.
public struct RecurrenceRule: Equatable, Sendable {
    public enum Frequency: Int, Sendable, Equatable {
        case daily = 0
        case weekly = 1
        case monthlyDay = 2
        case monthlyWeekday = 3
        case yearlyDay = 5
        case yearlyWeekday = 6
    }

    public var frequency: Frequency
    public var interval: Int
    /// UTC instant of the last allowed occurrence (EAS Compact DateTime).
    public var until: Date?
    public var occurrences: Int?
    public var weekdays: Set<Weekday>
    public var dayOfMonth: Int?
    /// 1…4, or 5 for "last of the month".
    public var weekOfMonth: Int?
    public var monthOfYear: Int?
    public var firstDayOfWeek: Weekday
    /// EAS `DayOfWeek == 127`: the rule means "last day of the month".
    public var lastDayOfMonth: Bool

    public init(
        frequency: Frequency,
        interval: Int = 1,
        until: Date? = nil,
        occurrences: Int? = nil,
        weekdays: Set<Weekday> = [],
        dayOfMonth: Int? = nil,
        weekOfMonth: Int? = nil,
        monthOfYear: Int? = nil,
        firstDayOfWeek: Weekday = .monday,
        lastDayOfMonth: Bool = false
    ) {
        self.frequency = frequency
        self.interval = max(1, interval)
        self.until = until
        self.occurrences = occurrences
        self.weekdays = weekdays
        self.dayOfMonth = dayOfMonth
        self.weekOfMonth = weekOfMonth
        self.monthOfYear = monthOfYear
        self.firstDayOfWeek = firstDayOfWeek
        self.lastDayOfMonth = lastDayOfMonth
    }
}

/// One overridden or deleted instance of a series (`InstanceType == 3`).
public struct MeetingException: Equatable, Sendable {
    /// Original start (UTC) of the instance being replaced.
    public var recurrenceId: Date
    public var start: Date?
    public var end: Date?
    public var subject: String?
    public var location: String?
    public var isDeleted: Bool

    public init(
        recurrenceId: Date,
        start: Date? = nil,
        end: Date? = nil,
        subject: String? = nil,
        location: String? = nil,
        isDeleted: Bool = false
    ) {
        self.recurrenceId = recurrenceId
        self.start = start
        self.end = end
        self.subject = subject
        self.location = location
        self.isDeleted = isDeleted
    }
}

/// A meeting request as stored in `meetings` and shown by the reading pane card.
public struct MeetingInvite: Equatable, Sendable {
    public var uid: String
    public var subject: String?
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var location: String?
    public var organizer: String?
    public var reminderMinutes: Int?
    public var responseRequested: Bool
    public var busyStatus: Int?
    public var messageType: MeetingMessageType
    public var isCancelled: Bool
    public var dtstamp: Date?
    public var timeZone: MeetingTimeZone?
    public var recurrence: RecurrenceRule?
    public var exceptions: [MeetingException]

    public init(
        uid: String,
        subject: String? = nil,
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        location: String? = nil,
        organizer: String? = nil,
        reminderMinutes: Int? = nil,
        responseRequested: Bool = false,
        busyStatus: Int? = nil,
        messageType: MeetingMessageType = .initial,
        isCancelled: Bool = false,
        dtstamp: Date? = nil,
        timeZone: MeetingTimeZone? = nil,
        recurrence: RecurrenceRule? = nil,
        exceptions: [MeetingException] = []
    ) {
        self.uid = uid
        self.subject = subject
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.organizer = organizer
        self.reminderMinutes = reminderMinutes
        self.responseRequested = responseRequested
        self.busyStatus = busyStatus
        self.messageType = messageType
        self.isCancelled = isCancelled
        self.dtstamp = dtstamp
        self.timeZone = timeZone
        self.recurrence = recurrence
        self.exceptions = exceptions
    }

    /// The wall clock the series is expressed in: the organizer's fixed zone, or UTC when
    /// the request carried no usable time zone (display then labels it as unknown).
    public var zone: TimeZone {
        TimeZone(secondsFromGMT: timeZone?.offsetSeconds ?? 0) ?? .gmt
    }
}

/// One instance of a meeting in a visible range.
public struct MeetingOccurrence: Equatable, Sendable {
    public var uid: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var subject: String?
    public var location: String?
    public var organizer: String?
    public var isRecurringInstance: Bool
    public var folderID: String
    public var serverID: String

    public init(
        uid: String,
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        subject: String? = nil,
        location: String? = nil,
        organizer: String? = nil,
        isRecurringInstance: Bool = false,
        folderID: String,
        serverID: String
    ) {
        self.uid = uid
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.subject = subject
        self.location = location
        self.organizer = organizer
        self.isRecurringInstance = isRecurringInstance
        self.folderID = folderID
        self.serverID = serverID
    }
}

// MARK: - Recurrence expansion

public extension MeetingInvite {
    /// Occurrences whose start falls inside `range`, capped by `limit`.
    ///
    /// The series is walked from its first instance in the organizer's fixed zone, so a
    /// weekly 16:00 meeting stays at 16:00 across month boundaries. DST transitions are not
    /// modeled (see `plan/open-questions.md` Q5): the offset is constant.
    func occurrences(in range: ClosedRange<Date>, limit: Int = 200) -> [MeetingOccurrence] {
        guard limit > 0 else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        calendar.firstWeekday = recurrence?.firstDayOfWeek.calendarWeekday ?? Weekday.monday.calendarWeekday

        let duration = end.timeIntervalSince(start)
        var results: [MeetingOccurrence] = []
        let exceptionsByID = Dictionary(
            exceptions.map { ($0.recurrenceId, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        func append(_ instanceStart: Date) {
            guard instanceStart >= range.lowerBound, instanceStart <= range.upperBound else { return }
            guard results.count < limit else { return }
            let exception = exceptionsByID[instanceStart]
            if exception?.isDeleted == true { return }
            let instanceEnd = exception?.end ?? instanceStart.addingTimeInterval(duration)
            results.append(MeetingOccurrence(
                uid: uid,
                start: exception?.start ?? instanceStart,
                end: instanceEnd,
                isAllDay: isAllDay,
                subject: exception?.subject ?? subject,
                location: exception?.location ?? location,
                organizer: organizer,
                isRecurringInstance: recurrence != nil,
                folderID: "",
                serverID: ""
            ))
        }

        guard let rule = recurrence else {
            if start >= range.lowerBound && start <= range.upperBound, exceptionsByID[start]?.isDeleted != true {
                append(start)
            }
            return results
        }

        let hardStop = range.upperBound
        let until = rule.until
        var produced = 0
        var cursor = start

        // The walk is bounded: a series that starts decades before the range still stops
        // once it passes the range, and `limit` caps what a single query can materialize.
        for _ in 0..<20_000 {
            if cursor > hardStop { break }
            if let until, cursor > until { break }
            if let count = rule.occurrences, produced >= count { break }
            produced += 1
            append(cursor)
            guard let next = Self.nextStart(after: cursor, rule: rule, calendar: calendar, seriesStart: start)
            else { break }
            if next <= cursor { break }
            cursor = next
        }
        return results
    }

    /// Next instance start after `cursor`, or nil when the rule cannot advance.
    private static func nextStart(
        after cursor: Date,
        rule: RecurrenceRule,
        calendar: Calendar,
        seriesStart: Date
    ) -> Date? {
        switch rule.frequency {
        case .daily:
            return calendar.date(byAdding: .day, value: rule.interval, to: cursor)
        case .weekly:
            if rule.weekdays.isEmpty {
                return calendar.date(byAdding: .weekOfYear, value: rule.interval, to: cursor)
            }
            return nextWeekly(after: cursor, rule: rule, calendar: calendar, seriesStart: seriesStart)
        case .monthlyDay:
            guard let day = rule.dayOfMonth else { return nil }
            return nextMonthlyDay(after: cursor, day: day, interval: rule.interval, calendar: calendar)
        case .monthlyWeekday:
            return nextMonthlyWeekday(after: cursor, rule: rule, calendar: calendar)
        case .yearlyDay:
            guard let month = rule.monthOfYear, let day = rule.dayOfMonth else { return nil }
            return nextYearlyDay(after: cursor, month: month, day: day, interval: rule.interval, calendar: calendar)
        case .yearlyWeekday:
            return nextYearlyWeekday(after: cursor, rule: rule, calendar: calendar)
        }
    }

    private static func nextWeekly(
        after cursor: Date,
        rule: RecurrenceRule,
        calendar: Calendar,
        seriesStart: Date
    ) -> Date? {
        let allowed = rule.weekdays.sorted { $0.calendarWeekday < $1.calendarWeekday }
        // Week index counted from the series start week, honoring the rule's first weekday.
        func weekStart(_ date: Date) -> Date {
            let weekday = calendar.component(.weekday, from: date)
            let delta = (weekday - calendar.firstWeekday + 7) % 7
            return calendar.date(byAdding: .day, value: -delta, to: calendar.startOfDay(for: date)) ?? date
        }
        let startWeek = weekStart(seriesStart)
        var candidate = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor
        for _ in 0..<(rule.interval * 8 + 8) {
            let days = calendar.dateComponents([.day], from: startWeek, to: weekStart(candidate)).day ?? 0
            let weekIndex = days / 7
            if weekIndex % rule.interval == 0,
               let weekday = Weekday.allCases.first(where: { $0.calendarWeekday == calendar.component(.weekday, from: candidate) }),
               allowed.contains(weekday) {
                return candidate
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: candidate) else { return nil }
            candidate = next
        }
        return nil
    }

    private static func nextMonthlyDay(
        after cursor: Date,
        day: Int,
        interval: Int,
        calendar: Calendar
    ) -> Date? {
        guard let month = calendar.date(byAdding: .month, value: interval, to: calendar.startOfDay(for: cursor)),
              let range = calendar.range(of: .day, in: .month, for: month)
        else { return nil }
        guard day <= range.count else {
            // 31st in a 30-day month: skip to the next month that has it.
            return nextMonthlyDay(after: month, day: day, interval: interval, calendar: calendar)
        }
        var components = calendar.dateComponents([.year, .month], from: month)
        components.day = day
        components.hour = calendar.component(.hour, from: cursor)
        components.minute = calendar.component(.minute, from: cursor)
        components.second = calendar.component(.second, from: cursor)
        return calendar.date(from: components)
    }

    private static func nextMonthlyWeekday(
        after cursor: Date,
        rule: RecurrenceRule,
        calendar: Calendar
    ) -> Date? {
        guard let month = calendar.date(byAdding: .month, value: rule.interval, to: calendar.startOfDay(for: cursor))
        else { return nil }
        return nthWeekday(inMonthOf: month, rule: rule, calendar: calendar, cursor: cursor)
    }

    private static func nextYearlyDay(
        after cursor: Date,
        month: Int,
        day: Int,
        interval: Int,
        calendar: Calendar
    ) -> Date? {
        guard let shifted = calendar.date(byAdding: .year, value: interval, to: calendar.startOfDay(for: cursor))
        else { return nil }
        var components = calendar.dateComponents([.year], from: shifted)
        components.month = month
        components.day = day
        components.hour = calendar.component(.hour, from: cursor)
        components.minute = calendar.component(.minute, from: cursor)
        components.second = calendar.component(.second, from: cursor)
        return calendar.date(from: components)
    }

    private static func nextYearlyWeekday(
        after cursor: Date,
        rule: RecurrenceRule,
        calendar: Calendar
    ) -> Date? {
        guard let month = rule.monthOfYear,
              let shifted = calendar.date(byAdding: .year, value: rule.interval, to: calendar.startOfDay(for: cursor))
        else { return nil }
        var components = calendar.dateComponents([.year], from: shifted)
        components.month = month
        return nthWeekday(inMonthOf: calendar.date(from: components) ?? shifted, rule: rule, calendar: calendar, cursor: cursor)
    }

    /// The nth (or last) matching weekday inside the month that contains `month`.
    private static func nthWeekday(
        inMonthOf month: Date,
        rule: RecurrenceRule,
        calendar: Calendar,
        cursor: Date
    ) -> Date? {
        guard let dayRange = calendar.range(of: .day, in: .month, for: month) else { return nil }
        let wanted = rule.weekdays.sorted { $0.calendarWeekday < $1.calendarWeekday }
        var matches: [Date] = []
        for day in dayRange {
            var components = calendar.dateComponents([.year, .month], from: month)
            components.day = day
            if let date = calendar.date(from: components),
               wanted.contains(where: { $0.calendarWeekday == calendar.component(.weekday, from: date) }) {
                matches.append(date)
            }
        }
        guard !matches.isEmpty else { return nil }
        let position = rule.lastDayOfMonth ? matches.count : (rule.weekOfMonth ?? 1)
        let index = position == 5 ? matches.count - 1 : min(max(position, 1) - 1, matches.count - 1)
        guard let day = matches.indices.contains(index) ? matches[index] : matches.last else { return nil }
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = calendar.component(.hour, from: cursor)
        components.minute = calendar.component(.minute, from: cursor)
        components.second = calendar.component(.second, from: cursor)
        return calendar.date(from: components)
    }
}

// MARK: - iCalendar export

public extension MeetingInvite {
    /// `text/calendar` body for the whole series (`METHOD:PUBLISH`), tuned so Calendar.app
    /// imports it as a plain event instead of an invitation awaiting a response.
    func ics(now: Date = Date()) -> String {
        var lines: [String] = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//uumail//uumail//CN",
            "CALSCALE:GREGORIAN",
            "METHOD:PUBLISH",
        ]
        lines.append(contentsOf: Self.vevent(self, recurrenceID: nil, now: now))
        for exception in exceptions where !exception.isDeleted {
            var overridden = self
            overridden.start = exception.start ?? start
            overridden.end = exception.end ?? end
            overridden.subject = exception.subject ?? subject
            overridden.location = exception.location ?? location
            overridden.recurrence = nil
            lines.append(contentsOf: Self.vevent(overridden, recurrenceID: exception.recurrenceId, now: now))
        }
        lines.append("END:VCALENDAR")
        return lines.map(Self.fold).joined(separator: "\r\n") + "\r\n"
    }

    private static func vevent(_ invite: MeetingInvite, recurrenceID: Date?, now: Date) -> [String] {
        var lines: [String] = ["BEGIN:VEVENT"]
        lines.append("UID:\(escape(invite.uid))")
        lines.append("DTSTAMP:\(utc(now))")
        lines.append("SUMMARY:\(escape(invite.subject ?? "会议"))")
        if let location = invite.location, !location.isEmpty {
            lines.append("LOCATION:\(escape(location))")
        }
        if let organizer = invite.organizer, !organizer.isEmpty {
            if let address = emailAddress(in: organizer) {
                lines.append("ORGANIZER:mailto:\(address)")
            }
        }
        if invite.isAllDay {
            let endExclusive = Calendar(identifier: .gregorian).date(
                byAdding: .day, value: 1, to: startOfDay(invite.end, zone: invite.zone)
            ) ?? invite.end
            lines.append("DTSTART;VALUE=DATE:\(dateOnly(invite.start, zone: invite.zone))")
            lines.append("DTEND;VALUE=DATE:\(dateOnly(endExclusive, zone: invite.zone))")
            lines.append("X-MICROSOFT-CDO-ALLDAYEVENT:TRUE")
        } else {
            if let recurrenceID {
                lines.append("RECURRENCE-ID:\(utc(recurrenceID))")
            } else {
                lines.append("DTSTART:\(utc(invite.start))")
                lines.append("DTEND:\(utc(invite.end))")
            }
            if let busy = invite.busyStatus, busy == 2 {
                lines.append("TRANSP:OPAQUE")
            } else {
                lines.append("TRANSP:TRANSPARENT")
            }
        }
        if let rule = invite.recurrence {
            lines.append("RRULE:\(RRuleText.make(rule))")
            for exception in invite.exceptions where exception.isDeleted {
                lines.append("EXDATE:\(utc(exception.recurrenceId))")
            }
        }
        lines.append("STATUS:CONFIRMED")
        lines.append("SEQUENCE:0")
        lines.append("END:VEVENT")
        return lines
    }

    /// RFC 5545 line folding at 75 octets (UTF-8), continuation lines start with a space.
    static func fold(_ line: String) -> String {
        var result = ""
        var current = ""
        var currentBytes = 0
        for character in line {
            let size = String(character).utf8.count
            if currentBytes + size > 74, !current.isEmpty {
                result += (result.isEmpty ? "" : "\r\n ") + current
                current = String(character)
                currentBytes = size
            } else {
                current.append(character)
                currentBytes += size
            }
        }
        return result.isEmpty ? current : result + "\r\n " + current
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private static func utc(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }

    private static func dateOnly(_ date: Date, zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }

    private static func startOfDay(_ date: Date, zone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.startOfDay(for: date)
    }

    private static func emailAddress(in organizer: String) -> String? {
        if let start = organizer.firstIndex(of: "<"),
           let end = organizer.lastIndex(of: ">"),
           start < end {
            return String(organizer[organizer.index(after: start)..<end])
        }
        let trimmed = organizer.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("@") ? trimmed : nil
    }
}

/// `RRULE` text for the normalized rule; kept separate so both ICS and tests share it.
enum RRuleText {
    static func make(_ rule: RecurrenceRule) -> String {
        var parts: [String] = []
        switch rule.frequency {
        case .daily:
            parts = ["FREQ=DAILY"]
        case .weekly:
            parts = ["FREQ=WEEKLY"]
            if !rule.weekdays.isEmpty {
                parts.append("BYDAY=" + rule.weekdays.sorted { $0.calendarWeekday < $1.calendarWeekday }
                    .map(\.iCalendarCode).joined(separator: ","))
            }
        case .monthlyDay:
            parts = ["FREQ=MONTHLY"]
            if let day = rule.dayOfMonth { parts.append("BYMONTHDAY=\(day)") }
        case .monthlyWeekday:
            parts = ["FREQ=MONTHLY"]
            if let day = weekdayPart(rule) { parts.append("BYDAY=\(day)") }
        case .yearlyDay:
            parts = ["FREQ=YEARLY"]
            if let month = rule.monthOfYear { parts.append("BYMONTH=\(month)") }
            if let day = rule.dayOfMonth { parts.append("BYMONTHDAY=\(day)") }
        case .yearlyWeekday:
            parts = ["FREQ=YEARLY"]
            if let month = rule.monthOfYear { parts.append("BYMONTH=\(month)") }
            if let day = weekdayPart(rule) { parts.append("BYDAY=\(day)") }
        }
        if rule.interval > 1 { parts.append("INTERVAL=\(rule.interval)") }
        if let count = rule.occurrences, rule.until == nil {
            parts.append("COUNT=\(count)")
        } else if let until = rule.until {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            parts.append("UNTIL=\(formatter.string(from: until))")
        }
        parts.append("WKST=\(rule.firstDayOfWeek.iCalendarCode)")
        return parts.joined(separator: ";")
    }

    private static func weekdayPart(_ rule: RecurrenceRule) -> String? {
        guard let weekday = rule.weekdays.sorted(by: { $0.calendarWeekday < $1.calendarWeekday }).first else {
            return nil
        }
        let position = rule.weekOfMonth ?? 1
        let prefix = position == 5 ? "-1" : "\(position)"
        return prefix + weekday.iCalendarCode
    }
}
