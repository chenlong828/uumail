import Foundation
import MailDomain
import MailStore
import Scenes
import Testing
import SyncContract

@testable import Presentation

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

@Suite("MailboxViewModel header")
@MainActor
struct MailboxHeaderTests {
    @Test("headerPresentation is nil without a selection and after switching folders")
    func nilWithoutSelection() throws {
        let fixture = try makeMailboxFixture(
            folders: [presentationInbox, presentationDrafts],
            messages: ["13": [presentationMessage("1", subject: "第一封")]]
        )

        #expect(fixture.viewModel.headerPresentation == nil)

        fixture.viewModel.loadCached()
        #expect(fixture.viewModel.headerPresentation?.subject == "第一封")

        fixture.viewModel.select(folderID: "4")
        #expect(fixture.viewModel.selectedMessage == nil)
        #expect(fixture.viewModel.headerPresentation == nil)
    }

    @Test("headerPresentation follows the selection and switching leaves no stale subject")
    func followsSelectionAndSwitch() throws {
        let fixture = try makeMailboxFixture(
            messages: ["13": [
                presentationMessage("1", subject: "第一封", sender: "one@example.com"),
                presentationMessage("2", subject: "第二封", sender: "two@example.com"),
            ]]
        )
        fixture.viewModel.loadCached()

        fixture.viewModel.select(messageID: "1")
        #expect(fixture.viewModel.headerPresentation?.subject == "第一封")
        #expect(fixture.viewModel.headerPresentation?.rows.first?.value == "one@example.com")

        fixture.viewModel.select(messageID: "2")
        let second = try #require(fixture.viewModel.headerPresentation)
        #expect(second.subject == "第二封")
        #expect(second.rows.first?.value == "two@example.com")
        #expect(!second.rows.contains { $0.value == "one@example.com" })
    }

    @Test("R23: cross-folder rows with the same server id map the selected row's header")
    func crossFolderSameServerID() async throws {
        let fixture = try makeMailboxFixture(
            folders: [presentationInbox, presentationDrafts],
            messages: [
                "13": [presentationMessage("1", subject: "周报-收件箱", folderID: "13")],
                "4": [presentationMessage("1", subject: "周报-草稿", folderID: "4")],
            ]
        )
        fixture.viewModel.loadCached()
        await fixture.viewModel.search("周报")
        let draft = try #require(fixture.viewModel.visibleMessages.first { $0.folderID == "4" })

        fixture.viewModel.select(listKey: MailboxViewModel.listKey(for: draft))

        #expect(fixture.viewModel.selection.folderID == "13", "search keeps the originating folder")
        #expect(fixture.viewModel.headerPresentation?.subject == "周报-草稿")
    }

