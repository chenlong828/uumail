import Foundation
import MailDomain
import MailStore
import SyncEngine
import Testing

@testable import Scenes

@Suite("ReadScene lookups (REQ-0031 / REQ-0033)")
struct ReadSceneLookupTests {
    private func makeScene(store: MailStore, account: AccountID, gateway: FakeGateway) -> ReadScene {
        let engine = SyncEngine(
            gateway: gateway, store: store, account: account,
            writeGateway: UnsupportedWriteGateway(), sleeper: { _ in }
        )
        return ReadScene(store: store, account: account, gateway: gateway,
                         files: FakeAttachmentFiles(), writeEngine: engine)
    }

    private func put(_ store: MailStore, _ account: AccountID, _ messages: [Message]) throws {
        try store.applySyncBatch(
            account: account, folder: "13", added: messages, changed: [],
            removedServerIDs: [], syncKey: "2-\(messages.count)"
        )
    }

    private func date(_ raw: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: raw))
    }

    @Test("message(_:) resolves one message without touching the gateway")
    func messageByRef() async throws {
        let (store, account) = try seededReadStore()
        try put(store, account, [
            Message(serverID: "m1", subject: "第一封", receivedRaw: "2026-11-20T01:00:00Z"),
            Message(serverID: "m2", subject: "第二封", receivedRaw: "2026-11-19T01:00:00Z"),
        ])
        let gateway = FakeGateway()
        let scene = makeScene(store: store, account: account, gateway: gateway)

        let found = try #require(try scene.message(MessageRef(folderID: "13", serverID: "m2")))
        #expect(found.subject == "第二封")
        #expect(found.folderID == "13")
        #expect(try scene.message(MessageRef(folderID: "13", serverID: "m9")) == nil)
        #expect(await gateway.calls.isEmpty, "a local lookup must not reach the gateway")
    }

    @Test("messages(folderID:since:) passes the window through and returns newest first")
    func windowedList() async throws {
        let (store, account) = try seededReadStore()
        try put(store, account, [
            Message(serverID: "old", receivedRaw: "2026-10-01T00:00:00Z"),
            Message(serverID: "new", receivedRaw: "2026-11-20T00:00:00Z"),
            Message(serverID: "mid", receivedRaw: "2026-11-10T00:00:00Z"),
        ])
        let gateway = FakeGateway()
        let scene = makeScene(store: store, account: account, gateway: gateway)

        let window = try scene.messages(folderID: "13", since: try date("2026-11-01T00:00:00Z"))
        #expect(window.map(\.serverID) == ["new", "mid"])
        #expect(await gateway.calls.isEmpty)
    }

    @Test("the windowed list keeps an unparseable timestamp instead of hiding the mail")
    func unparseableKept() async throws {
        let (store, account) = try seededReadStore()
        try put(store, account, [
            Message(serverID: "weird", subject: "日期坏了", receivedRaw: "not-a-date"),
            Message(serverID: "fresh", receivedRaw: "2026-11-20T00:00:00Z"),
        ])
        let scene = makeScene(store: store, account: account, gateway: FakeGateway())

        let window = try scene.messages(folderID: "13", since: try date("2026-11-01T00:00:00Z"))
        #expect(Set(window.map(\.serverID)) == ["weird", "fresh"])
    }

    @Test("the existing limit page still works and the new methods do not change its shape")
    func existingPageUnchanged() throws {
        let (store, account) = try seededReadStore()
        try put(store, account, (0..<5).map {
            Message(serverID: "p\($0)", receivedRaw: String(format: "2026-11-%02dT00:00:00Z", $0 + 1))
        })
        let scene = makeScene(store: store, account: account, gateway: FakeGateway())
        #expect(try scene.messages(folderID: "13", limit: 3).count == 3)
    }
}
