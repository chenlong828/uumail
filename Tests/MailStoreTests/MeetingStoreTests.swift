import Foundation
import MailDomain
import Testing
import MeetingDomain
import SyncContract

@testable import MailStore

@Suite("Meeting storage (v12)")
struct MeetingStoreTests {
    private func date(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)!
    }

    private func seeded() throws -> (store: MailStore, account: AccountID) {
        let store = try MailStore.inMemory()
        let account = try store.createAccount(
            NewAccount(displayName: "工作", address: "jdoe@corp.test", host: "mail.corp.test")
        )
        try store.applyFolderSnapshot(
            account: account,
            folders: [Folder(serverID: "13", parentID: "0", displayName: "收件箱", type: 2)],
            syncKey: "1"
        )
        return (store, account)
    }

    private func invite(
        uid: String = "u-1",
        start: String = "2026-11-19T01:30:00Z",
        end: String = "2026-11-19T04:00:00Z",
        dtstamp: String = "2026-11-13T09:54:53Z",
        cancelled: Bool = false,
        rule: RecurrenceRule? = nil,
        exceptionID: Date? = nil
    ) -> MeetingInvite {
        MeetingInvite(
            uid: uid,
            subject: "会议",
            start: date(start),
            end: date(end),
            location: "C4519",
            organizer: "wangqy@hundsun.com",
            reminderMinutes: 900,
            responseRequested: true,
            busyStatus: 2,
            messageType: .initial,
            isCancelled: cancelled,
            dtstamp: date(dtstamp),
            timeZone: MeetingTimeZone(name: "China Standard Time", offsetSeconds: 28800),
            recurrence: rule,
            exceptionRecurrenceID: exceptionID
        )
    }

    /// Seeds one message plus its meeting through the sync batch, the only write path.
    private func seed(
        _ store: MailStore,
        _ account: AccountID,
        key: String,
        serverID: String = "m-1",
        subject: String = "会议邀请",
        invite: MeetingInvite
    ) throws {
        try store.applySyncBatch(
            account: account, folder: "13",
            added: [Message(serverID: serverID, subject: subject, receivedRaw: "2026-11-13T09:54:55Z")],
            changed: [], removedServerIDs: [], syncKey: key,
            meetings: [MeetingDeltaEntry(serverID: serverID, subject: subject, invite: invite)]
        )
    }

    @Test("a synced meeting is stored once per UID and read back with its source")
    func upsertAndRead() throws {
        let (store, account) = try seeded()
        try seed(store, account, key: "2", invite: invite())

        let entries = try store.meetings(
            account: account,
            from: date("2026-11-01T00:00:00Z"),
            to: date("2026-11-30T00:00:00Z")
        )
        #expect(entries.count == 1)
        #expect(entries.first?.folderID == "13")
        #expect(entries.first?.serverID == "m-1")
        #expect(entries.first?.invite.uid == "u-1")
        #expect(entries.first?.invite.location == "C4519")
        #expect(entries.first?.invite.timeZone?.offsetSeconds == 28800)

        let invite = try #require(try store.meetingInvite(account: account, uid: "u-1"))
        #expect(invite.start == date("2026-11-19T01:30:00Z"))
    }

    @Test("the reading pane resolves the meeting by message key instead of decorating rows")
    func meetingByMessageKey() throws {
        let (store, account) = try seeded()
        try seed(store, account, key: "2", invite: invite())

        let page = try store.messages(account: account, folder: "13")
        #expect(page.count == 1, "the list page no longer carries meeting values")

        #expect(try store.meeting(account: account, folder: "13", serverID: "m-1")?.uid == "u-1")
        #expect(try store.meeting(account: account, folder: "13", serverID: "m-9") == nil)
    }

    @Test("a newer DtStamp replaces the row, an older one does not")
    func dtstampMonotonic() throws {
        let (store, account) = try seeded()
        try seed(store, account, key: "2", invite: invite(start: "2026-11-23T08:00:00Z", end: "2026-11-23T09:00:00Z", dtstamp: "2026-11-16T08:16:17Z"))
        // A late-arriving older invite must not roll the time back.
        try seed(store, account, key: "3", serverID: "m-0", invite: invite(start: "2026-11-16T08:00:00Z", end: "2026-11-16T09:00:00Z", dtstamp: "2026-11-09T08:19:58Z"))
        let invite = try #require(try store.meetingInvite(account: account, uid: "u-1"))
        #expect(invite.start == date("2026-11-23T08:00:00Z"))
        #expect(try store.meetings(
            account: account,
            from: date("2026-11-01T00:00:00Z"),
            to: date("2026-11-30T00:00:00Z")
        ).count == 1)
    }

    @Test("a cancellation deletes the meeting but keeps the mail")
    func cancellationDeletesRow() throws {
        let (store, account) = try seeded()
        try seed(store, account, key: "2", invite: invite())
        try seed(store, account, key: "3", serverID: "m-2", invite: invite(dtstamp: "2026-11-20T00:00:00Z", cancelled: true))
        #expect(try store.meetingInvite(account: account, uid: "u-1") == nil)
        #expect(try store.messages(account: account, folder: "13").count == 2)
    }

    @Test("an exception merges into the series instead of replacing it")
    func exceptionMerges() throws {
        let (store, account) = try seeded()
        let rule = RecurrenceRule(frequency: .weekly, weekdays: [.monday], firstDayOfWeek: .monday)
        try seed(store, account, key: "2", invite: invite(rule: rule))
        try seed(store, account, key: "3", serverID: "m-2", invite: invite(
            start: "2026-11-26T02:00:00Z",
            end: "2026-11-26T03:00:00Z",
            dtstamp: "2026-11-20T00:00:00Z",
            exceptionID: date("2026-11-26T01:30:00Z")
        ))
        let stored = try #require(try store.meetingInvite(account: account, uid: "u-1"))
        #expect(stored.recurrence != nil)
        #expect(stored.exceptions.count == 1)
        #expect(stored.exceptions.first?.start == date("2026-11-26T02:00:00Z"))
    }

    @Test("removing the source message removes its meeting row")
    func removedMessageDeletesMeeting() throws {
        let (store, account) = try seeded()
        try seed(store, account, key: "2", invite: invite())
        try store.applySyncBatch(
            account: account, folder: "13",
            added: [], changed: [], removedServerIDs: ["m-1"], syncKey: "3"
        )
        #expect(try store.meetingInvite(account: account, uid: "u-1") == nil)
    }
}
