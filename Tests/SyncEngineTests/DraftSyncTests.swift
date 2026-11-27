import Foundation
import MailDomain
import MailStore
import SyncContract
import Testing

@testable import SyncEngine

final class DraftSyncGatewayStub: MailGateway, @unchecked Sendable {
    var folders: [Folder]
    var delta: MessageDelta
    var bodies: [String: FetchedBody] = [:]
    /// Models the gateway's status 3/4 on a window Sync over an empty Drafts collection.
    var emptyWindowIsInvalid = false

    init(folders: [Folder], delta: MessageDelta, bodies: [String: FetchedBody] = [:]) {
        self.folders = folders
        self.delta = delta
        self.bodies = bodies
    }

    func probe() async throws -> ServerCapabilities {
        ServerCapabilities(protocolVersions: ["16.1"], commands: ["Sync"])
    }

    func provisionIfNeeded() async throws {}
    func fetchFolders(syncKey: String) async throws -> FolderListing {
        FolderListing(folders: folders, syncKey: "F1")
    }

    func fetchMessages(
        collectionID: String, syncKey: String, window: Int, filterType: Int
    ) async throws -> MessageDelta {
        if emptyWindowIsInvalid, syncKey != "0" {
            throw MailError.syncKeyInvalid
        }
        return delta
    }

    func fetchBody(collectionID: String, serverID: String) async throws -> FetchedBody {
        bodies[serverID] ?? FetchedBody(text: "", isHTML: false, isTruncated: false)
    }

    func fetchAttachment(fileReference: String) async throws -> Data { Data() }
    func send(mime: Data, clientID: String) async throws {}
}

final class DraftWriteStub: MailWriteGateway, @unchecked Sendable {
    var created: [DraftPayload] = []
    var updated: [String] = []
    var deleted: [String] = []
    var nextServerID = "S-new"
    var key = 10

    func markRead(collectionID: String, serverID: String, syncKey: String) async throws -> MessageDelta {
        throw MailError.unsupported
    }

    func delete(collectionID: String, serverID: String, syncKey: String) async throws -> MessageDelta {
        throw MailError.unsupported
    }

    func createDraft(
        _ payload: DraftPayload, collectionID: String, syncKey: String, clientID: String
    ) async throws -> DraftWriteResult {
        created.append(payload)
        key += 1
        return DraftWriteResult(serverID: nextServerID, syncKey: String(key))
    }

    func updateDraft(
        serverID: String, payload: DraftPayload, collectionID: String, syncKey: String
    ) async throws -> DraftWriteResult {
        updated.append(serverID)
        key += 1
        return DraftWriteResult(serverID: serverID, syncKey: String(key))
    }

    func deleteDraft(
        serverID: String, collectionID: String, syncKey: String
    ) async throws -> DraftWriteResult {
        deleted.append(serverID)
        key += 1
        return DraftWriteResult(serverID: nil, syncKey: String(key))
    }
}

@Suite("Draft sync")
struct DraftSyncTests {
    private func fixture() throws -> (store: MailStore, account: AccountID) {
        let store = try MailStore.inMemory()
        let account = try store.createAccount(
            NewAccount(displayName: "jdoe", address: "jdoe@corp.test", host: "mail.corp.test")
        )
        try store.applyFolderSnapshot(account: account, folders: [
            Folder(serverID: "4", parentID: "0", displayName: "草稿", type: 3),
            Folder(serverID: "13", parentID: "0", displayName: "收件箱", type: 2),
        ], syncKey: "F1")
        return (store, account)
    }

    private func engine(
        store: MailStore, account: AccountID,
        gateway: DraftSyncGatewayStub, write: DraftWriteStub
    ) -> SyncEngine {
        SyncEngine(
            gateway: gateway, store: store, account: account,
            writeGateway: write, draftStore: store
        )
    }

