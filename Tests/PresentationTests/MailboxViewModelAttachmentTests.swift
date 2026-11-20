import Foundation
import MailDomain
import MailStore
import Scenes
import Testing

@testable import Presentation

@Suite("MailboxViewModel attachment downloads")
@MainActor
struct MailboxViewModelAttachmentTests {
    private let attachmentA = MailDomain.Attachment(displayName: "报表.pdf", fileReference: "ref-a")
    private let attachmentB = MailDomain.Attachment(displayName: "合同.pdf", fileReference: "ref-b")

    private func message(_ id: String, attachments: [MailDomain.Attachment] = []) -> Message {
        Message(serverID: id, subject: id, folderID: "13", attachments: attachments)
    }

    private func listKey(_ id: String) -> String {
        MailboxViewModel.listKey(for: message(id))
    }

    private func makeFixture(
        messages: [Message],
        gateway: PresentationFakeGateway = PresentationFakeGateway(
            folders: FolderListing(folders: [presentationInbox], syncKey: "7")
        ),
        files: PresentationFakeAttachmentFiles = PresentationFakeAttachmentFiles()
    ) throws -> MailboxFixture {
        let fixture = try makeMailboxFixture(
            gateway: gateway,
            messages: ["13": messages],
            files: files
        )
        fixture.viewModel.loadCached()
        // The local list order is not part of this contract; pin the selected message.
        fixture.viewModel.select(listKey: listKey("1"))
        return fixture
    }

    private func cachedURL(_ fixture: MailboxFixture, _ attachment: MailDomain.Attachment) throws -> URL {
        let reference = AttachmentRef(
            fileReference: attachment.fileReference,
            displayName: attachment.displayName
        )
        return try fixture.files.store(Data("cached".utf8), for: reference)
    }

    private func storedCachePath(_ fixture: MailboxFixture, messageID: String) throws -> String? {
        try fixture.store.attachments(account: fixture.account, folder: "13", messageID: messageID)
            .first?.cachePath
    }

    @Test("T-SCN-0020-01a: a cached attachment returns the URL with zero gateway calls")
    func cachedAttachmentSkipsGateway() async throws {
        let fixture = try makeFixture(messages: [message("1", attachments: [attachmentA])])
        let cached = try cachedURL(fixture, attachmentA)

        let url = await fixture.viewModel.download(attachmentA)

        #expect(url == cached)
        #expect(fixture.gateway.attachmentCalls == 0)
        #expect(fixture.viewModel.attachmentErrorText == nil)
    }

    @Test("T-SCN-0020-01b: a miss fetches, stores and records the cache path once")
    func missFetchesStoresAndMarksOnce() async throws {
        let gateway = PresentationFakeGateway(
            folders: FolderListing(folders: [presentationInbox], syncKey: "7")
        )
        gateway.attachmentPayloads = ["ref-a": Data("payload".utf8)]
        let fixture = try makeFixture(
            messages: [message("1", attachments: [attachmentA])],
            gateway: gateway
        )

        let url = try #require(await fixture.viewModel.download(attachmentA))

        #expect(fixture.gateway.attachmentCalls == 1)
        #expect(fixture.files.storeCalls == 1)
        #expect(try Data(contentsOf: url) == Data("payload".utf8))
        #expect(try storedCachePath(fixture, messageID: "1") == url.path)
        #expect(fixture.viewModel.attachmentErrorText == nil)
    }

    @Test("T-SCN-0020-01c: offline maps to the shared ErrorText and returns nil")
    func offlineWritesErrorText() async throws {
        let gateway = PresentationFakeGateway(
            folders: FolderListing(folders: [presentationInbox], syncKey: "7")
        )
        gateway.attachmentError = .offline
        let fixture = try makeFixture(
            messages: [message("1", attachments: [attachmentA])],
            gateway: gateway
        )

        let url = await fixture.viewModel.download(attachmentA)

        #expect(url == nil)
        #expect(fixture.viewModel.attachmentErrorText == ErrorText.text(for: .offline))
    }

    @Test("T-SCN-0020-01d: a non-MailError storage failure becomes the storage Chinese text")
    func rawStoreErrorBecomesStorageText() async throws {
        let gateway = PresentationFakeGateway(
            folders: FolderListing(folders: [presentationInbox], syncKey: "7")
        )
        gateway.attachmentPayloads = ["ref-a": Data("payload".utf8)]
        let files = PresentationFakeAttachmentFiles()
        files.storeError = NSError(
            domain: "uumail.test",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "磁盘已满"]
        )
        let fixture = try makeFixture(
            messages: [message("1", attachments: [attachmentA])],
            gateway: gateway,
            files: files
        )

        let url = await fixture.viewModel.download(attachmentA)

