import Foundation
import MailDomain
import Testing

@testable import MailStore

@Suite("MailStore folders and sync state")
struct MailStoreTests {
    private func makeStore() throws -> MailStore {
        try MailStore.inMemory()
    }

    @Test("createAccount returns a usable id")
    func createAccount() throws {
        let store = try makeStore()
        let id = try store.createAccount(NewAccount(displayName: "工作", address: "jdoe@corp.test", host: "mail.corp.test"))
        let account = try #require(try store.account(id))
        #expect(account.displayName == "工作")
        #expect(account.address == "jdoe@corp.test")
    }

    @Test("applyFolderSnapshot stores folders in mailbox order and advances the key")
    func applySnapshot() throws {
        let store = try makeStore()
        let id = try store.createAccount(NewAccount(displayName: "工作", address: "jdoe@corp.test", host: "mail.corp.test"))
        try store.applyFolderSnapshot(
            account: id,
            folders: [
                MailFolder(serverID: "9", parentID: "0", displayName: "Projects", type: 1),
                MailFolder(serverID: "8", parentID: "0", displayName: "Inbox", type: 2),
                MailFolder(serverID: "7", parentID: "0", displayName: "Deleted", type: 4),
            ],
            syncKey: "3"
        )
        let folders = try store.folders(account: id)
        // 系统文件夹在前（收件箱/草稿/已发送/已删除），用户文件夹在后
        #expect(folders.map(\.displayName) == ["Inbox", "Deleted", "Projects"])
        #expect(try store.syncKey(account: id, collection: "folders") == "3")
    }

    @Test("re-applying the same snapshot does not duplicate rows")
    func idempotentUpsert() throws {
        let store = try makeStore()
        let id = try store.createAccount(NewAccount(displayName: "工作", address: "jdoe@corp.test", host: "mail.corp.test"))
        let snapshot = [MailFolder(serverID: "8", parentID: "0", displayName: "Inbox", type: 2)]
        try store.applyFolderSnapshot(account: id, folders: snapshot, syncKey: "1")
        try store.applyFolderSnapshot(account: id, folders: snapshot, syncKey: "2")
        #expect(try store.folders(account: id).count == 1)
        #expect(try store.syncKey(account: id, collection: "folders") == "2")
    }

    @Test("removed folders disappear from reads but survive as soft deletes")
    func softDelete() throws {
        let store = try makeStore()
        let id = try store.createAccount(NewAccount(displayName: "工作", address: "jdoe@corp.test", host: "mail.corp.test"))
        try store.applyFolderSnapshot(
            account: id,
            folders: [
                MailFolder(serverID: "8", parentID: "0", displayName: "Inbox", type: 2),
                MailFolder(serverID: "9", parentID: "0", displayName: "Old", type: 1),
            ],
            syncKey: "1"
        )
        try store.applyFolderSnapshot(account: id, folders: [], removedServerIDs: ["9"], syncKey: "2")
        #expect(try store.folders(account: id).map(\.displayName) == ["Inbox"])
    }

    @Test("a folder that comes back is resurrected, not duplicated")
    func resurrection() throws {
        let store = try makeStore()
        let id = try store.createAccount(NewAccount(displayName: "工作", address: "jdoe@corp.test", host: "mail.corp.test"))
        try store.applyFolderSnapshot(account: id, folders: [
            MailFolder(serverID: "9", parentID: "0", displayName: "Old", type: 1),
        ], syncKey: "1")
        try store.applyFolderSnapshot(account: id, folders: [], removedServerIDs: ["9"], syncKey: "2")
        try store.applyFolderSnapshot(account: id, folders: [
            MailFolder(serverID: "9", parentID: "0", displayName: "Old", type: 1),
        ], syncKey: "3")
        #expect(try store.folders(account: id).count == 1)
    }

    @Test("an invalid folder rolls the whole batch back")
    func rollbackOnInvalidFolder() throws {
        let store = try makeStore()
        let id = try store.createAccount(NewAccount(displayName: "工作", address: "jdoe@corp.test", host: "mail.corp.test"))
        #expect(throws: MailStoreError.invalidFolder(reason: "empty serverID")) {
            try store.applyFolderSnapshot(
                account: id,
                folders: [
                    MailFolder(serverID: "8", parentID: "0", displayName: "Inbox", type: 2),
                    MailFolder(serverID: "", parentID: "0", displayName: "Broken", type: 1),
                ],
                syncKey: "1"
            )
        }
        #expect(try store.folders(account: id).isEmpty)
        #expect(try store.syncKey(account: id, collection: "folders") == nil)
    }

    @Test("writing folders for an unknown account fails loudly")
    func unknownAccount() throws {
        let store = try makeStore()
        let ghost = AccountID("ghost")
        #expect(throws: MailStoreError.accountNotFound(ghost)) {
            try store.applyFolderSnapshot(account: ghost, folders: [], syncKey: "1")
        }
    }
}

