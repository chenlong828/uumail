import Foundation
import MailDomain
import MailStore

/// Adapts MailStore to the sync store port. Both sides now speak the domain values,
/// so this is a straight pass-through until `MailStore` conforms directly.
public struct StoreAdapter: SyncStore {
    public let store: MailStore
    public init(store: MailStore) { self.store = store }

    public func folders(_ account: AccountID) throws -> [Folder] {
        try store.folders(account: account)
    }

    public func applyFolderSnapshot(_ account: AccountID, folders: [Folder], syncKey: String) throws {
        try store.applyFolderSnapshot(account: account, folders: folders, syncKey: syncKey)
    }

    public func syncKey(_ account: AccountID, collection: String) throws -> String? {
        try store.syncKey(account: account, collection: collection)
    }

    public func applySyncBatch(_ account: AccountID, folder: String, delta: MessageDelta) throws {
        try store.applySyncBatch(
            account: account,
            folder: folder,
            added: delta.added,
            changed: delta.changed,
            removedServerIDs: delta.removedServerIDs,
            syncKey: delta.syncKey
        )
    }

    public func resetCollection(_ account: AccountID, folder: String) throws {
        try store.resetCollection(account: account, folder: folder)
    }
}
