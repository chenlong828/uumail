import Foundation
import MailDomain
import MailStore
import Testing

import Presentation

@Suite("ComposeViewModel")
@MainActor
struct ComposeViewModelTests {
    @Test("sending enqueues and reports 已加入发件箱")
    func sendEnqueues() async throws {
        let fixture = try makeMailboxFixture()
        let compose = fixture.viewModel.composeNew()
        compose.to = "a@b.c"
        compose.subject = "hi"
        compose.body = "text"

        let sent = await compose.send()

        #expect(sent)
        #expect(compose.status == .queued)
        #expect(compose.statusText == "已加入发件箱")
        let pending = try fixture.store.pendingOutbox(account: fixture.account)
        #expect(pending.count == 1)
        #expect(pending.first?.subject == "hi")
        #expect(pending.first?.to == "a@b.c")
    }

    @Test("a failed send keeps the editor text and surfaces the error")
    func sendFailureKeepsText() async throws {
        let fixture = try makeMailboxFixture()
        let compose = fixture.viewModel.composeNew()
        compose.to = ""
        compose.body = "text"

        let sent = await compose.send()

        #expect(!sent)
        #expect(
            compose.status
                == .failed(ErrorText.text(for: .invalidInput(reason: "recipient is empty")))
        )
        #expect(compose.statusText == ErrorText.text(for: .invalidInput(reason: "recipient is empty")))
        #expect(compose.body == "text")
        #expect(compose.to.isEmpty)
        #expect(try fixture.store.pendingOutbox(account: fixture.account).isEmpty)
    }

    @Test("saving a draft never enqueues it")
    func saveDraft() throws {
        let fixture = try makeMailboxFixture()
        let compose = fixture.viewModel.composeNew()
        compose.to = "a@b.c"
        compose.subject = "draft"
        compose.body = "wip"

        let saved = compose.saveDraft()

        #expect(saved)
        #expect(compose.status == .saved)
        #expect(compose.statusText == "草稿已保存")
        #expect(try fixture.store.pendingOutbox(account: fixture.account).isEmpty)
    }

    @Test("reply prefills the sender, keeps a single Re: prefix and quotes the body")
    func replySeed() async throws {
        let message = presentationMessage(
            "1",
            subject: "Re: 周报",
            sender: "\"张三\" <zhang@corp.test>"
        )
        let fixture = try makeMailboxFixture(messages: ["13": [message]])
        try fixture.store.applyBody(
            account: fixture.account,
            folder: "13",
            serverID: "1",
            html: "<p>hello</p><p>world</p>"
        )
        fixture.viewModel.loadCached()
        await fixture.viewModel.openSelected()

        let reply = fixture.viewModel.composeReply()

        #expect(reply?.to == "zhang@corp.test")
        #expect(reply?.subject == "Re: 周报")
        #expect(reply?.body.contains("hello") == true)
        #expect(reply?.body.contains("写道：") == true)
        #expect(reply?.bodyHTML.contains("<p>hello</p>") == true)
        #expect(reply?.bodyHTML.lowercased().contains("<blockquote") == false)
    }

    @Test("forward prefixes Fwd: and does not address anyone")
    func forwardSeed() async throws {
        let fixture = try makeMailboxFixture(
            messages: ["13": [presentationMessage("1", subject: "周报")]]
        )
        try fixture.store.applyBody(
            account: fixture.account,
            folder: "13",
            serverID: "1",
            html: "<div>hi</div>"
        )
        fixture.viewModel.loadCached()
        await fixture.viewModel.openSelected()

        let forward = fixture.viewModel.composeForward()

        #expect(forward?.subject == "Fwd: 周报")
        #expect(forward?.to.isEmpty == true)
        #expect(forward?.canSend == false)
    }

    @Test("reply-all prefills To and Cc from the seed")
    func replyAllPrefillsToAndCc() throws {
        let fixture = try makeMailboxFixture()
        let message = presentationMessage(
            "1",
            subject: "周报",
            sender: "\"张三\" <z@corp.test>",
            recipients: "a@corp.test; b@corp.test",
            cc: "c@corp.test; b@corp.test"
        )

        let compose = ComposeViewModel(
            replyingAllTo: message,
            bodyHTML: "<p>hello</p>",
            scene: fixture.composeScene,
            account: fixture.account
        )

        #expect(compose.mode == .replyAll)
        #expect(compose.to == "z@corp.test; a@corp.test; b@corp.test")
        #expect(compose.cc == "c@corp.test", "b@ is already in To and must not repeat in Cc")
        #expect(compose.subject == "Re: 周报")
        #expect(compose.body.contains("hello"))
    }

    @Test("sending a reply-all carries To and Cc into the outbox row")
    func replyAllSendCarriesCcIntoOutbox() async throws {
        let fixture = try makeMailboxFixture()
        let message = presentationMessage(
            "1",
            subject: "周报",
            sender: "z@corp.test",
            recipients: "a@corp.test",
            cc: "c@corp.test"
        )
        let compose = ComposeViewModel(
            replyingAllTo: message,
            bodyHTML: nil,
            scene: fixture.composeScene,
            account: fixture.account
        )

        let sent = await compose.send()

        #expect(sent)
        #expect(compose.status == .queued)
        let pending = try fixture.store.pendingOutbox(account: fixture.account)
        #expect(pending.count == 1)
        #expect(pending.first?.to == "z@corp.test; a@corp.test")
        #expect(pending.first?.cc == "c@corp.test")
        #expect(fixture.gateway.sendCalls == 0, "sending only enqueues; the outbox pump delivers")
    }

    @Test("reply-all with an empty To cannot send until the user fills it")
    func replyAllEmptyToCannotSend() throws {
        let fixture = try makeMailboxFixture()
        let message = presentationMessage(
            "1",
            subject: "周报",
            sender: "JDOE@corp.test",
            recipients: "jdoe@corp.test",
            cc: "jdoe@corp.test"
        )
        let compose = ComposeViewModel(
            replyingAllTo: message,
            bodyHTML: nil,
            scene: fixture.composeScene,
            account: fixture.account
        )

        #expect(compose.to.isEmpty, "the account's own address is never re-added")
        #expect(compose.cc.isEmpty)
        #expect(compose.canSend == false)

        compose.to = "a@corp.test"
        #expect(compose.canSend)
    }

    @Test("sending an HTML draft stores both the HTML and a readable text alternative")
    func sendCarriesHTML() async throws {
        let fixture = try makeMailboxFixture()
        let compose = fixture.viewModel.composeNew()
        compose.to = "a@b.c"
        compose.subject = "hi"
        let html = "<!DOCTYPE html><html><body><p>hello <b>world</b></p></body></html>"
        compose.editorDidLoad(html)
        compose.setEditorHTML(html)

        #expect(await compose.send())
        let pending = try #require(try fixture.store.pendingOutbox(account: fixture.account).first)
        #expect(pending.bodyHTML == html)
        #expect(pending.body == "hello world", "the plain-text part is derived from the edited HTML")
    }

    @Test("cancel compares against the editor's normalised baseline, not the seed string")
    func cancelBaseline() throws {
        let fixture = try makeMailboxFixture()
        let compose = fixture.viewModel.composeNew()
        #expect(!compose.hasEdits)

        let empty = "<!DOCTYPE html><html><body><div><br></div></body></html>"
        compose.editorDidLoad(empty)
        #expect(!compose.hasEdits)

        compose.setEditorHTML("<!DOCTYPE html><html><body><div>hi</div></body></html>")
        #expect(compose.hasEdits)

        compose.setEditorHTML(empty)
        #expect(!compose.hasEdits)

        compose.to = "a@b.c"
        #expect(compose.hasEdits, "an address change is an edit too")
    }

    @Test("a freshly opened reply is not dirty after the editor normalises its HTML")
    func replyNormalisedSeedIsNotDirty() throws {
        let fixture = try makeMailboxFixture()
        let message = presentationMessage("1", subject: "周报", sender: "z@corp.test")
        let reply = ComposeViewModel(
            replyTo: message,
            bodyHTML: "<p>hello</p>",
            scene: fixture.composeScene,
            account: fixture.account
        )

        let editor = ComposeDocument.editorDocument(emailHTML: reply.bodyHTML, allowRemoteContent: false)
        reply.editorDidLoad(ComposeDocument.emailHTML(fromEditorDocument: editor))

        #expect(!reply.hasEdits)
        reply.setEditorHTML(reply.bodyHTML + "<p>more</p>")
        #expect(reply.hasEdits)
    }
}
