import Foundation
import MailDomain
import MailStore
import Outbox
import Scenes
import SyncEngine
import Testing

import Presentation

// Test doubles for the presentation contracts. Real scenes sit behind them, so the view
// model is exercised through the same ports the app uses; nothing touches the network,
// the system Keychain or the notification center.

final class PresentationFakeGateway: MailGateway, @unchecked Sendable {
    nonisolated(unsafe) var folderListing: FolderListing
    nonisolated(unsafe) var deltas: [String: MessageDelta]
    nonisolated(unsafe) var bodyResult: Result<FetchedBody, MailError>?
    nonisolated(unsafe) var probeError: MailError?
    nonisolated(unsafe) var provisionError: MailError?
    nonisolated(unsafe) var folderError: MailError?
    nonisolated(unsafe) var attachmentData = Data()
    nonisolated(unsafe) private(set) var bodyCalls = 0
    nonisolated(unsafe) private(set) var sendCalls = 0

    init(
        folders: FolderListing = FolderListing(folders: [], syncKey: "0"),
        deltas: [String: MessageDelta] = [:],
        body: Result<FetchedBody, MailError>? = nil
    ) {
        self.folderListing = folders
        self.deltas = deltas
        self.bodyResult = body
    }

    func probe() async throws -> ServerCapabilities {
        if let probeError { throw probeError }
        return ServerCapabilities(protocolVersions: ["16.1"], commands: ["Sync"])
    }

    func provisionIfNeeded() async throws {
        if let provisionError { throw provisionError }
    }

    func fetchFolders(syncKey: String) async throws -> FolderListing {
        if let folderError { throw folderError }
        return folderListing
    }

    func fetchMessages(collectionID: String, syncKey: String, window: Int, filterType: Int) async throws -> MessageDelta {
        guard let delta = deltas[syncKey] else { throw MailError.syncKeyInvalid }
        return delta
    }

    func fetchBody(collectionID: String, serverID: String) async throws -> FetchedBody {
        bodyCalls += 1
        guard let bodyResult else { throw MailError.unsupported }
        return try bodyResult.get()
    }

    func fetchAttachment(fileReference: String) async throws -> Data {
        attachmentData
    }

    func send(mime: Data, clientID: String) async throws {
        sendCalls += 1
    }
}

final class PresentationFakeNotifier: Notifier, @unchecked Sendable {
    nonisolated(unsafe) private(set) var authorizationRequests = 0
    nonisolated(unsafe) private(set) var posts: [Int] = []

    func requestAuthorization() async { authorizationRequests += 1 }
    func postNewMail(count: Int) async { posts.append(count) }
}

final class PresentationFakeAttachmentFiles: AttachmentFiles, @unchecked Sendable {
    nonisolated(unsafe) private(set) var cache: [String: URL] = [:]

    func cachedURL(for reference: AttachmentRef) -> URL? {
        cache[reference.fileReference]
    }

    func store(_ data: Data, for reference: AttachmentRef) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(reference.fileReference)-\(reference.displayName)")
        cache[reference.fileReference] = url
        return url
    }
}

final class PresentationFakeCredentialStore: CredentialStore, @unchecked Sendable {
    nonisolated(unsafe) private(set) var saved: ServerConfiguration?
    nonisolated(unsafe) private(set) var saveCalls = 0

    func load() throws -> ServerConfiguration? { saved }

    func save(_ configuration: ServerConfiguration) throws {
        saveCalls += 1
        saved = configuration
    }

    func delete() throws { saved = nil }
}

struct PresentationFixedClock: MailClock {
    var now: Date

    init(now: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self.now = now
    }

    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

// MARK: - Fixtures

let presentationInbox = Folder(serverID: "13", parentID: "0", displayName: "收件箱", type: 2)
let presentationDrafts = Folder(serverID: "4", parentID: "0", displayName: "草稿", type: 3)

func presentationMessage(
    _ serverID: String,
    subject: String = "A",
    sender: String? = "a@b.c",
    recipients: String? = nil,
    cc: String? = nil,
    preview: String? = nil,
    folderID: String = "13"
) -> Message {
    Message(
        serverID: serverID,
        subject: subject,
        sender: sender,
        recipients: recipients,
        receivedRaw: nil,
        isRead: true,
        bodyPreview: preview,
        folderID: folderID,
        cc: cc
    )
}

/// Bootstrap delta (`SyncKey=0`) plus the window that carries the messages.
func presentationDeltas(added: [Message], folderID: String = "13") -> [String: MessageDelta] {
    [
        "0": MessageDelta(added: [], changed: [], removedServerIDs: [], syncKey: "100", moreAvailable: false),
        "100": MessageDelta(added: added, changed: [], removedServerIDs: [], syncKey: "101", moreAvailable: false),
    ]
}

/// The app's object graph for a test: real store and scenes, fake ports.
@MainActor
struct MailboxFixture {
    let store: MailStore
    let account: AccountID
    let gateway: PresentationFakeGateway
    let notifier: PresentationFakeNotifier
    let clock: PresentationFixedClock
    let viewModel: MailboxViewModel
    let composeScene: ComposeScene
}

@MainActor
func makeMailboxFixture(
    gateway: PresentationFakeGateway = PresentationFakeGateway(),
    folders: [Folder] = [presentationInbox],
    messages: [String: [Message]] = [:],
    notifier: PresentationFakeNotifier = PresentationFakeNotifier(),
    clock: PresentationFixedClock = PresentationFixedClock()
) throws -> MailboxFixture {
    let store = try MailStore.inMemory()
    let account = try store.createAccount(
        NewAccount(displayName: "jdoe", address: "jdoe@corp.test", host: "mail.corp.test")
    )
    try store.applyFolderSnapshot(account: account, folders: folders, syncKey: "1")
    for (folderID, list) in messages where !list.isEmpty {
        try store.applySyncBatch(
            account: account,
            folder: folderID,
            added: list,
            changed: [],
            removedServerIDs: [],
            syncKey: "2"
        )
    }

    let engine = SyncEngine(gateway: gateway, store: store, account: account, sleeper: { _ in })
    let syncScene = SyncScene(engine: engine, notifier: notifier, clock: clock)
    let outbox = Outbox(store: store, gateway: gateway, clock: clock)
    let readScene = ReadScene(
        store: store,
        account: account,
        gateway: gateway,
        files: PresentationFakeAttachmentFiles()
    )
    let composeScene = ComposeScene(store: store, outbox: outbox)
    let viewModel = MailboxViewModel(
        read: readScene,
        sync: syncScene,
        compose: composeScene,
        account: account
    )
    return MailboxFixture(
        store: store,
        account: account,
        gateway: gateway,
        notifier: notifier,
        clock: clock,
        viewModel: viewModel,
        composeScene: composeScene
    )
}
