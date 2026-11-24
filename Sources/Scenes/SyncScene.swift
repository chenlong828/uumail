import Foundation
import MailDomain
import SyncEngine

/// One refresh's result: the report when it worked, the classified error when it did not,
/// and the time the attempt started. Exactly one of `report` / `error` is set.
public struct RefreshOutcome: Equatable, Sendable {
    public var report: SyncReport?
    public var error: MailError?
    public var at: Date

    public init(report: SyncReport? = nil, error: MailError? = nil, at: Date) {
        self.report = report
        self.error = error
        self.at = at
    }
}

/// Refresh cadence, single flight and the notification rule (spec §4.8).
///
/// Rules live here, not in the view or the app shell: concurrent `refresh` callers share
/// one in-flight `SyncEngine.syncOnce`, a notification is posted only when the run added
/// mail, and an auth/device/policy rejection pauses automatic refresh.
public actor SyncScene {
    private let engine: SyncEngine
    private let notifier: any Notifier
    private let clock: any MailClock

    private var isRefreshing = false
    private var waiters: [CheckedContinuation<RefreshOutcome, Never>] = []
    private var autoRefreshTask: Task<Void, Never>?
    private var authorizationRequested = false
    private var autoRefreshPaused = false

    public init(engine: SyncEngine, notifier: any Notifier, clock: any MailClock) {
        self.engine = engine
        self.notifier = notifier
        self.clock = clock
    }

    // MARK: - Manual refresh

    /// Runs one sync. Concurrent callers join the run already in flight instead of starting
    /// a second one (single flight).
    public func refresh() async -> RefreshOutcome {
        if isRefreshing {
            return await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }

        isRefreshing = true
        let outcome = await performRefresh()
        isRefreshing = false

        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume(returning: outcome)
        }
        return outcome
    }

    /// Refreshes only Sent Items (REQ-0038). No new-mail notification: a sent copy is not
    /// incoming mail. Shares the engine's FIFO gate, so it never interleaves with a write.
    public func refreshSent() async -> RefreshOutcome {
        let startedAt = clock.now
        do {
            guard let report = try await engine.syncSentOnce() else {
                return RefreshOutcome(at: startedAt)
            }
            return RefreshOutcome(report: report, error: nil, at: startedAt)
        } catch {
            let failure = (error as? MailError) ?? .offline
            return RefreshOutcome(report: nil, error: failure, at: startedAt)
        }
    }

    // MARK: - Automatic refresh

    /// Emits one outcome immediately, then one per interval. The stream finishes when the
    /// scene pauses automatic refresh (auth/device/policy failure) or the consumer stops.
    public func startAutoRefresh(every: Duration = .seconds(300)) -> AsyncStream<RefreshOutcome> {
        stopAutoRefresh()

        let (stream, continuation) = AsyncStream<RefreshOutcome>.makeStream()
        guard !autoRefreshPaused else {
            continuation.finish()
            return stream
        }

        let clock = self.clock
        let task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                let outcome = await self.refresh()
                continuation.yield(outcome)
                if let error = outcome.error, Self.pausesAutoRefresh(error) {
                    break
                }
                do {
                    try await clock.sleep(for: every)
                } catch {
                    break
                }
            }
            continuation.finish()
        }
        autoRefreshTask = task
        continuation.onTermination = { @Sendable _ in
            task.cancel()
        }
        return stream
    }

    public func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    // MARK: - Rules

    private func performRefresh() async -> RefreshOutcome {
        let startedAt = clock.now
        await requestAuthorizationIfNeeded()

        do {
            let report = try await engine.syncOnce()
            autoRefreshPaused = false
            if report.added > 0 {
                // Non-throwing by contract; a notification failure must not change the
                // refresh result.
                await notifier.postNewMail(count: report.added)
            }
            return RefreshOutcome(report: report, error: nil, at: startedAt)
        } catch {
            let failure = (error as? MailError) ?? .offline
            if Self.pausesAutoRefresh(failure) {
                autoRefreshPaused = true
            }
            return RefreshOutcome(report: nil, error: failure, at: startedAt)
        }
    }

    /// Asks for notification permission once per scene lifetime. What "granted" means is
    /// the `Notifier` implementation's business; a refusal degrades silently.
    private func requestAuthorizationIfNeeded() async {
        guard !authorizationRequested else { return }
        authorizationRequested = true
        await notifier.requestAuthorization()
    }

    /// Credential and policy rejections cannot be fixed by retrying: only the user can act
    /// on them (spec §4.8). `deviceNotRegistered` is deliberately excluded (measured
    /// 2026-11-17): this gateway answers a stale SyncKey with the same `200`/zero-byte body
    /// it uses for a swallowed request, so a single occurrence must not end the only loop
    /// that can recover. A genuinely unregistered device still shows its text on every tick.
    private static func pausesAutoRefresh(_ error: MailError) -> Bool {
        switch error {
        case .authFailed, .policyBlocked:
            return true
        case .deviceNotRegistered, .syncKeyInvalid, .throttled, .offline, .unsupported,
             .storage, .invalidInput:
            return false
        }
    }
}
