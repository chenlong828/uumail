import Foundation
import MailDomain
import Scenes
import Testing

@testable import Presentation

@Suite("ReaderRouter (SCN-0025)")
@MainActor
struct ReaderRouterTests {
    private let geometry = ReaderGeometry(readingPaneWidth: 640, windowHeight: 800, screenHeight: 1200)

    @Test("default size is reading-pane width by 85% of the window height, floored and capped")
    func sizeRule() {
        let size = ReaderRouter.readerSize(for: geometry)
        #expect(size.width == 640)
        #expect(abs(size.height - 680) < 0.5) // 800 * 0.85

        let narrow = ReaderRouter.readerSize(
            for: ReaderGeometry(readingPaneWidth: 320, windowHeight: 400, screenHeight: 1200)
        )
        #expect(narrow.width == 480)
        #expect(narrow.height == 460)

        let tall = ReaderRouter.readerSize(
            for: ReaderGeometry(readingPaneWidth: 700, windowHeight: 2000, screenHeight: 900)
        )
        #expect(tall.height == 900)
    }

    @Test("first open creates, the next one replaces, and composing refuses to replace")
    func stateMachine() throws {
        let router = ReaderRouter()
        let first = MessageRef(folderID: "13", serverID: "m1")
        let second = MessageRef(folderID: "13", serverID: "m2")

        #expect(router.open(first, geometry: geometry) == .created)
        #expect(router.currentRef == first)
        #expect(router.targetSize == ReaderRouter.readerSize(for: geometry))

        #expect(router.open(second, geometry: geometry) == .replaced)
        #expect(router.currentRef == second)

        router.beginComposing()
        #expect(router.open(first, geometry: geometry) == .blocked)
        #expect(router.currentRef == second, "a draft must not be replaced")
        #expect(router.blockedNotice == "正在撰写中，请先取消或发送")

        router.endComposing()
        #expect(router.blockedNotice == nil)
        #expect(router.open(first, geometry: geometry) == .replaced)

        router.reset()
        #expect(router.currentRef == nil)
        #expect(router.open(second, geometry: geometry) == .created)
    }
}

@Suite("ReaderViewModel (SCN-0025)")
@MainActor
struct ReaderViewModelTests {
    private func iso(daysAgo: Double) -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: Date().addingTimeInterval(-daysAgo * 86_400))
    }

    private func makeFixture(
        read: Bool = false,
        bodyPreview: String? = nil
    ) throws -> (MailboxFixture, MessageRef) {
        let message = presentationMessage(
            "m1",
            subject: "季度评审",
            sender: "\"王权英\" <wangqy@corp.test>",
            recipients: "jdoe@corp.test",
            receivedRaw: iso(daysAgo: 1),
            preview: bodyPreview,
            isRead: read
        )
        let fixture = try makeMailboxFixture(messages: ["13": [message]])
        return (fixture, MessageRef(folderID: "13", serverID: "m1"))
    }

    @Test("loading a cached message fills header, body and marks it read once")
    func loadCachedMessage() async throws {
        let (fixture, ref) = try makeFixture()
        try fixture.store.applyBody(account: fixture.account, folder: "13", serverID: "m1",
                                    html: "<p>正文</p>")
        let reader = fixture.viewModel.makeReader()
        var readChanged = 0
        reader.onReadChanged = { readChanged += 1 }

        await reader.load(ref)

        #expect(reader.isMissing == false)
        #expect(reader.header?.subject == "季度评审")
        #expect(reader.body == .loaded(html: "<p>正文</p>", truncated: false))
        #expect(reader.bodyNotice == nil)
        #expect(reader.markReadErrorText == nil)
        #expect(reader.allowsRemoteContent, "the reader loads remote images by default (REQ-0031)")
        #expect(reader.message?.isRead == true)
        #expect(readChanged == 1)
        #expect(try fixture.store.message(account: fixture.account, folder: "13", serverID: "m1")?.isRead == true)
    }

    @Test("a deleted ref reports missing and cannot compose")
    func missingRef() async throws {
        let (fixture, _) = try makeFixture()
        let reader = fixture.viewModel.makeReader()

        await reader.load(MessageRef(folderID: "13", serverID: "gone"))

        #expect(reader.isMissing)
        #expect(reader.canCompose == false)
        #expect(reader.body == .none)
        reader.composeReply()
        #expect(reader.compose == nil)
    }

    @Test("reply seeds the composer from this window's message, not the mailbox selection")
    func replySeed() async throws {
        let (fixture, ref) = try makeFixture()
        try fixture.store.applyBody(account: fixture.account, folder: "13", serverID: "m1",
                                    html: "<p>原文</p>")
        let reader = fixture.viewModel.makeReader()
        await reader.load(ref)

        reader.composeReply()

        let compose = try #require(reader.compose)
        #expect(compose.to.contains("wangqy@corp.test"))
        #expect(compose.subject.hasPrefix("Re:"))
        #expect(compose.bodyHTML.contains("原文"))
        reader.endComposing()
        #expect(reader.compose == nil)
    }

    @Test("a sync preview is never quotable and the reader exposes it as a notice")
    func previewIsNotQuoted() async throws {
        let (fixture, ref) = try makeFixture(bodyPreview: "预览一行")
        let reader = fixture.viewModel.makeReader()

        await reader.load(ref)

        #expect(reader.bodyNotice != nil, "a preview on screen is always visible as a notice")
        #expect(reader.quotableHTML == nil)
    }
}

