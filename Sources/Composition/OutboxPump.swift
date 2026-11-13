import Foundation
import MailDomain
import Outbox

/// The app's delivery loop (spec §7): lifecycle only. It wakes on a compose enqueue and
/// every `interval`, then lets `Outbox.flushAll` decide what is due. Retry/backoff rules
/// stay in `Outbox`; nothing here inspects an outcome.
@MainActor
final class OutboxPump {
    private let outbox: Outbox
    private let account: AccountID
    private let interval: Duration
    private var timer: Task<Void, Never>?
    private var consumer: Task<Void, Never>?
    private var trigger: AsyncStream<Void>.Continuation?

    init(outbox: Outbox, account: AccountID, interval: Duration = .seconds(30)) {
        self.outbox = outbox
        self.account = account
        self.interval = interval
    }

    /// Startup catch-up plus one flush per trigger. `flushAll` stops at the first row that
    /// is not due, so a failed attempt cannot spin here.
    func start() {
        guard consumer == nil else { return }
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        trigger = continuation
        let interval = self.interval
        timer = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    break
                }
                continuation.yield(())
            }
        }
        let outbox = self.outbox
        let account = self.account
        consumer = Task {
            // A stop that lands before this task runs must not deliver anything.
            guard !Task.isCancelled else { return }
            _ = await outbox.flushAll(account: account)
            for await _ in stream {
                if Task.isCancelled { break }
                _ = await outbox.flushAll(account: account)
            }
        }
    }

    /// Wakes the loop after an enqueue, so a queued send does not wait for the next tick.
    func signal() {
        trigger?.yield(())
    }

    func stop() {
        timer?.cancel()
        timer = nil
        trigger?.finish()
        trigger = nil
        consumer?.cancel()
        consumer = nil
    }
}
