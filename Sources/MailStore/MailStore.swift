import Foundation
import GRDB

/// The single writer for the local mail database (see `doc/design/components/CMP-STORE/spec.md`).
/// This slice owns accounts, device profiles, folders and sync state; message tables arrive
/// with the sync work.
public final class MailStore: @unchecked Sendable {
    private let dbQueue: DatabaseQueue

    public init(path: String) throws {
        dbQueue = try DatabaseQueue(path: path)
        try migrate()
    }

    public static func inMemory() throws -> MailStore {
        let store = try MailStore(path: ":memory:")
        return store
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()
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
        try migrator.migrate(dbQueue)
    }

    // MARK: - Accounts

    @discardableResult
    public func createAccount(_ draft: NewAccount) throws -> AccountID {
        let id = AccountID(UUID().uuidString)
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO accounts (id, display_name, address, host, state, created_at)
                    VALUES (?, ?, ?, ?, 'draft', ?)
                    """,
                arguments: [id.raw, draft.displayName, draft.address, draft.host, Date().timeIntervalSince1970]
            )
        }
        return id
    }

    public func account(_ id: AccountID) throws -> (displayName: String, address: String)? {
        try dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT display_name, address FROM accounts WHERE id = ?", arguments: [id.raw])
                .map { ($0["display_name"], $0["address"]) }
        }
    }

    // MARK: - Folders

    public func folders(account id: AccountID) throws -> [StoredFolder] {
        try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT server_id, parent_id, display_name, type
                    FROM folders
                    WHERE account_id = ? AND deleted_at IS NULL
                    ORDER BY CASE type WHEN 2 THEN 0 WHEN 3 THEN 1 WHEN 4 THEN 2 WHEN 5 THEN 3 ELSE 9 END,
                             display_name
                    """,
                arguments: [id.raw]
            ).map { row in
                StoredFolder(
                    serverID: row["server_id"],
                    parentID: row["parent_id"],
                    displayName: row["display_name"],
                    type: row["type"]
                )
            }
        }
    }

    /// Applies a folder snapshot in one transaction: upserts, soft-deletes the given
    /// server ids, and advances the folder sync key. A throw rolls the whole batch back.
    public func applyFolderSnapshot(
        account id: AccountID,
        folders incoming: [MailFolder],
        removedServerIDs: [String] = [],
        syncKey: String
    ) throws {
        for folder in incoming where folder.serverID.isEmpty {
            throw MailStoreError.invalidFolder(reason: "empty serverID")
        }

        try dbQueue.write { db in
            guard try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM accounts WHERE id = ?)", arguments: [id.raw]) == true else {
                throw MailStoreError.accountNotFound(id)
            }

            let now = Date().timeIntervalSince1970
            for folder in incoming {
                try db.execute(
                    sql: """
                        INSERT INTO folders (account_id, server_id, parent_id, display_name, type, deleted_at, updated_at)
                        VALUES (?, ?, ?, ?, ?, NULL, ?)
                        ON CONFLICT(account_id, server_id) DO UPDATE SET
                            parent_id = excluded.parent_id,
                            display_name = excluded.display_name,
                            type = excluded.type,
                            deleted_at = NULL,
                            updated_at = excluded.updated_at
                        """,
                    arguments: [id.raw, folder.serverID, folder.parentID, folder.displayName, folder.type, now]
                )
            }

            for serverID in removedServerIDs {
                try db.execute(
                    sql: """
                        UPDATE folders SET deleted_at = ?, updated_at = ?
                        WHERE account_id = ? AND server_id = ? AND deleted_at IS NULL
                        """,
                    arguments: [now, now, id.raw, serverID]
                )
            }

            try db.execute(
                sql: """
                    INSERT INTO sync_state (account_id, collection, sync_key, last_sync_at)
                    VALUES (?, 'folders', ?, ?)
                    ON CONFLICT(account_id, collection) DO UPDATE SET
                        sync_key = excluded.sync_key,
                        last_sync_at = excluded.last_sync_at,
                        last_error = NULL
                    """,
                arguments: [id.raw, syncKey, now]
            )
        }
    }

    // MARK: - Sync state

    public func syncKey(account id: AccountID, collection: String) throws -> String? {
        try dbQueue.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT sync_key FROM sync_state WHERE account_id = ? AND collection = ?",
                arguments: [id.raw, collection]
            )
        }
    }
}
