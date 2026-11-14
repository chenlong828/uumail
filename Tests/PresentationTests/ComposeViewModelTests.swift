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
        #expect(reply?.body.contains("原邮件") == true)
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
}