@Suite("MailStore sync batches")
struct MailStoreSyncTests {
    private func seededStore() throws -> (MailStore, AccountID) {
        let store = try MailStore.inMemory()
        let id = try store.createAccount(NewAccount(displayName: "工作", address: "jdoe@corp.test", host: "mail.corp.test"))
        try store.applyFolderSnapshot(
            account: id,
            folders: [MailFolder(serverID: "13", parentID: "0", displayName: "收件箱", type: 2)],
            syncKey: "1"
        )
        return (store, id)
    }

    @Test("a batch stores envelopes and previews, then advances the key")
    func appliesBatch() throws {
        let (store, id) = try seededStore()
        try store.applySyncBatch(
            account: id,
            folder: "13",
            added: [
                MailMessage(serverID: "101", subject: "周报", sender: "a@corp.test",
                            receivedRaw: "2026-11-08T05:11:18.000Z", bodyPreview: "摘要"),
                MailMessage(serverID: "102", subject: "通知", sender: "b@corp.test",
                            receivedRaw: "2026-11-08T04:00:00.000Z", isRead: true),
            ],
            changed: [],
            removedServerIDs: [],
            syncKey: "2"
        )
        let messages = try store.messages(account: id, folder: "13")
        #expect(messages.count == 2)
        #expect(messages.first?.serverID == "101")
        #expect(messages.first?.bodyPreview == "摘要")
        #expect(try store.syncKey(account: id, collection: "13") == "2")
    }

    @Test("a batch stores To and Cc and the list read exposes them")
    func storesRecipientsAndCc() throws {
        let (store, id) = try seededStore()
        try store.applySyncBatch(
            account: id,
            folder: "13",
            added: [
                MailMessage(serverID: "101", subject: "周报", sender: "a@corp.test",
                            recipients: "a@corp.test; b@corp.test",
                            receivedRaw: "2026-11-08T05:11:18.000Z", cc: "c@corp.test"),
            ],
            changed: [],
            removedServerIDs: [],
            syncKey: "2"
        )

        let message = try #require(try store.messages(account: id, folder: "13").first)
        #expect(message.recipients == "a@corp.test; b@corp.test")
        #expect(message.cc == "c@corp.test")
    }

    @Test("a partial Change keeps the stored To and Cc")
    func partialChangeKeepsRecipientsAndCc() throws {
        let (store, id) = try seededStore()
        try store.applySyncBatch(
            account: id,
            folder: "13",
            added: [
                MailMessage(serverID: "101", subject: "周报",
                            recipients: "a@corp.test; b@corp.test",
                            receivedRaw: "2026-11-08T05:11:18.000Z", cc: "c@corp.test"),
            ],
            changed: [],
            removedServerIDs: [],
            syncKey: "2"
        )
        // EAS `Change` can carry only the Read flag: it must not erase the envelope's To/Cc.
        try store.applySyncBatch(
            account: id,
            folder: "13",
            added: [],
            changed: [
                MailMessage(serverID: "101", subject: "周报",
                            receivedRaw: "2026-11-08T05:11:18.000Z", isRead: true),
            ],
            removedServerIDs: [],
            syncKey: "3"
        )

        let message = try #require(try store.messages(account: id, folder: "13").first)
        #expect(message.isRead)
        #expect(message.recipients == "a@corp.test; b@corp.test")
        #expect(message.cc == "c@corp.test")
    }

    @Test("re-applying the same batch keeps one row per server id")
    func idempotentBatch() throws {
        let (store, id) = try seededStore()
        let message = MailMessage(serverID: "101", subject: "周报", receivedRaw: "2026-11-08T05:11:18.000Z")
        try store.applySyncBatch(account: id, folder: "13", added: [message], changed: [],
                                 removedServerIDs: [], syncKey: "2")
        try store.applySyncBatch(account: id, folder: "13", added: [message], changed: [],
                                 removedServerIDs: [], syncKey: "3")
        #expect(try store.messages(account: id, folder: "13").count == 1)
        #expect(try store.syncKey(account: id, collection: "13") == "3")
    }

