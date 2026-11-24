import Foundation
import GRDB
import MailDomain
import Testing
import MeetingDomain
import SyncContract

@testable import MailStore

/// Schema gate 4 from architecture spec §8: an old database opens, migrates and keeps
/// its data. The fixture is a *partial* old database: it carries the tables the migrations
/// and the assertions need (`accounts`, pre-v8 `outbox`, pre-v9 `messages`/`sync_state`),
/// and records v1–v7 as already applied so that opening the file runs `v8_outbox_v2` and
/// `v9_message_cc`. The other pre-v8 tables are not touched by those steps or by the
/// assertions; recreating them would duplicate the whole schema in the test.
@Suite("Schema migrations")
struct MigrationTests {
    @Test("opening a pre-v8 database forwards failed outbox rows to failed_retryable")
    func v8OutboxMigration() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("uumail-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("pre-v8.sqlite").path

        try makePreV8Database(at: path)

        // Opening runs v8 and must succeed on the old file.
        let store = try MailStore(path: path)
        let account = AccountID("account-1")

        // Old rows stay readable after the upgrade.
        #expect(try store.accounts() == [account])
        #expect(try store.account(account)?.address == "jdoe@corp.test")
        let item = try #require(try store.outbox.outboxItem(account: account, id: OutboxID("outbox-1")))
        #expect(item.state == "failed_retryable")
        #expect(item.to == "a@b.c")
        #expect(item.subject == "old draft")
        #expect(item.body == "queued before the upgrade")
        #expect(item.cc == nil)
        #expect(item.attempts == 2)
        #expect(item.lastError == "offline")
        #expect(item.nextAttemptAt == nil)

        // The renamed state is deliverable again: no backoff was stored by the old row.
        let claimed = try store.outbox.claimOutbox(
            account: account,
            now: Date(timeIntervalSince1970: 2_000),
            lease: .seconds(120)
        )
        #expect(claimed?.id == "outbox-1")
        #expect(claimed?.state == "sending")
    }

    @Test("pre-v9 messages read cc as nil, keep body/attachments, and backfill on the next sync")
    func v9MessageCcMigration() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("uumail-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("pre-v9.sqlite").path

        try makePreV9Database(at: path)

        // Opening runs v9: the cc column exists and old rows keep every other field.
        let store = try MailStore(path: path)
        let account = AccountID("account-1")
        let old = try #require(try store.messages(account: account, folder: "13").first)
        #expect(old.serverID == "101")
        #expect(old.recipients == "a@corp.test; b@corp.test")
        #expect(old.cc == nil)

        // The additive migration leaves the body and the attachment cache alone.
        #expect(try store.body(account: account, folder: "13", serverID: "101")?.text == "<p>正文</p>")
        let attachments = try store.attachments(account: account, folder: "13", messageID: "101")
        #expect(attachments.count == 1)
        #expect(attachments.first?.cachePath == "/tmp/101-1.pdf")

        // Message cursors rewind to bootstrap; the folder cursor is untouched.
        #expect(try store.syncKey(account: account, collection: "13") == "0")
        #expect(try store.syncKey(account: account, collection: "drafts") == "0")
        #expect(try store.syncKey(account: account, collection: "folders") == "folders-key-9")

        // The next sync re-pulls the same message with Cc; body and cache still survive.
        try store.applySyncBatch(
            account: account,
            folder: "13",
            added: [],
            changed: [
                MailMessage(serverID: "101", subject: "旧邮件",
                            recipients: "a@corp.test; b@corp.test",
                            receivedRaw: "2026-11-08T05:11:18.000Z", cc: "c@corp.test"),
            ],
            removedServerIDs: [],
            syncKey: "1"
        )
        let refreshed = try #require(try store.messages(account: account, folder: "13").first)
        #expect(refreshed.cc == "c@corp.test")
        #expect(try store.body(account: account, folder: "13", serverID: "101")?.text == "<p>正文</p>")
        #expect(try store.attachments(account: account, folder: "13", messageID: "101").first?.cachePath == "/tmp/101-1.pdf")
    }

    @Test("pre-v11 attachments read a nil ContentId and the next sync fills it")
    func v11AttachmentContentIDMigration() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("uumail-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("pre-v11.sqlite").path

        try makePreV9Database(at: path)
        let store = try MailStore(path: path)
        let account = AccountID("account-1")

        // The additive v11 column exists and old rows have no value yet.
        #expect(try store.attachments(account: account, folder: "13", messageID: "101").first?.contentID == nil)
        // Message cursors rewind so the next sync re-pulls the window; folders keep their key.
        #expect(try store.syncKey(account: account, collection: "13") == "0")
        #expect(try store.syncKey(account: account, collection: "drafts") == "0")
        #expect(try store.syncKey(account: account, collection: "folders") == "folders-key-9")

        try store.applySyncBatch(
            account: account,
            folder: "13",
            added: [],
            changed: [MailMessage(
                serverID: "101",
                receivedRaw: "2026-11-08T05:11:18.000Z",
                attachments: [Attachment(displayName: "a.pdf", fileReference: "1", contentID: "a@corp.test")]
            )],
            removedServerIDs: [],
            syncKey: "1"
        )
        #expect(try store.attachments(account: account, folder: "13", messageID: "101").first?.contentID == "a@corp.test")
    }

