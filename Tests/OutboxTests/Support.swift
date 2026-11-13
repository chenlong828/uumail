import Foundation
import MailDomain
import MailStore
import Outbox

/// A gateway fake: per-send outcomes in order (`nil` = success), attempt counter and
/// captured MIME/ClientId. One actor so concurrent deliveries are still observable.
actor FakeGateway: MailGateway {
    private var outcomes: [MailError?]
    private let delay: Duration?
    private(set) var attempts = 0
    private(set) var sentMIME: [Data] = []
    private(set) var clientIDs: [String] = []

    init(outcomes: [MailError?] = [], delay: Duration? = nil) {
        self.outcomes = outcomes
        self.delay = delay
    }

    func send(mime: Data, clientID: String) async throws {
        attempts += 1
        if let delay {
            try await Task.sleep(for: delay)
        }
        if !outcomes.isEmpty, let error = outcomes.removeFirst() {
            throw error
        }
        sentMIME.append(mime)
        clientIDs.append(clientID)
    }

    func probe() async throws -> ServerCapabilities { throw MailError.unsupported }
    func provisionIfNeeded() async throws { throw MailError.unsupported }
    func fetchFolders(syncKey: String) async throws -> FolderListing { throw MailError.unsupported }
    func fetchMessages(collectionID: String, syncKey: String, window: Int, filterType: Int) async throws -> MessageDelta {
        throw MailError.unsupported
    }
    func fetchBody(collectionID: String, serverID: String) async throws -> FetchedBody { throw MailError.unsupported }
    func fetchAttachment(fileReference: String) async throws -> Data { throw MailError.unsupported }
}

/// Controllable clock for lease/backoff time. `sleep` stays real so the delivery
/// timeout test can actually observe a slow send.
final class TestClock: MailClock, @unchecked Sendable {
    var now: Date

    init(now: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self.now = now
    }

    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }

    func advance(by seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }
}

/// Account fixtures use an address whose domain differs from the server host, so tests
/// can prove `Outbox` reads both from the store instead of deriving one from the other.
func seededStore() throws -> (MailStore, AccountID) {
    let store = try MailStore.inMemory()
    let id = try store.createAccount(
        NewAccount(displayName: "jdoe", address: "jdoe@corp.test", host: "mail.corp.test")
    )
    return (store, id)
}

func makeDraft() -> MailDraft {
    MailDraft(to: "a@b.c", cc: nil, subject: "hi", body: "text")
}
