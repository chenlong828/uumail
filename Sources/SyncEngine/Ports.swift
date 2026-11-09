import Foundation

/// The account the engine works on. Opaque to the engine; adapters map it to the
/// store's own identifier.
public struct AccountRef: Hashable, Sendable {
    public let raw: String

    public init(_ raw: String) {
        self.raw = raw
    }
}

/// Gateway port: implemented by the EAS anti-corruption layer, or by a fake in tests.
public protocol MailGateway: Sendable {
    func provisionIfNeeded() async throws
    func fetchFolders(syncKey: String) async throws -> FolderListing
    func fetchMessages(collectionID: String, syncKey: String, window: Int, filterType: Int) async throws -> MessageDelta
}

/// Store port: implemented by MailStore at the composition root, or by a fake in tests.
public protocol SyncStore: Sendable {
    func folders(_ account: AccountRef) async throws -> [FolderSummary]
    func applyFolderSnapshot(_ account: AccountRef, folders: [FolderSummary], syncKey: String) async throws
    func syncKey(_ account: AccountRef, collection: String) async throws -> String?
    func applySyncBatch(_ account: AccountRef, folder: String, delta: MessageDelta) async throws
    /// Drops the local mirror of one collection so a full re-sync can rebuild it.
    func resetCollection(_ account: AccountRef, folder: String) async throws
}
