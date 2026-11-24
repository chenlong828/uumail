import Foundation
import MailDomain
import MailStore
import SyncContract

/// The sending side of the mailbox: a durable outbox plus one-at-a-time delivery.
///
/// `enqueue` only writes the local row (no network, returns immediately). `flushOnce`
/// claims a due row under a 120s lease, builds the MIME body from the stored account,
/// sends it once with `ClientId = outboxID`, and records the outcome. The state machine
/// and backoff live here; the row and its transitions live in `MailStore`.
public actor Outbox {
    private let store: MailStore
    private let gateway: any MailGateway
    private let clock: any MailClock
    private let lease: Duration
    private let sendTimeout: Duration
    /// Cancel requests that arrive while a row is `sending`. Spec §4.6 only allows
    /// `canceled` from `queued`/`failed_*`, so the intent waits here and is applied
    /// once the in-flight delivery returns (the mail may already be on the wire).
    private var cancelRequested: Set<OutboxID> = []

    public init(
        store: MailStore,
        gateway: any MailGateway,
        clock: any MailClock,
        lease: Duration = .seconds(120),
        sendTimeout: Duration = .seconds(90)
    ) {
        self.store = store
        self.gateway = gateway
        self.clock = clock
        self.lease = lease
        self.sendTimeout = sendTimeout
    }

    // MARK: - Intent

    /// Persists a send intent. No MIME build, no network: delivery happens in `flush*`.
    @discardableResult
    public func enqueue(_ draft: Draft, account: AccountID) throws -> OutboxID {
        OutboxID(try store.outbox.enqueueOutbox(account: account, draft: draft))
    }

    /// Claims and delivers one row, or returns `nil` when nothing is deliverable.
    public func flushOnce(account: AccountID) async -> DeliveryOutcome? {
        guard let item = try? store.outbox.claimOutbox(account: account, now: clock.now, lease: lease) else {
            return nil
        }
        return await deliver(item, account: account)
    }

    /// Startup/CLI catch-up: drains every row that is deliverable now. Rows that just
    /// failed get a future `next_attempt_at`, so they are skipped instead of looped.
    public func flushAll(account: AccountID) async -> [DeliveryOutcome] {
        var outcomes: [DeliveryOutcome] = []
        while let outcome = await flushOnce(account: account) {
            outcomes.append(outcome)
        }
        return outcomes
    }

    /// Puts a failed row back in the queue for an immediate attempt (manual retry).
    public func retry(_ id: OutboxID, account: AccountID) throws {
        guard let item = try store.outbox.outboxItem(account: account, id: id),
              let state = OutboundState(rawValue: item.state),
              state == .failedRetryable || state == .failedPermanent
        else {
            return
        }
        try store.outbox.releaseOutbox(account: account, outboxID: id)
        cancelRequested.remove(id)
    }

    /// Cancels a row that has not been delivered. A `sending` row only records the
    /// request; `flushOnce` settles it when delivery returns.
    public func cancel(_ id: OutboxID, account: AccountID) throws {
        guard let item = try store.outbox.outboxItem(account: account, id: id),
              let state = OutboundState(rawValue: item.state)
        else {
            return
        }
        switch state {
        case .queued, .failedRetryable, .failedPermanent:
            try store.outbox.cancelOutbox(account: account, outboxID: id)
        case .sending:
            cancelRequested.insert(id)
        case .draft, .sent, .canceled:
            break
        }
    }

    // MARK: - Observation

    public func state(of id: OutboxID, account: AccountID) throws -> OutboundState? {
        guard let item = try store.outbox.outboxItem(account: account, id: id) else { return nil }
        return OutboundState(rawValue: item.state)
    }

    public func pending(account: AccountID) throws -> [OutboxItem] {
        try store.outbox.pendingOutbox(account: account)
    }

    // MARK: - Delivery

    private func deliver(_ item: OutboxItem, account: AccountID) async -> DeliveryOutcome {
        let id = OutboxID(item.id)
        let canceled = cancelRequested.remove(id) != nil

        guard let storedAccount = try? store.account(account) else {
            // A missing account row is a local setup problem: retrying the same row can
            // never fix it, so it is permanent even though `invalidInput` is not one of
            // the four gateway failures in the §4.6 table.
            let error = MailError.invalidInput(reason: "account \(account.raw) is missing")
            if canceled {
                try? store.outbox.releaseOutbox(account: account, outboxID: id)
                try? store.outbox.cancelOutbox(account: account, outboxID: id)
                return .canceled(id)
            }
            try? store.outbox.markOutboxFailed(
                account: account, outboxID: id, error: String(describing: error),
                retryable: false, nextAttempt: nil
            )
            return .failedPermanent(id, error: error)
        }

        let draft = Draft(
            to: item.to,
            cc: item.cc,
            subject: item.subject,
            body: item.body,
            inReplyTo: item.inReplyTo,
            references: item.references,
            bodyHTML: item.bodyHTML
        )
        let mime = MimeBuilder.build(
            from: storedAccount.address,
            draft: draft,
            messageID: "\(UUID().uuidString)@\(storedAccount.host)"
        )

        do {
            try await send(mime: mime, clientID: id.raw)
        } catch {
            let mailError = (error as? MailError) ?? .offline
            return settleFailure(item, id: id, account: account, error: mailError, canceled: canceled)
        }

        // The mail is on the wire, so a cancel request is moot: a send that succeeded is
        // final. A failed state write is recoverable through the lease.
        try? store.outbox.markOutboxSent(account: account, outboxID: id)
        return .sent(id)
    }

    private func settleFailure(
        _ item: OutboxItem,
        id: OutboxID,
        account: AccountID,
        error: MailError,
        canceled: Bool
    ) -> DeliveryOutcome {
        if canceled {
            // Walk the legal edge: sending → queued → canceled (a direct
            // sending → canceled transition is not part of the state machine).
            try? store.outbox.releaseOutbox(account: account, outboxID: id)
            try? store.outbox.cancelOutbox(account: account, outboxID: id)
            return .canceled(id)
        }

        let errorText = String(describing: error)
        if OutboxBackoff.isPermanent(error) {
            try? store.outbox.markOutboxFailed(
                account: account,
                outboxID: id,
                error: errorText,
                retryable: false,
                nextAttempt: nil
            )
            return .failedPermanent(id, error: error)
        }

        let nextAttempt = OutboxBackoff.nextAttempt(
            after: error,
            failedAttempts: item.attempts + 1,
            now: clock.now
        )
        try? store.outbox.markOutboxFailed(
            account: account,
            outboxID: id,
            error: errorText,
            retryable: true,
            nextAttempt: nextAttempt
        )
        return .retryScheduled(id, error: error, nextAttempt: nextAttempt)
    }

    /// Sends with the contract's 90s ceiling. A timeout is an outage (`offline`), which
    /// classifies as retryable.
    private func send(mime: Data, clientID: String) async throws {
        let gateway = self.gateway
        let clock = self.clock
        let timeout = self.sendTimeout
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await gateway.send(mime: mime, clientID: clientID)
            }
            group.addTask {
                try await clock.sleep(for: timeout)
                throw MailError.offline
            }
            try await group.next()
            group.cancelAll()
        }
    }
}