    @Test("server drafts are downloaded and bound to local rows")
    func downloadsServerDrafts() async throws {
        let (store, account) = try fixture()
        let gateway = DraftSyncGatewayStub(
            folders: [], delta: MessageDelta(
                added: [Message(
                    serverID: "S1", subject: "服务器草稿",
                    recipients: "a@b.c", receivedRaw: "2026-11-27T05:00:00.000Z"
                )],
                changed: [], removedServerIDs: [], syncKey: "K2", moreAvailable: false
            ),
            bodies: ["S1": FetchedBody(text: "<p>服务器正文</p>", isHTML: true, isTruncated: false)]
        )
        let write = DraftWriteStub()

        let report = try await engine(store: store, account: account, gateway: gateway, write: write)
            .syncDraftsOnce()

        #expect(report?.downloaded == 1)
        let drafts = try store.outbox.drafts(account: account)
        #expect(drafts.count == 1)
        #expect(drafts.first?.serverID == "S1")
        #expect(drafts.first?.subject == "服务器草稿")
        #expect(drafts.first?.bodyHTML?.contains("服务器正文") == true)
        #expect(write.created.isEmpty)
        #expect(try store.syncKey(account: account, collection: "4") == "K2")
    }

    @Test("local-only drafts are uploaded and bound")
    func uploadsLocalDraft() async throws {
        let (store, account) = try fixture()
        let gateway = DraftSyncGatewayStub(folders: [], delta: MessageDelta(
            added: [], changed: [], removedServerIDs: [], syncKey: "K1", moreAvailable: false
        ))
        let write = DraftWriteStub()
        try store.outbox.saveDraft(
            account: account,
            draft: MailDraft(to: "a@b.c", cc: nil, subject: "本地草稿", body: "text", isDraft: true)
        )

        let report = try await engine(store: store, account: account, gateway: gateway, write: write)
            .syncDraftsOnce()

        #expect(report?.uploaded == 1)
        #expect(write.created.count == 1)
        #expect(write.created.first?.subject == "本地草稿")
        let drafts = try store.outbox.drafts(account: account)
        #expect(drafts.first?.serverID == "S-new")
        #expect(drafts.first?.draftHash == drafts.first?.fingerprint)
    }

    @Test("a both-sides change keeps both drafts and uploads the local one")
    func conflictKeepsBoth() async throws {
        let (store, account) = try fixture()
        let gateway = DraftSyncGatewayStub(
            folders: [], delta: MessageDelta(
                added: [Message(
                    serverID: "S1", subject: "服务器版",
                    recipients: "a@b.c", receivedRaw: "2026-11-27T06:00:00.000Z"
                )],
                changed: [], removedServerIDs: [], syncKey: "K2", moreAvailable: false
            ),
            bodies: ["S1": FetchedBody(text: "<p>服务器新正文</p>", isHTML: true, isTruncated: false)]
        )
        let write = DraftWriteStub()
        let id = try store.outbox.saveDraft(
            account: account,
            draft: MailDraft(to: "a@b.c", cc: nil, subject: "本地旧", body: "旧", isDraft: true)
        )
        try store.outbox.bindDraft(account: account, draftID: id, serverID: "S1", hash: "stale")
        _ = try store.outbox.updateDraft(
            account: account, draftID: id,
            draft: MailDraft(to: "a@b.c", cc: nil, subject: "本地改", body: "新", isDraft: true)
        )

        let report = try await engine(store: store, account: account, gateway: gateway, write: write)
            .syncDraftsOnce()

        #expect(report?.conflicts == 1)
        let drafts = try store.outbox.drafts(account: account)
        #expect(drafts.count == 2, "the server version and the user's version both stay")
        #expect(drafts.contains { $0.serverID == "S1" && $0.subject == "服务器版" })
        #expect(drafts.contains { $0.subject == "本地改" })
        #expect(write.created.count == 1, "the local copy is uploaded as the second server draft")
    }

