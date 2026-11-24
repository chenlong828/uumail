import Foundation
import Testing
import MeetingDomain

@testable import MeetingDomain

@Suite("Meeting recurrence")
struct MeetingRecurrenceTests {
    private func date(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)!
    }

    private func invite(
        start: String = "2026-11-02T01:00:00Z",
        end: String = "2026-11-02T02:00:00Z",
        rule: RecurrenceRule? = nil,
        exceptions: [MeetingException] = []
    ) -> MeetingInvite {
        MeetingInvite(
            uid: "u-1",
            subject: "会议",
            start: date(start),
            end: date(end),
            timeZone: MeetingTimeZone(name: "China Standard Time", offsetSeconds: 28800),
            recurrence: rule,
            exceptions: exceptions
        )
    }

    private func range(_ from: String, _ to: String) -> ClosedRange<Date> {
        date(from)...date(to)
    }

    @Test("a single meeting occurs once and only inside the range")
    func singleMeeting() {
        let meeting = invite()
        #expect(meeting.occurrences(in: range("2026-11-01T00:00:00Z", "2026-11-30T00:00:00Z")).count == 1)
        #expect(meeting.occurrences(in: range("2026-11-03T00:00:00Z", "2026-11-30T00:00:00Z")).isEmpty)
    }

    @Test("daily repeats by interval and stops at the range edge")
    func daily() {
        let meeting = invite(rule: RecurrenceRule(frequency: .daily))
        let occurrences = meeting.occurrences(in: range("2026-11-02T00:00:00Z", "2026-11-05T23:59:59Z"))
        #expect(occurrences.count == 4)
        #expect(occurrences.first?.start == date("2026-11-02T01:00:00Z"))
    }

    @Test("weekly expands every selected weekday")
    func weekly() {
        let meeting = invite(rule: RecurrenceRule(
            frequency: .weekly,
            weekdays: [.monday, .wednesday],
            firstDayOfWeek: .monday
        ))
        let occurrences = meeting.occurrences(in: range("2026-11-02T00:00:00Z", "2026-11-15T23:59:59Z"))
        // Nov 2 (Mon), Nov 4 (Wed), Nov 9 (Mon), Nov 11 (Wed) at 09:00 local.
        #expect(occurrences.count == 4)
        #expect(occurrences.map(\.start) == [
            date("2026-11-02T01:00:00Z"),
            date("2026-11-04T01:00:00Z"),
            date("2026-11-09T01:00:00Z"),
            date("2026-11-11T01:00:00Z"),
        ])
    }

    @Test("monthly by day skips months that do not have that day")
    func monthlyDay() {
        let meeting = invite(
            start: "2026-01-31T01:00:00Z",
            end: "2026-01-31T02:00:00Z",
            rule: RecurrenceRule(frequency: .monthlyDay, dayOfMonth: 31)
        )
        let occurrences = meeting.occurrences(in: range("2026-01-01T00:00:00Z", "2026-06-30T23:59:59Z"))
        #expect(occurrences.count == 3)  // Jan 31, Mar 31, May 31
    }

    @Test("monthly on the nth weekday and on the last weekday")
    func monthlyWeekday() {
        let secondWednesday = invite(
            start: "2026-11-11T01:00:00Z",
            end: "2026-11-11T02:00:00Z",
            rule: RecurrenceRule(frequency: .monthlyWeekday, weekdays: [.wednesday], weekOfMonth: 2)
        )
        let second = secondWednesday.occurrences(in: range("2026-11-01T00:00:00Z", "2026-12-31T23:59:59Z"))
        #expect(second.map(\.start) == [date("2026-11-11T01:00:00Z"), date("2026-12-09T01:00:00Z")])

        let lastMonday = invite(
            start: "2026-11-30T01:00:00Z",
            end: "2026-11-30T02:00:00Z",
            rule: RecurrenceRule(frequency: .monthlyWeekday, weekdays: [.monday], weekOfMonth: 5)
        )
        let last = lastMonday.occurrences(in: range("2026-11-01T00:00:00Z", "2026-12-31T23:59:59Z"))
        #expect(last.map(\.start) == [date("2026-11-30T01:00:00Z"), date("2026-12-28T01:00:00Z")])
    }

    @Test("yearly by day repeats on the same month and day")
    func yearlyDay() {
        let meeting = invite(
            start: "2026-11-19T01:00:00Z",
            end: "2026-11-19T02:00:00Z",
            rule: RecurrenceRule(frequency: .yearlyDay, dayOfMonth: 19, monthOfYear: 11)
        )
        let occurrences = meeting.occurrences(in: range("2026-01-01T00:00:00Z", "2028-12-31T23:59:59Z"))
        #expect(occurrences.count == 3)
        #expect(occurrences.first?.start == date("2026-11-19T01:00:00Z"))
    }

    @Test("until, occurrences and limit all bound the result")
    func bounds() {
        let until = invite(rule: RecurrenceRule(frequency: .daily, until: date("2026-11-04T01:00:00Z")))
        #expect(until.occurrences(in: range("2026-11-01T00:00:00Z", "2026-11-30T00:00:00Z")).count == 3)

        let counted = invite(rule: RecurrenceRule(frequency: .daily, occurrences: 2))
        #expect(counted.occurrences(in: range("2026-11-01T00:00:00Z", "2026-11-30T00:00:00Z")).count == 2)

        let limited = invite(rule: RecurrenceRule(frequency: .daily))
        #expect(limited.occurrences(in: range("2026-11-01T00:00:00Z", "2026-11-30T00:00:00Z"), limit: 5).count == 5)
    }

    @Test("exceptions replace an instance or delete it")
    func exceptions() {
        let moved = MeetingException(
            recurrenceId: date("2026-11-03T01:00:00Z"),
            start: date("2026-11-03T05:00:00Z"),
            end: date("2026-11-03T06:00:00Z"),
            subject: "改期的会议"
        )
        let deleted = MeetingException(recurrenceId: date("2026-11-04T01:00:00Z"), isDeleted: true)
        let meeting = invite(rule: RecurrenceRule(frequency: .daily), exceptions: [moved, deleted])
        let occurrences = meeting.occurrences(in: range("2026-11-01T00:00:00Z", "2026-11-05T23:59:59Z"))
        #expect(occurrences.count == 3)
        #expect(occurrences.map(\.subject) == ["会议", "改期的会议", "会议"])
        #expect(occurrences[1].start == date("2026-11-03T05:00:00Z"))
    }

    @Test("an all-day series keeps whole days")
    func allDay() {
        var meeting = invite(rule: RecurrenceRule(frequency: .daily))
        meeting.isAllDay = true
        meeting.start = date("2026-11-02T00:00:00Z")
        meeting.end = date("2026-11-02T23:59:59Z")
        let occurrences = meeting.occurrences(in: range("2026-11-01T00:00:00Z", "2026-11-04T23:59:59Z"))
        let allAllDay = occurrences.allSatisfy { $0.isAllDay }
        #expect(occurrences.count == 3)
        #expect(allAllDay)
    }
}

