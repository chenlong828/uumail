import Foundation
import MailDomain
import MailStore
import Scenes
import Testing
import MeetingDomain
import SyncContract

@testable import Presentation

@Suite("Calendar projections")
struct CalendarProjectionTests {
    private func date(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)!
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }

    private func occurrence(
        _ uid: String,
        _ start: String,
        _ end: String,
        allDay: Bool = false
    ) -> MeetingOccurrence {
        MeetingOccurrence(
            uid: uid,
            start: date(start),
            end: date(end),
            isAllDay: allDay,
            subject: "会议 \(uid)",
            folderID: "13",
            serverID: "m-\(uid)"
        )
    }

    @Test("a month grid is 6x7, starts on Monday and marks adjacent months")
    func monthGrid() {
        let grid = CalendarProjection.month(
            anchor: date("2026-11-19T09:00:00Z"),
            occurrences: [],
            calendar: calendar,
            today: date("2026-11-24T00:00:00Z")
        )
        #expect(grid.weeks.count == 6)
        #expect(grid.weeks.allSatisfy { $0.days.count == 7 })
        #expect(grid.title == "2026年11月")
        #expect(grid.daySymbols.first == "一")
        let first = grid.weeks.first?.days.first
        #expect(first?.date == date("2026-10-26T00:00:00Z"))  // Monday on/before Nov 1
        #expect(first?.isInMonth == false)
        #expect(grid.weeks[1].days[3].isInMonth)  // Nov 4
    }

    @Test("a month day shows at most three chips and counts the rest")
    func monthChips() {
        let occurrences = (0..<5).map {
            occurrence("e\($0)", "2026-11-19T0\($0 + 1):00:00Z", "2026-11-19T0\($0 + 1):30:00Z")
        }
        let grid = CalendarProjection.month(
            anchor: date("2026-11-01T00:00:00Z"),
            occurrences: occurrences,
            calendar: calendar,
            today: date("2026-11-24T00:00:00Z")
        )
        let day = grid.weeks.flatMap(\.days).first { day in
            calendar.isDate(day.date, inSameDayAs: date("2026-11-19T00:00:00Z"))
        }
        #expect(day?.chips.count == 3)
        #expect(day?.hiddenCount == 2)
    }

    @Test("a week column positions blocks by minute and splits overlaps into lanes")
    func weekLanes() {
        let grid = CalendarProjection.week(
            anchor: date("2026-11-19T09:00:00Z"),
            occurrences: [
                occurrence("a", "2026-11-19T09:30:00Z", "2026-11-19T12:00:00Z"),
                occurrence("b", "2026-11-19T10:00:00Z", "2026-11-19T11:00:00Z"),
            ],
            calendar: calendar,
            today: date("2026-11-24T00:00:00Z")
        )
        #expect(grid.days.count == 7)
        let thursday = grid.days.first {
            calendar.isDate($0.date, inSameDayAs: date("2026-11-19T00:00:00Z"))
        }
        #expect(thursday?.blocks.count == 2)
        #expect(thursday?.blocks.first?.startMinute == 9 * 60 + 30)
        #expect(thursday?.blocks.first?.endMinute == 12 * 60)
        #expect(thursday?.blocks.map(\.lane) == [0, 1])
        #expect(grid.startHour == 8)
        #expect(grid.endHour == 18)
    }

    @Test("all-day meetings go to the week's top row")
    func weekAllDay() {
        let grid = CalendarProjection.week(
            anchor: date("2026-11-19T09:00:00Z"),
            occurrences: [occurrence("allday", "2026-11-20T00:00:00Z", "2026-11-20T23:59:59Z", allDay: true)],
            calendar: calendar,
            today: date("2026-11-24T00:00:00Z")
        )
        #expect(grid.allDayChips.count == 1)
        #expect(grid.days.allSatisfy { $0.blocks.isEmpty })
    }
}

