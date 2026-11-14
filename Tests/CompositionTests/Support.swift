import Foundation
import MailDomain
import MailStore
import Testing

@testable import Composition

// Test doubles for the composition assembly smoke tests: no network, no system Keychain,
// in-memory (or temporary-file) SQLite. Business behaviour belongs to the scene tests.

/// Configurable gateway fake. Assembly tests only inspect the calls, never the payload.
actor AssemblyGateway: MailGateway {
    enum Call: Equatable {
        case probe
        case provision
        case folders(syncKey: String)
        case messages(key: String)
        case body
        case attachment
        case send
    }

    private(set) var calls: [Call] = []

    private let foldersListing: FolderListing
    private let deltas: [String: MessageDelta]
    private let probeError: MailError?
    private let folderError: MailError?
    private let sendError: MailError?

    init(
        folders: FolderListing = FolderListing(folders: [], syncKey: "0"),
        deltas: [String: MessageDelta] = [:],
        probeError: MailError? = nil,
        folderError: MailError? = nil,
        sendError: MailError? = nil
    ) {
        self.foldersListing = folders
        self.deltas = deltas
        self.probeError = probeError
        self.folderError = folderError
        self.sendError = sendError
    }

    func probe() async throws -> ServerCapabilities {
        calls.append(.probe)
        if let probeError { throw probeError }
        return ServerCapabilities(protocolVersions: ["16.1"], commands: ["Sync"])
    }

    func provisionIfNeeded() async throws {
        calls.append(.provision)
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
        calls.append(.body)
        throw MailError.unsupported
    }

    func fetchAttachment(fileReference: String) async throws -> Data {
        calls.append(.attachment)
        throw MailError.unsupported
    }

    func send(mime: Data, clientID: String) async throws {
        calls.append(.send)
        if let sendError { throw sendError }
    }

    var probeCalls: Int { calls.filter { $0 == .probe }.count }
    var provisionCalls: Int { calls.filter { $0 == .provision }.count }
    var folderCalls: Int {
        calls.reduce(0) { count, call in
            if case .folders = call { return count + 1 }
            return count
        }
    }
    var sendCalls: Int { calls.filter { $0 == .send }.count }
}

/// In-memory credentials that record what the setup scene saved.
final class RecordingCredentialStore: CredentialStore, @unchecked Sendable {
    nonisolated(unsafe) private(set) var saved: ServerConfiguration?
    nonisolated(unsafe) private(set) var saveCalls = 0
    nonisolated(unsafe) private(set) var loadCalls = 0

    init(saved: ServerConfiguration? = nil) {
        self.saved = saved
    }

    func load() throws -> ServerConfiguration? {
        loadCalls += 1
        return saved
    }

    func save(_ configuration: ServerConfiguration) throws {
        saveCalls += 1
        saved = configuration
    }

    func delete() throws { saved = nil }
}

/// In-memory notification surface: the app's real notifier needs an app bundle.
final class RecordingNotifier: Notifier, @unchecked Sendable {
    nonisolated(unsafe) private(set) var authorizationRequests = 0
    nonisolated(unsafe) private(set) var posts: [Int] = []

    func requestAuthorization() async { authorizationRequests += 1 }
    func postNewMail(count: Int) async { posts.append(count) }
}

// MARK: - Fixtures

let assemblyInbox = Folder(serverID: "13", parentID: "0", displayName: "收件箱", type: 2)

func makeAssemblyConfiguration() -> ServerConfiguration {
    ServerConfiguration(
        host: "mail.corp.test",
        account: "jdoe",
        password: "secret",
        domain: "corp",
        deviceID: "DEV",
        displayName: "J Doe"
    )
}

func makeAssemblyStore(withAccountRow: Bool = false) throws -> MailStore {
    let store = try MailStore.inMemory()
    if withAccountRow {
        _ = try store.createAccount(
            NewAccount(displayName: "J Doe", address: "jdoe@mail.corp.test", host: "mail.corp.test")
        )
    }
    return store
}

func makeFolderListing() -> FolderListing {
    FolderListing(folders: [assemblyInbox], syncKey: "1")
}

/// The two responses `SyncEngine` needs: a SyncKey=0 bootstrap, then an empty window.
func makeSyncDeltas() -> [String: MessageDelta] {
    [
        "0": MessageDelta(added: [], changed: [], removedServerIDs: [], syncKey: "1", moreAvailable: false),
        "1": MessageDelta(added: [], changed: [], removedServerIDs: [], syncKey: "2", moreAvailable: false),
    ]
}

/// Test-only write stand-in: composition assembly never exercises mailbox writes.
struct UnsupportedWriteGateway: MailWriteGateway {
    func markRead(collectionID: String, serverID: String, syncKey: String) async throws -> MessageDelta {
        throw MailError.unsupported
    }

    func delete(collectionID: String, serverID: String, syncKey: String) async throws -> MessageDelta {
        throw MailError.unsupported
    }
}

func makeGatewayFactory(_ gateway: any MailGateway) -> GatewayFactory {
    { _ in GatewayEndpoints(read: gateway, write: UnsupportedWriteGateway()) }
}

func makeTemporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("uumail-composition-\(UUID().uuidString)", isDirectory: true)
}

// MARK: - Waiting

/// Polls until `condition` holds; the assertion fails (instead of hanging) on timeout.
@MainActor
func waitUntil(
    timeout: Duration = .seconds(2),
    _ condition: @MainActor () throws -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if try condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("condition was not met before the timeout")
}
