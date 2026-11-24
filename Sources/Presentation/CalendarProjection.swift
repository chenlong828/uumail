import Foundation
import MailDomain
import MeetingDomain

/// Pure grid math, split out so it can be tested without a scene or a clock.
public enum CalendarProjection {
    public static let daySymbols = ["一", "二", "三", "四", "五", "六", "日"]

    public static func startOfWeek(_ date: Date, calendar: Calendar) -> Date {
        var calendar = calendar
        calendar.firstWeekday = 2
        let day = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: day)
        let delta = (weekday - 2 + 7) % 7
        return calendar.date(byAdding: .day, value: -delta, to: day) ?? day
    }

    public static func month(
        anchor: Date,
        occurrences: [MeetingOccurrence],
        calendar: Calendar,
        today: Date
    ) -> MonthGridPresentation {
        var calendar = calendar
        calendar.firstWeekday = 2
        let monthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: anchor)
        ) ?? anchor
        let gridStart = startOfWeek(monthStart, calendar: calendar)
        let month = calendar.component(.month, from: anchor)
        let year = calendar.component(.year, from: anchor)

        var weeks: [MonthWeek] = []
        for week in 0..<6 {
            var days: [MonthDay] = []
            for offset in 0..<7 {
                guard let date = calendar.date(byAdding: .day, value: week * 7 + offset, to: gridStart)
                else { continue }
                let dayStart = calendar.startOfDay(for: date)
                let allChips = occurrences
                    .filter { calendar.isDate($0.start, inSameDayAs: dayStart) }
                    .sorted { $0.start < $1.start }
                    .map {
                        CalendarChip(
                            title: $0.subject ?? "会议",
                            start: $0.start,
                            isAllDay: $0.isAllDay,
                            occurrence: $0
                        )
                    }
                days.append(MonthDay(
                    date: dayStart,
                    isInMonth: calendar.component(.month, from: dayStart) == month,
                    isToday: calendar.isDate(dayStart, inSameDayAs: today),
                    chips: Array(allChips.prefix(3)),
                    hiddenCount: max(0, allChips.count - 3)
                ))
            }
            weeks.append(MonthWeek(days: days))
        }
        return MonthGridPresentation(
            weeks: weeks,
            title: "\(year)年\(month)月",
            daySymbols: daySymbols
        )
    }

    public static func week(
        anchor: Date,
        occurrences: [MeetingOccurrence],
        calendar: Calendar,
        today: Date
    ) -> WeekGridPresentation {
        var calendar = calendar
        calendar.firstWeekday = 2
        let start = startOfWeek(anchor, calendar: calendar)

        var columns: [WeekColumn] = []
        var allDay: [CalendarChip] = []
        var minMinute = 8 * 60
        var maxMinute = 18 * 60

        for offset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let dayStart = calendar.startOfDay(for: date)
            let dayEvents = occurrences
                .filter { calendar.isDate($0.start, inSameDayAs: dayStart) }
                .sorted { $0.start < $1.start }

            for event in dayEvents where event.isAllDay {
                allDay.append(CalendarChip(
                    title: event.subject ?? "会议",
                    start: event.start,
                    isAllDay: true,
                    occurrence: event
                ))
            }

            var laneEnds: [Int] = []
            var blocks: [WeekBlock] = []
            for event in dayEvents where !event.isAllDay {
                let startMinute = calendar.component(.hour, from: event.start) * 60
                    + calendar.component(.minute, from: event.start)
                let endDate = max(event.end, event.start.addingTimeInterval(60))
                let endMinute = calendar.component(.hour, from: endDate) * 60
                    + calendar.component(.minute, from: endDate)
                minMinute = min(minMinute, startMinute)
                maxMinute = max(maxMinute, endMinute)

                var lane = 0
                while lane < laneEnds.count && laneEnds[lane] > startMinute {
                    lane += 1
                }
                if lane == laneEnds.count {
                    laneEnds.append(endMinute)
                } else {
                    laneEnds[lane] = max(laneEnds[lane], endMinute)
                }
                blocks.append(WeekBlock(
                    startMinute: startMinute,
                    endMinute: max(endMinute, startMinute + 30),
                    lane: lane,
                    title: event.subject ?? "会议",
                    occurrence: event
                ))
            }
            columns.append(WeekColumn(
                date: dayStart,
                isToday: calendar.isDate(dayStart, inSameDayAs: today),
                blocks: blocks
            ))
        }

        let startHour = max(0, min(8, minMinute / 60))
        let endHour = min(24, max(18, (maxMinute + 59) / 60))
        let first = columns.first?.date ?? anchor
        let last = columns.last?.date ?? anchor
        return WeekGridPresentation(
            days: columns,
            startHour: startHour,
            endHour: endHour,
            allDayChips: allDay,
            title: "\(monthDay(first)) – \(monthDay(last))"
        )
    }

    private static func monthDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }
}

