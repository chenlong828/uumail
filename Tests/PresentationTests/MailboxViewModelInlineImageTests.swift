import Foundation
import MailDomain
import MailStore
import Scenes
import Testing

@testable import Presentation

@Suite("MailboxViewModel inline images")
@MainActor
struct MailboxViewModelInlineImageTests {
    private let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x01])
    private let rawA = "<p>正文 A</p><img src=\"cid:logo@test\">"
    private let rawB = "<p>正文 B</p>"

    private func message(_ id: String, attachments: [MailDomain.Attachment] = []) -> Message {
        Message(serverID: id, subject: id, folderID: "13", attachments: attachments)
    }

    private func makeFixture(
        messages: [Message],
        gateway: PresentationFakeGateway = PresentationFakeGateway(
            folders: FolderListing(folders: [presentationInbox], syncKey: "7")
        )
    ) throws -> MailboxFixture {
        try makeMailboxFixture(gateway: gateway, messages: ["13": messages])
    }

    private func seed(_ html: String, for id: String, in fixture: MailboxFixture) throws {
        try fixture.store.applyBody(account: fixture.account, folder: "13", serverID: id, html: html)
    }

    @Test("inline images set a render string but leave body and quote raw")
    func inlineImagesSetRenderHTMLWithoutTouchingBody() async throws {
        let gateway = PresentationFakeGateway(
            folders: FolderListing(folders: [presentationInbox], syncKey: "7")
        )
        gateway.attachmentPayloads = ["ref-logo": png]
        let logo = MailDomain.Attachment(displayName: "logo.png", fileReference: "ref-logo")
        let fixture = try makeFixture(messages: [message("1", attachments: [logo])], gateway: gateway)
        try seed(rawA, for: "1", in: fixture)

        fixture.viewModel.loadCached()
        await fixture.viewModel.openSelected()
        await fixture.viewModel.inlineImageTask?.value

        let rendered = try #require(fixture.viewModel.inlineImageHTML)
        #expect(rendered.contains("data:image/png;base64,"))
        #expect(!rendered.contains("cid:logo@test"))
        #expect(fixture.viewModel.body == .loaded(html: rawA, truncated: false))
        #expect(fixture.viewModel.quotableHTML == rawA)
        #expect(!(fixture.viewModel.quotableHTML ?? "").contains("data:"))
        #expect(gateway.attachmentCalls == 1)
    }

    @Test("a stale image render from the previous message is dropped")
    func switchingMessageDropsStaleInlineImages() async throws {
        let gateway = PresentationFakeGateway(
            folders: FolderListing(folders: [presentationInbox], syncKey: "7")
        )
        let gate = WriteGate()
        gateway.attachmentGate = gate
        gateway.attachmentPayloads = ["ref-logo": png]
        let logo = MailDomain.Attachment(displayName: "logo.png", fileReference: "ref-logo")
        let fixture = try makeFixture(
            messages: [message("1", attachments: [logo]), message("2")],
            gateway: gateway
        )
        try seed(rawA, for: "1", in: fixture)
        try seed(rawB, for: "2", in: fixture)

        fixture.viewModel.loadCached()
        await fixture.viewModel.openSelected()
        await gate.waitUntilWaiting()
        let stale = fixture.viewModel.inlineImageTask

        let secondKey = MailboxViewModel.listKey(for: message("2"))
        fixture.viewModel.select(listKey: secondKey)
        await fixture.viewModel.openSelected()
        #expect(fixture.viewModel.body == .loaded(html: rawB, truncated: false))
        #expect(fixture.viewModel.inlineImageHTML == nil)

        await gate.open()
        await stale?.value

        #expect(fixture.viewModel.inlineImageHTML == nil)
        #expect(fixture.viewModel.body == .loaded(html: rawB, truncated: false))
    }

    @Test("empty or failed payloads leave the raw HTML and do not retry")
    func emptyOrFailedPayloadsLeaveRawHTML() async throws {
        let gateway = PresentationFakeGateway(
            folders: FolderListing(folders: [presentationInbox], syncKey: "7")
        )
        gateway.attachmentPayloads = ["ref-broken": Data("not an image".utf8), "ref-empty": Data()]
        let broken = MailDomain.Attachment(displayName: "broken.png", fileReference: "ref-broken")
        let empty = MailDomain.Attachment(displayName: "empty.png", fileReference: "ref-empty")
        let raw = "<p>可读文字</p><img src=\"cid:broken@test\"><img src=\"cid:empty@test\">"
        let fixture = try makeFixture(messages: [message("1", attachments: [broken, empty])], gateway: gateway)
        try seed(raw, for: "1", in: fixture)

        fixture.viewModel.loadCached()
        await fixture.viewModel.openSelected()
        await fixture.viewModel.inlineImageTask?.value

        #expect(fixture.viewModel.inlineImageHTML == nil)
        #expect(fixture.viewModel.body == .loaded(html: raw, truncated: false))
        #expect(fixture.viewModel.bodyNotice == nil)
        #expect(gateway.attachmentCalls == 2)
    }

    @Test("the remote-image gate neither blocks nor reloads inline data URLs")
    func remoteGateDoesNotAffectInlineImages() async throws {
        let gateway = PresentationFakeGateway(
            folders: FolderListing(folders: [presentationInbox], syncKey: "7")
        )
        gateway.attachmentPayloads = ["ref-logo": png]
        let logo = MailDomain.Attachment(displayName: "logo.png", fileReference: "ref-logo")
        let fixture = try makeFixture(messages: [message("1", attachments: [logo])], gateway: gateway)
        try seed(rawA, for: "1", in: fixture)

        fixture.viewModel.loadCached()
        await fixture.viewModel.openSelected()
        await fixture.viewModel.inlineImageTask?.value
        let rendered = fixture.viewModel.inlineImageHTML

        #expect(fixture.viewModel.allowsRemoteContent == false)
        #expect(fixture.viewModel.canAllowRemoteContent)
        fixture.viewModel.setAllowsRemoteContent(true)

        #expect(fixture.viewModel.allowsRemoteContent)
        #expect(fixture.viewModel.inlineImageHTML == rendered)
        #expect(fixture.viewModel.body == .loaded(html: rawA, truncated: false))
        #expect(gateway.attachmentCalls == 1)

        fixture.viewModel.setAllowsRemoteContent(false)
        #expect(fixture.viewModel.allowsRemoteContent == false)
        #expect(fixture.viewModel.inlineImageHTML == rendered)
    }
}
