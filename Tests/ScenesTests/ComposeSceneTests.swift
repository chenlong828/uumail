import Foundation
import GRDB
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

    @Test("reply seed carries the original HTML at full width and a dated header")
    func replySeedRules() throws {
        let scene = try makeSceneWithoutStore()
        let message = Message(serverID: "m1", subject: "周报", sender: "\"张三\" <z@corp.com>")

        let draft = scene.replySeed(
            to: message,
            bodyHTML: "<p>第一行<br>第二行</p>",
            quotedHeader: "2026年11月9日 20:11，张三 <z@corp.com> 写道："
        )

        #expect(draft.to == "z@corp.com")
        #expect(draft.subject == "Re: 周报")
        let html = try #require(draft.bodyHTML)
        #expect(html.hasPrefix("<!DOCTYPE html>"))
        #expect(html.contains("2026年11月9日 20:11"))
        #expect(html.contains("张三 &lt;z@corp.com&gt; 写道："))
        #expect(html.contains("<p>第一行<br>第二行</p>"), "the original markup is kept")
        #expect(!html.lowercased().contains("<blockquote"), "the quote is not indented")
        #expect(!html.lowercased().contains("margin-left"), "no left offset on the quote")
        #expect(draft.body.contains("2026年11月9日 20:11"))
        #expect(draft.body.contains("第一行\n第二行"))
    }

    @Test("reply seed drops scripts, iframes and event handlers from the quoted original")
    func replySeedSanitisesOriginal() throws {
        let scene = try makeSceneWithoutStore()
        let message = Message(serverID: "m1", subject: "周报", sender: "z@corp.com")

        let draft = scene.replySeed(
            to: message,
            bodyHTML: """
            <p onclick="steal()">safe</p>
            <script>alert(1)</script>
            <iframe src="https://tracker.test"></iframe>
            <a href="javascript:alert(2)">link</a>
            """
        )

        let html = try #require(draft.bodyHTML)
        #expect(!html.lowercased().contains("<script"))
        #expect(!html.lowercased().contains("<iframe"))
        #expect(!html.lowercased().contains("onclick"))
        #expect(!html.lowercased().contains("javascript:"))
        #expect(html.contains("safe"))
        #expect(html.contains(">link<"))
    }

    @Test("forward seed uses Fwd: and keeps the message body quoted")
    func forwardSeedRules() throws {
        let scene = try makeSceneWithoutStore()
        let message = Message(serverID: "m1", subject: "Re: 周报", sender: "z@corp.com")

        let draft = scene.forwardSeed(from: message, bodyHTML: "<div>原文</div>")

        #expect(draft.to.isEmpty, "forward starts without a recipient")
        #expect(draft.subject == "Fwd: Re: 周报")
        #expect(try #require(draft.bodyHTML).contains("---------- 转发邮件 ----------"))
        #expect(draft.body.contains("---------- 转发邮件 ----------"))
        #expect(draft.body.contains("原文"))
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
        #expect(noSubject.body == "原邮件")
        #expect(try #require(noSubject.bodyHTML).contains("原邮件"))
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
        #expect(draft.body.contains("原邮件"))
        #expect(draft.body.contains("第一行\n第二行"))
        #expect(try #require(draft.bodyHTML).contains("<p>第一行<br>第二行</p>"))
    }

    @Test("replyAll reads the Cc written by the post-migration backfill")
    func replyAllUsesBackfilledCc() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("uumail-replyall-backfill-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("pre-v9.sqlite").path
        try makePreV9Database(at: path)

        // Opening the old file runs v9: the cc column is added and message cursors rewind.
        let store = try MailStore(path: path)
        let account = AccountID("account-1")
        let migrated = try #require(try store.messages(account: account, folder: "13").first)
        #expect(migrated.serverID == "101")
        #expect(migrated.cc == nil)
        let legacyDraft = try #require(try store.outboxItem(account: account, id: OutboxID("old-outbox")))
        #expect(legacyDraft.bodyHTML == nil, "pre-v10 rows read back as plain text only")
        #expect(try store.syncKey(account: account, collection: "13") == "0")

        // The next sync re-pulls the same message as `changed`; the Cc is coalesced in.
        try store.applySyncBatch(
            account: account,
            folder: "13",
            added: [],
            changed: [
                MailMessage(
                    serverID: "101",
                    subject: "旧邮件",
                    sender: "z@corp.test",
                    recipients: "a@corp.test; b@corp.test",
                    receivedRaw: "2026-11-08T05:11:18.000Z",
                    cc: "c@corp.test"
                )
            ],
            removedServerIDs: [],
            syncKey: "1"
        )
        let backfilled = try #require(try store.messages(account: account, folder: "13").first)
        #expect(backfilled.cc == "c@corp.test")
        #expect(try store.body(account: account, folder: "13", serverID: "101")?.text == "<p>正文</p>")

        let scene = ComposeScene(
            store: store,
            outbox: Outbox(store: store, gateway: FakeGateway(), clock: FixedClock())
        )
        let draft = scene.replyAllSeed(to: backfilled, bodyHTML: nil, account: account)

        #expect(draft.to == "z@corp.test; a@corp.test; b@corp.test")
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
        #expect(emptyDraft.body == "原邮件")
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
        #expect(draft.body.contains("原文"))
        #expect(try #require(draft.bodyHTML).contains("<div>原文</div>"))
    }

    /// Seed rules need no mail data; this keeps those tests from sharing fixtures.
    private func makeSceneWithoutStore() throws -> ComposeScene {
        let store = try MailStore.inMemory()
        let outbox = Outbox(store: store, gateway: FakeGateway(), clock: FixedClock())
        return ComposeScene(store: store, outbox: outbox)
    }
}