    @Test("removed messages disappear but keep their row")
    func softDeleteMessage() throws {
        let (store, id) = try seededStore()
        try store.applySyncBatch(account: id, folder: "13", added: [
            MailMessage(serverID: "101", subject: "A", receivedRaw: "2026-11-08T05:11:18.000Z"),
            MailMessage(serverID: "102", subject: "B", receivedRaw: "2026-11-08T04:00:00.000Z"),
        ], changed: [], removedServerIDs: [], syncKey: "2")
        try store.applySyncBatch(account: id, folder: "13", added: [], changed: [],
                                 removedServerIDs: ["102"], syncKey: "3")
        let remaining = try store.messages(account: id, folder: "13")
        #expect(remaining.map(\.serverID) == ["101"])
    }

    @Test("a failed batch does not advance the key")
    func rollbackKeepsKey() throws {
        let (store, id) = try seededStore()
        #expect(throws: MailStoreError.invalidFolder(reason: "empty message serverID")) {
            try store.applySyncBatch(account: id, folder: "13", added: [
                MailMessage(serverID: "101", subject: "A"),
                MailMessage(serverID: "", subject: "broken"),
            ], changed: [], removedServerIDs: [], syncKey: "2")
        }
        #expect(try store.messages(account: id, folder: "13").isEmpty)
        #expect(try store.syncKey(account: id, collection: "13") == nil)
    }

    @Test("syncing into an unknown folder fails loudly")
    func unknownFolder() throws {
        let (store, id) = try seededStore()
        #expect(throws: MailStoreError.folderNotFound(account: id, folder: "999")) {
            try store.applySyncBatch(account: id, folder: "999", added: [], changed: [],
                                     removedServerIDs: [], syncKey: "2")
        }
    }
}

@Suite("MailStore bodies")
struct MailStoreBodyTests {
    @Test("a fetched body is stored separately from the envelope and updated in place")
    func storesBody() throws {
        let store = try MailStore.inMemory()
        let id = try store.createAccount(NewAccount(displayName: "工作", address: "jdoe@corp.test", host: "mail.corp.test"))
        try store.applyFolderSnapshot(account: id, folders: [
            MailFolder(serverID: "13", parentID: "0", displayName: "收件箱", type: 2),
        ], syncKey: "1")
        try store.applySyncBatch(account: id, folder: "13", added: [
            MailMessage(serverID: "1", subject: "A", receivedRaw: "2026-11-08T05:11:18.000Z"),
        ], changed: [], removedServerIDs: [], syncKey: "2")

        try store.applyBody(account: id, folder: "13", serverID: "1", html: "<html>v1</html>")
        #expect(try store.body(account: id, folder: "13", serverID: "1")?.text == "<html>v1</html>")
        #expect(try store.body(account: id, folder: "13", serverID: "1")?.isHTML == true)

        try store.applyBody(account: id, folder: "13", serverID: "1", html: "<html>v2</html>")
        #expect(try store.body(account: id, folder: "13", serverID: "1")?.text == "<html>v2</html>")
    }

    @Test("an unfetched message has no body row")
    func noBody() throws {
        let store = try MailStore.inMemory()
        let id = try store.createAccount(NewAccount(displayName: "工作", address: "jdoe@corp.test", host: "mail.corp.test"))
        #expect(try store.body(account: id, folder: "13", serverID: "1") == nil)
    }

    @Test("a sync preview rides on the envelope and never counts as a body")
    func previewIsNotABody() throws {
        let store = try MailStore.inMemory()
        let id = try store.createAccount(NewAccount(displayName: "工作", address: "jdoe@corp.test", host: "mail.corp.test"))
        try store.applyFolderSnapshot(account: id, folders: [
            MailFolder(serverID: "13", parentID: "0", displayName: "收件箱", type: 2),
        ], syncKey: "1")
        try store.applySyncBatch(account: id, folder: "13", added: [
            MailMessage(serverID: "1", subject: "A", receivedRaw: "2026-11-08T05:11:18.000Z",
                        bodyPreview: "摘要前 500 字"),
        ], changed: [], removedServerIDs: [], syncKey: "2")

        #expect(try store.body(account: id, folder: "13", serverID: "1") == nil,
                "the preview must not short-circuit the real body fetch")
        #expect(try store.messages(account: id, folder: "13").first?.bodyPreview == "摘要前 500 字")