    @Test("an old database gains the v12 meetings table without backfilling")
    func v12MeetingsMigration() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("uumail-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("pre-v12.sqlite").path

        try makePreV9Database(at: path)
        let store = try MailStore(path: path)
        let account = AccountID("account-1")

        // The table exists and is empty: old mail never carried MeetingRequest, and the
        // confirmed scope does not backfill.
        #expect(try store.meetings(
            account: account,
            from: Date(timeIntervalSince1970: 0),
            to: Date(timeIntervalSince1970: 4_000_000_000)
        ).isEmpty)
        #expect(try store.meetingInvite(account: account, uid: "u-1") == nil)

        try store.applySyncBatch(
            account: account,
            folder: "13",
            added: [MailMessage(
                serverID: "m-new",
                subject: "会议",
                receivedRaw: "2026-11-24T00:00:00Z"
            )],
            changed: [],
            removedServerIDs: [],
            syncKey: "1",
            meetings: [MeetingDeltaEntry(
                serverID: "m-new",
                subject: "会议",
                invite: MeetingInvite(
                    uid: "u-1",
                    start: Date(timeIntervalSince1970: 1_800_000_000),
                    end: Date(timeIntervalSince1970: 1_800_003_600)
                )
            )]
        )
        #expect(try store.meetingInvite(account: account, uid: "u-1") != nil)
    }
}

// MARK: - Fixture

/// Builds the pre-v8 file with the v5 `outbox` shape and a `failed` row. `grdb_migrations`
/// is the table GRDB's migrator reads, so writing the v1–v7 identifiers here makes opening
/// the file run exactly the v8 step.
private func makePreV8Database(at path: String) throws {
    let queue = try DatabaseQueue(path: path)
    try queue.write { db in
        try db.execute(sql: """
            CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY);
            INSERT INTO grdb_migrations (identifier) VALUES
                ('v1_accounts_folders'), ('v2_messages'), ('v3_body_html'),
                ('v6_search'), ('v5_outbox'), ('v4_attachments'), ('v7_preview_split');

            CREATE TABLE accounts (
                id TEXT PRIMARY KEY,
                display_name TEXT NOT NULL,
                address TEXT NOT NULL,
                host TEXT NOT NULL,
                state TEXT NOT NULL,
                created_at REAL NOT NULL
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
                updated_at REAL NOT NULL
            );
            CREATE INDEX idx_outbox_state ON outbox(account_id, state);

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

            CREATE TABLE sync_state (
                account_id TEXT NOT NULL,
                collection TEXT NOT NULL,
                sync_key TEXT NOT NULL,
                last_sync_at REAL,
                last_error TEXT,
                PRIMARY KEY (account_id, collection)
            );

            CREATE TABLE attachments (
                account_id TEXT NOT NULL,
                folder_id TEXT NOT NULL,
                message_id TEXT NOT NULL,
                file_reference TEXT NOT NULL,
                display_name TEXT NOT NULL,
                size INTEGER,
                cache_path TEXT,
                downloaded_at REAL,
                PRIMARY KEY (account_id, folder_id, message_id, file_reference)
            );

            INSERT INTO accounts (id, display_name, address, host, state, created_at)
            VALUES ('account-1', 'J Doe', 'jdoe@corp.test', 'mail.corp.test', 'ready', 1700000000);

            INSERT INTO outbox (
                id, account_id, to_recipients, cc, subject, body, in_reply_to, refs,
                is_draft, state, attempts, last_error, created_at, updated_at
            ) VALUES (
                'outbox-1', 'account-1', 'a@b.c', NULL, 'old draft', 'queued before the upgrade',
                NULL, NULL, 0, 'failed', 2, 'offline', 1700000001, 1700000002
            );
            """)
    }
}

/// Builds a pre-v9 file with every table v9 touches or the assertions read: accounts,
/// folders, messages (no `cc` column yet), bodies, attachment metadata and sync cursors.
/// v1–v8 are recorded as applied so opening the file runs exactly the v9 step.
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

            CREATE TABLE attachments (
                account_id TEXT NOT NULL,
                folder_id TEXT NOT NULL,
                message_id TEXT NOT NULL,
                file_reference TEXT NOT NULL,
                display_name TEXT NOT NULL,
                size INTEGER,
                cache_path TEXT,
                downloaded_at REAL,
                PRIMARY KEY (account_id, folder_id, message_id, file_reference)
            );

            CREATE VIRTUAL TABLE messages_fts USING fts5(
                subject, sender, body, tokenize='trigram'
            );

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

            INSERT INTO attachments (
                account_id, folder_id, message_id, file_reference, display_name, size, cache_path, downloaded_at
            ) VALUES (
                'account-1', '13', '101', '1', 'a.pdf', 123, '/tmp/101-1.pdf', 1700000002
            );

            INSERT INTO sync_state (account_id, collection, sync_key, last_sync_at, last_error)
            VALUES
                ('account-1', 'folders', 'folders-key-9', 1700000000, NULL),
                ('account-1', '13', 'msg-key-9', 1700000000, NULL),
                ('account-1', 'drafts', 'draft-key-9', 1700000000, NULL);
            """)
    }
}
