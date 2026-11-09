import EASClient
import Foundation
import MailStore
import SyncEngine

/// Adapts the EAS client to the sync engine's gateway port. This is the anti-corruption
/// point: EAS status codes become domain errors here and nowhere else.
struct EASGateway: MailGateway {
    let client: EASClient

    func provisionIfNeeded() async throws {
        if await client.currentPolicyKey() == nil {
            do {
                _ = try await client.provision()
            } catch {
                throw Self.map(error)
            }
        }
    }

    func fetchFolders(syncKey: String) async throws -> FolderListing {
        do {
            let result = try await client.folderSync(syncKey: syncKey)
            return FolderListing(
                folders: result.folders.map {
                    FolderSummary(
                        serverID: $0.serverID,
                        parentID: $0.parentID,
                        displayName: $0.displayName,
                        type: $0.type
                    )
                },
                syncKey: result.syncKey
            )
        } catch {
            throw Self.map(error)
        }
    }

    func fetchMessages(collectionID: String, syncKey: String, window: Int) async throws -> MessageDelta {
        do {
            let result = try await client.sync(collectionID: collectionID, syncKey: syncKey, window: window)
            return MessageDelta(
                added: result.added.map(Self.summary),
                changed: result.changed.map(Self.summary),
                removedServerIDs: result.removedServerIDs,
                syncKey: result.syncKey,
                moreAvailable: result.moreAvailable
            )
        } catch {
            throw Self.map(error)
        }
    }

    private static func summary(_ message: EASMessage) -> MessageSummary {
        MessageSummary(
            serverID: message.serverID,
            subject: message.subject,
            sender: message.from,
            recipients: message.to,
            receivedRaw: message.dateReceived,
            isRead: message.isRead ?? false,
            importance: message.importance,
            bodyPreview: message.bodyPreview
        )
    }

    static func map(_ error: Error) -> MailGatewayError {
        guard let eas = error as? EASError else {
            return .offline
        }
        switch eas {
        case .authFailed: return .authFailed
        case .deviceNotRegistered: return .deviceNotRegistered
        case .policyRequired: return .policyBlocked
        case .syncKeyInvalid: return .syncKeyInvalid
        case .throttled(let after): return .throttled(retryAfterSeconds: after)
        case .transient: return .offline
        case .gatewayRejected, .protocolRejected, .permanent, .malformedResponse:
            return .unsupported
        }
    }
}

/// Adapts MailStore to the sync engine's store port.
struct StoreAdapter: SyncStore {
    let store: MailStore
    let account: AccountID

    func folders(_ ref: AccountRef) async throws -> [FolderSummary] {
        try store.folders(account: account).map {
            FolderSummary(
                serverID: $0.serverID,
                parentID: $0.parentID,
                displayName: $0.displayName,
                type: $0.type
            )
        }
    }

    func applyFolderSnapshot(_ ref: AccountRef, folders: [FolderSummary], syncKey: String) async throws {
        try store.applyFolderSnapshot(
            account: account,
            folders: folders.map {
                MailFolder(serverID: $0.serverID, parentID: $0.parentID, displayName: $0.displayName, type: $0.type)
            },
            syncKey: syncKey
        )
    }

    func syncKey(_ ref: AccountRef, collection: String) async throws -> String? {
        try store.syncKey(account: account, collection: collection)
    }

    func applySyncBatch(_ ref: AccountRef, folder: String, delta: MessageDelta) async throws {
        try store.applySyncBatch(
            account: account,
            folder: folder,
            added: delta.added.map(Self.mailMessage),
            changed: delta.changed.map(Self.mailMessage),
            removedServerIDs: delta.removedServerIDs,
            syncKey: delta.syncKey
        )
    }

    func resetCollection(_ ref: AccountRef, folder: String) async throws {
        try store.resetCollection(account: account, folder: folder)
    }

    private static func mailMessage(_ message: MessageSummary) -> MailMessage {
        MailMessage(
            serverID: message.serverID,
            subject: message.subject,
            sender: message.sender,
            recipients: message.recipients,
            receivedRaw: message.receivedRaw,
            isRead: message.isRead,
            importance: message.importance,
            bodyPreview: message.bodyPreview
        )
    }
}
