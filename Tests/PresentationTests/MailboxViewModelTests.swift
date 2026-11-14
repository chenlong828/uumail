import Foundation
import MailDomain
import MailStore
import Testing

import Presentation

@Suite("MailboxViewModel sync")
@MainActor
struct MailboxSyncTests {
    @Test("refresh loads folders, picks the inbox and reflects the sync outcome")
    func refreshPicksInbox() async throws {
        let gateway = PresentationFakeGateway(
            folders: FolderListing(folders: [presentationDrafts, presentationInbox], syncKey: "7"),
            deltas: presentationDeltas(added: [presentationMessage("1", subject: "周报")])
        )
        let fixture = try makeMailboxFixture(gateway: gateway, folders: [])

        await fixture.viewModel.refresh()

        #expect(fixture.viewModel.sync.phase == .idle)
        #expect(fixture.viewModel.sync.lastSyncedAt == fixture.clock.now)
        #expect(fixture.viewModel.selection.folderID == "13")
        #expect(fixture.viewModel.messages.count == 1)
        #expect(fixture.viewModel.messages.first?.subject == "周报")
    }

    @Test("a failed sync keeps the cached list and shows the Chinese error text")
    func failureKeepsCache() async throws {
        let gateway = PresentationFakeGateway(
            folders: FolderListing(folders: [presentationInbox], syncKey: "7")
        )
        gateway.folderError = .authFailed
        let fixture = try makeMailboxFixture(
            gateway: gateway,
            messages: ["13": [presentationMessage("1", subject: "旧信")]]
        )

        await fixture.viewModel.refresh()

        #expect(fixture.viewModel.messages.count == 1)
        #expect(fixture.viewModel.sync.phase == .failed(ErrorText.text(for: .authFailed)))
        #expect(fixture.viewModel.sync.lastSyncedAt == nil)
    }

    @Test("new mail is reflected once with the added count")
    func notificationCountReflection() async throws {
        let added = (0..<3).map { presentationMessage("m\($0)", subject: "新邮件\($0)") }
        let gateway = PresentationFakeGateway(
            folders: FolderListing(folders: [presentationInbox], syncKey: "7"),
            deltas: presentationDeltas(added: added)
        )
        let fixture = try makeMailboxFixture(gateway: gateway, folders: [])

        await fixture.viewModel.refresh()

        #expect(fixture.notifier.authorizationRequests == 1)
        #expect(fixture.notifier.posts == [3])
        #expect(fixture.viewModel.messages.count == 3)
    }

    @Test("selecting another folder clears the message and the reading pane")
    func folderSelection() throws {
        let fixture = try makeMailboxFixture(
            folders: [presentationInbox, presentationDrafts],
            messages: ["13": [presentationMessage("1", subject: "A")]]
        )
        fixture.viewModel.loadCached()

        fixture.viewModel.select(folderID: "4")

        #expect(fixture.viewModel.selection.folderID == "4")
        #expect(fixture.viewModel.messages.isEmpty)
        #expect(fixture.viewModel.selection.messageID == nil)
        #expect(fixture.viewModel.body == .none)
    }
}

@Suite("MailboxViewModel body")
@MainActor
struct MailboxBodyTests {
    private func fixture(
        messages: [Message],
        body: Result<FetchedBody, MailError>? = nil
    ) throws -> MailboxFixture {
        let gateway = PresentationFakeGateway(
            folders: FolderListing(folders: [presentationInbox], syncKey: "7"),
            body: body
        )
        return try makeMailboxFixture(gateway: gateway, messages: ["13": messages])
    }

    @Test("a cached body is shown without a network call")
    func cachedBody() async throws {
        let fixture = try fixture(messages: [presentationMessage("1")])
        try fixture.store.applyBody(
            account: fixture.account,
            folder: "13",
            serverID: "1",
            html: "<html>cached</html>"
        )

        fixture.viewModel.loadCached()
        await fixture.viewModel.openSelected()

        #expect(fixture.viewModel.body == .loaded(html: "<html>cached</html>", truncated: false))
        #expect(fixture.viewModel.bodyNotice == nil)
        #expect(fixture.gateway.bodyCalls == 0)
    }

    @Test("a message without cache or preview starts in the loading state")
    func loadingState() async throws {
        let fixture = try fixture(
            messages: [presentationMessage("1")],
            body: .success(FetchedBody(text: "<html>fetched</html>", isHTML: true, isTruncated: false))
        )

        fixture.viewModel.loadCached()
        await Task.yield()
        #expect(fixture.viewModel.body == .loading)

        await fixture.viewModel.openSelected()
        #expect(fixture.viewModel.body == .loaded(html: "<html>fetched</html>", truncated: false))
    }

    @Test("a missing body is fetched and becomes the loaded state")
    func fetchedBody() async throws {
        let fixture = try fixture(
            messages: [presentationMessage("1")],
            body: .success(FetchedBody(text: "<html>fetched</html>", isHTML: true, isTruncated: false))
        )

        fixture.viewModel.loadCached()
        await fixture.viewModel.openSelected()

        #expect(fixture.viewModel.body == .loaded(html: "<html>fetched</html>", truncated: false))
        #expect(fixture.gateway.bodyCalls == 1)
    }

    @Test("a failed fetch without a preview becomes the retry state")
    func failedBody() async throws {
        let fixture = try fixture(messages: [presentationMessage("1")], body: .failure(.offline))

        fixture.viewModel.loadCached()
        await fixture.viewModel.openSelected()

        #expect(fixture.viewModel.body == .failed(text: ErrorText.text(for: .offline)))
        #expect(fixture.viewModel.bodyNotice == nil)
    }

