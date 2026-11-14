import Foundation
import MailDomain
import MailStore
import Testing

@testable import Scenes

// Test doubles for the scene contracts. Nothing here reaches the network or the
// system Keychain/notification center.

/// Configurable gateway fake shared by the scene tests.
actor FakeGateway: MailGateway {
    enum Call: Equatable {
        case probe
        case provision
        case folders(syncKey: String)
        case messages(key: String)
        case body(folderID: String, serverID: String)
        case attachment(fileReference: String)
        case send
    }

    private(set) var calls: [Call] = []

    private let foldersListing: FolderListing
    private let deltas: [String: MessageDelta]
    private let bodyResult: FetchedBody?
    private let bodyError: MailError?
    private let probeError: MailError?
    private let provisionError: MailError?
    private let folderError: MailError?
    private let attachmentData: Data?
    private let attachmentError: MailError?
    private let provisionDelay: Duration?

    init(
        folders: FolderListing = FolderListing(folders: [], syncKey: "0"),
        deltas: [String: MessageDelta] = [:],
        body: FetchedBody? = nil,
        bodyError: MailError? = nil,
        probeError: MailError? = nil,
        provisionError: MailError? = nil,
        folderError: MailError? = nil,
        attachmentData: Data? = nil,
        attachmentError: MailError? = nil,
        provisionDelay: Duration? = nil
    ) {
        self.foldersListing = folders
        self.deltas = deltas
        self.bodyResult = body
        self.bodyError = bodyError
        self.probeError = probeError
        self.provisionError = provisionError
        self.folderError = folderError
        self.attachmentData = attachmentData
        self.attachmentError = attachmentError
        self.provisionDelay = provisionDelay
    }

    func probe() async throws -> ServerCapabilities {
        calls.append(.probe)
        if let probeError { throw probeError }
        return ServerCapabilities(protocolVersions: ["16.1"], commands: ["Sync", "ItemOperations"])
    }

    func provisionIfNeeded() async throws {
        calls.append(.provision)
        if let provisionDelay {
            try await Task.sleep(for: provisionDelay)
        }
        if let provisionError { throw provisionError }
    }

    func fetchFolders(syncKey: String) async throws -> FolderListing {
        calls.append(.folders(syncKey: syncKey))
        if let folderError { throw folderError }
        return foldersListing
    }

    func fetchMessages(collectionID: String, syncKey: String, window: Int, filterType: Int) async throws -> MessageDelta {
        calls.append(.messages(key: syncKey))
        guard let delta = deltas[syncKey] else { throw MailError.syncKeyInvalid }
        return delta
    }

    func fetchBody(collectionID: String, serverID: String) async throws -> FetchedBody {
        calls.append(.body(folderID: collectionID, serverID: serverID))
        if let bodyError { throw bodyError }
        guard let bodyResult else { throw MailError.unsupported }
        return bodyResult
    }

    func fetchAttachment(fileReference: String) async throws -> Data {
        calls.append(.attachment(fileReference: fileReference))
        if let attachmentError { throw attachmentError }
        return attachmentData ?? Data()
    }

    func send(mime: Data, clientID: String) async throws {
        calls.append(.send)
    }

    // MARK: - Call counters

    var provisionCalls: Int {
        calls.reduce(0) { count, call in call == .provision ? count + 1 : count }
    }

    var folderCalls: Int {
        calls.reduce(0) { count, call in
            if case .folders = call { return count + 1 }
            return count
        }
    }

    var bodyCalls: Int {
        calls.reduce(0) { count, call in
            if case .body = call { return count + 1 }
            return count
        }
    }

    var attachmentCalls: Int {
        calls.reduce(0) { count, call in
            if case .attachment = call { return count + 1 }
            return count
        }
    }

    var sendCalls: Int {
        calls.reduce(0) { count, call in call == .send ? count + 1 : count }
    }
}

/// In-memory credentials: records the saved configuration and when it was written.
final class FakeCredentialStore: CredentialStore, @unchecked Sendable {
    nonisolated(unsafe) private(set) var saved: ServerConfiguration?
    nonisolated(unsafe) private(set) var saveCalls = 0
    nonisolated(unsafe) var saveError: Error?
    nonisolated(unsafe) var onSave: (@Sendable (ServerConfiguration) -> Void)?

    func load() throws -> ServerConfiguration? { saved }

    func save(_ configuration: ServerConfiguration) throws {
        saveCalls += 1
        if let saveError { throw saveError }
        saved = configuration
        onSave?(configuration)
    }

    func delete() throws { saved = nil }
}

/// Sync-store fake: enough of `SyncStore` for `SyncEngine` to run without SQLite.
final class FakeSyncStore: SyncStore, @unchecked Sendable {
    nonisolated(unsafe) private(set) var folderSnapshot: [Folder] = []
    nonisolated(unsafe) var snapshotKey: String?
    nonisolated(unsafe) var keys: [String: String] = [:]
    nonisolated(unsafe) var folderFailure: Error?
    nonisolated(unsafe) var markReadResult = false
    nonisolated(unsafe) private(set) var markReadCalls: [String] = []
    nonisolated(unsafe) private(set) var commitMarkReads: [MessageDelta] = []
    nonisolated(unsafe) private(set) var commitDeletes: [MessageDelta] = []

