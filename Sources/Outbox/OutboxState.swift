import Foundation
import MailDomain

/// The outbox row state machine from architecture spec §4.6. `sent` is terminal but
/// never stored: a successful delivery deletes the row.
public enum OutboundState: String, CaseIterable, Sendable {
    case draft
    case queued
    case sending
    case sent
    case failedRetryable = "failed_retryable"
    case failedPermanent = "failed_permanent"
    case canceled
}

/// What one `flushOnce` attempt did, for callers that need the result (CLI `send`, the
/// app's pump, tests). `retryScheduled` carries the backoff deadline.
public enum DeliveryOutcome: Equatable, Sendable {
    case sent(OutboxID)
    case retryScheduled(OutboxID, error: MailError, nextAttempt: Date)
    case failedPermanent(OutboxID, error: MailError)
    case canceled(OutboxID)

    public var outboxID: OutboxID {
        switch self {
        case .sent(let id), .retryScheduled(let id, _, _), .failedPermanent(let id, _), .canceled(let id):
            return id
        }
    }

    /// The delivery error, or `nil` when the item left the outbox without one.
    public var error: MailError? {
        switch self {
        case .sent, .canceled: return nil
        case .retryScheduled(_, let error, _), .failedPermanent(_, let error): return error
        }
    }
}

/// Backoff policy and the error split from spec §4.6:
/// `offline`/`throttled` retry with 30s → 2m → 10m → 30m, then doubling capped at 24h;
/// auth/device/policy/protocol failures are permanent until a manual retry.
public enum OutboxBackoff {
    /// The first four retry delays (seconds), exactly as the spec lists them.
    public static let initialDelays: [TimeInterval] = [30, 120, 600, 1800]
    /// No retry is ever scheduled further out than one day.
    public static let maximumDelay: TimeInterval = 24 * 60 * 60

    /// `failedAttempts` is 1-based: the failure count *after* the attempt that failed.
    public static func delay(failedAttempts: Int) -> TimeInterval {
        let attempt = max(failedAttempts, 1)
        if attempt <= initialDelays.count {
            return initialDelays[attempt - 1]
        }
        var delay = initialDelays[initialDelays.count - 1] * 2
        for _ in (initialDelays.count + 1)..<attempt {
            delay = min(delay * 2, maximumDelay)
        }
        return min(delay, maximumDelay)
    }

    /// `throttled` honours the server's Retry-After (clamped to [1s, 24h]); everything
    /// else uses the progressive schedule.
    public static func nextAttempt(after error: MailError, failedAttempts: Int, now: Date) -> Date {
        if case .throttled(let seconds) = error, let seconds {
            let clamped = min(max(Double(seconds), 1), maximumDelay)
            return now.addingTimeInterval(clamped)
        }
        return now.addingTimeInterval(delay(failedAttempts: failedAttempts))
    }

    /// Only these four stop automatic redelivery (spec §4.6). `syncKeyInvalid` is a
    /// read-path error and cannot come out of `send`, so it is left retryable.
    public static func isPermanent(_ error: MailError) -> Bool {
        switch error {
        case .authFailed, .deviceNotRegistered, .policyBlocked, .unsupported:
            return true
        case .syncKeyInvalid, .throttled, .offline, .storage, .invalidInput:
            return false
        }
    }
}

public extension OutboxItem {
    /// Typed view of the stored state string, `nil` if a future build wrote an
    /// unknown value.
    var outboundState: OutboundState? { OutboundState(rawValue: state) }
}