        #expect(url == nil)
        let text = try #require(fixture.viewModel.attachmentErrorText)
        #expect(text.hasPrefix("本地存储失败："))
        #expect(text.contains("磁盘已满"))
    }

    @Test("T-SCN-0020-01e: success clears the text; a selection change clears it; same-key reload does not")
    func errorTextClearsOnSuccessAndSelectionChange() async throws {
        let gateway = PresentationFakeGateway(
            folders: FolderListing(folders: [presentationInbox], syncKey: "7")
        )
        gateway.attachmentError = .offline
        let fixture = try makeFixture(
            messages: [message("1", attachments: [attachmentA]), message("2", attachments: [attachmentB])],
            gateway: gateway
        )

        _ = await fixture.viewModel.download(attachmentA)
        #expect(fixture.viewModel.attachmentErrorText == ErrorText.text(for: .offline))

        // A same-key reload is not a selection change and must keep the text.
        fixture.viewModel.loadCached()
        #expect(fixture.viewModel.attachmentErrorText == ErrorText.text(for: .offline))

        gateway.attachmentError = nil
        gateway.attachmentPayloads = ["ref-a": Data("payload".utf8)]
        _ = try #require(await fixture.viewModel.download(attachmentA))
        #expect(fixture.viewModel.attachmentErrorText == nil)

        gateway.attachmentError = .offline
        _ = await fixture.viewModel.download(attachmentB)
        #expect(fixture.viewModel.attachmentErrorText == ErrorText.text(for: .offline))
        fixture.viewModel.select(listKey: listKey("2"))
        #expect(fixture.viewModel.attachmentErrorText == nil)
    }

    @Test("T-SCN-0020-01f: an A download finishing after a switch to B does not write B")
    func lateFailureAfterSwitchDoesNotWrite() async throws {
        let gateway = PresentationFakeGateway(
            folders: FolderListing(folders: [presentationInbox], syncKey: "7")
        )
        let gate = WriteGate()
        gateway.attachmentGate = gate
        gateway.attachmentError = .offline
        let fixture = try makeFixture(
            messages: [message("1", attachments: [attachmentA]), message("2", attachments: [attachmentB])],
            gateway: gateway
        )
        fixture.viewModel.select(listKey: listKey("1"))

        let task = Task { await fixture.viewModel.download(attachmentA) }
        await gate.waitUntilWaiting()
        fixture.viewModel.select(listKey: listKey("2"))
        fixture.viewModel.attachmentErrorText = "B 自己的错误"
        await gate.open()

        let url = await task.value
        #expect(url == nil)
        #expect(fixture.viewModel.attachmentErrorText == "B 自己的错误")
    }

    @Test("T-SCN-0020-01f: an A success finishing after a switch to B does not clear B")
    func lateSuccessAfterSwitchDoesNotClear() async throws {
        let gateway = PresentationFakeGateway(
            folders: FolderListing(folders: [presentationInbox], syncKey: "7")
        )
        let gate = WriteGate()
        gateway.attachmentGate = gate
        gateway.attachmentPayloads = ["ref-a": Data("payload".utf8)]
        let fixture = try makeFixture(
            messages: [message("1", attachments: [attachmentA]), message("2", attachments: [attachmentB])],
            gateway: gateway
        )
        fixture.viewModel.select(listKey: listKey("1"))

        let task = Task { await fixture.viewModel.download(attachmentA) }
        await gate.waitUntilWaiting()
        fixture.viewModel.select(listKey: listKey("2"))
        fixture.viewModel.attachmentErrorText = "B 自己的错误"
        await gate.open()

        let url = await task.value
        #expect(url == nil)
        #expect(fixture.viewModel.attachmentErrorText == "B 自己的错误")
    }

    @Test("T-SCN-0020-01f: A to B to A still drops the old generation")
    func roundTripSelectionStillDropsResult() async throws {
        let gateway = PresentationFakeGateway(
            folders: FolderListing(folders: [presentationInbox], syncKey: "7")
        )
        let gate = WriteGate()
        gateway.attachmentGate = gate
        gateway.attachmentPayloads = ["ref-a": Data("payload".utf8)]
        let fixture = try makeFixture(
            messages: [message("1", attachments: [attachmentA]), message("2", attachments: [attachmentB])],
            gateway: gateway
        )
        fixture.viewModel.select(listKey: listKey("1"))

        let task = Task { await fixture.viewModel.download(attachmentA) }
        await gate.waitUntilWaiting()
        fixture.viewModel.select(listKey: listKey("2"))
        fixture.viewModel.select(listKey: listKey("1"))
        fixture.viewModel.attachmentErrorText = "A 新会话的错误"
        await gate.open()

        let url = await task.value
        #expect(url == nil)
        #expect(fixture.viewModel.attachmentErrorText == "A 新会话的错误")
    }

    @Test("T-SCN-0020-01f: the current selection still writes its own failure normally")
    func currentSelectionFailureStillWrites() async throws {
        let gateway = PresentationFakeGateway(
            folders: FolderListing(folders: [presentationInbox], syncKey: "7")
        )
        gateway.attachmentError = .offline
        let fixture = try makeFixture(messages: [message("1", attachments: [attachmentA])], gateway: gateway)

        let url = await fixture.viewModel.download(attachmentA)

        #expect(url == nil)
        #expect(fixture.viewModel.attachmentErrorText == ErrorText.text(for: .offline))
    }

    @Test("T-SCN-0020-01g: cancelling the caller during download writes and clears nothing")
    func cancelledCallerWritesNothing() async throws {
        let gateway = PresentationFakeGateway(
            folders: FolderListing(folders: [presentationInbox], syncKey: "7")
        )
        let gate = WriteGate()
        gateway.attachmentGate = gate
        gateway.attachmentError = .offline
        let fixture = try makeFixture(messages: [message("1", attachments: [attachmentA])], gateway: gateway)
        fixture.viewModel.attachmentErrorText = "既有错误"

        let task = Task { await fixture.viewModel.download(attachmentA) }
        await gate.waitUntilWaiting()
        task.cancel()
        await gate.open()

        let url = await task.value
        #expect(url == nil)
        #expect(fixture.viewModel.attachmentErrorText == "既有错误")

        // An un-cancelled current selection still surfaces its failure.
        gateway.attachmentGate = nil
        let second = await fixture.viewModel.download(attachmentA)
        #expect(second == nil)
        #expect(fixture.viewModel.attachmentErrorText == ErrorText.text(for: .offline))
    }
}