        try store.applyBody(account: id, folder: "13", serverID: "1", html: "<p>完整正文</p>")
        #expect(try store.body(account: id, folder: "13", serverID: "1")?.text == "<p>完整正文</p>")
        #expect(try store.messages(account: id, folder: "13").first?.bodyPreview == "摘要前 500 字")
    }

    @Test("a resync does not overwrite a fetched body with the preview")
    func resyncKeepsFetchedBody() throws {
        let store = try MailStore.inMemory()
        let id = try store.createAccount(NewAccount(displayName: "工作", address: "jdoe@corp.test", host: "mail.corp.test"))
        try store.applyFolderSnapshot(account: id, folders: [
            MailFolder(serverID: "13", parentID: "0", displayName: "收件箱", type: 2),
        ], syncKey: "1")
        try store.applySyncBatch(account: id, folder: "13", added: [
            MailMessage(serverID: "1", subject: "A", receivedRaw: "2026-11-08T05:11:18.000Z",
                        bodyPreview: "摘要"),
        ], changed: [], removedServerIDs: [], syncKey: "2")
        try store.applyBody(account: id, folder: "13", serverID: "1", html: "<p>完整正文</p>")

        try store.applySyncBatch(account: id, folder: "13", added: [], changed: [
            MailMessage(serverID: "1", subject: "A", receivedRaw: "2026-11-08T05:11:18.000Z",
                        isRead: true, bodyPreview: "摘要"),
        ], removedServerIDs: [], syncKey: "3")

        #expect(try store.body(account: id, folder: "13", serverID: "1")?.text == "<p>完整正文</p>")
    }

    @Test("a message is searchable by its preview before the body arrives")
    func previewSearchable() throws {
        let store = try MailStore.inMemory()
        let id = try store.createAccount(NewAccount(displayName: "工作", address: "jdoe@corp.test", host: "mail.corp.test"))
        try store.applyFolderSnapshot(account: id, folders: [
            MailFolder(serverID: "13", parentID: "0", displayName: "收件箱", type: 2),
        ], syncKey: "1")
        try store.applySyncBatch(account: id, folder: "13", added: [
            MailMessage(serverID: "1", subject: "A", receivedRaw: "2026-11-08T05:11:18.000Z",
                        bodyPreview: "五矿证券拜访会议纪要正文"),
        ], changed: [], removedServerIDs: [], syncKey: "2")

        #expect(try store.searchLocal(account: id, query: "会议纪要").map(\.serverID) == ["1"])
        #expect(try store.searchLocal(account: id, query: "会议").map(\.serverID) == ["1"])
    }
}

@Suite("MailStore outbox")
struct MailStoreOutboxTests {
    private func seeded() throws -> (MailStore, AccountID) {
        let store = try MailStore.inMemory()
        let id = try store.createAccount(NewAccount(displayName: "工作", address: "jdoe@corp.test", host: "mail.corp.test"))
        return (store, id)
    }

    private func now() -> Date { Date(timeIntervalSince1970: 1_700_000_000) }

    private func draft() -> MailDraft {
        MailDraft(to: "a@b.c", cc: nil, subject: "hi", body: "text")
    }

    @Test("a claimed row appears in pending; marking it sent removes it")
    func queueAndSend() throws {
        let (store, id) = try seeded()
        let raw = try store.enqueueOutbox(account: id, draft: draft())
        let outboxID = OutboxID(raw)
        #expect(try store.pendingOutbox(account: id).map(\.id) == [raw])

        let claimed = try #require(try store.claimOutbox(account: id, now: now(), lease: .seconds(120)))
        #expect(claimed.id == raw)
        #expect(claimed.state == "sending")

        try store.markOutboxSent(account: id, outboxID: outboxID)
        #expect(try store.pendingOutbox(account: id).isEmpty)
        #expect(try store.outboxItem(account: id, id: outboxID) == nil)
    }

    @Test("a retryable failure keeps content, error, attempt count and next attempt")
    func failedStaysPending() throws {
        let (store, id) = try seeded()
        let outboxID = OutboxID(try store.enqueueOutbox(account: id, draft: draft()))
        _ = try store.claimOutbox(account: id, now: now(), lease: .seconds(120))
        let next = now().addingTimeInterval(30)
        try store.markOutboxFailed(
            account: id, outboxID: outboxID, error: "offline", retryable: true, nextAttempt: next
        )

        let pending = try store.pendingOutbox(account: id)
        #expect(pending.count == 1)
        #expect(pending.first?.state == "failed_retryable")
        #expect(pending.first?.attempts == 1)
        #expect(pending.first?.lastError == "offline")
        #expect(pending.first?.nextAttemptAt == next)
        #expect(pending.first?.body == "text")
    }

