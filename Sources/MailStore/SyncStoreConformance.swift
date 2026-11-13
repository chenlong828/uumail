import Foundation
import MailDomain

/// `MailStore` is the `SyncStore` implementation. The port uses the domain shapes
/// (`folder:` and `delta:`), while the store keeps the batch primitives it has always
/// had; these forwarders are the only glue (spec §4.4/D6 replaces `StoreAdapter`).
extension MailStore: SyncStore {
    public func folders(_ account: AccountID) throws -> [Folder] {
        try folders(account: account)
    }

    public func applyFolderSnapshot(_ account: AccountID, folders: [Folder], syncKey: String) throws {
        try applyFolderSnapshot(account: account, folders: folders, syncKey: syncKey)
    }

    public func syncKey(_ account: AccountID, collection: String) throws -> String? {
        try syncKey(account: account, collection: collection)
    }

    public func applySyncBatch(_ account: AccountID, folder: String, delta: MessageDelta) throws {
        try applySyncBatch(
            account: account,
            folder: folder,
            added: delta.added,
            changed: delta.changed,
            removedServerIDs: delta.removedServerIDs,
            syncKey: delta.syncKey
        )
    }

    public func resetCollection(_ account: AccountID, folder: String) throws {
        try resetCollection(account: account, folder: folder)
    }
}
