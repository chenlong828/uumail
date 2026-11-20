import Foundation
import MailDomain
import Scenes

/// Attachment downloads live in their own file so the mailbox state machine stays under
/// the component line budget. Same component; the only public member is the existing
/// `download(_:)` signature plus the read-only `attachmentErrorText` added in the state.
extension MailboxViewModel {

    /// Downloads (or reuses) one attachment and returns the file to open. On failure the
    /// normalized error is mapped to `attachmentErrorText` and `nil` is returned. A cancelled
    /// caller task, or a result that arrives after the selection moved on, is dropped without
    /// writing or clearing any state (REQ-0026 / SCN-0020; D18).
    public func download(_ attachment: Attachment) async -> URL? {
        guard let ref = selectedRef, !Task.isCancelled else { return nil }
        let generation = selectionGeneration
        let key = selectedListKey
        do {
            let url = try await read.downloadAttachment(attachment, in: ref)
            guard !Task.isCancelled else { return nil }
            guard generation == selectionGeneration, key == selectedListKey else { return nil }
            attachmentErrorText = nil
            return url
        } catch is CancellationError {
            return nil
        } catch {
            // The only cancellation source today is the caller's task; `ReadScene.classify`
            // folds a throwing `CancellationError` into `.storage`, so check the task too.
            guard !Task.isCancelled else { return nil }
            guard generation == selectionGeneration, key == selectedListKey else { return nil }
            let normalized = (error as? MailError) ?? .storage(reason: String(describing: error))
            attachmentErrorText = ErrorText.text(for: normalized)
            return nil
        }
    }
}