    func folders(_ account: AccountID) throws -> [Folder] { folderSnapshot }

    func applyFolderSnapshot(_ account: AccountID, folders: [Folder], syncKey: String) throws {
        if let folderFailure { throw folderFailure }
        folderSnapshot = folders
        snapshotKey = syncKey
    }

    func syncKey(_ account: AccountID, collection: String) throws -> String? { keys[collection] }

    func applySyncBatch(_ account: AccountID, folder: String, delta: MessageDelta) throws {
        keys[folder] = delta.syncKey
    }

    func resetCollection(_ account: AccountID, folder: String) throws {
        keys[folder] = nil
    }

    @discardableResult
    func markRead(_ account: AccountID, folder: String, serverID: String) throws -> Bool {
        markReadCalls.append(serverID)
        return markReadResult
    }

    func commitMarkRead(_ account: AccountID, folder: String, serverID: String, delta: MessageDelta) throws {
        commitMarkReads.append(delta)
        keys[folder] = delta.syncKey
    }

    func commitDelete(_ account: AccountID, folder: String, serverID: String, delta: MessageDelta) throws {
        commitDeletes.append(delta)
        keys[folder] = delta.syncKey
    }
}

final class FakeNotifier: Notifier, @unchecked Sendable {
    nonisolated(unsafe) private(set) var authorizationRequests = 0
    nonisolated(unsafe) private(set) var posts: [Int] = []

    func requestAuthorization() async { authorizationRequests += 1 }
    func postNewMail(count: Int) async { posts.append(count) }
}

/// Attachment-file fake: records the cache without touching the disk (the real
/// `FileAttachmentFiles` owns the budget and is covered by its own tests).
final class FakeAttachmentFiles: AttachmentFiles, @unchecked Sendable {
    nonisolated(unsafe) private(set) var cache: [String: URL] = [:]
    nonisolated(unsafe) private(set) var storeCalls = 0
    nonisolated(unsafe) var storeError: Error?

    private let directory: URL

    init(directory: URL = FileManager.default.temporaryDirectory.appendingPathComponent("uumail-scenes-tests")) {
        self.directory = directory
    }

    func cachedURL(for reference: AttachmentRef) -> URL? {
        cache[reference.fileReference]
    }

    func store(_ data: Data, for reference: AttachmentRef) throws -> URL {
        storeCalls += 1
        if let storeError { throw storeError }
        let url = directory.appendingPathComponent("\(reference.fileReference)-\(reference.displayName)")
        cache[reference.fileReference] = url
        return url
    }

    func preload(_ url: URL, for reference: AttachmentRef) {
        cache[reference.fileReference] = url
    }
}

struct FixedClock: MailClock {
    var now: Date

    init(now: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self.now = now
    }

    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

// MARK: - Fixtures

let inboxFolder = Folder(serverID: "13", parentID: "0", displayName: "收件箱", type: 2)
let draftsFolder = Folder(serverID: "4", parentID: "0", displayName: "草稿", type: 3)

func makeAccountInput(
    host: String = "mail.corp.test",
    account: String = "jdoe",
    password: String = "secret",
    domain: String = "corp",
    deviceID: String = "device-1",
    displayName: String = "J Doe"
) -> AccountInput {
    AccountInput(
        host: host,
        account: account,
        password: password,
        domain: domain,
        deviceID: deviceID,
        displayName: displayName
    )
}

/// A store with one ready account and the inbox folder; read tests apply bodies on top.
func seededReadStore() throws -> (MailStore, AccountID) {
    let store = try MailStore.inMemory()
    let account = try store.createAccount(
        NewAccount(displayName: "jdoe", address: "jdoe@corp.test", host: "mail.corp.test")
    )
    try store.applyFolderSnapshot(account: account, folders: [inboxFolder], syncKey: "1")
    return (store, account)
}

func makeSyncDeltas(added: Int) -> [String: MessageDelta] {
    let messages = (0..<added).map { Message(serverID: "m\($0)") }
    return [
        "0": MessageDelta(added: [], changed: [], removedServerIDs: [], syncKey: "100", moreAvailable: false),
        "100": MessageDelta(added: messages, changed: [], removedServerIDs: [], syncKey: "101", moreAvailable: false),
    ]
}

/// Asserts that the operation throws exactly `expected`. `MailError` is `Equatable`, so
/// the associated values (and their messages) are checked too.
func expectMailError(_ expected: MailError, _ operation: () async throws -> Void) async {
    do {
        try await operation()
        Issue.record("expected \(expected) but nothing was thrown")
    } catch let error as MailError {
        #expect(error == expected)
    } catch {
        Issue.record("expected \(expected), got \(error)")
    }
}
