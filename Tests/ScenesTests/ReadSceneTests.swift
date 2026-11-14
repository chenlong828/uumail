import Foundation
import MailDomain
import MailStore
import SyncEngine
import Testing

@testable import Scenes
import SyncEngine

@Suite("ReadScene")
struct ReadSceneTests {
    private let ref = MessageRef(folderID: "13", serverID: "m1")

    private func makeScene(
        store: MailStore,
        account: AccountID,
        gateway: FakeGateway,
        files: FakeAttachmentFiles = FakeAttachmentFiles(),
        write: any MailWriteGateway = UnsupportedWriteGateway()
    ) -> ReadScene {
        let engine = SyncEngine(
            gateway: gateway, store: store, account: account,
            writeGateway: write, sleeper: { _ in }
        )
        return ReadScene(store: store, account: account, gateway: gateway, files: files, writeEngine: engine)
    }

    @Test("a cached body is yielded without touching the gateway")
    func cachedBodySkipsGateway() async throws {
        let (store, account) = try seededReadStore()
        try store.applyBody(account: account, folder: "13", serverID: "m1", html: "<p>cached</p>")
        let gateway = FakeGateway()
        let scene = makeScene(store: store, account: account, gateway: gateway)

        var events: [BodyEvent] = []
        for await event in scene.open(ref) {
            events.append(event)
        }

        #expect(events == [.cached("<p>cached</p>")])
        #expect(await gateway.bodyCalls == 0, "the read path never fetches a cached body")
    }

    @Test("a missing body is fetched once, stored as HTML, then yielded as loaded")
    func missingBodyFetchesStoresThenYields() async throws {
        let (store, account) = try seededReadStore()
        let gateway = FakeGateway(body: FetchedBody(text: "第一行\n第二行", isHTML: false, isTruncated: true))
        let scene = makeScene(store: store, account: account, gateway: gateway)
        let expectedHTML = HTMLText.fromPlainText("第一行\n第二行")

        var events: [BodyEvent] = []
        for await event in scene.open(ref) {
            events.append(event)
        }

        #expect(events == [.loaded(FetchedBody(text: expectedHTML, isHTML: true, isTruncated: true))])
        #expect(await gateway.bodyCalls == 1)
        // The store was written before `loaded` was yielded, so a repeat open is a cache hit.
        #expect(try scene.bodyIfCached(ref) == expectedHTML)

        var second: [BodyEvent] = []
        for await event in scene.open(ref) {
            second.append(event)
        }
        #expect(second == [.cached(expectedHTML)])
        #expect(await gateway.bodyCalls == 1)
    }

    @Test("a gateway failure is yielded as failed and does not overwrite the cache")
    func failedFetchKeepsCacheEmpty() async throws {
        let (store, account) = try seededReadStore()
        let gateway = FakeGateway(bodyError: .offline)
        let scene = makeScene(store: store, account: account, gateway: gateway)

        var events: [BodyEvent] = []
        for await event in scene.open(ref) {
            events.append(event)
        }

        #expect(events == [.failed(.offline)])
        #expect(try scene.bodyIfCached(ref) == nil)
    }

    @Test("downloadAttachment returns a cached file without fetching")
    func attachmentCacheHit() async throws {
        let (store, account) = try seededReadStore()
        let files = FakeAttachmentFiles()
        let reference = AttachmentRef(fileReference: "ref-1", displayName: "报表.pdf")
        let cached = files.fileURLForTesting(reference)
        files.preload(cached, for: reference)
        let gateway = FakeGateway()
        let scene = makeScene(store: store, account: account, gateway: gateway, files: files)

        let url = try await scene.downloadAttachment(
            Attachment(displayName: "报表.pdf", fileReference: "ref-1"),
            in: ref
        )

        #expect(url == cached)
        #expect(await gateway.attachmentCalls == 0)
        #expect(files.storeCalls == 0)
    }

    @Test("downloadAttachment fetches, stores and records the cache path")
    func attachmentDownload() async throws {
        let (store, account) = try seededReadStore()
        try store.applySyncBatch(
            account: account,
            folder: "13",
            added: [
                Message(
                    serverID: "m1",
                    subject: "带附件",
                    attachments: [Attachment(displayName: "报表.pdf", fileReference: "ref-1")]
                )
            ],
            changed: [],
            removedServerIDs: [],
            syncKey: "1"
        )
        let files = FakeAttachmentFiles()
        let gateway = FakeGateway(attachmentData: Data("payload".utf8))
        let scene = makeScene(store: store, account: account, gateway: gateway, files: files)
        let attachment = try #require(scene.attachments(for: ref).first)

        let url = try await scene.downloadAttachment(attachment, in: ref)

        #expect(await gateway.attachmentCalls == 1)
        #expect(files.storeCalls == 1)
        #expect(try scene.attachments(for: ref).first?.cachePath == url.path)
    }

    @Test("folders and search read the local store only")
    func localReads() async throws {
        let (store, account) = try seededReadStore()
        try store.applySyncBatch(
            account: account,
            folder: "13",
            added: [Message(serverID: "m1", subject: "周报", sender: "a@b.c")],
            changed: [],
            removedServerIDs: [],
            syncKey: "1"
        )
        let gateway = FakeGateway()
        let scene = makeScene(store: store, account: account, gateway: gateway)

        #expect(try scene.folders().map(\.serverID) == ["13"])
        #expect(try scene.messages(folderID: "13").map(\.serverID) == ["m1"])
        #expect(try scene.search("周报").map(\.serverID) == ["m1"])
        #expect(await gateway.calls.isEmpty)
    }
}

