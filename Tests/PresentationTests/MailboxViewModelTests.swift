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

// MARK: - Dwell

@Suite("MailboxViewModel dwell")
@MainActor
struct MailboxDwellTests {
    private func fixture(
        messages: [Message],
        write: any MailWriteGateway = UnsupportedWriteGateway(),
        sleepMilliseconds: Int = 60
    ) throws -> MailboxFixture {
        try makeMailboxFixture(
            messages: ["13": messages],
            write: write,
            dwellSleep: { _ in try await Task.sleep(for: .milliseconds(sleepMilliseconds)) }
        )
    }

    @Test("T-SCN-0008-01: a selected unread message becomes read after the dwell")
    func dwellMarksSelectedUnreadAfterTenSeconds() async throws {
        let fixture = try fixture(messages: [presentationMessage("1", isRead: false)], sleepMilliseconds: 20)
        fixture.viewModel.loadCached()

        try await Task.sleep(for: .milliseconds(80))

        #expect(try fixture.store.messages(account: fixture.account, folder: "13").first?.isRead == true)
        #expect(fixture.viewModel.deleteErrorText == nil)
    }

    @Test("T-SCN-0008-02: switching selection cancels the old clock and starts a new one")
    func dwellCancelsOnSelectionChangeAndRestarts() async throws {
        let fixture = try fixture(
            messages: [presentationMessage("1", isRead: false), presentationMessage("2", isRead: false)],
            sleepMilliseconds: 80
        )
        fixture.viewModel.loadCached()
        try await Task.sleep(for: .milliseconds(25))
        fixture.viewModel.select(messageID: "2")
        try await Task.sleep(for: .milliseconds(30))

        #expect(try fixture.store.messages(account: fixture.account, folder: "13").first { $0.serverID == "1" }?.isRead == false)
        try await Task.sleep(for: .milliseconds(80))
        #expect(try fixture.store.messages(account: fixture.account, folder: "13").first { $0.serverID == "2" }?.isRead == true)
    }

    @Test("T-SCN-0008-02: background pauses and returning to the foreground restarts a full dwell")
    func dwellPausesInBackgroundAndRestarts() async throws {
        let fixture = try fixture(messages: [presentationMessage("1", isRead: false)], sleepMilliseconds: 70)
        fixture.viewModel.loadCached()
        try await Task.sleep(for: .milliseconds(20))
        fixture.viewModel.setApplicationActive(false)
        try await Task.sleep(for: .milliseconds(100))
        #expect(try fixture.store.messages(account: fixture.account, folder: "13").first?.isRead == false)

        fixture.viewModel.setApplicationActive(true)
        try await Task.sleep(for: .milliseconds(100))
        #expect(try fixture.store.messages(account: fixture.account, folder: "13").first?.isRead == true)
    }

    @Test("T-SCN-0008-02: a plain sync reload does not reset a running clock")
    func dwellSurvivesSyncReload() async throws {
        let sleeper = DwellSleeper()
        let fixture = try makeMailboxFixture(
            messages: ["13": [presentationMessage("1", isRead: false)]],
            dwellSleep: { duration in try await sleeper.sleep(duration) }
        )
        fixture.viewModel.loadCached()
        try await Task.sleep(for: .milliseconds(20))

        fixture.viewModel.loadCached()
        try await Task.sleep(for: .milliseconds(20))
        #expect(await sleeper.count == 1, "the same eligible target keeps the original clock")

        await sleeper.release()
        try await Task.sleep(for: .milliseconds(60))
        #expect(try fixture.store.messages(account: fixture.account, folder: "13").first?.isRead == true)
    }

    @Test("T-SCN-0008-04: background does not mark the message read")
    func dwellDoesNotRunInBackground() async throws {
        let fixture = try fixture(messages: [presentationMessage("1", isRead: false)], sleepMilliseconds: 20)
        fixture.viewModel.setApplicationActive(false)
        fixture.viewModel.loadCached()
        try await Task.sleep(for: .milliseconds(80))
        #expect(try fixture.store.messages(account: fixture.account, folder: "13").first?.isRead == false)
    }

