import Foundation
import MailDomain
import MailStore
import SyncEngine
import Testing

@testable import Scenes

@Suite("ReadScene inline images")
struct ReadSceneInlineImageTests {
    private let ref = MessageRef(folderID: "13", serverID: "m1")
    private let logo = MailDomain.Attachment(displayName: "logo.png", fileReference: "ref-logo")
    private let photo = MailDomain.Attachment(displayName: "photo.png", fileReference: "ref-photo")
    private let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x01])

    private func makeScene(
        store: MailStore,
        account: AccountID,
        gateway: FakeGateway,
        files: FakeAttachmentFiles
    ) -> ReadScene {
        let engine = SyncEngine(
            gateway: gateway, store: store, account: account,
            writeGateway: UnsupportedWriteGateway(), sleeper: { _ in }
        )
        return ReadScene(store: store, account: account, gateway: gateway, files: files, writeEngine: engine)
    }

    private func seeded(
        attachments: [MailDomain.Attachment],
        gateway: FakeGateway,
        files: FakeAttachmentFiles = FakeAttachmentFiles()
    ) throws -> ReadScene {
        let (store, account) = try seededReadStore()
        try store.applySyncBatch(
            account: account,
            folder: "13",
            added: [Message(serverID: "m1", attachments: attachments)],
            changed: [],
            removedServerIDs: [],
            syncKey: "2"
        )
        return makeScene(store: store, account: account, gateway: gateway, files: files)
    }

    private func occurrences(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    @Test("only referenced inline attachments are fetched and rewritten")
    func fetchesOnlyReferencedAttachments() async throws {
        let notes = MailDomain.Attachment(displayName: "notes.pdf", fileReference: "ref-notes")
        let files = FakeAttachmentFiles()
        let gateway = FakeGateway(attachmentPayloads: ["ref-logo": png, "ref-notes": Data("notes".utf8)])
        let scene = try seeded(attachments: [logo, notes], gateway: gateway, files: files)
        let html = "<p>hello</p><img src=\"cid:logo@test\"><p>tail</p>"

        let rendered = try #require(await scene.renderInlineImages(for: ref, html: html))

        #expect(rendered.contains("data:image/png;base64,"))
        #expect(!rendered.contains("cid:logo@test"))
        #expect(rendered.contains("<p>hello</p>"))
        #expect(rendered.contains("<p>tail</p>"))
        #expect(await gateway.calls == [.attachment(fileReference: "ref-logo")])
    }

    @Test("repeated references share one download and the disk cache serves a reopen")
    func reusesCachedFileAndSingleFlight() async throws {
        let files = FakeAttachmentFiles()
        let gateway = FakeGateway(attachmentPayloads: ["ref-logo": png])
        let scene = try seeded(attachments: [logo], gateway: gateway, files: files)
        let html = """
        <img src="cid:logo@test"><img src="cid:logo.png"><img src="cid:logo@test">
        """

        let first = try #require(await scene.renderInlineImages(for: ref, html: html))
        let second = try #require(await scene.renderInlineImages(for: ref, html: html))

        #expect(occurrences(of: "data:image/png;base64,", in: first) == 3)
        #expect(second == first)
        #expect(await gateway.attachmentCalls == 1)
        #expect(files.storeCalls == 1)
        #expect(files.cache["ref-logo"] != nil)
    }

    @Test("a failed fetch or non-image bytes skip only that image")
    func failedPayloadIsSkipped() async throws {
        let broken = MailDomain.Attachment(displayName: "broken.png", fileReference: "ref-broken")
        let failed = MailDomain.Attachment(displayName: "failed.png", fileReference: "ref-failed")
        let gateway = FakeGateway(
            attachmentPayloads: ["ref-logo": png, "ref-broken": Data("not an image".utf8)],
            attachmentFailures: ["ref-failed": .offline]
        )
        let scene = try seeded(attachments: [logo, broken, failed], gateway: gateway)
        let html = """
        <img src="cid:logo@test"><img src="cid:broken@test"><img src="cid:failed@test">
        """

        let rendered = try #require(await scene.renderInlineImages(for: ref, html: html))

        #expect(rendered.contains("data:image/png;base64,"))
        #expect(rendered.contains("cid:broken@test"))
        #expect(rendered.contains("cid:failed@test"))
        #expect(await gateway.attachmentCalls == 3)
    }

    @Test("an attachment over the 20 MB guard is skipped")
    func oversizedAttachmentIsSkipped() async throws {
        let oversized = MailDomain.Attachment(displayName: "huge.png", fileReference: "ref-huge")
        var huge = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        huge.append(Data(repeating: 0, count: 20 * 1024 * 1024))
        let gateway = FakeGateway(attachmentPayloads: ["ref-huge": huge])
        let scene = try seeded(attachments: [oversized], gateway: gateway)

        let rendered = await scene.renderInlineImages(for: ref, html: "<img src=\"cid:huge@test\">")

        #expect(rendered == nil)
        #expect(await gateway.attachmentCalls == 1)
    }

    @Test("cancellation stops before the next attachment and keeps no partial render")
    func cancellationStopsBetweenAttachments() async throws {
        let gate = AttachmentGate()
        let gateway = FakeGateway(
            attachmentPayloads: ["ref-logo": png, "ref-photo": png],
            attachmentGate: gate
        )
        let scene = try seeded(attachments: [logo, photo], gateway: gateway)
        let html = "<img src=\"cid:logo@test\"><img src=\"cid:photo@test\">"

        let task = Task { await scene.renderInlineImages(for: ref, html: html) }
        await gate.waitUntilWaiting()
        task.cancel()
        await gate.open()

        #expect(await task.value == nil)
        #expect(await gateway.attachmentCalls == 1)
    }
}