    @Test("a permanent failure is kept but has no next attempt")
    func permanentFailure() throws {
        let (store, id) = try seeded()
        let outboxID = OutboxID(try store.enqueueOutbox(account: id, draft: draft()))
        _ = try store.claimOutbox(account: id, now: now(), lease: .seconds(120))
        try store.markOutboxFailed(
            account: id, outboxID: outboxID, error: "authFailed", retryable: false, nextAttempt: nil
        )

        let item = try #require(try store.outboxItem(account: id, id: outboxID))
        #expect(item.state == "failed_permanent")
        #expect(item.attempts == 1)
        #expect(item.nextAttemptAt == nil)
        // It stays visible for the compose status line, but is not auto-claimable.
        #expect(try store.pendingOutbox(account: id).map(\.id) == [outboxID.raw])
        #expect(try store.claimOutbox(account: id, now: now().addingTimeInterval(86_400), lease: .seconds(120)) == nil)
    }

    @Test("a second claim returns nil while the lease is live")
    func singleClaim() throws {
        let (store, id) = try seeded()
        let raw = try store.enqueueOutbox(account: id, draft: draft())
        #expect(try store.claimOutbox(account: id, now: now(), lease: .seconds(120))?.id == raw)
        #expect(try store.claimOutbox(account: id, now: now(), lease: .seconds(120)) == nil)
    }

    @Test("a failed retryable row is claimable only once its backoff elapsed")
    func backoffGating() throws {
        let (store, id) = try seeded()
        let raw = try store.enqueueOutbox(account: id, draft: draft())
        let outboxID = OutboxID(raw)
        _ = try store.claimOutbox(account: id, now: now(), lease: .seconds(120))
        try store.markOutboxFailed(
            account: id, outboxID: outboxID, error: "offline",
            retryable: true, nextAttempt: now().addingTimeInterval(30)
        )

        #expect(try store.claimOutbox(account: id, now: now(), lease: .seconds(120)) == nil)
        #expect(try store.claimOutbox(account: id, now: now().addingTimeInterval(29), lease: .seconds(120)) == nil)
        #expect(try store.claimOutbox(account: id, now: now().addingTimeInterval(30), lease: .seconds(120))?.id == raw)
    }

    @Test("an expired sending lease is reclaimable; a live one is not")
    func expiredLease() throws {
        let (store, id) = try seeded()
        let raw = try store.enqueueOutbox(account: id, draft: draft())
        #expect(try store.claimOutbox(account: id, now: now(), lease: .seconds(120))?.id == raw)

        #expect(try store.claimOutbox(account: id, now: now().addingTimeInterval(119), lease: .seconds(120)) == nil)
        #expect(try store.claimOutbox(account: id, now: now().addingTimeInterval(120), lease: .seconds(120))?.id == raw)
    }

    @Test("release returns a claimed row to the queue")
    func release() throws {
        let (store, id) = try seeded()
        let raw = try store.enqueueOutbox(account: id, draft: draft())
        let outboxID = OutboxID(raw)
        _ = try store.claimOutbox(account: id, now: now(), lease: .seconds(120))

        try store.releaseOutbox(account: id, outboxID: outboxID)
        #expect(try store.outboxItem(account: id, id: outboxID)?.state == "queued")
        #expect(try store.claimOutbox(account: id, now: now(), lease: .seconds(120))?.id == raw)
    }

    @Test("cancel records a canceled row that is neither pending nor claimable")
    func cancel() throws {
        let (store, id) = try seeded()
        let outboxID = OutboxID(try store.enqueueOutbox(account: id, draft: draft()))

        try store.cancelOutbox(account: id, outboxID: outboxID)
        #expect(try store.outboxItem(account: id, id: outboxID)?.state == "canceled")
        #expect(try store.pendingOutbox(account: id).isEmpty)
        #expect(try store.claimOutbox(account: id, now: now(), lease: .seconds(120)) == nil)
    }

    @Test("marking a row that was never claimed reports outboxNotClaimable")
    func unclaimedMark() throws {
        let (store, id) = try seeded()
        let outboxID = OutboxID(try store.enqueueOutbox(account: id, draft: draft()))

        #expect(throws: MailStoreError.outboxNotClaimable(account: id, outboxID: outboxID)) {
            try store.markOutboxSent(account: id, outboxID: outboxID)
        }
    }

    @Test("drafts are stored but not pending")
    func draftsAreNotPending() throws {
        let (store, id) = try seeded()
        _ = try store.saveDraft(account: id, draft: MailDraft(to: "a@b.c", cc: nil, subject: "draft", body: "", isDraft: true))
        #expect(try store.pendingOutbox(account: id).isEmpty)
    }
}