    @Test("T-SCN-0008-03: an already-read row never writes again")
    func dwellMarkIsPersistentAndIdempotent() async throws {
        let write = PresentationRecordingWriteGateway(delta: MessageDelta(
            added: [], changed: [], removedServerIDs: [], syncKey: "3", moreAvailable: false
        ))
        let fixture = try fixture(
            messages: [presentationMessage("1", isRead: false)],
            write: write,
            sleepMilliseconds: 20
        )
        fixture.viewModel.loadCached()
        var firstCount = 0
        for _ in 0..<300 {
            firstCount = await write.calls.count
            if firstCount == 1 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(firstCount == 1)

        fixture.viewModel.loadCached()
        try await Task.sleep(for: .milliseconds(80))
        #expect(await write.calls.count == 1, "an already-read message must not start a second write")
        #expect(try fixture.store.messages(account: fixture.account, folder: "13").first?.isRead == true)
    }

    @Test("T-SCN-0008-04: a failed write-back keeps the local read and shows no error")
    func dwellWriteBackFailureIsSilent() async throws {
        let write = PresentationRecordingWriteGateway(delta: MessageDelta(
            added: [], changed: [], removedServerIDs: [], syncKey: "3", moreAvailable: false
        ))
        await write.setFailure(.offline)
        let fixture = try fixture(
            messages: [presentationMessage("1", isRead: false)],
            write: write,
            sleepMilliseconds: 20
        )
        fixture.viewModel.loadCached()
        try await Task.sleep(for: .milliseconds(80))

        #expect(try fixture.store.messages(account: fixture.account, folder: "13").first?.isRead == true)
        #expect(fixture.viewModel.deleteErrorText == nil)
        #expect(fixture.viewModel.sync.phase == .idle)
    }
}

// MARK: - Delete

@Suite("MailboxViewModel delete")
@MainActor
struct MailboxDeleteTests {
    private func deleteDelta(key: String = "3", removed: [String] = []) -> MessageDelta {
        MessageDelta(added: [], changed: [], removedServerIDs: removed, syncKey: key, moreAvailable: false)
    }

    @Test("T-SCN-0009-01: delete hides the row immediately, advances selection and soft-deletes after the gate")
    func deleteSelectedHidesRowAndAdvancesSelection() async throws {
        let write = PresentationRecordingWriteGateway(delta: deleteDelta(removed: ["1"]))
        let gate = WriteGate()
        await write.setGate(gate)
        let fixture = try makeMailboxFixture(
            messages: ["13": [
                presentationMessage("1", subject: "第一封"),
                presentationMessage("2", subject: "第二封"),
            ]],
            write: write
        )
        fixture.viewModel.loadCached()
        fixture.viewModel.select(messageID: "1")
        try await Task.sleep(for: .milliseconds(10))

        let task = Task { await fixture.viewModel.deleteSelected() }
        await gate.waitUntilWaiting()
        #expect(fixture.viewModel.visibleMessages.map(\.serverID) == ["2"])
        #expect(fixture.viewModel.selection.messageID == "2")

        await gate.open()
        await task.value
        #expect(try fixture.store.messages(account: fixture.account, folder: "13").map(\.serverID) == ["2"])
        #expect(fixture.viewModel.deleteErrorText == nil)
    }

    @Test("T-SCN-0009-02: deleting the only row clears selection and body")
    func deleteLastMessageClearsSelectionAndBody() async throws {
        let write = PresentationRecordingWriteGateway(delta: deleteDelta(removed: ["1"]))
        let fixture = try makeMailboxFixture(
            messages: ["13": [presentationMessage("1")]],
            write: write
        )
        fixture.viewModel.loadCached()

        await fixture.viewModel.deleteSelected()

        #expect(fixture.viewModel.visibleMessages.isEmpty)
        #expect(fixture.viewModel.selection.messageID == nil)
        #expect(fixture.viewModel.body == .none)
        #expect(try fixture.store.messages(account: fixture.account, folder: "13").isEmpty)
    }

    @Test("T-SCN-0009-04: a failed delete restores the row, selection and Chinese error")
    func deleteFailureRestoresRowAndShowsError() async throws {
        let write = PresentationRecordingWriteGateway(delta: deleteDelta(removed: ["1"]))
        await write.setFailure(.offline)
        let fixture = try makeMailboxFixture(
            messages: ["13": [presentationMessage("1"), presentationMessage("2")]],
            write: write
        )
        fixture.viewModel.loadCached()
        let keyBefore = fixture.viewModel.selectedListKey

        await fixture.viewModel.deleteSelected()

        #expect(Set(fixture.viewModel.visibleMessages.map(\.serverID)) == ["1", "2"])
        #expect(fixture.viewModel.selectedListKey == keyBefore)
        #expect(fixture.viewModel.deleteErrorText?.contains("网络") == true)
        #expect(try fixture.store.messages(account: fixture.account, folder: "13").count == 2)
    }

    @Test("T-SCN-0009-03: a second key press during the in-flight delete is ignored")
    func deleteTwiceSendsOneNetworkWrite() async throws {
        let write = PresentationRecordingWriteGateway(delta: deleteDelta(removed: ["1"]))
        let gate = WriteGate()
        await write.setGate(gate)
        let fixture = try makeMailboxFixture(
            messages: ["13": [presentationMessage("1"), presentationMessage("2")]],
            write: write
        )
        fixture.viewModel.loadCached()

        let first = Task { await fixture.viewModel.deleteSelected() }
        await gate.waitUntilWaiting()
        await fixture.viewModel.deleteSelected()
        await gate.open()
        await first.value

        #expect(await write.calls.count == 1)
    }