    @Test("retry fetches again after a failed body")
    func failedBodyRetry() async throws {
        let fixture = try fixture(messages: [presentationMessage("1")], body: .failure(.offline))
        fixture.viewModel.loadCached()
        await fixture.viewModel.openSelected()

        fixture.gateway.bodyResult = .success(
            FetchedBody(text: "<html>retried</html>", isHTML: true, isTruncated: false)
        )
        await fixture.viewModel.openSelected()

        #expect(fixture.viewModel.body == .loaded(html: "<html>retried</html>", truncated: false))
        #expect(fixture.gateway.bodyCalls == 2)
    }

    @Test("a sync preview shows immediately but never stands in for the body")
    func previewDoesNotBlockFetch() async throws {
        let fixture = try fixture(
            messages: [presentationMessage("1", preview: "第一行\n第二行")],
            body: .success(FetchedBody(text: "<p>完整正文</p>", isHTML: true, isTruncated: false))
        )

        fixture.viewModel.loadCached()
        await fixture.viewModel.openSelected()

        #expect(fixture.gateway.bodyCalls == 1)
        #expect(fixture.viewModel.body == .loaded(html: "<p>完整正文</p>", truncated: false))
        #expect(fixture.viewModel.bodyNotice == nil)
    }

    @Test("a failed fetch keeps the preview readable and allows retry")
    func failedFetchKeepsPreview() async throws {
        let fixture = try fixture(
            messages: [presentationMessage("1", preview: "第一行\n第二行")],
            body: .failure(.offline)
        )

        fixture.viewModel.loadCached()
        await fixture.viewModel.openSelected()

        guard case .loaded(let html, let truncated) = fixture.viewModel.body else {
            Issue.record("expected the preview to stay on screen")
            return
        }
        #expect(!truncated)
        #expect(html.contains("第一行\n第二行"), "a preview keeps its own line breaks")
        #expect(fixture.viewModel.bodyNotice == .previewFallback(text: ErrorText.text(for: .offline)))
    }

    @Test("a truncated body is flagged so the pane can say so")
    func truncatedBody() async throws {
        let fixture = try fixture(
            messages: [presentationMessage("1")],
            body: .success(FetchedBody(text: "<p>很长</p>", isHTML: true, isTruncated: true))
        )

        fixture.viewModel.loadCached()
        await fixture.viewModel.openSelected()

        #expect(fixture.viewModel.body == .loaded(html: "<p>很长</p>", truncated: true))
        #expect(fixture.viewModel.bodyNotice == nil)
    }
}

@Suite("MailboxViewModel search")
@MainActor
struct MailboxSearchTests {
    @Test("a query replaces the list and clearing restores the folder")
    func searchFlow() async throws {
        let fixture = try makeMailboxFixture(
            messages: ["13": [presentationMessage("1", subject: "周报")]]
        )
        fixture.viewModel.loadCached()

        await fixture.viewModel.search("周报")
        #expect(fixture.viewModel.selection.searchQuery == "周报")
        #expect(fixture.viewModel.messages.count == 1)
        #expect(fixture.viewModel.messages.first?.subject == "周报")

        await fixture.viewModel.search("")
        #expect(fixture.viewModel.selection.searchQuery.isEmpty)
        #expect(fixture.viewModel.messages.count == 1)
    }
}

@Suite("MailboxViewModel compose")
@MainActor
struct MailboxComposeTests {
    @Test("composeReplyAll seeds from the selected message, its stored Cc and the loaded body")
    func composeReplyAllUsesSelection() async throws {
        let fixture = try makeMailboxFixture(
            messages: ["13": [
                presentationMessage(
                    "1",
                    subject: "周报",
                    sender: "\"张三\" <z@corp.test>",
                    recipients: "a@corp.test",
                    cc: "c@corp.test"
                ),
                presentationMessage("2", subject: "另一封", sender: "other@corp.test"),
            ]]
        )
        try fixture.store.applyBody(
            account: fixture.account,
            folder: "13",
            serverID: "1",
            html: "<p>原文</p>"
        )
        fixture.viewModel.loadCached()
        fixture.viewModel.select(messageID: "1")
        await fixture.viewModel.openSelected()

        let compose = fixture.viewModel.composeReplyAll()

        #expect(compose?.mode == .replyAll)
        #expect(compose?.to == "z@corp.test; a@corp.test")
        #expect(compose?.cc == "c@corp.test")
        #expect(compose?.subject == "Re: 周报")
        #expect(compose?.body.contains("原文") == true)
    }

    @Test("composeReplyAll needs a selected message")
    func composeReplyAllWithoutSelection() throws {
        let fixture = try makeMailboxFixture()

        #expect(fixture.viewModel.composeReplyAll() == nil)
    }
}

@Suite("ErrorText")
struct ErrorTextTests {
    @Test("MailError maps to the single Chinese table")
    func mapping() {
        #expect(ErrorText.text(for: MailError.authFailed) == "账号或密码不正确，请重新配置")
        #expect(ErrorText.text(for: MailError.deviceNotRegistered).contains("设备未登记"))
        #expect(ErrorText.text(for: MailError.policyBlocked).contains("策略"))
        #expect(ErrorText.text(for: MailError.offline).contains("网络"))
        #expect(ErrorText.text(for: MailError.unsupported).contains("不支持"))
        #expect(ErrorText.text(for: MailError.storage(reason: "disk full")).contains("disk full"))
        #expect(ErrorText.text(for: MailError.invalidInput(reason: "recipient is empty")).contains("recipient is empty"))
    }
}
