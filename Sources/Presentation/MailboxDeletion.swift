import Foundation
import Observation
import Scenes

/// Temporary hide set + single-flight + error text for keyboard deletion. The scene owns
/// the server call; this only reflects it and restores the row on failure.
@MainActor
@Observable
final class MailboxDeletion {
    enum Outcome: Equatable {
        case deleted
        case failed
        case ignored
    }

    private(set) var hidden: Set<MessageRef> = []
    private(set) var isDeleting = false
    private(set) var errorText: String?

    private let read: ReadScene

    init(read: ReadScene) {
        self.read = read
    }

    /// Immediately hides the row. Returns false when another delete is already in flight.
    func begin(_ ref: MessageRef) -> Bool {
        guard !isDeleting else { return false }
        hidden.insert(ref)
        isDeleting = true
        errorText = nil
        return true
    }

    func commit(_ ref: MessageRef) async -> Outcome {
        do {
            try await read.deleteMessage(ref)
            isDeleting = false
            return .deleted
        } catch {
            hidden.remove(ref)
            errorText = ErrorText.text(for: error)
            isDeleting = false
            return .failed
        }
    }

    func clearHidden(_ ref: MessageRef) {
        hidden.remove(ref)
    }

    /// A successful sync proves the account is reachable, so an old warning must not stay
    /// on the status bar until the next delete attempt.
    func clearErrorText() {
        errorText = nil
    }
}
