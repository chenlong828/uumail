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

        let insertStart = Date()
        for chunk in 0..<50 {
            let messages = (0..<100).map { index in
                MailMessage(
                    serverID: "\(chunk)-\(index)",
                    subject: "周报 \(chunk)-\(index)",
                    sender: "sender\(index)@corp.test",
                    receivedRaw: String(format: "2026-10-%02dT05:11:18.000Z", (index % 28) + 1)
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

        #expect(page.count == 200)
        #expect(!hits.isEmpty)
        #expect(insert < 20)
        #expect(list < 1.0)
        #expect(search < 3.0)
    }
}
