import Foundation
import MailDomain
import MailStore
import Testing

@testable import Presentation

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
        let pending = try fixture.store.outbox.pendingOutbox(account: fixture.account)
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
        #expect(try fixture.store.outbox.pendingOutbox(account: fixture.account).isEmpty)
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
        #expect(try fixture.store.outbox.pendingOutbox(account: fixture.account).isEmpty)
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
        let pending = try fixture.store.outbox.pendingOutbox(account: fixture.account)
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
        let pending = try #require(try fixture.store.outbox.pendingOutbox(account: fixture.account).first)
        #expect(pending.bodyHTML == html)
        #expect(pending.body == "hello world", "the plain-text part is derived from the edited HTML")
    }

    // MARK: - Recipient suggestions (REQ-0022 / SCN-0017)

    private func makeAutocompleteCompose() throws -> (MailboxFixture, ComposeViewModel) {
        let fixture = try makeMailboxFixture(messages: ["13": [
            presentationMessage(
                "1",
                sender: "\"张三\" <zhang.san@corp.test>",
                recipients: "li.si@corp.test",
                receivedRaw: "2026-11-18T09:00:00Z"
            ),
            presentationMessage(
                "2",
                sender: "\"李四\" <li.si@corp.test>",
                receivedRaw: "2026-11-17T09:00:00Z"
            ),
            presentationMessage(
                "3",
                sender: "\"Alice\" <alice@corp.test>",
                receivedRaw: "2026-11-16T09:00:00Z"
            ),
            presentationMessage(
                "4",
                sender: "wang@corp.test",
                receivedRaw: "2026-11-15T09:00:00Z"
            ),
            presentationMessage(
                "5",
                sender: "jdoe@corp.test",
                receivedRaw: "2026-11-14T09:00:00Z"
            ),
        ]])
        return (fixture, fixture.viewModel.composeNew())
    }

    @Test("suggestions refresh with the trailing fragment and stay case-insensitive")
    func suggestionsRefreshWithFragment() throws {
        let (_, compose) = try makeAutocompleteCompose()
        compose.recipientFocusChanged(in: .to)

        compose.to = "zh"
        compose.recipientTextChanged(in: .to, caretAtEnd: true)
        #expect(
            compose.recipientSuggestions
                == [ContactAddress(name: "张三", address: "zhang.san@corp.test")]
        )

        compose.to = "zha"
        compose.recipientTextChanged(in: .to, caretAtEnd: true)
        #expect(compose.recipientSuggestions.map(\.address) == ["zhang.san@corp.test"])

        compose.to = "ALICE"
        compose.recipientTextChanged(in: .to, caretAtEnd: true)
        #expect(
            compose.recipientSuggestions
                == [ContactAddress(name: "Alice", address: "alice@corp.test")]
        )

        compose.to = "wang@"
        compose.recipientTextChanged(in: .to, caretAtEnd: true)
        #expect(
            compose.recipientSuggestions
                == [ContactAddress(name: nil, address: "wang@corp.test")]
        )
    }

    @Test("selection replaces only the trailing fragment")
    func selectionReplacesTailOnly() throws {
        let (_, compose) = try makeAutocompleteCompose()
        compose.to = "li.si@corp.test; zha"
        compose.cc = "alice@corp.test"
        compose.subject = "主题"
        compose.body = "正文"
        compose.recipientFocusChanged(in: .to)
        compose.recipientTextChanged(in: .to, caretAtEnd: true)

        #expect(compose.selectRecipientSuggestion(at: 0))

        #expect(compose.to == "li.si@corp.test; zhang.san@corp.test; ")
        #expect(compose.cc == "alice@corp.test")
        #expect(compose.subject == "主题")
        #expect(compose.body == "正文")
        #expect(compose.hasEdits)
        #expect(compose.recipientSuggestions.isEmpty)
    }

    @Test("Cc has its own fragment and does not disturb To")
    func ccIsIndependent() throws {
        let (_, compose) = try makeAutocompleteCompose()
        compose.to = "alice@corp.test; "
        compose.cc = "li"
        compose.recipientFocusChanged(in: .cc)
        compose.recipientTextChanged(in: .cc, caretAtEnd: true)

        #expect(compose.recipientSuggestions.map(\.address) == ["li.si@corp.test"])
        #expect(compose.selectRecipientSuggestion(at: 0))

        #expect(compose.to == "alice@corp.test; ")
        #expect(compose.cc == "li.si@corp.test; ")
    }

    @Test("the inserted address is pure ASCII and becomes the draft recipient")
    func selectionWritesPureAddressIntoDraft() async throws {
        let (fixture, compose) = try makeAutocompleteCompose()
        compose.to = "zha"
        compose.subject = "hi"
        compose.recipientFocusChanged(in: .to)
        compose.recipientTextChanged(in: .to, caretAtEnd: true)
        #expect(compose.selectRecipientSuggestion(at: 0))

        #expect(await compose.send())
        let pending = try #require(try fixture.store.outbox.pendingOutbox(account: fixture.account).first)
        #expect(pending.to == "zhang.san@corp.test;")
        #expect(!pending.to.contains("张三"))
    }

    @Test("the directory loads once per compose, not once per keystroke")
    func directoryLoadsOncePerCompose() throws {
        let (_, compose) = try makeAutocompleteCompose()
        compose.recipientFocusChanged(in: .to)
        #expect(compose.directoryLoadCount == 1)

        for text in ["z", "zh", "zha", "zhan"] {
            compose.to = text
            compose.recipientTextChanged(in: .to, caretAtEnd: true)
        }
        #expect(compose.directoryLoadCount == 1)

        compose.recipientFocusLost()
        compose.recipientFocusChanged(in: .cc)
        #expect(compose.directoryLoadCount == 1)
    }

    @Test("a caret in the middle hides suggestions and blocks insertion")
    func middleCaretHidesSuggestions() throws {
        let (_, compose) = try makeAutocompleteCompose()
        compose.to = "zh"
        compose.recipientFocusChanged(in: .to)
        compose.recipientTextChanged(in: .to, caretAtEnd: true)
        #expect(!compose.recipientSuggestions.isEmpty)

        compose.to = "zhang"
        compose.recipientTextChanged(in: .to, caretAtEnd: false)
        #expect(compose.recipientSuggestions.isEmpty)
        #expect(!compose.selectRecipientSuggestion(at: 0))
        #expect(compose.to == "zhang")

        compose.recipientCaretChanged(atEnd: false)
        #expect(compose.recipientSuggestions.isEmpty)
    }

    @Test("no row is highlighted by default, so Return cannot commit")
    func noDefaultHighlightSoReturnDoesNotCommit() throws {
        let (_, compose) = try makeAutocompleteCompose()
        compose.to = "zh"
        compose.recipientFocusChanged(in: .to)
        compose.recipientTextChanged(in: .to, caretAtEnd: true)

        #expect(compose.highlightedSuggestion == nil)
        #expect(!compose.selectHighlightedRecipientSuggestion())
        #expect(compose.to == "zh")

        compose.moveRecipientHighlight(by: 1)
        #expect(compose.highlightedSuggestion == 0)
        #expect(compose.selectHighlightedRecipientSuggestion())
        #expect(compose.to == "zhang.san@corp.test; ")
    }

    @Test("Escape dismisses suggestions and a blur clears them")
    func escapeDismissesAndBlurClears() throws {
        let (_, compose) = try makeAutocompleteCompose()
        compose.to = "zh"
        compose.recipientFocusChanged(in: .to)
        compose.recipientTextChanged(in: .to, caretAtEnd: true)
        #expect(!compose.recipientSuggestions.isEmpty)

        compose.dismissRecipientSuggestions()
        #expect(compose.recipientSuggestions.isEmpty)
        #expect(!compose.selectHighlightedRecipientSuggestion())

        compose.recipientTextChanged(in: .to, caretAtEnd: true)
        #expect(!compose.recipientSuggestions.isEmpty)
        compose.recipientFocusLost()
        #expect(compose.recipientSuggestions.isEmpty)
    }

    @Test("a filled address is not suggested again, in either field")
    func duplicateNotSuggested() throws {
        let (_, compose) = try makeAutocompleteCompose()
        compose.to = "zhang.san@corp.test; zha"
        compose.recipientFocusChanged(in: .to)
        compose.recipientTextChanged(in: .to, caretAtEnd: true)
        #expect(compose.recipientSuggestions.isEmpty, "zhang is already before the fragment")

        compose.to = "zha"
        compose.cc = "zhang.san@corp.test; "
        compose.recipientFocusChanged(in: .to)
        compose.recipientTextChanged(in: .to, caretAtEnd: true)
        #expect(compose.recipientSuggestions.isEmpty, "zhang is already in Cc")
    }

    @Test("rapid typing only ever exposes the latest fragment")
    func rapidTypingUsesLatestFragment() throws {
        let (_, compose) = try makeAutocompleteCompose()
        compose.recipientFocusChanged(in: .to)
        for text in ["z", "zh", "zha", "zzz"] {
            compose.to = text
            compose.recipientTextChanged(in: .to, caretAtEnd: true)
        }
        #expect(compose.recipientSuggestions.isEmpty)
        #expect(compose.directoryLoadCount == 1)
    }

    @Test("an empty trailing fragment never shows suggestions")
    func emptyFragmentHasNoSuggestions() throws {
        let (_, compose) = try makeAutocompleteCompose()
        compose.to = "li.si@corp.test;  "
        compose.recipientFocusChanged(in: .to)
        compose.recipientTextChanged(in: .to, caretAtEnd: true)
        #expect(compose.recipientSuggestions.isEmpty)

        compose.to = "   "
        compose.recipientTextChanged(in: .to, caretAtEnd: true)
        #expect(compose.recipientSuggestions.isEmpty)
    }

    @Test("highlight movement stops at both ends instead of wrapping")
    func highlightMovementClamps() throws {
        let (_, compose) = try makeAutocompleteCompose()
        compose.recipientFocusChanged(in: .to)
        compose.to = "corp"
        compose.recipientTextChanged(in: .to, caretAtEnd: true)
        #expect(compose.recipientSuggestions.count > 1)

        compose.moveRecipientHighlight(by: -1)
        #expect(compose.highlightedSuggestion == compose.recipientSuggestions.count - 1)
        compose.moveRecipientHighlight(by: 1)
        #expect(compose.highlightedSuggestion == compose.recipientSuggestions.count - 1)
        for _ in 0..<10 { compose.moveRecipientHighlight(by: -1) }
        #expect(compose.highlightedSuggestion == 0)
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

@Suite("Drafts")
@MainActor
struct DraftListTests {
    @Test("a draft opened from the list saves back into the same row")
    func reopenedDraftSavesInPlace() throws {
        let fixture = try makeMailboxFixture()
        let first = fixture.viewModel.composeNew()
        first.to = "a@b.c"
        first.subject = "草稿"
        first.body = "初稿"
        #expect(first.saveDraft())

        fixture.viewModel.loadDrafts()
        #expect(fixture.viewModel.drafts.count == 1)
        let record = try #require(fixture.viewModel.drafts.first)

        let reopened = fixture.viewModel.compose(draft: record)
        #expect(reopened.mode == .draft)
        #expect(reopened.draftID?.raw == record.id)
        #expect(reopened.statusText == nil, "a freshly reopened draft is not dirty or saved")

        reopened.subject = "改过"
        #expect(reopened.saveDraft())
        fixture.viewModel.loadDrafts()
        #expect(fixture.viewModel.drafts.count == 1, "saving again must not duplicate the draft")
        #expect(fixture.viewModel.drafts.first?.subject == "改过")
        #expect(try fixture.store.outbox.pendingOutbox(account: fixture.account).isEmpty)
    }

    @Test("sending an opened draft removes it from the list and queues one row")
    func sendingOpenedDraft() async throws {
        let fixture = try makeMailboxFixture()
        let first = fixture.viewModel.composeNew()
        first.to = "a@b.c"
        first.subject = "发我"
        first.body = "正文"
        #expect(first.saveDraft())
        fixture.viewModel.loadDrafts()
        let record = try #require(fixture.viewModel.drafts.first)

        let reopened = fixture.viewModel.compose(draft: record)
        let sent = await reopened.send()

        #expect(sent)
        #expect(reopened.status == .queued)
        fixture.viewModel.loadDrafts()
        #expect(fixture.viewModel.drafts.isEmpty)
        let pending = try fixture.store.outbox.pendingOutbox(account: fixture.account)
        #expect(pending.map(\.id) == [record.id])
    }

    @Test("a draft from another account is not listed")
    func draftsArePerAccount() throws {
        let fixture = try makeMailboxFixture()
        let other = try fixture.store.createAccount(
            NewAccount(displayName: "other", address: "o@corp.test", host: "mail.corp.test")
        )
        let first = fixture.viewModel.composeNew()
        first.to = "a@b.c"
        first.subject = "本机草稿"
        #expect(first.saveDraft())

        fixture.viewModel.loadDrafts()
        #expect(fixture.viewModel.drafts.count == 1)
        #expect(try fixture.store.outbox.drafts(account: other).isEmpty)
    }
}
