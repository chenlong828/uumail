import Foundation
import Testing

@testable import MailStore

@Suite("MailStore baseline")
struct PerformanceTests {
    @Test("5k messages: batch insert, list and search stay inside the budget")
    func baseline() throws {
        let store = try MailStore.inMemory()
        let id = try store.createAccount(NewAccount(displayName: "工作", address: "jdoe@corp.test", host: "mail.corp.test"))
        try store.applyFolderSnapshot(account: id, folders: [
            MailFolder(serverID: "13", parentID: "0", displayName: "收件箱", type: 2),
        ], syncKey: "1")

        // Relative dates keep the 30-day window assertion stable as the wall clock moves;
        // fixed October dates used to fall out of the window after 2026-11-26.
        let formatter = ISO8601DateFormatter()
        let seedNow = Date()
        let insertStart = Date()
        for chunk in 0..<50 {
            let messages = (0..<100).map { index -> MailMessage in
                let raw = formatter.string(
                    from: seedNow.addingTimeInterval(-Double(index % 28) * 86_400)
                )
                return MailMessage(
                    serverID: "\(chunk)-\(index)",
                    subject: "周报 \(chunk)-\(index)",
                    sender: "sender\(index)@corp.test",
                    receivedRaw: raw
                )
            }
            try store.applySyncBatch(
                account: id, folder: "13", added: messages, changed: [],
                removedServerIDs: [], syncKey: "\(chunk + 2)"
            )
        }
        let insert = Date().timeIntervalSince(insertStart)

        let listStart = Date()
        let page = try store.messages(account: id, folder: "13", limit: 200)
        let list = Date().timeIntervalSince(listStart)

        let searchStart = Date()
        let hits = try store.searchLocal(account: id, query: "周报", limit: 50)
        let search = Date().timeIntervalSince(searchStart)

        print(String(format: "BASELINE insert5000=%.2fs list200=%.3fs search=%.3fs hits=%d page=%d",
                     insert, list, search, hits.count, page.count))

        // REQ-0033: the list window is a time range, not a page. Same 5k fixture, one
        // query with no row cap, measured against the same 1s budget.
        let windowStart = Date().addingTimeInterval(-30 * 86_400)
        let windowClock = Date()
        let windowRows = try store.messages(account: id, folder: "13", since: windowStart)
        let windowSeconds = Date().timeIntervalSince(windowClock)
        print(String(format: "BASELINE window30d=%.3fs rows=%d", windowSeconds, windowRows.count))
        #expect(windowRows.count > 200, "the window query is not a page")
        #expect(windowSeconds < 1.0)

        #expect(page.count == 200)
        #expect(!hits.isEmpty)
        #expect(insert < 20)
        #expect(list < 1.0)
        #expect(search < 3.0)
    }
}

extension PerformanceTests {
    @Test("5k messages inside the window: the uncapped list query stays under 1s")
    func windowBaseline() throws {
        let store = try MailStore.inMemory()
        let id = try store.createAccount(
            NewAccount(displayName: "工作", address: "jdoe@corp.test", host: "mail.corp.test")
        )
        try store.applyFolderSnapshot(account: id, folders: [
            MailFolder(serverID: "13", parentID: "0", displayName: "收件箱", type: 2),
        ], syncKey: "1")

        let formatter = ISO8601DateFormatter()
        let now = Date()
        for chunk in 0..<50 {
            let messages = (0..<100).map { index -> MailMessage in
                let age = Double((chunk * 100 + index) % 20)
                let raw = formatter.string(from: now.addingTimeInterval((-age - 1) * 86_400))
                return MailMessage(serverID: "\(chunk)-\(index)", subject: "窗口内 \(index)",
                                   receivedRaw: raw)
            }
            try store.applySyncBatch(
                account: id, folder: "13", added: messages, changed: [],
                removedServerIDs: [], syncKey: "\(chunk + 2)"
            )
        }

        let start = Date()
        let rows = try store.messages(account: id, folder: "13", since: now.addingTimeInterval(-30 * 86_400))
        let seconds = Date().timeIntervalSince(start)
        print(String(format: "BASELINE window30d-in-window=%.3fs rows=%d", seconds, rows.count))

        #expect(rows.count == 5_000)
        #expect(seconds < 1.0)
    }
}
