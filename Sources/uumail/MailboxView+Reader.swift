import AppKit
import MailDomain
import Presentation
import SwiftUI

/// Reader entries on the message list (SCN-0025): double click, Return and Space all open
/// the same floating window. Kept out of `MailboxView.swift` for the single-file budget.
extension MailboxView {
    func openSelectedInReader() {
        guard let message = viewModel.selectedMessage else { return }
        openReader(message)
    }

    func openReader(_ message: Message) {
        let folder = message.folderID ?? viewModel.selection.folderID ?? ""
        guard !folder.isEmpty else { return }
        let coordinator = ReaderCoordinator.shared
        coordinator.show(
            folderID: folder,
            serverID: message.serverID,
            geometry: coordinator.geometry(readingPaneWidth: readingPaneSize.width),
            style: .mail
        )
    }
}
