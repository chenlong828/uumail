import Foundation
import MeetingDomain
import Presentation

/// Shared "open this meeting's source mail" entry for the calendar page (REQ-0040). Both
/// the month/week blocks and the new invitation-email list open the same floating reader
/// with the calendar toolbar (`转发` + `在日历中打开`).
@MainActor
enum CalendarReader {
    static func open(
        _ occurrence: MeetingOccurrence,
        model: CalendarViewModel,
        onExportFailure: @escaping @MainActor () -> Void = {}
    ) {
        let coordinator = ReaderCoordinator.shared
        coordinator.show(
            folderID: occurrence.folderID,
            serverID: occurrence.serverID,
            geometry: coordinator.geometry(readingPaneWidth: nil),
            style: .calendar,
            openInCalendar: {
                guard let text = model.icsText(for: occurrence) else {
                    onExportFailure()
                    return
                }
                if !CalendarExport.present(text, uid: occurrence.uid) {
                    onExportFailure()
                }
            }
        )
    }
}
