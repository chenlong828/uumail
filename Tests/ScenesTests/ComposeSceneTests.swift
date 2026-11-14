import Foundation
import MailDomain
import MailStore
import Outbox
import Testing

@testable import Scenes

@Suite("ComposeScene")
struct ComposeSceneTests {
    private func makeScene(
        accountAddress: String = "jdoe@corp.test"
    ) throws -> (ComposeScene, MailStore, AccountID, FakeGateway) {
        let store = try MailStore.inMemory()
        let account = try store.createAccount(
            NewAccount(displayName: "jdoe", address: accountAddress, host: "mail.corp.test")
        )
        let gateway = FakeGateway()
        let outbox = Outbox(store: store, gateway: gateway, clock: FixedClock())
        return (ComposeScene(store: store, outbox: outbox), store, account, gateway)
    }

    @Test("send enqueues locally and returns immediately without touching the network")
    func sendEnqueuesImmediately() async throws {
        let (scene, store, account, gateway) = try makeScene()

        let id = try await scene.send(
            Draft(to: " a@b.c ", cc: nil, subject: "hi", body: "text"),
            account: account
        )

        #expect(await gateway.sendCalls == 0, "send must not wait for delivery")
        let stored = try store.outboxItem(account: account, id: id)
        #expect(stored?.to == "a@b.c", "the recipient is trimmed")
        #expect(stored?.state == "queued")

        let pending = try await scene.pending(account: account)
        #expect(pending.map(\.id) == [id.raw])
    }

    @Test("an empty recipient is rejected before anything is enqueued")
    func rejectsEmptyRecipient() async throws {
        let (scene, store, account, _) = try makeScene()

        await expectMailError(.invalidInput(reason: "recipient is empty")) {
            _ = try await scene.send(
                Draft(to: "   ", cc: nil, subject: "hi", body: "text"),
                account: account
            )
        }

        #expect(try store.pendingOutbox(account: account).isEmpty)
    }

    @Test("saveDraft stores a draft row that is never queued")
    func saveDraftDoesNotQueue() async throws {
        let (scene, store, account, gateway) = try makeScene()

        let id = try scene.saveDraft(
            Draft(to: "", cc: nil, subject: "未写完", body: "草稿正文"),
            account: account
        )

        #expect(try store.outboxItem(account: account, id: id)?.state == "draft")
        let pending = try await scene.pending(account: account)
        #expect(pending.isEmpty)
        #expect(await gateway.sendCalls == 0)
    }

    @Test("reply seed uses Re:, the sender address and the quote marker")
    func replySeedRules() throws {
        let scene = try makeSceneWithoutStore()
        let message = Message(serverID: "m1", subject: "周报", sender: "\"张三\" <z@corp.com>")

        let draft = scene.replySeed(to: message, bodyHTML: "<p>第一行<br>第二行</p>")

        #expect(draft.to == "z@corp.com")
        #expect(draft.subject == "Re: 周报")
        #expect(draft.body == "\n\n--- 原邮件 ---\n第一行\n第二行")
    }

    @Test("forward seed uses Fwd: and keeps the message body quoted")
    func forwardSeedRules() throws {
        let scene = try makeSceneWithoutStore()
        let message = Message(serverID: "m1", subject: "Re: 周报", sender: "z@corp.com")

        let draft = scene.forwardSeed(from: message, bodyHTML: "<div>原文</div>")

        #expect(draft.to.isEmpty, "forward starts without a recipient")
        #expect(draft.subject == "Fwd: Re: 周报")
        #expect(draft.body == "\n\n--- 转发邮件 ---\n原文")
    }

    @Test("existing prefixes and empty subjects follow the old rules")
    func subjectRules() throws {
        let scene = try makeSceneWithoutStore()

        let alreadyReplied = scene.replySeed(
            to: Message(serverID: "m1", subject: "RE: 周报", sender: "z@corp.com"),
            bodyHTML: nil
        )
        #expect(alreadyReplied.subject == "RE: 周报")

        let noSubject = scene.replySeed(
            to: Message(serverID: "m1", subject: nil, sender: nil),
            bodyHTML: nil
        )
        #expect(noSubject.subject == "Re: (无主题)")
        #expect(noSubject.to.isEmpty)
        #expect(noSubject.body == "\n\n--- 原邮件 ---\n")
    }

