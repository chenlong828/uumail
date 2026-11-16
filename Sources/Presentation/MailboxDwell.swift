import Foundation
import Scenes

/// Three-second dwell timer for the selected unread row. It only counts time: the view
/// model supplies the target and owns the write path, so the automatic timer and the
/// manual toolbar action share one mark-read implementation. Sleep is injected so tests
/// do not wait three real seconds.
@MainActor
final class MailboxDwell {
    /// Fixed by REQ-0013; not configurable. The test sleeper asserts this exact value.
    private static let interval: Duration = .seconds(3)

    private let sleep: @Sendable (Duration) async throws -> Void

    /// Called after the target stayed eligible for the full interval. The view model
    /// performs the local write and the conditional server write-back.
    var onElapsed: (@MainActor (MessageRef) -> Void)?

    private var target: MessageRef?
    private var task: Task<Void, Never>?
    private var generation = 0

    init(sleep: @escaping @Sendable (Duration) async throws -> Void) {
        self.sleep = sleep
    }

    func update(target: MessageRef?, isUnread: Bool, isActive: Bool) {
        guard let target, isUnread, isActive else {
            cancel()
            return
        }
        // Same eligible target: the clock keeps running. A sync reload must not reset it.
        if self.target == target, task != nil { return }

        cancel()
        self.target = target
        generation += 1
        let current = generation
        task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.sleep(Self.interval)
            } catch {
                return
            }
            guard !Task.isCancelled, self.generation == current, self.target == target else { return }
            self.task = nil
            self.target = nil
            self.onElapsed?(target)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        target = nil
        generation += 1
    }
}
