import Foundation

/// The only error catalog crossing module boundaries. Gateway adapters translate
/// transport/protocol failures into these cases; scenes decide whether to retry.
public enum MailError: Error, Equatable, Sendable {
    /// Credentials rejected (`401` on a read). Do not retry automatically.
    case authFailed
    /// `200` with a zero-byte body, or `401` on a write: the device is not registered.
    case deviceNotRegistered
    /// `449` / policy rejection: provisioning cannot satisfy the server.
    case policyBlocked
    /// Sync `Status=3/4`: the stored key is stale and the collection must be rebuilt.
    case syncKeyInvalid
    /// `503` + `Retry-After`; the caller backs off for `seconds` (nil = server default).
    case throttled(seconds: Int?)
    /// Connection failed or timed out. Retryable with backoff.
    case offline
    /// Protocol/gateway behaviour the client cannot satisfy (`444`, `502`, bad WBXML).
    case unsupported
    /// Local storage failure.
    case storage(reason: String)
    /// Caller passed something the domain cannot accept (empty recipients, bad ids).
    case invalidInput(reason: String)
}