private extension FakeAttachmentFiles {
    /// Deterministic stand-in for the real implementation's file naming (this fake does not
    /// write to disk, so the test only needs a stable URL).
    func fileURLForTesting(_ reference: AttachmentRef) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("uumail-scenes-tests")
            .appendingPathComponent("\(reference.fileReference)-\(reference.displayName)")
    }
}

@Suite("ReadScene write path")
struct ReadSceneWriteTests {
    private let ref = MessageRef(folderID: "13", serverID: "101")

    private func seeded(with write: any MailWriteGateway) throws -> (ReadScene, MailStore, AccountID) {
        let (store, account) = try seededReadStore()
        try store.applySyncBatch(
            account: account,
            folder: "13",
            added: [Message(serverID: "101", subject: "目标", sender: "a@corp.test")],
            changed: [],
            removedServerIDs: [],
            syncKey: "5"
        )
        let gateway = FakeGateway()
        let engine = SyncEngine(
            gateway: gateway, store: store, account: account,
            writeGateway: write, sleeper: { _ in }
        )
        let scene = ReadScene(
            store: store, account: account, gateway: gateway,
            files: FakeAttachmentFiles(), writeEngine: engine
        )
        return (scene, store, account)
    }

    @Test("markReadLocally persists first, then writeBackMarkRead sends one gated command")
    func markReadLocallyPersistsBeforeWriteBack() async throws {
        let write = RecordingWriteGateway(delta: MessageDelta(
            added: [], changed: [], removedServerIDs: [], syncKey: "6", moreAvailable: false
        ))
        let (scene, store, account) = try seeded(with: write)

        #expect(try scene.markReadLocally(ref) == true)
        #expect(try store.messages(account: account, folder: "13").first?.isRead == true)

        let outcome = await scene.writeBackMarkRead(ref)
        #expect(outcome == .succeeded)
        #expect(await write.calls == [.markRead(collectionID: "13", serverID: "101", key: "5")])
        #expect(try store.syncKey(account: account, collection: "13") == "6")
    }

    @Test("a failed write-back keeps the local read and never rolls back")
    func markReadKeepsLocalReadWhenWriteBackFails() async throws {
        let write = RecordingWriteGateway(delta: MessageDelta(
            added: [], changed: [], removedServerIDs: [], syncKey: "6", moreAvailable: false
        ))
        await write.setFailure(.offline)
        let (scene, store, account) = try seeded(with: write)

        #expect(try scene.markReadLocally(ref) == true)
        let outcome = await scene.writeBackMarkRead(ref)

        #expect(outcome == .failed(.offline))
        #expect(try store.messages(account: account, folder: "13").first?.isRead == true)
        #expect(try store.syncKey(account: account, collection: "13") == "5")
    }

    @Test("deleteMessage soft-deletes only after the gateway succeeds")
    func deleteSoftDeletesOnlyAfterGatewaySuccess() async throws {
        let write = RecordingWriteGateway(delta: MessageDelta(
            added: [], changed: [], removedServerIDs: ["101"], syncKey: "7", moreAvailable: false
        ))
        let (scene, store, account) = try seeded(with: write)

        try await scene.deleteMessage(ref)

        #expect(try store.messages(account: account, folder: "13").isEmpty)
        #expect(try store.syncKey(account: account, collection: "13") == "7")
        #expect(await write.calls == [.delete(collectionID: "13", serverID: "101", key: "5")])
    }

    @Test("a failed delete leaves the row and the key in place")
    func deleteFailureDoesNotSoftDelete() async throws {
        let write = RecordingWriteGateway(delta: MessageDelta(
            added: [], changed: [], removedServerIDs: ["101"], syncKey: "7", moreAvailable: false
        ))
        await write.setFailure(.offline)
        let (scene, store, account) = try seeded(with: write)

        await expectMailError(.offline) {
            try await scene.deleteMessage(ref)
        }
        #expect(try store.messages(account: account, folder: "13").map(\.serverID) == ["101"])
        #expect(try store.syncKey(account: account, collection: "13") == "5")
    }

    @Test("deleteMessage propagates cancellation instead of folding it into storage")
    func deleteCancellationPropagates() async throws {
        let write = RecordingWriteGateway(delta: MessageDelta(
            added: [], changed: [], removedServerIDs: [], syncKey: "7", moreAvailable: false
        ))
        await write.setCancels(true)
        let (scene, store, account) = try seeded(with: write)

        await #expect(throws: CancellationError.self) {
            try await scene.deleteMessage(ref)
        }
        #expect(try store.messages(account: account, folder: "13").map(\.serverID) == ["101"])
    }

    @Test("a non-MailError delete failure is stored as storage")
    func nonMailErrorBecomesStorage() async throws {
        let write = RecordingWriteGateway(delta: MessageDelta(
            added: [], changed: [], removedServerIDs: [], syncKey: "7", moreAvailable: false
        ))
        await write.setThrowsRaw(true)
        let (scene, store, account) = try seeded(with: write)

        do {
            try await scene.deleteMessage(ref)
            Issue.record("expected storage error")
        } catch let error as MailError {
            guard case .storage(let reason) = error else {
                Issue.record("expected storage, got \(error)")
                return
            }
            #expect(reason.contains("raw"))
        }
        #expect(try store.messages(account: account, folder: "13").map(\.serverID) == ["101"])
    }
}