    @Test("replyAll seeds the sender and original To/Cc, deduplicated and excluding the account")
    func replyAllFillsSenderAndOriginalRecipients() throws {
        let (scene, _, account, _) = try makeScene(accountAddress: "me@corp.test")
        let message = Message(
            serverID: "m1",
            subject: "周报",
            sender: "\"张三\" <z@corp.test>",
            recipients: "a@corp.test; b@corp.test",
            cc: "c@corp.test; z@corp.test"
        )

        let draft = scene.replyAllSeed(
            to: message,
            bodyHTML: "<p>第一行<br>第二行</p>",
            account: account
        )

        #expect(draft.to == "z@corp.test; a@corp.test; b@corp.test")
        #expect(draft.cc == "c@corp.test", "z@ is already in To and must not repeat in Cc")
        #expect(draft.subject == "Re: 周报")
        #expect(draft.body == "\n\n--- 原邮件 ---\n第一行\n第二行")
    }

    @Test("replyAll reads the Cc written by the post-migration backfill")
    func replyAllUsesBackfilledCc() throws {
        let (scene, store, account, _) = try makeScene(accountAddress: "me@corp.test")
        try store.applyFolderSnapshot(
            account: account,
            folders: [Folder(serverID: "13", parentID: nil, displayName: "收件箱", type: 2)],
            syncKey: "folders-key"
        )
        try store.applySyncBatch(
            account: account,
            folder: "13",
            added: [
                MailMessage(
                    serverID: "101",
                    subject: "旧邮件",
                    sender: "z@corp.test",
                    recipients: "a@corp.test",
                    receivedRaw: "2026-11-08T05:11:18.000Z",
                    cc: "c@corp.test"
                )
            ],
            changed: [],
            removedServerIDs: [],
            syncKey: "1"
        )

        let stored = try #require(try store.messages(account: account, folder: "13").first)
        #expect(stored.cc == "c@corp.test")

        let draft = scene.replyAllSeed(to: stored, bodyHTML: nil, account: account)

        #expect(draft.to == "z@corp.test; a@corp.test")
        #expect(draft.cc == "c@corp.test")
    }

    @Test("replyAll skips malformed headers, duplicates and the account's own address")
    func replyAllSkipsMalformedAndSelf() throws {
        let (scene, _, account, _) = try makeScene(accountAddress: "me@corp.test")
        let messy = Message(
            serverID: "m1",
            subject: "周报",
            sender: "\"Doe, John\" <j@corp.test>",
            recipients: "\"Doe, Jane\" <k@corp.test>, A@CORP.TEST; a@corp.test; 张三; team; me@corp.test",
            cc: "a@corp.test; ME@corp.test; team; c@corp.test"
        )

        let draft = scene.replyAllSeed(to: messy, bodyHTML: nil, account: account)

        #expect(draft.to == "j@corp.test; k@corp.test; A@CORP.TEST")
        #expect(draft.cc == "c@corp.test", "a@ is already in To, me@ is the account, team is not an address")

        let empty = Message(
            serverID: "m2",
            sender: nil,
            recipients: " ; ",
            cc: "me@corp.test"
        )
        let emptyDraft = scene.replyAllSeed(to: empty, bodyHTML: nil, account: account)

        #expect(emptyDraft.to.isEmpty)
        #expect(emptyDraft.cc == nil)
        #expect(emptyDraft.subject == "Re: (无主题)")
        #expect(emptyDraft.body == "\n\n--- 原邮件 ---\n")
    }

    @Test("replyAll keeps every address when the stored account cannot be read")
    func replyAllKeepsAddressesWithoutStoredAccount() throws {
        let (scene, _, _, _) = try makeScene(accountAddress: "me@corp.test")
        let message = Message(
            serverID: "m1",
            subject: "RE: 周报",
            sender: "z@corp.test",
            recipients: "a@corp.test",
            cc: "me@corp.test"
        )

        let draft = scene.replyAllSeed(
            to: message,
            bodyHTML: "<div>原文</div>",
            account: AccountID("missing-account")
        )

        #expect(draft.to == "z@corp.test; a@corp.test")
        #expect(draft.cc == "me@corp.test", "without a readable account address nothing is excluded")
        #expect(draft.subject == "RE: 周报", "the existing Re: prefix is not duplicated")
        #expect(draft.body == "\n\n--- 原邮件 ---\n原文")
    }

    /// Seed rules need no mail data; this keeps those tests from sharing fixtures.
    private func makeSceneWithoutStore() throws -> ComposeScene {
        let store = try MailStore.inMemory()
        let outbox = Outbox(store: store, gateway: FakeGateway(), clock: FixedClock())
        return ComposeScene(store: store, outbox: outbox)
    }
}
