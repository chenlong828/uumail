import Foundation
import MailDomain
import MailStore
import Scenes
import Testing
import MeetingDomain
import SyncContract

@testable import Presentation

/// Scenario-level L1 evidence for SCN-0024 / SCN-0023. The ids match the scenario cards so
/// the verification table can be checked one-to-one.
@Suite("SCN-0024 calendar grid")
struct CalendarGridScenarioTests {
    private func date(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)!
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 28800)!
        calendar.firstWeekday = 2
        return calendar
    }

    @MainActor
    private func make() throws -> (CalendarViewModel, MailStore, AccountID) {
        let store = try MailStore.inMemory()
        let account = try store.createAccount(
            NewAccount(displayName: "工作", address: "jdoe@corp.test", host: "mail.corp.test")
        )
        try store.applyFolderSnapshot(
            account: account,
            folders: [Folder(serverID: "13", parentID: "0", displayName: "收件箱", type: 2)],
            syncKey: "1"
        )
        let model = CalendarViewModel(
            calendar: CalendarScene(store: store, account: account),
            now: { self.date("2026-11-24T00:00:00Z") },
            calendar: self.calendar
        )
        return (model, store, account)
    }

    @MainActor
    private func seed(_ store: MailStore, _ account: AccountID, _ invites: [MeetingInvite], key: String = "2") throws {
        try store.applySyncBatch(
            account: account,
            folder: "13",
            added: invites.enumerated().map { index, invite in
                Message(serverID: "m-\(key)-\(index)", subject: invite.subject)
            },
            changed: [],
            removedServerIDs: [],
            syncKey: key,
            meetings: invites.enumerated().map { index, invite in
                MeetingDeltaEntry(serverID: "m-\(key)-\(index)", subject: invite.subject, invite: invite)
            }
        )
    }

    private func invite(
        _ uid: String,
        _ start: String,
        _ end: String,
        rule: RecurrenceRule? = nil,
        dtstamp: String = "2026-11-13T09:54:53Z",
        cancelled: Bool = false
    ) -> MeetingInvite {
        MeetingInvite(
            uid: uid,
            subject: "会议 \(uid)",
            start: date(start),
            end: date(end),
            location: "C4519",
            organizer: "wangqy@hundsun.com",
            messageType: .initial,
            isCancelled: cancelled,
            dtstamp: date(dtstamp),
            timeZone: MeetingTimeZone(name: "China Standard Time", offsetSeconds: 28800),
            recurrence: rule
        )
    }

    @MainActor
    @Test("T-SCN-0024-01: the month grid shows one chip on each invited day")
    func monthCells() async throws {
        let (model, store, account) = try make()
        try seed(store, account, [
            invite("a", "2026-11-19T01:30:00Z", "2026-11-19T04:00:00Z"),
            invite("b", "2026-11-23T08:00:00Z", "2026-11-23T09:00:00Z"),
        ])
        await model.activate()

        let days = model.month.weeks.flatMap(\.days)
        let nov19 = days.first { calendar.isDate($0.date, inSameDayAs: date("2026-11-19T00:00:00Z")) }
        let nov23 = days.first { calendar.isDate($0.date, inSameDayAs: date("2026-11-23T00:00:00Z")) }
        let nov20 = days.first { calendar.isDate($0.date, inSameDayAs: date("2026-11-20T00:00:00Z")) }
        #expect(nov19?.chips.count == 1)
        #expect(nov19?.chips.first?.title == "会议 a")
        #expect(nov23?.chips.count == 1)
        #expect(nov20?.chips.isEmpty == true)
        #expect(model.month.daySymbols == ["一", "二", "三", "四", "五", "六", "日"])
    }

    @MainActor
    @Test("T-SCN-0024-02: the week view positions blocks by minute with lanes")
    func weekGeometry() async throws {
        let (model, store, account) = try make()
        try seed(store, account, [
            invite("a", "2026-11-19T01:30:00Z", "2026-11-19T04:00:00Z"),
            invite("b", "2026-11-19T02:00:00Z", "2026-11-19T03:00:00Z"),
            invite("c", "2026-11-20T01:30:00Z", "2026-11-20T02:00:00Z", rule: nil),
        ])
        await model.activate()
        await model.setMode(.week)
        // Anchor is the week of Nov 23, so move back one week to reach Nov 16–22.
        await model.showPrevious()

        let thursday = model.week.days.first {
            calendar.isDate($0.date, inSameDayAs: date("2026-11-19T00:00:00Z"))
        }
        let blocks = try #require(thursday?.blocks)
        #expect(blocks.count == 2)
        #expect(blocks.first?.startMinute == 9 * 60 + 30)
        #expect(blocks.first?.endMinute == 12 * 60)
        #expect(Set(blocks.map(\.lane)).count == 2)
        #expect(model.week.allDayChips.isEmpty)
        #expect(model.week.startHour <= 9 && model.week.endHour >= 12)
    }

    @MainActor
    @Test("T-SCN-0024-03: a weekly series expands once per week inside the range")
    func recurringWeeks() async throws {
        let (model, store, account) = try make()
        try seed(store, account, [
            invite(
                "weekly",
                "2026-11-02T08:00:00Z",
                "2026-11-02T09:00:00Z",
                rule: RecurrenceRule(frequency: .weekly, weekdays: [.monday], firstDayOfWeek: .monday)
            ),
        ])
        await model.activate()

        let mondays = model.occurrences.map {
            calendar.component(.weekday, from: $0.start)
        }
        #expect(model.occurrences.count == 5)  // Nov 2, 9, 16, 23, 30
        #expect(mondays.allSatisfy { $0 == 2 })
    }

    @MainActor
    @Test("T-SCN-0024-04: stale updates and cancellations do not reach the grid; limits truncate")
    func staleAndCancelled() async throws {
        let (model, store, account) = try make()
        try seed(store, account, [
            invite("u-1", "2026-11-23T08:00:00Z", "2026-11-23T09:00:00Z", dtstamp: "2026-11-16T08:16:17Z"),
        ], key: "2")
        // A late older invite for the same UID must not move the meeting.
        try seed(store, account, [
            invite("u-1", "2026-11-16T08:00:00Z", "2026-11-16T09:00:00Z", dtstamp: "2026-11-09T08:19:58Z"),
        ], key: "3")
        // A cancellation removes it entirely.
        try seed(store, account, [
            invite("u-2", "2026-11-19T01:30:00Z", "2026-11-19T02:30:00Z", cancelled: true),
        ], key: "4")

        await model.activate()
        #expect(model.occurrences.count == 1)
        #expect(model.occurrences.first?.start == date("2026-11-23T08:00:00Z"))

        // Truncation is reported when the query limit is reached.
        for index in 0..<4 {
            try seed(store, account, [
                invite("x-\(index)", "2026-11-0\(index + 1)T08:00:00Z", "2026-11-0\(index + 1)T09:00:00Z"),
            ], key: "5-\(index)")
        }
        await model.activate()
        let clipped = try CalendarScene(store: store, account: account).events(
            from: date("2026-11-01T00:00:00Z"),
            to: date("2026-11-30T23:59:59Z"),
            limit: 3
        )
        #expect(clipped.occurrences.count == 3)
        #expect(clipped.truncated)
    }
}

