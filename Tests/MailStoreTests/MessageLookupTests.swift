import Foundation
import Testing

@testable import MailStore

@Suite("Message lookups (REQ-0031 / REQ-0033)")
struct MessageLookupTests {
    /// Inbox "13" plus archive "14"; both exist so the same server id can live in two folders.
    private func makeStore() throws -> (MailStore, AccountID) {
        let store = try MailStore.inMemory()
        let id = try store.createAccount(
            NewAccount(displayName: "工作", address: "jdoe@corp.test", host: "mail.corp.test")
        )
        try store.applyFolderSnapshot(account: id, folders: [
            MailFolder(serverID: "13", parentID: "0", displayName: "收件箱", type: 2),
            MailFolder(serverID: "14", parentID: "0", displayName: "归档", type: 3),
        ], syncKey: "1")
        return (store, id)
    }

    private func put(_ store: MailStore, _ id: AccountID, folder: String, _ messages: [MailMessage]) throws {
        try store.applySyncBatch(
            account: id, folder: folder, added: messages, changed: [],
            removedServerIDs: [], syncKey: "2-\(folder)-\(messages.count)"
        )
    }

    private func date(_ raw: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        return try #require(formatter.date(from: raw))
    }

    @Test("message(account:folder:serverID:) hits one row, misses cleanly, and keeps folders apart")
    func singleByRef() throws {
        let (store, id) = try makeStore()
        try put(store, id, folder: "13", [
            MailMessage(serverID: "100", subject: "收件箱里的一封", sender: "a@corp.test",
                        receivedRaw: "2026-11-20T01:00:00Z"),
        ])
        try put(store, id, folder: "14", [
            MailMessage(serverID: "100", subject: "归档里的同名 id", sender: "b@corp.test",
                        receivedRaw: "2026-11-19T01:00:00Z"),
        ])

        let inbox = try #require(try store.message(account: id, folder: "13", serverID: "100"))
        #expect(inbox.subject == "收件箱里的一封")
        #expect(inbox.folderID == "13")

        let archive = try #require(try store.message(account: id, folder: "14", serverID: "100"))
        #expect(archive.subject == "归档里的同名 id")
        #expect(archive.folderID == "14")

        #expect(try store.message(account: id, folder: "13", serverID: "missing") == nil)

        // Soft-deleted rows are invisible to the reader, same as the list.
        try store.applySyncBatch(
            account: id, folder: "13", added: [], changed: [], removedServerIDs: ["100"], syncKey: "3"
        )
        #expect(try store.message(account: id, folder: "13", serverID: "100") == nil)
    }

    @Test("messages(since:) includes the boundary instant, excludes the second before, keeps unparseable rows")
    func windowBoundary() throws {
        let (store, id) = try makeStore()
        try put(store, id, folder: "13", [
            MailMessage(serverID: "1", subject: "正好 30 天", receivedRaw: "2026-10-25T00:00:00Z"),
            MailMessage(serverID: "2", subject: "早一秒", receivedRaw: "2026-10-24T23:59:59Z"),
            MailMessage(serverID: "3", subject: "没有日期", receivedRaw: nil),
            MailMessage(serverID: "4", subject: "畸形日期", receivedRaw: "not-a-date"),
            MailMessage(serverID: "5", subject: "昨天", receivedRaw: "2026-11-20T03:00:00Z"),
        ])

        let since = try date("2026-10-25T00:00:00Z")
        let window = try store.messages(account: id, folder: "13", since: since)
        let ids = Set(window.map(\.serverID))

        #expect(ids.contains("1"))
        #expect(!ids.contains("2"))
        #expect(ids.contains("3"))
        #expect(ids.contains("4"))
        #expect(ids.contains("5"))
    }

    @Test("messages(since:) returns the whole window with no 200-row cap, newest first")
    func noCapAndOrdering() throws {
        let (store, id) = try makeStore()
        var rows: [MailMessage] = []
        for index in 0..<250 {
            // Spread over 20 days inside the window; every row is newer than the boundary.
            let day = 20 - (index % 20)
            rows.append(MailMessage(
                serverID: String(format: "%03d", index),
                subject: "第 \(index) 封",
                receivedRaw: String(format: "2026-11-%02dT05:00:00Z", day)
            ))
        }
        try put(store, id, folder: "13", rows)

        let window = try store.messages(account: id, folder: "13", since: try date("2026-10-25T00:00:00Z"))
        #expect(window.count == 250)

        let received = window.compactMap(\.receivedRaw)
        #expect(received == received.sorted(by: >))
    }

    @Test("messages(since:) keeps the folder boundary and excludes older mail only")
    func windowSeparatesFolders() throws {
        let (store, id) = try makeStore()
        try put(store, id, folder: "13", [
            MailMessage(serverID: "a", receivedRaw: "2026-11-20T00:00:00Z"),
        ])
        try put(store, id, folder: "14", [
            MailMessage(serverID: "b", receivedRaw: "2026-11-18T00:00:00Z"),
        ])

        let window = try store.messages(account: id, folder: "13", since: try date("2026-11-01T00:00:00Z"))
        #expect(window.map(\.serverID) == ["a"])
    }
}
