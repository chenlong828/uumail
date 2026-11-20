import EASClient
import Foundation
import MailDomain

/// Adapts the EAS client to the domain gateway port. This is the anti-corruption
/// point: EAS status codes become `MailError` here and nowhere else.
public struct EASAdapter: MailGateway, MailWriteGateway {
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
            return Self.delta(result)
        } catch {
            throw Self.map(error)
        }
    }

    // MARK: - Write port

    public func markRead(collectionID: String, serverID: String, syncKey: String) async throws -> MessageDelta {
        do {
            let result = try await client.sync(
                collectionID: collectionID,
                syncKey: syncKey,
                change: .read(serverID: serverID)
            )
            return Self.delta(result)
        } catch {
            throw Self.map(error)
        }
    }

    public func delete(collectionID: String, serverID: String, syncKey: String) async throws -> MessageDelta {
        do {
            let result = try await client.sync(
                collectionID: collectionID,
                syncKey: syncKey,
                change: .delete(serverID: serverID)
            )
            return Self.delta(result)
        } catch {
            throw Self.map(error)
        }
    }

    /// Read and write responses share one shape; both keep every field the server sent.
    private static func delta(_ result: SyncResult) -> MessageDelta {
        MessageDelta(
            added: result.added.map(Self.message),
            changed: result.changed.map(Self.message),
            removedServerIDs: result.removedServerIDs,
            syncKey: result.syncKey,
            moreAvailable: result.moreAvailable
        )
    }

    /// Keeps the gateway's own flags: `EASClient` already retries a truncated body
    /// without a cap, but the server can still answer short — the scene turns that
    /// into the "正文过长" note.
    public func fetchBody(collectionID: String, serverID: String) async throws -> FetchedBody {
        do {
            let fetched = try await client.fetchBody(collectionID: collectionID, serverID: serverID)
            return FetchedBody(
                text: fetched.payload,
                isHTML: fetched.isHTML,
                isTruncated: fetched.isTruncated
            )
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
                Attachment(
                    displayName: $0.displayName,
                    fileReference: $0.fileReference,
                    size: $0.size,
                    contentID: $0.contentID
                )
            },
            cc: message.cc
        )
    }

    /// The single EAS → domain error mapping. Nothing above this layer sees `EASError`.
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
