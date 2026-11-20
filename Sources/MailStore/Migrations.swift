import GRDB

/// Forward-only schema history for `MailStore`. Registrations are kept in their
/// historical order; GRDB records identifiers, so old databases only run the steps
/// they have not seen yet.
enum MailStoreMigrations {
    static func register(on migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1_accounts_folders") { db in
            try db.execute(sql: """
                CREATE TABLE accounts (
                    id TEXT PRIMARY KEY,
                    display_name TEXT NOT NULL,
                    address TEXT NOT NULL,
                    host TEXT NOT NULL,
                    state TEXT NOT NULL,
                    created_at REAL NOT NULL
                );

                CREATE TABLE device_profiles (
                    account_id TEXT PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
                    device_id TEXT NOT NULL,
                    device_type TEXT NOT NULL,
                    protocol_version TEXT NOT NULL,
                    user_agent TEXT NOT NULL
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

                CREATE INDEX idx_folders_account_type ON folders(account_id, type);

                CREATE TABLE sync_state (
                    account_id TEXT NOT NULL,
                    collection TEXT NOT NULL,
                    sync_key TEXT NOT NULL,
                    last_sync_at REAL,
                    last_error TEXT,
                    PRIMARY KEY (account_id, collection)
                );
                """)
        }

        migrator.registerMigration("v2_messages") { db in
            try db.execute(sql: """
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
                    deleted_at REAL,
                    updated_at REAL NOT NULL,
                    PRIMARY KEY (account_id, folder_id, server_id)
                );

                CREATE INDEX idx_messages_page
                    ON messages(account_id, folder_id, received_raw DESC);

                CREATE TABLE message_bodies (
                    account_id TEXT NOT NULL,
                    folder_id TEXT NOT NULL,
                    server_id TEXT NOT NULL,
                    text TEXT,
                    fetched_at REAL,
                    PRIMARY KEY (account_id, folder_id, server_id)
                );
                """)
        }
        migrator.registerMigration("v3_body_html") { db in
            try db.execute(sql: "ALTER TABLE message_bodies ADD COLUMN is_html INTEGER NOT NULL DEFAULT 0")
        }

        migrator.registerMigration("v6_search") { db in
            try db.execute(sql: """
                CREATE VIRTUAL TABLE messages_fts USING fts5(
                    subject, sender, body, tokenize='trigram'
                );
                """)
        }

        migrator.registerMigration("v5_outbox") { db in
            try db.execute(sql: """
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
                """)
        }

        migrator.registerMigration("v4_attachments") { db in
            try db.execute(sql: """
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
                """)
        }
        // Previews are envelope data: they belong on `messages` and never in the body
        // table, which holds fetched bodies only (see doc/design/components/CMP-STORE/spec.md).
        migrator.registerMigration("v7_preview_split") { db in
            try db.execute(sql: "ALTER TABLE messages ADD COLUMN preview TEXT")
            try db.execute(sql: """
                UPDATE messages SET preview = (
                    SELECT b.text FROM message_bodies b
                    WHERE b.account_id = messages.account_id
                      AND b.folder_id = messages.folder_id
                      AND b.server_id = messages.server_id
                      AND b.is_html = 0
                );
                DELETE FROM message_bodies WHERE is_html = 0;
                """)
        }
        // Outbox v2 (architecture spec §4.4 / D7): explicit retry state plus the
        // lease and backoff columns. Additive migration, forward-only.
        migrator.registerMigration("v8_outbox_v2") { db in
            try db.execute(sql: "ALTER TABLE outbox ADD COLUMN sending_since REAL")
            try db.execute(sql: "ALTER TABLE outbox ADD COLUMN next_attempt_at REAL")
            try db.execute(sql: "UPDATE outbox SET state = 'failed_retryable' WHERE state = 'failed'")
        }
        // Messages gain the Cc envelope header for reply-all. Rewinding message cursors
        // (not folder cursors) makes the next sync re-pull the recent window and fill
        // `cc` in place; bodies and attachment caches are left untouched. Older mail
        // keeps `cc = NULL` rather than a fabricated value.
        migrator.registerMigration("v9_message_cc") { db in
            try db.execute(sql: "ALTER TABLE messages ADD COLUMN cc TEXT")
            try db.execute(sql: "UPDATE sync_state SET sync_key = '0' WHERE collection <> 'folders'")
        }
        // Outbox v3 (REQ-0021 / SCN-0016): an optional HTML alternative next to the
        // plain-text body. Additive and forward-only: old rows keep NULL and still
        // deliver as text/plain.
        migrator.registerMigration("v10_outbox_html") { db in
            try db.execute(sql: "ALTER TABLE outbox ADD COLUMN body_html TEXT")
        }
        // Inline images (REQ-0025 / SCN-0019, 2026-11-21): persist the MIME ContentId the
        // gateway reports so `cid:` references resolve without leaning on file names.
        // Additive and forward-only: rows synced before v11 keep NULL until the next sync.
        migrator.registerMigration("v11_attachment_content_id") { db in
            try db.execute(sql: "ALTER TABLE attachments ADD COLUMN content_id TEXT")
            // Old attachment rows have no ContentId, and an incremental Sync only returns
            // items that changed. Rewind the message cursors so the next run re-pulls the
            // recent window once and fills the column; bodies and the attachment cache are
            // untouched (same mechanism as v9).
            try db.execute(sql: "UPDATE sync_state SET sync_key = '0' WHERE collection <> 'folders'")
        }
    }
}