    @Test("reading headerPresentation adds no gateway call and leaves the body/list alone")
    func readIsPureDerivation() async throws {
        let fixture = try makeMailboxFixture(
            messages: ["13": [
                presentationMessage(
                    "1",
                    subject: "只读头部",
                    recipients: "b@example.com",
                    receivedRaw: "2026-11-16T09:30:00Z"
                )
            ]]
        )
        fixture.viewModel.loadCached()
        await fixture.viewModel.openSelected()

        let bodyCalls = fixture.gateway.bodyCalls
        let sendCalls = fixture.gateway.sendCalls
        let body = fixture.viewModel.body
        let messages = fixture.viewModel.messages
        let header = fixture.viewModel.headerPresentation

        #expect(header?.subject == "只读头部")
        for _ in 0..<3 {
            #expect(fixture.viewModel.headerPresentation == header)
        }
        #expect(fixture.gateway.bodyCalls == bodyCalls)
        #expect(fixture.gateway.sendCalls == sendCalls)
        #expect(fixture.viewModel.body == body)
        #expect(fixture.viewModel.messages == messages)
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


/// Polls a MainActor predicate; positive assertions use this instead of a fixed sleep so
/// a loaded machine cannot turn "has not fired yet" into a false failure.
@MainActor
func waitFor(_ condition: @escaping () throws -> Bool, attempts: Int = 300) async throws -> Bool {
    for _ in 0..<attempts {
        if try condition() { return true }
        try await Task.sleep(for: .milliseconds(10))
    }
    return try condition()
}

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

    @Test("T-SCN-0008-01: the dwell asks for exactly three seconds and then marks read")
    func dwellAsksForThreeSecondsAndMarks() async throws {
        let sleeper = DwellSleeper()
        let write = PresentationRecordingWriteGateway(delta: MessageDelta(
            added: [], changed: [], removedServerIDs: [], syncKey: "3", moreAvailable: false
        ))
        let fixture = try makeMailboxFixture(
            messages: ["13": [presentationMessage("1", isRead: false)]],
            write: write,
            dwellSleep: { duration in try await sleeper.sleep(duration) }
        )
        fixture.viewModel.loadCached()
        for _ in 0..<200 {
            if await sleeper.count == 1 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await sleeper.durations == [.seconds(3)], "the timer must request exactly three seconds")

        await sleeper.release()
        let marked = try await waitFor {
            try fixture.store.messages(account: fixture.account, folder: "13").first?.isRead == true
        }
        #expect(marked)
        #expect(fixture.viewModel.markReadErrorText == nil)
    }

    @Test("T-SCN-0008-02: switching selection cancels the old clock and starts a new one")
    func dwellCancelsOnSelectionChangeAndRestarts() async throws {
        let sleeper = DwellSleeper()
        let fixture = try makeMailboxFixture(
            messages: ["13": [presentationMessage("1", isRead: false), presentationMessage("2", isRead: false)]],
            dwellSleep: { duration in try await sleeper.sleep(duration) }
        )
        fixture.viewModel.loadCached()
        for _ in 0..<200 {
            if await sleeper.count == 1 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await sleeper.count == 1, "the first clock must be running")

        // loadCached auto-selects the first row (serverID "2"); switching to "1" must
        // cancel that clock and start a new one for the other unread row.
        fixture.viewModel.select(messageID: "1")
        for _ in 0..<200 {
            let count = await sleeper.count
            let cancelled = await sleeper.cancelled
            let pending = await sleeper.pending
            if count == 2 && cancelled == 1 && pending == 1 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await sleeper.cancelled == 1, "switching selection must cancel the first clock")
        #expect(await sleeper.count == 2, "the second clock must start")
        #expect(try fixture.store.messages(account: fixture.account, folder: "13").first { $0.serverID == "2" }?.isRead == false)

        await sleeper.release()
        try await Task.sleep(for: .milliseconds(20))
        let marked = try await waitFor {
            try fixture.store.messages(account: fixture.account, folder: "13").first { $0.serverID == "1" }?.isRead == true
        }
        #expect(marked)
        #expect(try fixture.store.messages(account: fixture.account, folder: "13").first { $0.serverID == "2" }?.isRead == false)
    }

    @Test("T-SCN-0008-02: switching at two seconds cancels the old clock and only the new row marks")
    func dwellTwoSecondsSwitchDoesNotMarkTheOldSelection() async throws {
        let sleeper = DwellSleeper()
        let write = PresentationRecordingWriteGateway(delta: MessageDelta(
            added: [], changed: [], removedServerIDs: [], syncKey: "3", moreAvailable: false
        ))
        let fixture = try makeMailboxFixture(
            messages: ["13": [presentationMessage("1", isRead: false), presentationMessage("2", isRead: false)]],
            write: write,
            dwellSleep: { duration in try await sleeper.sleep(duration) }
        )
        fixture.viewModel.loadCached()
        for _ in 0..<200 {
            let count = await sleeper.count
            let pending = await sleeper.pending
            if count == 1 && pending == 1 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await sleeper.durations == [.seconds(3)], "the timer must request exactly three seconds")
        let firstTarget = try #require(fixture.viewModel.selectedMessage?.serverID)
        #expect(firstTarget == "2", "loadCached auto-selects the newest row")

        // Two seconds in, neither row may be read yet.
        await sleeper.advance(by: .seconds(2))
        try await Task.sleep(for: .milliseconds(20))
        #expect(try fixture.store.messages(account: fixture.account, folder: "13").allSatisfy { !$0.isRead })

        // Switch at the two-second mark: the old clock is cancelled, not allowed to elapse.
        fixture.viewModel.select(messageID: "1")
        for _ in 0..<200 {
            let cancelled = await sleeper.cancelled
            let count = await sleeper.count
            let pending = await sleeper.pending
            if cancelled == 1 && count == 2 && pending == 1 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await sleeper.cancelled == 1, "the two-second switch must cancel the first clock")
        #expect(try fixture.store.messages(account: fixture.account, folder: "13").first { $0.serverID == "2" }?.isRead == false)
        #expect(await write.calls.isEmpty)

        // The new row only marks after its own full three seconds.
        await sleeper.advance(by: .seconds(3))
        let marked = try await waitFor {
            try fixture.store.messages(account: fixture.account, folder: "13").first { $0.serverID == "1" }?.isRead == true
        }
        #expect(marked)
        #expect(try fixture.store.messages(account: fixture.account, folder: "13").first { $0.serverID == "2" }?.isRead == false)
        #expect(await write.calls == [.markRead(collectionID: "13", serverID: "1", key: "2")])
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
        let marked = try await waitFor {
            try fixture.store.messages(account: fixture.account, folder: "13").first?.isRead == true
        }
        #expect(marked)
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
        let marked = try await waitFor {
            try fixture.store.messages(account: fixture.account, folder: "13").first?.isRead == true
        }
        #expect(marked)
        #expect(fixture.viewModel.deleteErrorText == nil)
        #expect(fixture.viewModel.sync.phase == .idle)
    }

    @Test("T-SCN-0008-02: switching folders cancels the running dwell")
    func dwellCancelsOnFolderSwitch() async throws {
        let write = PresentationRecordingWriteGateway(delta: MessageDelta(
            added: [], changed: [], removedServerIDs: [], syncKey: "3", moreAvailable: false
        ))
        let fixture = try makeMailboxFixture(
            folders: [presentationInbox, presentationDrafts],
            messages: ["13": [presentationMessage("1", isRead: false)], "4": []],
            write: write,
            dwellSleep: { _ in try await Task.sleep(for: .milliseconds(150)) }
        )
        fixture.viewModel.loadCached()
        try await Task.sleep(for: .milliseconds(40))
        fixture.viewModel.select(folderID: "4")
        try await Task.sleep(for: .milliseconds(220))

        #expect(try fixture.store.messages(account: fixture.account, folder: "13").first?.isRead == false)
        #expect(fixture.viewModel.selectedMessage == nil)
        #expect(await write.calls.isEmpty)
    }

    @Test("T-SCN-0008-02: entering and staying in search mode never starts the clock")
    func dwellDoesNotRunInSearchMode() async throws {
        let write = PresentationRecordingWriteGateway(delta: MessageDelta(
            added: [], changed: [], removedServerIDs: [], syncKey: "3", moreAvailable: false
        ))
        let fixture = try makeMailboxFixture(
            messages: ["13": [presentationMessage("1", subject: "周报会议", isRead: false)]],
            write: write,
            dwellSleep: { _ in try await Task.sleep(for: .milliseconds(150)) }
        )
        fixture.viewModel.loadCached()
        try await Task.sleep(for: .milliseconds(40))
        await fixture.viewModel.search("周报")
        try await Task.sleep(for: .milliseconds(220))

        #expect(fixture.viewModel.selection.searchQuery == "周报")
        #expect(try fixture.store.messages(account: fixture.account, folder: "13").first?.isRead == false)
        #expect(await write.calls.isEmpty)

        // Staying in search (a reload / second search) must not restart a clock either.
        fixture.viewModel.loadCached()
        await fixture.viewModel.search("周报")
        try await Task.sleep(for: .milliseconds(220))
        #expect(try fixture.store.messages(account: fixture.account, folder: "13").first?.isRead == false)
        #expect(await write.calls.isEmpty)
    }

    @Test("T-SCN-0008-02: deleting the selected message cancels its dwell")
    func dwellCancelsWhenSelectedMessageIsDeleted() async throws {
        let sleeper = DwellSleeper()
        let write = PresentationRecordingWriteGateway(delta: MessageDelta(
            added: [], changed: [], removedServerIDs: ["1"], syncKey: "3", moreAvailable: false
        ))
        let fixture = try makeMailboxFixture(
            messages: ["13": [presentationMessage("1", isRead: false)]],
            write: write,
            dwellSleep: { duration in try await sleeper.sleep(duration) }
        )
        fixture.viewModel.loadCached()
        for _ in 0..<200 {
            if await sleeper.count == 1 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(await sleeper.count == 1, "the dwell clock must be running before the delete")

        await fixture.viewModel.deleteSelected()
        for _ in 0..<200 {
            if await sleeper.cancelled == 1 { break }
            try await Task.sleep(for: .milliseconds(5))
        }

        #expect(await sleeper.cancelled == 1, "delete must cancel the selected row's clock")
        #expect(await write.calls == [.delete(collectionID: "13", serverID: "1", key: "2")])
    }

    @Test("T-SCN-0008-04: background for a full dwell marks nothing read and sends no network")
    func dwellDoesNotRunInBackground() async throws {
        let write = PresentationRecordingWriteGateway(delta: MessageDelta(
            added: [], changed: [], removedServerIDs: [], syncKey: "3", moreAvailable: false
        ))
        let fixture = try fixture(
            messages: [presentationMessage("1", isRead: false)],
            write: write,
            sleepMilliseconds: 20
        )
        fixture.viewModel.setApplicationActive(false)
        fixture.viewModel.loadCached()
        try await Task.sleep(for: .milliseconds(120))

        #expect(try fixture.store.messages(account: fixture.account, folder: "13").first?.isRead == false)
        #expect(await write.calls.isEmpty)
    }

    @Test("T-SCN-0008-04: returning to the foreground requires a fresh full dwell")
    func dwellForegroundRestartNeedsFullDwell() async throws {
        let write = PresentationRecordingWriteGateway(delta: MessageDelta(
            added: [], changed: [], removedServerIDs: [], syncKey: "3", moreAvailable: false
        ))
        let fixture = try fixture(
            messages: [presentationMessage("1", isRead: false)],
            write: write,
            sleepMilliseconds: 200
        )
        fixture.viewModel.loadCached()
        try await Task.sleep(for: .milliseconds(40))
        fixture.viewModel.setApplicationActive(false)
        try await Task.sleep(for: .milliseconds(260))
        #expect(try fixture.store.messages(account: fixture.account, folder: "13").first?.isRead == false)
        #expect(await write.calls.isEmpty)

        fixture.viewModel.setApplicationActive(true)
        try await Task.sleep(for: .milliseconds(80))
        #expect(try fixture.store.messages(account: fixture.account, folder: "13").first?.isRead == false,
                "less than three seconds after re-activation must not mark it read")
        #expect(await write.calls.isEmpty)

        let marked = try await waitFor {
            try fixture.store.messages(account: fixture.account, folder: "13").first?.isRead == true
        }
        #expect(marked)
    }

    @Test("T-SCN-0008-03: a Read=0 echo in the write response cannot flip the local read")
    func dwellServerReadZeroEchoDoesNotFlipLocal() async throws {
        let write = PresentationRecordingWriteGateway(delta: MessageDelta(
            added: [],
            changed: [
                Message(serverID: "1", isRead: false, folderID: "13"),
                Message(serverID: "2", subject: "邻居-更新", isRead: true, folderID: "13"),
            ],
            removedServerIDs: [],
            syncKey: "3",
            moreAvailable: false
        ))
        let fixture = try fixture(
            messages: [presentationMessage("1", subject: "目标", isRead: false), presentationMessage("2", isRead: false)],
            write: write,
            sleepMilliseconds: 20
        )
        fixture.viewModel.loadCached()
        fixture.viewModel.select(messageID: "1")
        for _ in 0..<200 {
            if await write.calls.count == 1 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        try await Task.sleep(for: .milliseconds(40))

        #expect(try fixture.store.messages(account: fixture.account, folder: "13").first { $0.serverID == "1" }?.isRead == true)
        #expect(fixture.viewModel.visibleMessages.first { $0.serverID == "1" }?.isRead == true)
        #expect(try fixture.store.messages(account: fixture.account, folder: "13").first { $0.serverID == "2" }?.subject == "邻居-更新")
    }

}

// MARK: - Remote content / manual mark-read

@Suite("MailboxViewModel remote content")
@MainActor
struct MailboxRemoteContentTests {
    private func fixture(messages: [Message], bodies: [String: String]) throws -> MailboxFixture {
        let fixture = try makeMailboxFixture(messages: ["13": messages])
        for (id, html) in bodies {
            try fixture.store.applyBody(account: fixture.account, folder: "13", serverID: id, html: html)
        }
        return fixture
    }

    private func loadBody(_ fixture: MailboxFixture, _ id: String) async throws {
        fixture.viewModel.select(messageID: id)
        for _ in 0..<200 {
            if case .loaded = fixture.viewModel.body,
               fixture.viewModel.selectedMessage?.serverID == id,
               fixture.viewModel.canAllowRemoteContent {
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test("T-SCN-0013-02/03: default off and a selection change resets the permission")
    func remoteContentResetsOnSelectionChange() async throws {
        let fixture = try fixture(
            messages: [presentationMessage("1"), presentationMessage("2")],
            bodies: ["1": "<p>A</p>", "2": "<p>B</p>"]
        )
        fixture.viewModel.loadCached()
        try await loadBody(fixture, "1")
        #expect(fixture.viewModel.canAllowRemoteContent)
        #expect(!fixture.viewModel.allowsRemoteContent, "remote content starts off")

        fixture.viewModel.setAllowsRemoteContent(true)
        #expect(fixture.viewModel.allowsRemoteContent)

        fixture.viewModel.select(messageID: "2")
        #expect(!fixture.viewModel.allowsRemoteContent, "selecting B resets the permission immediately")
        try await loadBody(fixture, "2")
        #expect(fixture.viewModel.canAllowRemoteContent)
        #expect(!fixture.viewModel.allowsRemoteContent, "B still starts blocked")

        fixture.viewModel.select(messageID: "1")
        #expect(!fixture.viewModel.allowsRemoteContent, "returning to A stays blocked (session-only)")
    }

    @Test("T-SCN-0013-03: a stale loaded body cannot inherit the new selection's permission")
    func remoteContentCannotLeakToStaleBody() async throws {
        let fixture = try fixture(
            messages: [presentationMessage("1"), presentationMessage("2")],
            bodies: ["1": "<p>A</p>", "2": "<p>B</p>"]
        )
        fixture.viewModel.loadCached()
        try await loadBody(fixture, "1")
        fixture.viewModel.setAllowsRemoteContent(true)
        #expect(fixture.viewModel.allowsRemoteContent)

        let second = try #require(fixture.viewModel.messages.first { $0.serverID == "2" })
        // Simulate the window where selection already moved to B but A's loaded HTML is
        // still on screen: the old permission must not carry over.
        fixture.viewModel.selectedListKey = MailboxViewModel.listKey(for: second)
        #expect(!fixture.viewModel.allowsRemoteContent)
        #expect(!fixture.viewModel.canAllowRemoteContent)
        fixture.viewModel.setAllowsRemoteContent(true)
        #expect(!fixture.viewModel.allowsRemoteContent, "forced allow is a no-op on a stale body")
        #expect(fixture.viewModel.body == .loaded(html: "<p>A</p>", truncated: false))
    }

    @Test("T-SCN-0013-04: unavailable states make a forced allow a no-op")
    func forcedRemoteAllowIsNoOpWhenUnavailable() async throws {
        let fixture = try fixture(
            messages: [presentationMessage("1")],
            bodies: ["1": "<p>A</p>"]
        )
        fixture.viewModel.loadCached()
        try await loadBody(fixture, "1")
        fixture.viewModel.setAllowsRemoteContent(true)
        #expect(fixture.viewModel.allowsRemoteContent)
        fixture.viewModel.setAllowsRemoteContent(false)

        for state in [BodyPresentation.loading, .failed(text: "失败"), .none] {
            fixture.viewModel.body = state
            #expect(!fixture.viewModel.canAllowRemoteContent)
            fixture.viewModel.setAllowsRemoteContent(true)
            #expect(!fixture.viewModel.allowsRemoteContent, "forced allow must not fire in \(state)")
        }

        fixture.viewModel.body = .loaded(html: "<p>A</p>", truncated: false)
        fixture.viewModel.selectedListKey = nil
        fixture.viewModel.selection.messageID = nil
        #expect(!fixture.viewModel.canAllowRemoteContent)
        fixture.viewModel.setAllowsRemoteContent(true)
        #expect(!fixture.viewModel.allowsRemoteContent, "no selection means no permission")
    }

    @Test("T-SCN-0013-04: a retry success is usable and still defaults to blocked")
    func retrySuccessRestoresDefaultOffAndAvailability() async throws {
        let fixture = try fixture(
            messages: [presentationMessage("1")],
            bodies: ["1": "<p>A</p>"]
        )
        fixture.viewModel.loadCached()
        try await loadBody(fixture, "1")
        #expect(!fixture.viewModel.allowsRemoteContent)

        // A failed body disables the entry even if the old loaded HTML is still tracked.
        fixture.viewModel.body = .failed(text: "失败")
        #expect(!fixture.viewModel.canAllowRemoteContent)
        fixture.viewModel.setAllowsRemoteContent(true)
        #expect(!fixture.viewModel.allowsRemoteContent, "a forced allow must not fire while failed")

        // Retry succeeds for the same selection: the entry is usable and still off.
        fixture.viewModel.body = .loaded(html: "<p>A</p>", truncated: false)
        #expect(fixture.viewModel.canAllowRemoteContent)
        #expect(!fixture.viewModel.allowsRemoteContent, "a retry must not inherit a permission")
        fixture.viewModel.setAllowsRemoteContent(true)
        #expect(fixture.viewModel.allowsRemoteContent)
    }
}

@Suite("MailboxViewModel manual mark-read")
@MainActor
struct MailboxManualMarkReadTests {
    private func delta(key: String = "3") -> MessageDelta {
        MessageDelta(added: [], changed: [], removedServerIDs: [], syncKey: key, moreAvailable: false)
    }

    private func waitForCalls(_ write: PresentationRecordingWriteGateway, _ count: Int) async throws {
        for _ in 0..<300 {
            if await write.calls.count == count { return }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test("T-SCN-0014-01: the local read lands before the background write-back")
    func manualMarkReadPersistsBeforeWriteBack() async throws {
        let write = PresentationRecordingWriteGateway(delta: delta())
        let gate = WriteGate()
        await write.setGate(gate)
        let fixture = try makeMailboxFixture(
            messages: ["13": [presentationMessage("1", isRead: false)]],
            write: write
        )
        fixture.viewModel.loadCached()
        #expect(fixture.viewModel.canMarkSelectedRead)

        fixture.viewModel.markSelectedRead()

        #expect(try fixture.store.messages(account: fixture.account, folder: "13").first?.isRead == true,
                "the local read must be visible before the server write completes")
        #expect(fixture.viewModel.visibleMessages.first?.isRead == true)
        #expect(fixture.viewModel.markReadErrorText == nil)
        for _ in 0..<300 {
            if await write.calls.count == 1 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let calls = await write.calls
        #expect(calls == [.markRead(collectionID: "13", serverID: "1", key: "2")], "calls=\(calls)")
        await gate.open()
        for _ in 0..<300 {
            if try fixture.store.syncKey(account: fixture.account, collection: "13") == "3" { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(try fixture.store.syncKey(account: fixture.account, collection: "13") == "3")
    }

    @Test("T-SCN-0014-01: a false local transition does not write back and reloads the stale list")
    func manualMarkReadFalseReturnDoesNotWriteBack() async throws {
        let write = PresentationRecordingWriteGateway(delta: delta())
        let fixture = try makeMailboxFixture(
            messages: ["13": [presentationMessage("1", isRead: false)]],
            write: write
        )
        fixture.viewModel.loadCached()
        #expect(fixture.viewModel.canMarkSelectedRead)
        #expect(fixture.viewModel.visibleMessages.first?.isRead == false)

        // The race: another writer marks the row read after the VM's guard, so the real
        // `markReadLocally` observes no 0→1 and returns false while the VM list is stale.
        let store = fixture.store
        let account = fixture.account
        let realLocalMarkRead = fixture.viewModel.localMarkRead
        fixture.viewModel.localMarkRead = { ref in
            _ = try store.markRead(account: account, folder: ref.folderID, serverID: ref.serverID)
            return try realLocalMarkRead(ref)
        }

        fixture.viewModel.markSelectedRead()
        try await Task.sleep(for: .milliseconds(30))

        #expect(try fixture.store.messages(account: fixture.account, folder: "13").first?.isRead == true)
        #expect(fixture.viewModel.visibleMessages.first?.isRead == true,
                "the false transition must reload the stale list from the store")
        #expect(fixture.viewModel.markReadErrorText == nil)
        #expect(await write.calls.isEmpty, "a false 0→1 must not start a server write")
        #expect(!fixture.viewModel.canMarkSelectedRead, "the reloaded row is already read")
    }

    @Test("T-SCN-0014-02: repeated marks and other selections never write twice or leak")
    func manualMarkReadIsIdempotentAndSelectionScoped() async throws {
        let write = PresentationRecordingWriteGateway(delta: delta())
        let fixture = try makeMailboxFixture(
            messages: ["13": [
                presentationMessage("1", isRead: false),
                presentationMessage("2", isRead: false),
            ]],
            write: write
        )
        fixture.viewModel.loadCached()
        // The list auto-selects the newest row ("2"); explicitly start on "1".
        fixture.viewModel.select(messageID: "1")

        fixture.viewModel.markSelectedRead()
        try await waitForCalls(write, 1)
        fixture.viewModel.markSelectedRead()
        try await Task.sleep(for: .milliseconds(30))
        #expect(await write.calls.count == 1, "an already-read message must not write again")
        #expect(try fixture.store.messages(account: fixture.account, folder: "13").first { $0.serverID == "1" }?.isRead == true)
        #expect(try fixture.store.messages(account: fixture.account, folder: "13").first { $0.serverID == "2" }?.isRead == false)

        fixture.viewModel.select(messageID: "2")
        fixture.viewModel.markSelectedRead()
        try await waitForCalls(write, 2)
        #expect(try fixture.store.messages(account: fixture.account, folder: "13").allSatisfy(\.isRead))

        let calls = await write.calls.count
        fixture.viewModel.selectedListKey = nil
        fixture.viewModel.selection.messageID = nil
        fixture.viewModel.markSelectedRead()
        try await Task.sleep(for: .milliseconds(30))
        #expect(await write.calls.count == calls, "no selection means no local write and no network")
    }

    @Test("T-SCN-0014-02: a hidden selected row is a no-op for manual mark-read")
    func manualMarkReadHiddenRowIsNoOp() async throws {
        let write = PresentationRecordingWriteGateway(delta: delta())
        let fixture = try makeMailboxFixture(
            messages: ["13": [presentationMessage("1", isRead: false)]],
            write: write
        )
        fixture.viewModel.loadCached()
        let ref = MessageRef(folderID: "13", serverID: "1")
        #expect(fixture.viewModel.deletion.begin(ref))
        #expect(fixture.viewModel.selectedMessage == nil)

        fixture.viewModel.markSelectedRead()
        try await Task.sleep(for: .milliseconds(30))

        #expect(try fixture.store.messages(account: fixture.account, folder: "13").first?.isRead == false)
        #expect(await write.calls.isEmpty, "a hidden row must not start a local or server write")
        #expect(fixture.viewModel.markReadErrorText == nil)
    }

    @Test("T-SCN-0014-03: manual and automatic mark-read share one write")
    func manualMarkReadRacesDwellOnce() async throws {
        let sleeper = DwellSleeper()
        let write = PresentationRecordingWriteGateway(delta: delta())
        let fixture = try makeMailboxFixture(
            messages: ["13": [presentationMessage("1", isRead: false)]],
            write: write,
            dwellSleep: { duration in try await sleeper.sleep(duration) }
        )
        fixture.viewModel.loadCached()
        for _ in 0..<200 {
            if await sleeper.count == 1 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await sleeper.count == 1)

        fixture.viewModel.markSelectedRead()
        try await waitForCalls(write, 1)
        for _ in 0..<200 {
            if await sleeper.cancelled == 1 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        await sleeper.release()
        try await Task.sleep(for: .milliseconds(40))

        #expect(await sleeper.cancelled == 1, "the manual write cancels the automatic clock")
        #expect(await write.calls.count == 1, "only one 0→1 transition and one server write")
        #expect(try fixture.store.messages(account: fixture.account, folder: "13").first?.isRead == true)
    }

    @Test("T-SCN-0014-04: a failed write-back keeps the local read and stays silent")
    func manualMarkReadWriteBackFailureKeepsLocal() async throws {
        let write = PresentationRecordingWriteGateway(delta: delta())
        await write.setFailure(.offline)
        let fixture = try makeMailboxFixture(
            messages: ["13": [presentationMessage("1", isRead: false)]],
            write: write
        )
        fixture.viewModel.loadCached()

        fixture.viewModel.markSelectedRead()
        try await waitForCalls(write, 1)
        try await Task.sleep(for: .milliseconds(40))

        #expect(try fixture.store.messages(account: fixture.account, folder: "13").first?.isRead == true)
        #expect(fixture.viewModel.markReadErrorText == nil, "a server write failure is silent")
        #expect(fixture.viewModel.sync.phase == .idle)
    }

    @Test("T-SCN-0014-04: a 503 write-back keeps the local read and stays silent")
    func manualMarkReadThrottledWriteBackKeepsLocal() async throws {
        let write = PresentationRecordingWriteGateway(delta: delta())
        await write.setFailure(.throttled(seconds: nil))
        let fixture = try makeMailboxFixture(
            messages: ["13": [presentationMessage("1", isRead: false)]],
            write: write
        )
        fixture.viewModel.loadCached()

        fixture.viewModel.markSelectedRead()
        try await waitForCalls(write, 1)
        try await Task.sleep(for: .milliseconds(40))

        #expect(try fixture.store.messages(account: fixture.account, folder: "13").first?.isRead == true)
        #expect(fixture.viewModel.markReadErrorText == nil, "503 is a silent write-back failure")
        #expect(fixture.viewModel.sync.phase == .idle)
    }

    @Test("T-SCN-0014-05: a successful sync retires the mark-read warning")
    func successfulSyncClearsMarkReadError() async throws {
        let write = PresentationRecordingWriteGateway(delta: delta())
        let gateway = PresentationFakeGateway(
            folders: FolderListing(folders: [presentationInbox], syncKey: "1"),
            deltas: ["2": MessageDelta(added: [], changed: [], removedServerIDs: [], syncKey: "3", moreAvailable: false)]
        )
        let fixture = try makeMailboxFixture(
            gateway: gateway,
            messages: ["13": [presentationMessage("1", isRead: false)]],
            write: write
        )
        fixture.viewModel.loadCached()
        fixture.viewModel.localMarkRead = { _ in throw MailError.storage(reason: "磁盘写入失败") }

        fixture.viewModel.markSelectedRead()
        #expect(fixture.viewModel.markReadErrorText != nil)

        await fixture.viewModel.refresh()

        #expect(fixture.viewModel.sync.phase == .idle)
        #expect(fixture.viewModel.markReadErrorText == nil)
    }

    @Test("T-SCN-0014-04: a MailError local failure keeps the row unread and shows Chinese")
    func manualMarkReadLocalFailureReportsChinese() async throws {
        let write = PresentationRecordingWriteGateway(delta: delta())
        let fixture = try makeMailboxFixture(
            messages: ["13": [presentationMessage("1", isRead: false)]],
            write: write
        )
        fixture.viewModel.loadCached()
        fixture.viewModel.localMarkRead = { _ in throw MailError.storage(reason: "磁盘写入失败") }

        fixture.viewModel.markSelectedRead()

        #expect(fixture.viewModel.markReadErrorText == ErrorText.text(for: .storage(reason: "磁盘写入失败")))
        #expect(fixture.viewModel.markReadErrorText?.hasPrefix("本地存储失败") == true)
        #expect(try fixture.store.messages(account: fixture.account, folder: "13").first?.isRead == false)
        #expect(await write.calls.isEmpty, "a failed local write must not start a server write")

        // A repeated click after the local failure still treats the row as unread and does
        // not fall through to a server write; the Chinese error stays visible.
        fixture.viewModel.markSelectedRead()
        #expect(try fixture.store.messages(account: fixture.account, folder: "13").first?.isRead == false)
        #expect(await write.calls.isEmpty)
        #expect(fixture.viewModel.markReadErrorText?.hasPrefix("本地存储失败") == true)
    }

    @Test("T-SCN-0014-04: a non-MailError local failure is normalized before the UI")
    func manualMarkReadNonMailErrorReportsChinese() async throws {
        let write = PresentationRecordingWriteGateway(delta: delta())
        let fixture = try makeMailboxFixture(
            messages: ["13": [presentationMessage("1", isRead: false)]],
            write: write
        )
        fixture.viewModel.loadCached()
        fixture.viewModel.localMarkRead = { _ in throw MailStoreError.database("磁盘写入失败") }

        fixture.viewModel.markSelectedRead()

        #expect(fixture.viewModel.markReadErrorText?.hasPrefix("本地存储失败") == true)
        #expect(fixture.viewModel.markReadErrorText?.contains("磁盘写入失败") == true)
        #expect(try fixture.store.messages(account: fixture.account, folder: "13").first?.isRead == false)
        #expect(await write.calls.isEmpty)

        let second = try makeMailboxFixture(
            messages: ["13": [presentationMessage("1", isRead: false)]],
            write: write
        )
        second.viewModel.loadCached()
        second.viewModel.localMarkRead = { _ in throw NSError(domain: "test", code: 1) }
        second.viewModel.markSelectedRead()
        #expect(second.viewModel.markReadErrorText?.hasPrefix("本地存储失败") == true)
        #expect(try second.store.messages(account: second.account, folder: "13").first?.isRead == false)
    }

    @Test("F1: normalizeMarkReadError keeps MailError and wraps everything else as storage")
    func normalizeMarkReadErrorWrapsNonMailError() {
        #expect(MailboxViewModel.normalizeMarkReadError(MailError.offline) == .offline)
        #expect(MailboxViewModel.normalizeMarkReadError(MailError.authFailed) == .authFailed)

        let storeError = MailStoreError.database("磁盘写入失败")
        #expect(
            MailboxViewModel.normalizeMarkReadError(storeError)
                == .storage(reason: String(describing: storeError))
        )

        let cocoaError = NSError(domain: "test", code: 1)
        guard case .storage(let reason) = MailboxViewModel.normalizeMarkReadError(cocoaError) else {
            Issue.record("a non-MailError must be normalized to .storage")
            return
        }
        #expect(reason == String(describing: cocoaError))
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
        for _ in 0..<200 {
            if fixture.viewModel.body == .loaded(html: "<p>第一封正文</p>", truncated: false) { break }
            try await Task.sleep(for: .milliseconds(5))
        }

        #expect(Set(fixture.viewModel.visibleMessages.map(\.serverID)) == ["1", "2"])
        #expect(fixture.viewModel.selectedListKey == keyBefore)
        #expect(fixture.viewModel.deleteErrorText?.contains("网络") == true)
        #expect(try fixture.store.messages(account: fixture.account, folder: "13").count == 2)
    }

    @Test("T-SCN-0009-05: a successful sync retires the delete warning")
    func successfulSyncClearsDeleteError() async throws {
        let write = PresentationRecordingWriteGateway(delta: deleteDelta(removed: ["1"]))
        await write.setFailure(.offline)
        let gateway = PresentationFakeGateway(
            folders: FolderListing(folders: [presentationInbox], syncKey: "1"),
            deltas: ["2": MessageDelta(added: [], changed: [], removedServerIDs: [], syncKey: "3", moreAvailable: false)]
        )
        let fixture = try makeMailboxFixture(
            gateway: gateway,
            messages: ["13": [presentationMessage("1")]],
            write: write
        )
        fixture.viewModel.loadCached()

        await fixture.viewModel.deleteSelected()
        #expect(fixture.viewModel.deleteErrorText?.contains("网络") == true, "the failure is reported first")

        await fixture.viewModel.refresh()

        #expect(fixture.viewModel.sync.phase == .idle)
        #expect(
            fixture.viewModel.deleteErrorText == nil,
            "a healthy sync must not leave the old warning on the status bar"
        )
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

    @Test("T-SCN-0009-01: deleting a non-last row opens the next message's body")
    func deleteNonLastRowLoadsNextBody() async throws {
        let write = PresentationRecordingWriteGateway(delta: deleteDelta(removed: ["2"]))
        let fixture = try makeMailboxFixture(
            messages: ["13": [
                presentationMessage("1", subject: "第一封"),
                presentationMessage("2", subject: "第二封"),
            ]],
            write: write
        )
        try fixture.store.applyBody(account: fixture.account, folder: "13", serverID: "1", html: "<p>第一封正文</p>")
        try fixture.store.applyBody(account: fixture.account, folder: "13", serverID: "2", html: "<p>第二封正文</p>")
        fixture.viewModel.loadCached()
        for _ in 0..<200 {
            if fixture.viewModel.body == .loaded(html: "<p>第二封正文</p>", truncated: false) { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(fixture.viewModel.selection.messageID == "2")

        await fixture.viewModel.deleteSelected()
        for _ in 0..<200 {
            if fixture.viewModel.body == .loaded(html: "<p>第一封正文</p>", truncated: false) { break }
            try await Task.sleep(for: .milliseconds(5))
        }

        #expect(fixture.viewModel.selection.messageID == "1")
        #expect(fixture.viewModel.body == .loaded(html: "<p>第一封正文</p>", truncated: false))
        #expect(try fixture.store.messages(account: fixture.account, folder: "13").map(\.serverID) == ["1"])
    }

    @Test("T-SCN-0009-04: a failed delete restores the body and a retry then succeeds")
    func deleteFailureThenRetrySucceeds() async throws {
        let write = PresentationRecordingWriteGateway(delta: deleteDelta(removed: ["1"]))
        await write.setFailure(.offline)
        let fixture = try makeMailboxFixture(
            messages: ["13": [
                presentationMessage("1", subject: "第一封"),
                presentationMessage("2", subject: "第二封"),
            ]],
            write: write
        )
        try fixture.store.applyBody(account: fixture.account, folder: "13", serverID: "1", html: "<p>第一封正文</p>")
        try fixture.store.applyBody(account: fixture.account, folder: "13", serverID: "2", html: "<p>第二封正文</p>")
        fixture.viewModel.loadCached()
        fixture.viewModel.select(messageID: "1")
        for _ in 0..<200 {
            if fixture.viewModel.body == .loaded(html: "<p>第一封正文</p>", truncated: false) { break }
            try await Task.sleep(for: .milliseconds(5))
        }

        await fixture.viewModel.deleteSelected()
        for _ in 0..<200 {
            if fixture.viewModel.body == .loaded(html: "<p>第一封正文</p>", truncated: false) { break }
            try await Task.sleep(for: .milliseconds(5))
        }

        #expect(Set(fixture.viewModel.visibleMessages.map(\.serverID)) == ["1", "2"])
        #expect(fixture.viewModel.selection.messageID == "1")
        #expect(fixture.viewModel.body == .loaded(html: "<p>第一封正文</p>", truncated: false),
                "the failed delete must reopen the original body")
        #expect(fixture.viewModel.deleteErrorText?.contains("网络") == true)
        #expect(try fixture.store.messages(account: fixture.account, folder: "13").count == 2)

        await write.setFailure(nil)
        await fixture.viewModel.deleteSelected()

        #expect(fixture.viewModel.deleteErrorText == nil)
        #expect(try fixture.store.messages(account: fixture.account, folder: "13").map(\.serverID) == ["2"])
        #expect(await write.calls.count == 2, "the retry sends the delete again")
    }

    @Test("T-SCN-0009-03: a delete response with no removed id is still a successful not-found delete")
    func deleteNotFoundDeltaStillCommits() async throws {
        let write = PresentationRecordingWriteGateway(delta: MessageDelta(
            added: [], changed: [], removedServerIDs: [], syncKey: "3", moreAvailable: false
        ))
        let fixture = try makeMailboxFixture(
            messages: ["13": [presentationMessage("1"), presentationMessage("2")]],
            write: write
        )
        fixture.viewModel.loadCached()
        fixture.viewModel.select(messageID: "1")

        await fixture.viewModel.deleteSelected()

        #expect(fixture.viewModel.deleteErrorText == nil)
        #expect(try fixture.store.messages(account: fixture.account, folder: "13").map(\.serverID) == ["2"])
        #expect(try fixture.store.syncKey(account: fixture.account, collection: "13") == "3")
    }

    @Test("B5: a temporarily hidden row cannot be selected or opened")
    func hiddenRowCannotBeSelectedOrOpened() async throws {
        let fixture = try makeMailboxFixture(
            messages: ["13": [presentationMessage("1"), presentationMessage("2")]]
        )
        fixture.viewModel.loadCached()
        fixture.viewModel.select(messageID: "1")
        let ref = MessageRef(folderID: "13", serverID: "1")

        #expect(fixture.viewModel.deletion.begin(ref) == true)
        #expect(fixture.viewModel.visibleMessages.map(\.serverID) == ["2"])
        #expect(fixture.viewModel.selectedMessage == nil)
        #expect(fixture.viewModel.selectedRef == nil)

        // The compatibility path (`selection.messageID` only) is filtered too.
        fixture.viewModel.selectedListKey = nil
        fixture.viewModel.selection.messageID = "1"
        #expect(fixture.viewModel.selectedMessage == nil)

        fixture.viewModel.deletion.clearHidden(ref)
        #expect(fixture.viewModel.selectedMessage?.serverID == "1")
    }

}

/// A controllable sleeper that counts clock starts. A reload that incorrectly restarts the
/// dwell would request a second sleep. Virtual time can be advanced without releasing a
/// sleep whose full duration has not elapsed, so the 2-second switch negative case is real.
actor DwellSleeper {
    private(set) var count = 0
    private(set) var cancelled = 0
    private(set) var durations: [Duration] = []
    /// Continuations actually parked; `count` alone is set before the await, so tests
    /// that release the waiter must wait for this to be > 0.
    private(set) var pending = 0
    private var waiters: [UUID: CheckedContinuation<Void, Error>] = [:]
    private var elapsed: Duration = .zero
    private var deadlines: [UUID: Duration] = [:]

    func sleep(_ duration: Duration) async throws {
        count += 1
        durations.append(duration)
        let id = UUID()
        let deadline = elapsed + duration
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                pending += 1
                waiters[id] = continuation
                deadlines[id] = deadline
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    /// Advances virtual time and resumes exactly the sleeps whose deadline is reached.
    /// Advancing by 2 seconds therefore cannot release a 3-second dwell.
    func advance(by delta: Duration) {
        elapsed += delta
        let due = deadlines.filter { $0.value <= elapsed }.map(\.key)
        for id in due {
            deadlines.removeValue(forKey: id)
            guard let continuation = waiters.removeValue(forKey: id) else { continue }
            pending -= 1
            continuation.resume()
        }
    }

    func release() {
        let parked = waiters
        waiters.removeAll()
        deadlines.removeAll()
        pending = 0
        for (_, continuation) in parked { continuation.resume() }
    }

    private func cancel(_ id: UUID) {
        guard let continuation = waiters.removeValue(forKey: id) else { return }
        deadlines.removeValue(forKey: id)
        cancelled += 1
        pending -= 1
        continuation.resume(throwing: CancellationError())
    }
}

@Suite("MailboxViewModel calendar jump")
@MainActor
struct MailboxRevealTests {
    @Test("reveal switches to the invite's folder and selects it")
    func revealFromAnotherFolder() throws {
        let fixture = try makeMailboxFixture(
            folders: [presentationInbox, presentationDrafts],
            messages: ["13": [presentationMessage("invite-1", subject: "会议邀请")]]
        )
        fixture.viewModel.loadCached()
        fixture.viewModel.select(folderID: "4")
        #expect(fixture.viewModel.messages.isEmpty)

        let found = fixture.viewModel.reveal(folderID: "13", serverID: "invite-1")

        #expect(found)
        #expect(fixture.viewModel.selection.folderID == "13")
        #expect(fixture.viewModel.selectedMessage?.serverID == "invite-1")
        #expect(fixture.viewModel.selection.messageID == "invite-1")
    }

    @Test("reveal leaves search mode before selecting")
    func revealClearsSearch() async throws {
        let fixture = try makeMailboxFixture(
            folders: [presentationInbox],
            messages: ["13": [presentationMessage("invite-1", subject: "会议邀请")]]
        )
        fixture.viewModel.loadCached()
        await fixture.viewModel.search("会议")
        #expect(fixture.viewModel.selection.searchQuery == "会议")

        let found = fixture.viewModel.reveal(folderID: "13", serverID: "invite-1")

        #expect(found)
        #expect(fixture.viewModel.selection.searchQuery.isEmpty)
        #expect(fixture.viewModel.selectedMessage?.serverID == "invite-1")
    }

    @Test("reveal reports a message that is not in the loaded page")
    func revealMissing() throws {
        let fixture = try makeMailboxFixture(
            folders: [presentationInbox],
            messages: ["13": [presentationMessage("invite-1", subject: "会议邀请")]]
        )
        fixture.viewModel.loadCached()

        #expect(fixture.viewModel.reveal(folderID: "13", serverID: "gone") == false)
        #expect(fixture.viewModel.selectedMessage == nil)
    }
}