    @Test("T-SCN-0009-04: no selection means no network write")
    func deleteWithoutSelectionDoesNothing() async throws {
        let write = PresentationRecordingWriteGateway(delta: deleteDelta())
        let fixture = try makeMailboxFixture(write: write)
        fixture.viewModel.loadCached()

        await fixture.viewModel.deleteSelected()

        #expect(await write.calls.isEmpty)
    }

    @Test("T-SCN-0009-02: deleting from search keeps search mode and updates the folder list")
    func deleteFromSearchResultsRemovesFromFolderList() async throws {
        let write = PresentationRecordingWriteGateway(delta: deleteDelta(removed: ["1"]))
        let fixture = try makeMailboxFixture(
            messages: ["13": [
                presentationMessage("1", subject: "周报会议"),
                presentationMessage("2", subject: "其他通知"),
            ]],
            write: write
        )
        fixture.viewModel.loadCached()
        await fixture.viewModel.search("周报")
        #expect(fixture.viewModel.messages.count == 1)
        fixture.viewModel.select(messageID: "1")
        try await Task.sleep(for: .milliseconds(10))

        await fixture.viewModel.deleteSelected()

        #expect(fixture.viewModel.selection.searchQuery == "周报")
        #expect(fixture.viewModel.visibleMessages.isEmpty)
        await fixture.viewModel.search("")
        #expect(fixture.viewModel.visibleMessages.map(\.serverID) == ["2"])
    }

    @Test("R23: cross-folder rows with the same server id select and delete the right folder")
    func crossFolderSameServerIDUsesCompositeIdentity() async throws {
        let write = PresentationRecordingWriteGateway(delta: deleteDelta(removed: ["1"]))
        let fixture = try makeMailboxFixture(
            folders: [presentationInbox, presentationDrafts],
            messages: [
                "13": [presentationMessage("1", subject: "周报", folderID: "13")],
                "4": [presentationMessage("1", subject: "周报", folderID: "4")],
            ],
            write: write
        )
        fixture.viewModel.loadCached()
        await fixture.viewModel.search("周报")
        #expect(fixture.viewModel.visibleMessages.count == 2)

        let draft = try #require(fixture.viewModel.visibleMessages.first { $0.folderID == "4" })
        fixture.viewModel.select(listKey: MailboxViewModel.listKey(for: draft))
        await fixture.viewModel.deleteSelected()

        #expect(try fixture.store.messages(account: fixture.account, folder: "13").map(\.serverID) == ["1"])
        #expect(try fixture.store.messages(account: fixture.account, folder: "4").isEmpty)
        #expect(fixture.viewModel.visibleMessages.map(\.folderID) == ["13"])
    }

    @Test("O5: a slow next-body fetch never delays the delete command")
    func slowBodyFetchDoesNotBlockDelete() async throws {
        let gateway = PresentationFakeGateway(
            folders: FolderListing(folders: [presentationInbox], syncKey: "7"),
            body: .success(FetchedBody(text: "<p>慢正文</p>", isHTML: true, isTruncated: false))
        )
        gateway.bodyDelay = .milliseconds(500)
        let write = PresentationRecordingWriteGateway(delta: deleteDelta(removed: ["1"]))
        let gate = WriteGate()
        await write.setGate(gate)
        let fixture = try makeMailboxFixture(
            gateway: gateway,
            messages: ["13": [presentationMessage("1"), presentationMessage("2")]],
            write: write
        )
        fixture.viewModel.loadCached()
        try await Task.sleep(for: .milliseconds(20))

        let task = Task { await fixture.viewModel.deleteSelected() }
        await gate.waitUntilWaiting()
        #expect(await write.calls.count == 1, "the delete write must be issued while the next body is still fetching")
        await gate.open()
        await task.value
    }
}


/// A controllable sleeper that counts clock starts. A reload that incorrectly restarts the
/// dwell would request a second sleep.
actor DwellSleeper {
    private(set) var count = 0
    private var waiter: CheckedContinuation<Void, Error>?

    func sleep(_ duration: Duration) async throws {
        count += 1
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                waiter = continuation
            }
        } onCancel: {
            Task { await self.cancel() }
        }
    }

    func release() {
        waiter?.resume()
        waiter = nil
    }

    private func cancel() {
        waiter?.resume(throwing: CancellationError())
        waiter = nil
    }
}
