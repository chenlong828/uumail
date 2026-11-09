import Foundation
import MailStore
import SyncEngine
import Testing

@testable import AppServices

final class FakeService: MailServiceProtocol, @unchecked Sendable {
    nonisolated(unsafe) var folderList: [StoredFolder]
    nonisolated(unsafe) var messageList: [StoredMessage]
    nonisolated(unsafe) var syncError: Error?
    nonisolated(unsafe) private(set) var syncCalls = 0

    init(folderList: [StoredFolder] = [], messageList: [StoredMessage] = [], syncError: Error? = nil) {
        self.folderList = folderList
        self.messageList = messageList
        self.syncError = syncError
    }

    func syncOnce() async throws -> SyncReport {
        syncCalls += 1
        if let syncError { throw syncError }
        return SyncReport(folders: folderList.count, added: messageList.count, changed: 0, removed: 0, rounds: 1, syncKey: "1")
    }

    func folders() throws -> [StoredFolder] { folderList }

    func messages(folderID: String, limit: Int) throws -> [StoredMessage] {
        messageList
    }
}

@Suite("MailboxModel")
@MainActor
struct MailboxModelTests {
    @Test("refresh loads folders and picks the inbox")
    func refreshPicksInbox() async {
        let service = FakeService(
            folderList: [
                StoredFolder(serverID: "4", parentID: "0", displayName: "草稿", type: 3),
                StoredFolder(serverID: "13", parentID: "0", displayName: "收件箱", type: 2),
            ],
            messageList: [
                StoredMessage(serverID: "1", subject: "周报", sender: "a@b.c", receivedRaw: "2026-11-08T05:11:18.000Z", isRead: false, bodyPreview: nil)
            ]
        )
        let model = MailboxModel(service: service)
        await model.refresh()

        #expect(model.state == .idle)
        #expect(model.selectedFolderID == "13")
        #expect(model.messages.count == 1)
        #expect(model.messages.first?.subject == "周报")
        #expect(model.lastSyncedAt != nil)
    }

    @Test("a failed sync keeps the cached list and reports the error")
    func failureKeepsCache() async {
        let service = FakeService(
            folderList: [StoredFolder(serverID: "13", parentID: "0", displayName: "收件箱", type: 2)],
            messageList: [StoredMessage(serverID: "1", subject: "旧信", sender: "a@b.c", receivedRaw: nil, isRead: true, bodyPreview: nil)],
            syncError: MailGatewayError.deviceNotRegistered
        )
        let model = MailboxModel(service: service)
        await model.refresh()

        #expect(model.messages.count == 1)
        guard case .failed(let message) = model.state else {
            Issue.record("expected failed state")
            return
        }
        #expect(message.contains("deviceNotRegistered"))
    }

    @Test("selecting a folder reloads only that folder's messages")
    func folderSelection() async {
        let service = FakeService(
            folderList: [
                StoredFolder(serverID: "13", parentID: "0", displayName: "收件箱", type: 2),
                StoredFolder(serverID: "4", parentID: "0", displayName: "草稿", type: 3),
            ],
            messageList: []
        )
        let model = MailboxModel(service: service)
        model.loadCached()
        #expect(model.selectedFolderID == "13")
        model.selectedFolderID = "4"
        #expect(model.messages.isEmpty)
    }
}
