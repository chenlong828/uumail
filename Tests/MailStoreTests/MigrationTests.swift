import Foundation
import GRDB
import MailDomain
import Testing

@testable import MailStore

/// Schema gate 4 from architecture spec §8: an old database opens, migrates and keeps
/// its data. The fixture is a *partial* pre-v8 database: it carries the two tables the
/// migration and the assertions need (`accounts`, pre-v8 `outbox`), and records v1–v7 as
/// already applied so that opening the file runs only `v8_outbox_v2`. The other pre-v8
/// tables are not touched by that migration or by the assertions; recreating them would
/// duplicate the whole schema in the test.
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
        let item = try #require(try store.outboxItem(account: account, id: OutboxID("outbox-1")))
        #expect(item.state == "failed_retryable")
        #expect(item.to == "a@b.c")
        #expect(item.subject == "old draft")
        #expect(item.body == "queued before the upgrade")
        #expect(item.cc == nil)
        #expect(item.attempts == 2)
        #expect(item.lastError == "offline")
        #expect(item.nextAttemptAt == nil)

        // The renamed state is deliverable again: no backoff was stored by the old row.
        let claimed = try store.claimOutbox(
            account: account,
            now: Date(timeIntervalSince1970: 2_000),
            lease: .seconds(120)
        )
        #expect(claimed?.id == "outbox-1")
        #expect(claimed?.state == "sending")
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
