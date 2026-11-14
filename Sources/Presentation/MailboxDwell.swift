import Foundation
import Scenes

/// 10-second dwell timer for the selected unread row. It is declaration-driven: the view
/// model calls `update` after every selection/list/foreground change, and the same target
/// does not restart the clock. Sleep is injected so tests do not wait ten real seconds.
@MainActor
final class MailboxDwell {
    private let read: ReadScene
    private let sleep: @Sendable (Duration) async throws -> Void

    /// Called after the local write attempt succeeds (including a false 0→1 result, so a
    /// stale list is refreshed once). The view model reloads; it never shows write errors.
    var onMarked: (@MainActor (MessageRef) -> Void)?

    private var target: MessageRef?
    private var task: Task<Void, Never>?
    private var generation = 0

    init(read: ReadScene, sleep: @escaping @Sendable (Duration) async throws -> Void) {
        self.read = read
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
                try await self.sleep(.seconds(10))
            } catch {
                return
            }
            guard !Task.isCancelled, self.generation == current, self.target == target else { return }
            self.task = nil
            self.target = nil
            self.fire(target)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        target = nil
        generation += 1
    }

    private func fire(_ ref: MessageRef) {
        do {
            let changed = try read.markReadLocally(ref)
            onMarked?(ref)
            // Only a real 0→1 starts the server write; an already-read row must not write.
            if changed {
                Task { _ = await read.writeBackMarkRead(ref) }
            }
        } catch {
            // Rare local storage failure: keep the row unread, no write-back, no UI error.
        }
    }
}