@Suite("Mailbox list window (SCN-0026)")
@MainActor
struct MailboxListWindowTests {
    private func iso(daysAgo: Double) -> String {
        ISO8601DateFormatter().string(from: Date().addingTimeInterval(-daysAgo * 86_400))
    }

    @Test("the default window is 30 natural days back from now")
    func windowStartMath() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = try #require(ISO8601DateFormatter().date(from: "2026-11-24T08:00:00Z"))
        let start = MailboxViewModel.listWindowStart(now: now, calendar: calendar)
        let expected = try #require(calendar.date(byAdding: .day, value: -30, to: calendar.startOfDay(for: now)))
        #expect(start == expected)
    }

    @Test("the list shows the whole 30-day window, not the old 200-row page")
    func listUsesWindow() async throws {
        var messages: [Message] = []
        // 240 rows inside the window and 10 older ones.
        for index in 0..<240 {
            messages.append(presentationMessage("in\(index)", subject: "窗口内 \(index)",
                                              receivedRaw: iso(daysAgo: Double(index % 20) + 1)))
        }
        for index in 0..<10 {
            messages.append(presentationMessage("out\(index)", subject: "窗口外 \(index)",
                                              receivedRaw: iso(daysAgo: 40 + Double(index))))
        }
        let fixture = try makeMailboxFixture(messages: ["13": messages])
        fixture.viewModel.select(folderID: "13")

        fixture.viewModel.reloadListAfterExternalChange()

        #expect(fixture.viewModel.messages.count == 240)
        #expect(fixture.viewModel.visibleMessages.count == 240)
        #expect(fixture.viewModel.messages.allSatisfy { !($0.subject ?? "").hasPrefix("窗口外") })
    }

    @Test("an empty folder keeps the existing empty list")
    func emptyFolder() async throws {
        let fixture = try makeMailboxFixture()
        fixture.viewModel.select(folderID: "13")

        fixture.viewModel.reloadListAfterExternalChange()

        #expect(fixture.viewModel.messages.isEmpty)
        #expect(fixture.viewModel.visibleMessages.isEmpty)
    }

    @Test("30-day-old mail is excluded while the boundary day is kept")
    func boundary() async throws {
        let kept = presentationMessage("kept", receivedRaw: iso(daysAgo: 29.5))
        let dropped = presentationMessage("dropped", receivedRaw: iso(daysAgo: 31))
        let fixture = try makeMailboxFixture(messages: ["13": [kept, dropped]])
        fixture.viewModel.select(folderID: "13")

        fixture.viewModel.reloadListAfterExternalChange()

        #expect(fixture.viewModel.messages.map { $0.serverID } == ["kept"])
    }
}
