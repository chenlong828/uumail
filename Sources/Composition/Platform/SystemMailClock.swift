import Foundation
import MailDomain

/// Wall clock for the outbox lease/backoff and the refresh cadence.
public struct SystemMailClock: MailClock {
    public init() {}

    public var now: Date { Date() }

    public func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}