@Suite("MailStore account lifecycle")
struct MailStoreAccountLifecycleTests {
    private func seeded() throws -> (MailStore, AccountID) {
        let store = try MailStore.inMemory()
        let id = try store.createAccount(NewAccount(displayName: "工作", address: "jdoe@corp.test", host: "mail.corp.test"))
        return (store, id)
    }

    @Test("account() exposes the stored host that sending uses")
    func accountHost() throws {
        let (store, id) = try seeded()
        let account = try #require(try store.account(id))
        #expect(account.address == "jdoe@corp.test")
        #expect(account.host == "mail.corp.test")
    }

    @Test("discardAccount removes an account that never received mail")
    func discardEmpty() throws {
        let (store, id) = try seeded()
        try store.discardAccount(id)
        #expect(try store.accounts().isEmpty)
        #expect(try store.account(id) == nil)
    }

    @Test("discardAccount refuses to drop an account that owns messages")
    func discardNotEmpty() throws {
        let (store, id) = try seeded()
        try store.applyFolderSnapshot(account: id, folders: [
            MailFolder(serverID: "13", parentID: "0", displayName: "收件箱", type: 2),
        ], syncKey: "1")
        try store.applySyncBatch(account: id, folder: "13", added: [
            MailMessage(serverID: "1", subject: "hi", sender: "a@corp.test", receivedRaw: "2026-11-08T05:11:18.000Z"),
        ], changed: [], removedServerIDs: [], syncKey: "2")

        #expect(throws: MailStoreError.accountNotEmpty(id)) {
            try store.discardAccount(id)
        }
        #expect(try store.accounts() == [id])
    }

    @Test("markAccountReady requires an existing account")
    func markReady() throws {
        let (store, id) = try seeded()
        try store.markAccountReady(id)
        #expect(throws: MailStoreError.accountNotFound(AccountID("missing"))) {
            try store.markAccountReady(AccountID("missing"))
        }
    }
}

@Suite("MailStore search")
struct MailStoreSearchTests {
    private func seeded() throws -> (MailStore, AccountID) {
        let store = try MailStore.inMemory()
        let id = try store.createAccount(NewAccount(displayName: "工作", address: "jdoe@corp.test", host: "mail.corp.test"))
        try store.applyFolderSnapshot(account: id, folders: [
            MailFolder(serverID: "13", parentID: "0", displayName: "收件箱", type: 2),
        ], syncKey: "1")
        try store.applySyncBatch(account: id, folder: "13", added: [
            MailMessage(serverID: "1", subject: "周报会议纪要", sender: "a@corp.test",
                        receivedRaw: "2026-11-08T05:11:18.000Z"),
            MailMessage(serverID: "2", subject: "PB1.0 系统通知", sender: "b@corp.test",
                        receivedRaw: "2026-11-07T05:11:18.000Z"),
        ], changed: [], removedServerIDs: [], syncKey: "2")
        return (store, id)
    }

    @Test("substring search matches Chinese subjects")
    func chineseSubstring() throws {
        let (store, id) = try seeded()
        let hits = try store.searchLocal(account: id, query: "会议纪要")
        #expect(hits.map(\.serverID) == ["1"])
    }

    @Test("body text is searchable after it is fetched")
    func bodyIndexed() throws {
        let (store, id) = try seeded()
        try store.applyBody(account: id, folder: "13", serverID: "2",
                            html: "<p>单拎补丁申请流程说明</p>")
        #expect(try store.searchLocal(account: id, query: "补丁申请").map(\.serverID) == ["2"])
    }

    @Test("search results carry To and Cc for reply-all seeding")
    func searchCarriesRecipientsAndCc() throws {
        let (store, id) = try seeded()
        try store.applySyncBatch(
            account: id,
            folder: "13",
            added: [
                MailMessage(serverID: "3", subject: "全部回复测试", sender: "z@corp.test",
                            recipients: "a@corp.test; b@corp.test",
                            receivedRaw: "2026-11-06T05:11:18.000Z", cc: "c@corp.test"),
            ],
            changed: [],
            removedServerIDs: [],
            syncKey: "3"
        )

        let hit = try #require(try store.searchLocal(account: id, query: "全部回复").first)
        #expect(hit.serverID == "3")
        #expect(hit.recipients == "a@corp.test; b@corp.test")
        #expect(hit.cc == "c@corp.test")
    }