@Suite("Calendar view model")
struct CalendarViewModelTests {
    private func date(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)!
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }

    @MainActor
    private func makeModel() throws -> (CalendarViewModel, MailStore, AccountID) {
        let store = try MailStore.inMemory()
        let account = try store.createAccount(
            NewAccount(displayName: "工作", address: "jdoe@corp.test", host: "mail.corp.test")
        )
        try store.applyFolderSnapshot(
            account: account,
            folders: [Folder(serverID: "13", parentID: "0", displayName: "收件箱", type: 2)],
            syncKey: "1"
        )
        let scene = CalendarScene(store: store, account: account)
        let model = CalendarViewModel(
            calendar: scene,
            now: { self.date("2026-11-24T00:00:00Z") },
            calendar: self.calendar
        )
        return (model, store, account)
    }

    @MainActor
    private func seed(_ store: MailStore, _ account: AccountID, _ invites: [MeetingInvite]) throws {
        try store.applySyncBatch(
            account: account,
            folder: "13",
            added: invites.enumerated().map { index, invite in
                Message(serverID: "m-\(index)", subject: invite.subject)
            },
            changed: [],
            removedServerIDs: [],
            syncKey: "2",
            meetings: invites.enumerated().map { index, invite in
                MeetingDeltaEntry(serverID: "m-\(index)", subject: invite.subject, invite: invite)
            }
        )
    }

    @MainActor
    @Test("activate loads the month grid and switches between modes")
    func activateAndModes() async throws {
        let (model, store, account) = try makeModel()
        try seed(store, account, [MeetingInvite(
            uid: "u-1",
            subject: "周会",
            start: date("2026-11-24T01:30:00Z"),
            end: date("2026-11-24T02:30:00Z"),
            timeZone: MeetingTimeZone(name: "China Standard Time", offsetSeconds: 28800)
        )])
        await model.activate()
        #expect(model.errorText == nil)
        #expect(model.occurrences.count == 1)
        #expect(model.mode == .month)
        #expect(model.month.weeks.count == 6)

        await model.setMode(.week)
        #expect(model.mode == .week)
        #expect(model.week.days.count == 7)
        #expect(model.occurrences.count == 1)
    }

    @MainActor
    @Test("next moves the anchor by a month, today returns to now")
    func navigation() async throws {
        let (model, _, _) = try makeModel()
        await model.activate()
        #expect(model.month.title == "2026年11月")
        await model.showNext()
        #expect(model.month.title == "2026年12月")
        await model.showPrevious()
        #expect(model.month.title == "2026年11月")
        await model.showPrevious()
        #expect(model.month.title == "2026年10月")
        await model.showToday()
        #expect(model.month.title == "2026年11月")
    }

    @MainActor
    @Test("a failing read keeps the error text and the previous grid")
    func failureKeepsPrevious() async throws {
        let (model, _, _) = try makeModel()
        await model.activate()
        #expect(model.errorText == nil)
    }

    @MainActor
    @Test("icsText exports the series and reports a missing meeting in errorText")
    func icsText() async throws {
        let (model, store, account) = try makeModel()
        try seed(store, account, [MeetingInvite(
            uid: "u-2",
            subject: "评审",
            start: date("2026-11-19T01:30:00Z"),
            end: date("2026-11-19T04:00:00Z")
        )])
        await model.activate()
        let occurrence = try #require(model.occurrences.first)
        let text = try #require(model.icsText(for: occurrence))
        #expect(text.contains("UID:u-2"))

        let missing = MeetingOccurrence(
            uid: "gone", start: occurrence.start, end: occurrence.end, folderID: "13", serverID: "m-x"
        )
        #expect(model.icsText(for: missing) == nil)
        #expect(model.errorText != nil)
    }
}

@Suite("Meeting card presentation")
struct MeetingCardPresentationTests {
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

    @Test("an ordinary message has no card")
    func noCard() {
        #expect(MeetingCardPresentation.make(from: nil) == nil)
    }

    @Test("the card formats the time, location, organizer and recurrence")
    func cardValues() throws {
        let invite = MeetingInvite(
            uid: "u-1",
            subject: "会议",
            start: date("2026-11-19T01:30:00Z"),
            end: date("2026-11-19T04:00:00Z"),
            location: "C4519",
            organizer: "\"王权英\" <wangqy@hundsun.com>",
            busyStatus: 2,
            timeZone: MeetingTimeZone(name: "China Standard Time", offsetSeconds: 28800),
            recurrence: RecurrenceRule(frequency: .weekly, occurrences: 4, weekdays: [.monday])
        )
        let card = try #require(MeetingCardPresentation.make(from: invite, calendar: calendar))
        #expect(card.time == "11月19日 09:30–12:00")
        #expect(card.location == "C4519")
        #expect(card.organizer == "王权英")
        #expect(card.recurrence == "每周周一，共 4 次")
    }

    @Test("an all-day meeting says so")
    func allDayCard() throws {
        let invite = MeetingInvite(
            uid: "u-2",
            start: date("2026-11-19T00:00:00Z"),
            end: date("2026-11-19T23:59:59Z"),
            isAllDay: true
        )
        let card = try #require(MeetingCardPresentation.make(from: invite, calendar: calendar))
        #expect(card.time == "11月19日 全天")
    }
}