    @Test("deleting a bound draft sends a server delete and clears the tombstone")
    func deleteTombstoneIsFlushed() async throws {
        let (store, account) = try fixture()
        let gateway = DraftSyncGatewayStub(folders: [], delta: MessageDelta(
            added: [], changed: [], removedServerIDs: [], syncKey: "K1", moreAvailable: false
        ))
        let write = DraftWriteStub()
        let id = try store.outbox.saveDraft(
            account: account,
            draft: MailDraft(to: "a@b.c", cc: nil, subject: "待删", body: "x", isDraft: true)
        )
        try store.outbox.bindDraft(account: account, draftID: id, serverID: "S9", hash: "h")
        _ = try store.outbox.deleteDraft(account: account, draftID: id)
        #expect(try store.outbox.draftTombstones(account: account) == ["S9"])

        let report = try await engine(store: store, account: account, gateway: gateway, write: write)
            .syncDraftsOnce()

        #expect(report?.deleted == 1)
        #expect(write.deleted == ["S9"])
        #expect(try store.outbox.draftTombstones(account: account).isEmpty)
        #expect(try store.outbox.drafts(account: account).isEmpty)
    }

    @Test("an empty Drafts collection with status 3/4 still uploads local drafts")
    func emptyCollectionStillPushes() async throws {
        let (store, account) = try fixture()
        let gateway = DraftSyncGatewayStub(folders: [], delta: MessageDelta(
            added: [], changed: [], removedServerIDs: [], syncKey: "K0", moreAvailable: false
        ))
        gateway.emptyWindowIsInvalid = true
        let write = DraftWriteStub()
        try store.outbox.saveDraft(
            account: account,
            draft: MailDraft(to: "a@b.c", cc: nil, subject: "空目录草稿", body: "x", isDraft: true)
        )

        let report = try await engine(store: store, account: account, gateway: gateway, write: write)
            .syncDraftsOnce()

        #expect(report?.uploaded == 1)
        #expect(write.created.count == 1)
        #expect(try store.outbox.drafts(account: account).first?.serverID == "S-new")
    }

    @Test("a tombstoned draft is not resurrected by the pull")
    func tombstoneSkipsPull() async throws {
        let (store, account) = try fixture()
        let gateway = DraftSyncGatewayStub(
            folders: [], delta: MessageDelta(
                added: [Message(
                    serverID: "S1", subject: "已删草稿",
                    recipients: "a@b.c", receivedRaw: "2026-11-27T06:00:00.000Z"
                )],
                changed: [], removedServerIDs: [], syncKey: "K2", moreAvailable: false
            ),
            bodies: ["S1": FetchedBody(text: "<p>x</p>", isHTML: true, isTruncated: false)]
        )
        let write = DraftWriteStub()
        let id = try store.outbox.saveDraft(
            account: account,
            draft: MailDraft(to: "a@b.c", cc: nil, subject: "已删草稿", body: "x", isDraft: true)
        )
        try store.outbox.bindDraft(account: account, draftID: id, serverID: "S1", hash: "h")
        _ = try store.outbox.deleteDraft(account: account, draftID: id)

        _ = try await engine(store: store, account: account, gateway: gateway, write: write)
            .syncDraftsOnce()

        #expect(try store.outbox.drafts(account: account).isEmpty, "the deleted draft stays deleted")
        #expect(write.deleted == ["S1"])
    }

    @Test("sending a bound draft tombstones the server copy")
    func sendingBoundDraftDeletesServerDraft() async throws {
        let (store, account) = try fixture()
        let gateway = DraftSyncGatewayStub(folders: [], delta: MessageDelta(
            added: [], changed: [], removedServerIDs: [], syncKey: "K1", moreAvailable: false
        ))
        let write = DraftWriteStub()
        let id = try store.outbox.saveDraft(
            account: account,
            draft: MailDraft(to: "a@b.c", cc: nil, subject: "要发", body: "x", isDraft: true)
        )
        try store.outbox.bindDraft(account: account, draftID: id, serverID: "S8", hash: "h")
        _ = try store.outbox.sendDraft(
            account: account, draftID: id,
            draft: MailDraft(to: "a@b.c", cc: nil, subject: "要发", body: "x", isDraft: true)
        )

        _ = try await engine(store: store, account: account, gateway: gateway, write: write)
            .syncDraftsOnce()

        #expect(write.deleted == ["S8"])
        #expect(try store.outbox.draftTombstones(account: account).isEmpty)
    }
}
