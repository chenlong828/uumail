import Foundation
import MailDomain
import Scenes

/// List loading and selection for the mailbox window. Extension-only so
/// `MailboxViewModel.swift` stays inside its 400-line budget (R70).
extension MailboxViewModel {
    func reloadFolders() throws {
        folders = try read.folders()
        if let current = selection.folderID, folders.contains(where: { $0.serverID == current }) {
            return
        }
        selection.folderID = folders.first(where: \.isInbox)?.serverID ?? folders.first?.serverID
    }

    func reloadCurrentList(autoSelect: Bool) throws {
        let query = selection.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            guard let folder = selection.folderID else {
                messages = []
                clearSelection()
                return
            }
            // REQ-0033: the folder's last 30 days, no row cap (the sync window is one
            // month, so this is everything the local store holds for the folder).
            messages = try read.messages(folderID: folder, since: Self.listWindowStart())
        } else {
            messages = try read.search(query, limit: 100)
        }

        if let key = selectedListKey,
           let message = messages.first(where: { Self.listKey(for: $0) == key }),
           !isHidden(message) {
            return
        }
        if let id = selection.messageID,
           let message = messages.first(where: { $0.serverID == id }),
           !isHidden(message) {
            selectedListKey = Self.listKey(for: message)
            return
        }
        if autoSelect, let first = visibleMessages.first {
            select(first, open: true)
        } else {
            clearSelection()
        }
    }

    func select(_ message: Message, open: Bool) {
        selectedListKey = Self.listKey(for: message)
        selection.messageID = message.serverID
        refreshSelectedMeeting()
        refreshDwell()
        if open {
            startBodyLoad()
        }
    }

    func clearSelection() {
        selection.messageID = nil
        selectedListKey = nil
        meetingInvite = nil
        clearBody()
        dwell.cancel()
    }

    func isHidden(_ message: Message) -> Bool {
        guard let ref = ref(for: message) else { return false }
        return deletion.hidden.contains(ref)
    }
}
