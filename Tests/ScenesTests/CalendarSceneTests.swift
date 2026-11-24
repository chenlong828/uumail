import Foundation
import MailDomain
import MailStore
import Testing
import MeetingDomain
import SyncContract

@testable import Scenes

@Suite("CalendarScene")
struct CalendarSceneTests {
    private func date(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)!
    }

    private func seeded() throws -> (store: MailStore, account: AccountID, scene: CalendarScene) {
        let store = try MailStore.inMemory()
        let account = try store.createAccount(
            NewAccount(displayName: "工作", address: "jdoe@corp.test", host: "mail.corp.test")
        )
        try store.applyFolderSnapshot(
            account: account,
            folders: [Folder(serverID: "13", parentID: "0", displayName: "收件箱", type: 2)],
            syncKey: "1"
        )
        return (store, account, CalendarScene(store: store, account: account))
    }

    private func invite(
        uid: String = "u-1",
        start: String,
        end: String,
        rule: RecurrenceRule? = nil,
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
            dtstamp: date("2026-11-13T09:54:53Z"),
            timeZone: MeetingTimeZone(name: "China Standard Time", offsetSeconds: 28800),
            recurrence: rule
        )
    }

    private func sync(_ store: MailStore, _ account: AccountID, _ invites: [MeetingInvite], key: String) throws {
        try store.applySyncBatch(
            account: account,
            folder: "13",
            added: invites.enumerated().map { index, invite in
                Message(
                    serverID: "m-\(key)-\(index)",
                    subject: invite.subject,
                    receivedRaw: "2026-11-13T09:54:55Z"
                )
            },
            changed: [],
            removedServerIDs: [],
            syncKey: key,
            meetings: invites.enumerated().map { index, invite in
                MeetingDeltaEntry(serverID: "m-\(key)-\(index)", subject: invite.subject, invite: invite)
            }
        )
    }

    @Test("events only include occurrences inside the range, sorted by start")
    func rangeAndSort() throws {
        let (store, account, scene) = try seeded()
        try sync(store, account, [
            invite(uid: "a", start: "2026-11-19T01:30:00Z", end: "2026-11-19T04:00:00Z"),
            invite(uid: "b", start: "2026-11-23T08:00:00Z", end: "2026-11-23T09:00:00Z"),
            invite(uid: "c", start: "2026-12-02T08:00:00Z", end: "2026-12-02T09:00:00Z"),
        ], key: "2")

        let result = try scene.events(
            from: date("2026-11-01T00:00:00Z"),
            to: date("2026-11-30T23:59:59Z")
        )
        #expect(result.occurrences.map(\.uid) == ["a", "b"])
        #expect(result.truncated == false)
        #expect(result.occurrences.first?.folderID == "13")
        #expect(result.occurrences.first?.serverID == "m-2-0")
        #expect(result.occurrences.first?.subject == "会议 a")
    }

    @Test("a recurring series expands and is clipped by the query limit")
    func recurrenceAndLimit() throws {
        let (store, account, scene) = try seeded()
        try sync(store, account, [
            invite(
                uid: "weekly",
                start: "2026-11-02T01:00:00Z",
                end: "2026-11-02T02:00:00Z",
                rule: RecurrenceRule(frequency: .weekly, weekdays: [.monday])
            ),
        ], key: "2")

        let fourWeeks = try scene.events(
            from: date("2026-11-01T00:00:00Z"),
            to: date("2026-11-30T23:59:59Z")
        )
        #expect(fourWeeks.occurrences.count == 5)  // Nov 2, 9, 16, 23, 30

        let clipped = try scene.events(
            from: date("2026-11-01T00:00:00Z"),
            to: date("2026-11-30T23:59:59Z"),
            limit: 2
        )
        #expect(clipped.occurrences.count == 2)
        #expect(clipped.truncated)
    }

    @Test("cancelled meetings are invisible")
    func cancellationHidden() throws {
        let (store, account, scene) = try seeded()
        try sync(store, account, [
            invite(uid: "cancel", start: "2026-11-19T01:30:00Z", end: "2026-11-19T04:00:00Z", cancelled: true),
        ], key: "2")
        #expect(try scene.events(
            from: date("2026-11-01T00:00:00Z"),
            to: date("2026-11-30T23:59:59Z")
        ).occurrences.isEmpty)
    }

    @Test("ics returns the stored series and reports a missing meeting")
    func icsExport() throws {
        let (store, account, scene) = try seeded()
        try sync(store, account, [
            invite(uid: "u-9", start: "2026-11-19T01:30:00Z", end: "2026-11-19T04:00:00Z"),
        ], key: "2")

        let text = try scene.ics(uid: "u-9", now: date("2026-11-24T00:00:00Z"))
        #expect(text.contains("BEGIN:VEVENT"))
        #expect(text.contains("UID:u-9"))
        #expect(try scene.meeting(uid: "u-9")?.location == "C4519")

        #expect(throws: CalendarSceneError.meetingNotFound(uid: "missing")) {
            _ = try scene.ics(uid: "missing")
        }
    }

    @Test("an inverted range is rejected")
    func invalidRange() throws {
        let (_, _, scene) = try seeded()
        #expect(throws: CalendarSceneError.invalidRange) {
            _ = try scene.events(
                from: date("2026-11-30T00:00:00Z"),
                to: date("2026-11-01T00:00:00Z")
            )
        }
    }
}
