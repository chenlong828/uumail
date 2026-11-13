import EASClient
import Foundation
import MailDomain
import MailStore
import SyncEngine

/// Adapts the EAS client to the domain gateway port. This is the anti-corruption
/// point: EAS status codes become `MailError` here and nowhere else.
public struct EASGateway: MailGateway {
    public let client: EASClient
    public init(client: EASClient) { self.client = client }

    public func probe() async throws -> ServerCapabilities {
        do {
            let capabilities = try await client.options()
            return ServerCapabilities(
                protocolVersions: capabilities.protocolVersions,
                commands: capabilities.commands
            )
        } catch {
            throw Self.map(error)
        }
    }

    public func provisionIfNeeded() async throws {
        if await client.currentPolicyKey() == nil {
            do {
                _ = try await client.provision()
            } catch {
                throw Self.map(error)
            }
        }
    }

    public func fetchFolders(syncKey: String) async throws -> FolderListing {
        do {
            let result = try await client.folderSync(syncKey: syncKey)
            return FolderListing(
                folders: result.folders.map {
                    Folder(
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

    public func fetchMessages(collectionID: String, syncKey: String, window: Int, filterType: Int) async throws -> MessageDelta {
        do {
            let result = try await client.sync(
                collectionID: collectionID, syncKey: syncKey, window: window, filterType: filterType
            )
            return MessageDelta(
                added: result.added.map(Self.message),
                changed: result.changed.map(Self.message),
                removedServerIDs: result.removedServerIDs,
                syncKey: result.syncKey,
                moreAvailable: result.moreAvailable
            )
        } catch {
            throw Self.map(error)
        }
    }

    /// The port exposes the payload only; truncation is re-fetched inside `EASClient`
    /// and is not part of the domain contract (the pane treats a short body as normal).
    public func fetchBody(collectionID: String, serverID: String) async throws -> String {
        do {
            return try await client.fetchBody(collectionID: collectionID, serverID: serverID).payload
        } catch {
            throw Self.map(error)
        }
    }

    public func fetchAttachment(fileReference: String) async throws -> Data {
        do {
            return try await client.fetchAttachment(fileReference: fileReference)
        } catch {
            throw Self.map(error)
        }
    }

    public func send(mime: Data, clientID: String) async throws {
        do {
            try await client.send(mime: mime, clientID: clientID)
        } catch {
            throw Self.map(error)
        }
    }

    private static func message(_ message: EASMessage) -> Message {
        Message(
            serverID: message.serverID,
            subject: message.subject,
            sender: message.from,
            recipients: message.to,
            receivedRaw: message.dateReceived,
            isRead: message.isRead ?? false,
            importance: message.importance,
            bodyPreview: message.bodyPreview,
            attachments: message.attachments.map {
                Attachment(displayName: $0.displayName, fileReference: $0.fileReference, size: $0.size)
            }
        )
    }

    public static func map(_ error: Error) -> MailError {
        guard let eas = error as? EASError else {
            return .offline
        }
        switch eas {
        case .authFailed: return .authFailed
        case .deviceNotRegistered: return .deviceNotRegistered
        case .policyRequired: return .policyBlocked
        case .syncKeyInvalid: return .syncKeyInvalid
        case .throttled(let after): return .throttled(seconds: after)
        case .transient: return .offline
        case .gatewayRejected, .protocolRejected, .permanent, .malformedResponse:
            return .unsupported
        }
    }
}

/// Adapts MailStore to the sync store port. Both sides now speak the domain values,
/// so this is a straight pass-through until the adapter is deleted (T-1110-02).
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