    @Test("blank queries return nothing instead of everything")
    func blankQuery() throws {
        let (store, id) = try seeded()
        #expect(try store.searchLocal(account: id, query: "   ").isEmpty)
    }
}

@Suite("MailStore short queries")
struct MailStoreShortQueryTests {
    @Test("two-character CJK queries fall back to LIKE and still match")
    func shortQuery() throws {
        let store = try MailStore.inMemory()
        let id = try store.createAccount(NewAccount(displayName: "工作", address: "jdoe@corp.test", host: "mail.corp.test"))
        try store.applyFolderSnapshot(account: id, folders: [
            MailFolder(serverID: "13", parentID: "0", displayName: "收件箱", type: 2),
        ], syncKey: "1")
        try store.applySyncBatch(account: id, folder: "13", added: [
            MailMessage(serverID: "1", subject: "周报 1109", sender: "a@corp.test", receivedRaw: "2026-11-08T05:11:18.000Z"),
        ], changed: [], removedServerIDs: [], syncKey: "2")
        #expect(try store.searchLocal(account: id, query: "周报").map(\.serverID) == ["1"])
    }
}

@Suite("MailStore write path")
struct MailStoreWritePathTests {
    private func seeded() throws -> (MailStore, AccountID) {
        let store = try MailStore.inMemory()
        let id = try store.createAccount(
            NewAccount(displayName: "工作", address: "jdoe@corp.test", host: "mail.corp.test")
        )
        try store.applyFolderSnapshot(
            account: id,
            folders: [MailFolder(serverID: "13", parentID: "0", displayName: "收件箱", type: 2)],
            syncKey: "1"
        )
        try store.applySyncBatch(
            account: id,
            folder: "13",
            added: [
                MailMessage(
                    serverID: "101", subject: "目标", sender: "a@corp.test",
                    recipients: "me@corp.test", receivedRaw: "2026-11-08T05:11:18.000Z",
                    attachments: [Attachment(displayName: "报表.pdf", fileReference: "ref-1")]
                ),
                MailMessage(
                    serverID: "102", subject: "邻居", sender: "b@corp.test",
                    receivedRaw: "2026-11-08T04:11:18.000Z"
                ),
            ],
            changed: [],
            removedServerIDs: [],
            syncKey: "2"
        )
        try store.applyBody(account: id, folder: "13", serverID: "101", html: "<p>正文</p>")
        return (store, id)
    }

    private func delta(
        added: [MailMessage] = [],
        changed: [MailMessage] = [],
        removed: [String] = [],
        key: String
    ) -> MessageDelta {
        MessageDelta(added: added, changed: changed, removedServerIDs: removed, syncKey: key, moreAvailable: false)
    }

    @Test("attachment ContentId is stored, read back, and kept when a resync omits it")
    func attachmentContentIDRoundTrip() throws {
        let store = try MailStore.inMemory()
        let id = try store.createAccount(
            NewAccount(displayName: "工作", address: "jdoe@corp.test", host: "mail.corp.test")
        )
        try store.applyFolderSnapshot(
            account: id,
            folders: [MailFolder(serverID: "13", parentID: "0", displayName: "收件箱", type: 2)],
            syncKey: "1"
        )
        let logo = Attachment(
            displayName: "36979_logo.gif",
            fileReference: "ref-gif",
            contentID: "_Foxmail.1@7a87418d"
        )
        try store.applySyncBatch(
            account: id,
            folder: "13",
            added: [MailMessage(serverID: "101", receivedRaw: "2026-11-20T09:24:45.000Z", attachments: [logo])],
            changed: [],
            removedServerIDs: [],
            syncKey: "2"
        )
        #expect(try store.attachments(account: id, folder: "13", messageID: "101").first?.contentID == "_Foxmail.1@7a87418d")

        // A later envelope without ContentId (older gateway or a partial update) must not
        // wipe the stored value: the render path depends on it.
        try store.applySyncBatch(
            account: id,
            folder: "13",
            added: [],
            changed: [MailMessage(
                serverID: "101",
                receivedRaw: "2026-11-20T09:24:45.000Z",
                attachments: [Attachment(displayName: "36979_logo.gif", fileReference: "ref-gif")]
            )],
            removedServerIDs: [],
            syncKey: "3"
        )
        #expect(try store.attachments(account: id, folder: "13", messageID: "101").first?.contentID == "_Foxmail.1@7a87418d")
    }

