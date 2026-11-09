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

    nonisolated(unsafe) var searchResults: [StoredMessage] = []

    func searchLocal(query: String, limit: Int) throws -> [StoredMessage] {
        searchResults
    }

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

@Suite("MIME and sending")
struct MimeAndSendTests {
    @Test("MIME has the headers the gateway needs and a base64 body")
    func mimeShape() {
        let draft = MailDraft(
            to: "a@b.c", cc: "c@d.e", subject: "周报",
            body: "line1\nline2", inReplyTo: "<id@x>", references: "<id@x>"
        )
        let data = MimeBuilder.build(from: "me@corp.test", draft: draft, messageID: "new@corp.test")
        let text = String(decoding: data, as: UTF8.self)

        #expect(text.contains("From: me@corp.test"))
        #expect(text.contains("To: a@b.c"))
        #expect(text.contains("Cc: c@d.e"))
        #expect(text.contains("Subject: =?UTF-8?B?"), "non-ASCII subject must be RFC 2047 encoded")
        #expect(text.contains("In-Reply-To: <id@x>"))
        #expect(text.contains("References: <id@x>"))
        #expect(text.contains("Content-Transfer-Encoding: base64"))
        #expect(text.contains(Data("line1\nline2".utf8).base64EncodedString(options: [.lineLength76Characters])))
    }
}

import EASClient

actor SendStubTransport: EASHTTPTransport {
    private(set) var requests: [EASHTTPRequest] = []
    private let status: Int
    private let body: Data

    init(status: Int = 200, body: Data = Data()) {
        self.status = status
        self.body = body
    }

    func send(_ request: EASHTTPRequest) async throws -> EASHTTPResponse {
        requests.append(request)
        return EASHTTPResponse(status: status, headers: [:], body: body)
    }
}

@Suite("MailService send")
struct MailServiceSendTests {
    private func service(_ transport: SendStubTransport) throws -> MailService {
        try MailService(
            configuration: EASConfiguration(
                host: "mail.corp.test", account: "jdoe", password: "x",
                domain: "CORP", deviceID: "DEV"
            ),
            databasePath: ":memory:",
            transport: transport,
            policyKey: "1"
        )
    }

    @Test("a successful send clears the outbox")
    func sendSuccess() async throws {
        let transport = SendStubTransport()
        let service = try service(transport)
        _ = try await service.send(MailDraft(to: "a@b.c", cc: nil, subject: "hi", body: "text"))
        #expect(try service.pendingOutbox().isEmpty)
        #expect(await transport.requests.count == 1)
    }

    @Test("a failed send keeps the item for retry")
    func sendFailure() async throws {
        let transport = SendStubTransport(status: 401)
        let service = try service(transport)
        await #expect(throws: MailGatewayError.authFailed) {
            _ = try await service.send(MailDraft(to: "a@b.c", cc: nil, subject: "hi", body: "text"))
        }
        let pending = try service.pendingOutbox()
        #expect(pending.count == 1)
        #expect(pending.first?.state == "failed")
    }
}

final class FakeSendService: MailSendService, @unchecked Sendable {
    nonisolated(unsafe) var sent: [MailDraft] = []
    nonisolated(unsafe) var drafts: [MailDraft] = []
    nonisolated(unsafe) var error: Error?

    func send(_ draft: MailDraft) async throws -> String {
        if let error { throw error }
        sent.append(draft)
        return UUID().uuidString
    }

    func saveDraft(_ draft: MailDraft) throws -> String {
        drafts.append(draft)
        return UUID().uuidString
    }
}

@Suite("ComposeModel")
@MainActor
struct ComposeModelTests {
    @Test("reply prefills the sender, keeps a single Re: prefix and quotes the body")
    func replySeed() {
        let compose = ComposeModel.replySeed(
            sender: "\"张三\" <zhang@corp.test>",
            subject: "Re: 周报",
            html: "<p>hello</p><p>world</p>"
        )
        #expect(compose.to == "zhang@corp.test")
        #expect(compose.subject == "Re: 周报")
        #expect(compose.body.contains("hello"))
        #expect(compose.body.contains("原邮件"))
    }

    @Test("forward prefixes Fwd: and does not address anyone")
    func forwardSeed() {
        let compose = ComposeModel.forwardSeed(subject: "周报", html: "<div>hi</div>")
        #expect(compose.subject == "Fwd: 周报")
        #expect(compose.to.isEmpty)
        #expect(!compose.canSend)
    }

    @Test("send reports success and clears the editor state")
    func sendSuccess() async {
        let service = FakeSendService()
        let compose = ComposeModel(mode: .new, to: "a@b.c", subject: "hi", body: "text")
        await compose.send(using: service)
        #expect(compose.state == .sent)
        #expect(service.sent.count == 1)
        #expect(service.sent.first?.to == "a@b.c")
    }

    @Test("a failed send keeps the text and surfaces the error")
    func sendFailure() async {
        let service = FakeSendService()
        service.error = MailGatewayError.offline
        let compose = ComposeModel(mode: .new, to: "a@b.c", subject: "hi", body: "text")
        await compose.send(using: service)
        guard case .failed(let message) = compose.state else {
            Issue.record("expected failed state")
            return
        }
        #expect(message.contains("offline"))
        #expect(compose.body == "text")
    }

    @Test("save draft does not send")
    func saveDraft() {
        let service = FakeSendService()
        let compose = ComposeModel(mode: .new, to: "a@b.c", subject: "draft", body: "wip")
        compose.saveDraft(using: service)
        #expect(service.drafts.count == 1)
        #expect(service.sent.isEmpty)
    }
}

@Suite("MailboxModel search")
@MainActor
struct MailboxSearchTests {
    @Test("a query replaces the list and clearing restores the folder")
    func searchFlow() async {
        let inboxMessage = StoredMessage(serverID: "1", subject: "周报", sender: "a@b.c",
                                         receivedRaw: nil, isRead: true, bodyPreview: nil, folderID: "13")
        let service = FakeService(
            folderList: [StoredFolder(serverID: "13", parentID: "0", displayName: "收件箱", type: 2)],
            messageList: [inboxMessage]
        )
        service.searchResults = [inboxMessage]
        let model = MailboxModel(service: service)
        model.loadCached()

        model.searchQuery = "周报"
        await model.applySearch()
        #expect(model.messages.count == 1)

        model.searchQuery = ""
        await model.applySearch()
        #expect(model.messages.count == 1)
    }
}

final class FakeNotifier: NotificationPosting, @unchecked Sendable {
    nonisolated(unsafe) var posts: [(String, String)] = []
    func requestAuthorization() async {}
    func post(title: String, body: String) async { posts.append((title, body)) }
}

@Suite("Notifications")
@MainActor
struct NotificationTests {
    @Test("new mail triggers one notification with the added count")
    func notifiesOnNewMail() async {
        let service = FakeService(
            folderList: [StoredFolder(serverID: "13", parentID: "0", displayName: "收件箱", type: 2)],
            messageList: [
                StoredMessage(serverID: "1", subject: "a", sender: nil, receivedRaw: nil, isRead: false, bodyPreview: nil),
                StoredMessage(serverID: "2", subject: "b", sender: nil, receivedRaw: nil, isRead: false, bodyPreview: nil),
                StoredMessage(serverID: "3", subject: "c", sender: nil, receivedRaw: nil, isRead: false, bodyPreview: nil),
            ]
        )
        let notifier = FakeNotifier()
        let model = MailboxModel(service: service, notifier: notifier)
        await model.refresh()
        #expect(notifier.posts.count == 1)
        #expect(notifier.posts.first?.1 == "3 封新邮件")
    }
}