@Suite("Meeting iCalendar export")
struct MeetingICSTests {
    private func date(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)!
    }

    @Test("a single meeting exports VCALENDAR/VEVENT with UTC times")
    func single() {
        let meeting = MeetingInvite(
            uid: "u-1",
            subject: "会议, 带逗号",
            start: date("2026-11-19T01:30:00Z"),
            end: date("2026-11-19T04:00:00Z"),
            location: "C4519",
            organizer: "\"王权英\" <wangqy@hundsun.com>",
            busyStatus: 2
        )
        let text = meeting.ics(now: date("2026-11-24T00:00:00Z"))
        #expect(text.hasPrefix("BEGIN:VCALENDAR\r\n"))
        #expect(text.contains("METHOD:PUBLISH"))
        #expect(text.contains("BEGIN:VEVENT"))
        #expect(text.contains("UID:u-1"))
        #expect(text.contains("DTSTART:20261119T013000Z"))
        #expect(text.contains("DTEND:20261119T040000Z"))
        #expect(text.contains("SUMMARY:会议\\, 带逗号"))
        #expect(text.contains("LOCATION:C4519"))
        #expect(text.contains("ORGANIZER:mailto:wangqy@hundsun.com"))
        #expect(text.contains("DTSTAMP:20261124T000000Z"))
        #expect(text.hasSuffix("END:VCALENDAR\r\n"))
    }

    @Test("a series exports RRULE and EXDATE for deleted instances")
    func series() {
        var meeting = MeetingInvite(
            uid: "u-2",
            subject: "周会",
            start: date("2026-11-02T01:00:00Z"),
            end: date("2026-11-02T02:00:00Z"),
            timeZone: MeetingTimeZone(name: "China Standard Time", offsetSeconds: 28800),
            recurrence: RecurrenceRule(
                frequency: .weekly,
                weekdays: [.monday],
                firstDayOfWeek: .monday
            )
        )
        meeting.exceptions = [
            MeetingException(recurrenceId: date("2026-11-09T01:00:00Z"), isDeleted: true),
        ]
        let text = meeting.ics(now: date("2026-11-24T00:00:00Z"))
        #expect(text.contains("RRULE:FREQ=WEEKLY;BYDAY=MO;WKST=MO"))
        #expect(text.contains("EXDATE:20261109T010000Z"))
    }

    @Test("an all-day meeting uses DATE values")
    func allDay() {
        let meeting = MeetingInvite(
            uid: "u-3",
            subject: "全天",
            start: date("2026-11-19T00:00:00Z"),
            end: date("2026-11-19T23:59:59Z"),
            isAllDay: true
        )
        let text = meeting.ics(now: date("2026-11-24T00:00:00Z"))
        #expect(text.contains("DTSTART;VALUE=DATE:20261119"))
        #expect(text.contains("DTEND;VALUE=DATE:20261120"))
    }
}
