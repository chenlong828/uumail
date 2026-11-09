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

    nonisolated(unsafe) var cachedBody: String?
    nonisolated(unsafe) var fetchBodyResult: Result<String, Error> = .success("<html><body>hi</body></html>")
    nonisolated(unsafe) private(set) var fetchBodyCalls = 0

    func body(folderID: String, serverID: String) throws -> String? {
        cachedBody
    }

    func fetchBody(folderID: String, serverID: String) async throws -> String {
        fetchBodyCalls += 1
        return try fetchBodyResult.get()
    }

    nonisolated(unsafe) var attachmentList: [StoredAttachment] = []

    func attachments(folderID: String, messageID: String) throws -> [StoredAttachment] {
        attachmentList
    }

    func downloadAttachment(folderID: String, messageID: String, attachment: StoredAttachment) async throws -> URL {
        URL(fileURLWithPath: "/tmp/\(attachment.displayName)")
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

@Suite("MailboxModel body loading")
@MainActor
struct MailboxModelBodyTests {
    private func model(_ service: FakeService) -> MailboxModel {
        let model = MailboxModel(service: service)
        model.loadCached()
        model.selectedMessageID = "1"
        return model
    }

    @Test("a cached body is shown without a network call")
    func cachedBody() async {
        let service = FakeService(
            folderList: [StoredFolder(serverID: "13", parentID: "0", displayName: "收件箱", type: 2)],
            messageList: [StoredMessage(serverID: "1", subject: "A", sender: "a@b.c", receivedRaw: nil, isRead: true, bodyPreview: nil)]
        )
        service.cachedBody = "<html>cached</html>"
        let model = model(service)
        await model.loadBody()

        #expect(model.detailState == .loaded("<html>cached</html>"))
        #expect(service.fetchBodyCalls == 0)
    }

    @Test("a missing body is fetched and becomes the detail state")
    func fetchedBody() async {
        let service = FakeService(
            folderList: [StoredFolder(serverID: "13", parentID: "0", displayName: "收件箱", type: 2)],
            messageList: [StoredMessage(serverID: "1", subject: "A", sender: "a@b.c", receivedRaw: nil, isRead: true, bodyPreview: nil)]
        )
        service.fetchBodyResult = .success("<html>fetched</html>")
        let model = model(service)
        await model.loadBody()

        #expect(model.detailState == .loaded("<html>fetched</html>"))
        #expect(service.fetchBodyCalls == 1)
    }

    @Test("a failed fetch is reported instead of showing an empty body")
    func failedBody() async {
        let service = FakeService(
            folderList: [StoredFolder(serverID: "13", parentID: "0", displayName: "收件箱", type: 2)],
            messageList: [StoredMessage(serverID: "1", subject: "A", sender: "a@b.c", receivedRaw: nil, isRead: true, bodyPreview: nil)]
        )
        service.fetchBodyResult = .failure(MailGatewayError.offline)
        let model = model(service)
        await model.loadBody()

        guard case .failed(let message) = model.detailState else {
            Issue.record("expected failed detail state")
            return
        }
        #expect(message.contains("offline"))
    }
}