    @Test("markRead flips only the target unread row, is idempotent and leaves the key alone")
    func markReadOnlyTarget() throws {
        let (store, id) = try seeded()

        #expect(try store.markRead(account: id, folder: "13", serverID: "101") == true)
        let messages = try store.messages(account: id, folder: "13")
        #expect(messages.first { $0.serverID == "101" }?.isRead == true)
        #expect(messages.first { $0.serverID == "102" }?.isRead == false)
        #expect(try store.markRead(account: id, folder: "13", serverID: "101") == false)
        #expect(try store.syncKey(account: id, collection: "13") == "2", "a local read marker never advances the key")
    }

    @Test("commitMarkRead applies the delta and the local read in one commit")
    func commitMarkReadAppliesDeltaAndEffect() throws {
        let (store, id) = try seeded()
        // The echo for the target is partial (nil subject/sender); the neighbour carries a real change.
        let response = delta(
            added: [MailMessage(serverID: "101", isRead: false)],
            changed: [
                MailMessage(serverID: "101", subject: nil, sender: nil, isRead: false),
                MailMessage(serverID: "102", subject: "邻居-更新", isRead: true),
            ],
            key: "9"
        )

        try store.commitMarkRead(account: id, folder: "13", serverID: "101", delta: response)

        let messages = try store.messages(account: id, folder: "13")
        let target = try #require(messages.first { $0.serverID == "101" })
        #expect(target.isRead == true, "the local effect wins over a Read=0 echo")
        #expect(target.subject == "目标", "a partial echo must not wipe the target envelope")
        #expect(target.sender == "a@corp.test")
        #expect(messages.first { $0.serverID == "102" }?.subject == "邻居-更新")
        #expect(try store.syncKey(account: id, collection: "13") == "9")
    }

    @Test("commitMarkRead rolls back and keeps the old key when the folder is unknown")
    func commitMarkReadRollbackKeepsKey() throws {
        let (store, id) = try seeded()
        #expect(throws: MailStoreError.folderNotFound(account: id, folder: "999")) {
            try store.commitMarkRead(
                account: id, folder: "999", serverID: "101",
                delta: delta(key: "9")
            )
        }
        #expect(try store.syncKey(account: id, collection: "13") == "2")
        #expect(try store.messages(account: id, folder: "13").first { $0.serverID == "101" }?.isRead == false)
    }

    @Test("commitDelete soft-deletes only the target, keeps body/attachment rows and advances the key")
    func commitDeleteSoftDeletes() throws {
        let (store, id) = try seeded()
        try store.commitDelete(
            account: id, folder: "13", serverID: "101",
            delta: delta(removed: ["101"], key: "10")
        )

        let messages = try store.messages(account: id, folder: "13")
        #expect(messages.map(\.serverID) == ["102"])
        #expect(try store.body(account: id, folder: "13", serverID: "101")?.text == "<p>正文</p>")
        #expect(try store.attachments(account: id, folder: "13", messageID: "101").count == 1)
        #expect(try store.syncKey(account: id, collection: "13") == "10")

        // A second delete is a no-op apart from the key it carried.
        try store.commitDelete(
            account: id, folder: "13", serverID: "101",
            delta: delta(key: "11")
        )
        #expect(try store.syncKey(account: id, collection: "13") == "11")
    }

    @Test("a partial echo of the target cannot resurrect or overwrite it during commitDelete")
    func commitDeleteProtectsTargetEnvelope() throws {
        let (store, id) = try seeded()
        try store.commitDelete(
            account: id, folder: "13", serverID: "101",
            delta: delta(
                changed: [MailMessage(serverID: "101", subject: nil, sender: nil, isRead: false)],
                key: "12"
            )
        )
        #expect(try store.messages(account: id, folder: "13").map(\.serverID) == ["102"])
        #expect(try store.syncKey(account: id, collection: "13") == "12")
    }

    @Test("commitDelete rolls back and keeps the old key on an unknown folder")
    func commitDeleteRollbackKeepsKey() throws {
        let (store, id) = try seeded()
        #expect(throws: MailStoreError.folderNotFound(account: id, folder: "999")) {
            try store.commitDelete(
                account: id, folder: "999", serverID: "101",
                delta: delta(removed: ["101"], key: "9")
            )
        }
        #expect(try store.syncKey(account: id, collection: "13") == "2")
        #expect(try store.messages(account: id, folder: "13").map(\.serverID) == ["101", "102"])
    }
}
