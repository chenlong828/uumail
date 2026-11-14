import Foundation
import MailDomain
import Scenes

/// Keyboard delete lives in its own file so the mailbox state machine stays under the
/// component line budget.
extension MailboxViewModel {

    /// Keyboard delete: hide immediately, advance selection, then let the scene confirm.
    public func deleteSelected() async {
        guard !isDeleteInFlight,
              selectedMessage != nil,
              let ref = selectedRef,
              let originalKey = selectedListKey
        else { return }

        let index = visibleMessages.firstIndex(where: { Self.listKey(for: $0) == originalKey }) ?? 0
        let folderID = selection.folderID
        let query = selection.searchQuery
        guard deletion.begin(ref) else { return }

        isDeleteInFlight = true
        defer { isDeleteInFlight = false }
        dwell.cancel()

        let remaining = visibleMessages
        let next = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)]
        let nextKey = next.map(Self.listKey(for:))
        if let next {
            selectedListKey = nextKey
            selection.messageID = next.serverID
            startBodyLoad()
        } else {
            selectedListKey = nil
            selection.messageID = nil
            clearBody()
        }

        let outcome = await deletion.commit(ref)
        let stillOnNext = selection.folderID == folderID
            && selection.searchQuery == query
            && selectedListKey == nextKey

        switch outcome {
        case .deleted:
            try? reloadCurrentList(autoSelect: false)
            deletion.clearHidden(ref)
            refreshDwell()
        case .failed:
            try? reloadCurrentList(autoSelect: false)
            if stillOnNext,
               let original = messages.first(where: { Self.listKey(for: $0) == originalKey }) {
                selectedListKey = originalKey
                selection.messageID = original.serverID
                startBodyLoad()
            }
            refreshDwell()
        case .ignored:
            break
        }
    }
}
