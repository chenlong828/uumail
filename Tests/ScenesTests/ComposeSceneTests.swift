import Foundation
import MailDomain
import MailStore
import Outbox
import Testing

@testable import Scenes

@Suite("ComposeScene")
struct ComposeSceneTests {
    private func makeScene() throws -> (ComposeScene, MailStore, AccountID, FakeGateway) {
        let store = try MailStore.inMemory()
        let account = try store.createAccount(
            NewAccount(displayName: "jdoe", address: "jdoe@corp.test", host: "mail.corp.test")
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

    /// Seed rules need no mail data; this keeps those tests from sharing fixtures.
    private func makeSceneWithoutStore() throws -> ComposeScene {
        let store = try MailStore.inMemory()
        let outbox = Outbox(store: store, gateway: FakeGateway(), clock: FixedClock())
        return ComposeScene(store: store, outbox: outbox)
    }
}