@Suite("SCN-0023 meeting card")
struct MeetingCardScenarioTests {
    private func date(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)!
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 28800)!
        return calendar
    }

    private func invite(
        uid: String = "u-1",
        allDay: Bool = false,
        timeZone: MeetingTimeZone? = MeetingTimeZone(name: "China Standard Time", offsetSeconds: 28800),
        rule: RecurrenceRule? = nil
    ) -> MeetingInvite {
        MeetingInvite(
            uid: uid,
            subject: "会议",
            start: date("2026-11-19T01:30:00Z"),
            end: date("2026-11-19T04:00:00Z"),
            isAllDay: allDay,
            location: "C4519",
            organizer: "\"王权英\" <wangqy@hundsun.com>",
            reminderMinutes: 900,
            responseRequested: true,
            busyStatus: 2,
            timeZone: timeZone,
            recurrence: rule
        )
    }

    @Test("T-SCN-0023-01: an invite shows time, location, organizer and recurrence")
    func cardFields() throws {
        let card = try #require(MeetingCardPresentation.make(
            from: invite(rule: RecurrenceRule(frequency: .weekly, weekdays: [.monday])),
            calendar: calendar
        ))
        #expect(card.time == "11月19日 09:30–12:00")
        #expect(card.location == "C4519")
        #expect(card.organizer == "王权英")
        #expect(card.recurrence == "每周周一")
    }

    @Test("T-SCN-0023-02: ordinary mail has no card")
    func noCard() {
        #expect(MeetingCardPresentation.make(from: nil, calendar: calendar) == nil)
        // `Message` no longer carries a meeting, so "not an invite" is simply a nil lookup.
        #expect(MeetingCardPresentation.make(from: .none, calendar: calendar) == nil)
    }

    @Test("T-SCN-0023-03: the exported ics carries the event and its series rule")
    func icsText() {
        let text = invite(rule: RecurrenceRule(frequency: .weekly, weekdays: [.monday]))
            .ics(now: date("2026-11-24T00:00:00Z"))
        #expect(text.contains("BEGIN:VEVENT"))
        #expect(text.contains("DTSTART:20261119T013000Z"))
        #expect(text.contains("DTEND:20261119T040000Z"))
        #expect(text.contains("SUMMARY:会议"))
        #expect(text.contains("LOCATION:C4519"))
        #expect(text.contains("RRULE:FREQ=WEEKLY;BYDAY=MO"))
        #expect(text.contains("UID:u-1"))
    }

    @Test("T-SCN-0023-04: a missing time zone still renders and exports consistently")
    func missingTimeZone() throws {
        let card = try #require(MeetingCardPresentation.make(
            from: invite(timeZone: nil),
            calendar: calendar
        ))
        #expect(card.time == "11月19日 09:30–12:00")
        let text = invite(timeZone: nil).ics(now: date("2026-11-24T00:00:00Z"))
        #expect(text.contains("DTSTART:20261119T013000Z"))
    }
}