/// Pre-v9 shape for `replyAllUsesBackfilledCc`: v1–v8 are recorded as applied so opening
/// the file runs exactly the v9 step. The tables match what v9 and `applySyncBatch` touch;
/// the message has a body so the backfill can be checked to preserve it.
/// (Kept local to this target; `MigrationTests` has its own richer v8/v9 fixtures.)
private func makePreV9Database(at path: String) throws {
    let queue = try DatabaseQueue(path: path)
    try queue.write { db in
        try db.execute(sql: """
            CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY);
            INSERT INTO grdb_migrations (identifier) VALUES
                ('v1_accounts_folders'), ('v2_messages'), ('v3_body_html'),
                ('v6_search'), ('v5_outbox'), ('v4_attachments'), ('v7_preview_split'),
                ('v8_outbox_v2');

            CREATE TABLE accounts (
                id TEXT PRIMARY KEY,
                display_name TEXT NOT NULL,
                address TEXT NOT NULL,
                host TEXT NOT NULL,
                state TEXT NOT NULL,
                created_at REAL NOT NULL
            );

            CREATE TABLE folders (
                account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
                server_id TEXT NOT NULL,
                parent_id TEXT,
                display_name TEXT NOT NULL,
                type INTEGER NOT NULL,
                deleted_at REAL,
                updated_at REAL NOT NULL,
                PRIMARY KEY (account_id, server_id)
            );

            CREATE TABLE sync_state (
                account_id TEXT NOT NULL,
                collection TEXT NOT NULL,
                sync_key TEXT NOT NULL,
                last_sync_at REAL,
                last_error TEXT,
                PRIMARY KEY (account_id, collection)
            );

            CREATE TABLE messages (
                account_id TEXT NOT NULL,
                folder_id TEXT NOT NULL,
                server_id TEXT NOT NULL,
                subject TEXT,
                sender TEXT,
                recipients TEXT,
                received_raw TEXT,
                is_read INTEGER NOT NULL DEFAULT 0,
                importance INTEGER,
                preview TEXT,
                deleted_at REAL,
                updated_at REAL NOT NULL,
                PRIMARY KEY (account_id, folder_id, server_id)
            );

            CREATE TABLE message_bodies (
                account_id TEXT NOT NULL,
                folder_id TEXT NOT NULL,
                server_id TEXT NOT NULL,
                text TEXT,
                fetched_at REAL,
                is_html INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (account_id, folder_id, server_id)
            );

            CREATE VIRTUAL TABLE messages_fts USING fts5(
                subject, sender, body, tokenize='trigram'
            );

            CREATE TABLE outbox (
                id TEXT PRIMARY KEY,
                account_id TEXT NOT NULL,
                to_recipients TEXT NOT NULL,
                cc TEXT,
                subject TEXT NOT NULL,
                body TEXT NOT NULL,
                in_reply_to TEXT,
                refs TEXT,
                is_draft INTEGER NOT NULL DEFAULT 0,
                state TEXT NOT NULL,
                attempts INTEGER NOT NULL DEFAULT 0,
                last_error TEXT,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                sending_since REAL,
                next_attempt_at REAL
            );

            INSERT INTO outbox (id, account_id, to_recipients, cc, subject, body, is_draft, state,
                                attempts, created_at, updated_at)
            VALUES ('old-outbox', 'account-1', 'a@corp.test', NULL, '旧草稿', '旧正文', 1, 'draft',
                    0, 1700000000, 1700000000);

            INSERT INTO accounts (id, display_name, address, host, state, created_at)
            VALUES ('account-1', 'J Doe', 'jdoe@corp.test', 'mail.corp.test', 'ready', 1700000000);

            INSERT INTO folders (account_id, server_id, parent_id, display_name, type, deleted_at, updated_at)
            VALUES ('account-1', '13', '0', '收件箱', 2, NULL, 1700000000);

            INSERT INTO messages (
                account_id, folder_id, server_id, subject, sender, recipients,
                received_raw, is_read, importance, preview, deleted_at, updated_at
            ) VALUES (
                'account-1', '13', '101', '旧邮件', 'z@corp.test', 'a@corp.test; b@corp.test',
                '2026-11-08T05:11:18.000Z', 0, 1, '摘要', NULL, 1700000000
            );

            INSERT INTO message_bodies (account_id, folder_id, server_id, text, fetched_at, is_html)
            VALUES ('account-1', '13', '101', '<p>正文</p>', 1700000001, 1);

            INSERT INTO sync_state (account_id, collection, sync_key, last_sync_at, last_error)
            VALUES
                ('account-1', 'folders', 'folders-key-9', 1700000000, NULL),
                ('account-1', '13', 'msg-key-9', 1700000000, NULL);
            """)
    }
}