// MARK: - Meeting card

public extension MeetingCardPresentation {
    /// Values for the reading pane card; `nil` for ordinary mail.
    static func make(
        from meeting: MeetingInvite?,
        calendar: Calendar = .current
    ) -> MeetingCardPresentation? {
        guard let meeting else { return nil }
        return MeetingCardPresentation(
            time: MeetingFormat.timeRange(meeting, calendar: calendar),
            location: meeting.location?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            organizer: DisplayFormat.senderName(meeting.organizer).nilIfEmpty,
            recurrence: meeting.recurrence.map { MeetingFormat.recurrenceSummary($0) }
        )
    }
}

enum MeetingFormat {
    static func timeRange(_ meeting: MeetingInvite, calendar: Calendar) -> String {
        let day = dayLabel(meeting.start, calendar: calendar)
        if meeting.isAllDay {
            return "\(day) 全天"
        }
        let start = timeLabel(meeting.start, calendar: calendar)
        let end = timeLabel(meeting.end, calendar: calendar)
        return "\(day) \(start)–\(end)"
    }

    static func dayLabel(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }

    static func timeLabel(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func recurrenceSummary(_ rule: RecurrenceRule) -> String {
        let weekdays = rule.weekdays.sorted { $0.calendarWeekday < $1.calendarWeekday }
            .map(weekdayName).joined(separator: "、")
        var text: String
        switch rule.frequency {
        case .daily:
            text = rule.interval > 1 ? "每 \(rule.interval) 天" : "每天"
        case .weekly:
            if weekdays.isEmpty {
                text = rule.interval > 1 ? "每 \(rule.interval) 周" : "每周"
            } else {
                text = (rule.interval > 1 ? "每 \(rule.interval) 周 " : "每周") + weekdays
            }
        case .monthlyDay:
            text = "每月 \(rule.dayOfMonth ?? 1) 日"
        case .monthlyWeekday:
            text = "每月" + positionLabel(rule) + (weekdays.isEmpty ? "" : weekdays)
        case .yearlyDay:
            text = "每年 \(rule.monthOfYear ?? 1) 月 \(rule.dayOfMonth ?? 1) 日"
        case .yearlyWeekday:
            text = "每年 \(rule.monthOfYear ?? 1) 月" + positionLabel(rule) + weekdays
        }
        if let count = rule.occurrences {
            text += "，共 \(count) 次"
        } else if let until = rule.until {
            text += "，至 \(dayLabel(until, calendar: .current))"
        }
        return text
    }

    private static func positionLabel(_ rule: RecurrenceRule) -> String {
        switch rule.weekOfMonth {
        case 5: "最后一个"
        case let value?: "第 \(value) 个"
        default: ""
        }
    }

    static func weekdayName(_ weekday: Weekday) -> String {
        switch weekday {
        case .sunday: "周日"
        case .monday: "周一"
        case .tuesday: "周二"
        case .wednesday: "周三"
        case .thursday: "周四"
        case .friday: "周五"
        case .saturday: "周六"
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
