import Foundation

/// Credentials: Keychain in the app, in-memory in tests.
public protocol CredentialStore: Sendable {
    func load() throws -> ServerConfiguration?
    func save(_ configuration: ServerConfiguration) throws
    func delete() throws
}

/// System notification poster. Failures degrade silently by design.
public protocol Notifier: Sendable {
    func requestAuthorization() async
    func postNewMail(count: Int) async
}

/// Attachment file cache. Implementations own the 2 GB oldest-first budget.
public protocol AttachmentFiles: Sendable {
    func cachedURL(for reference: AttachmentRef) -> URL?
    func store(_ data: Data, for reference: AttachmentRef) throws -> URL
}

/// Injectable clock so polling and leases are testable without real time.
public protocol MailClock: Sendable {
    var now: Date { get }
    func sleep(for duration: Duration) async throws
}
