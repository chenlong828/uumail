import Foundation
import MailDomain

/// Wiring for the floating reader (SCN-0025) and the 30-day list window (SCN-0026).
/// Extension-only so `MailboxViewModel.swift` stays under its line budget.
extension MailboxViewModel {
    /// Start of the default list window: 30 natural days (local time) back from `now`.
    public static func listWindowStart(now: Date = Date(), calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: now.addingTimeInterval(-30 * 86_400))
    }

    /// Builds the reader's independent read model from the ports this view model already
    /// owns. The reader shares `ReadScene`/`ComposeScene` but nothing mutable.
    public func makeReader() -> ReaderViewModel {
        ReaderViewModel(
            read: read,
            compose: composeScene,
            account: account,
            onEnqueued: onEnqueued
        )
    }

    /// Re-reads the current folder after another window changed read state (the reader
    /// marks a message read). Selection is preserved; no auto-select is requested.
    public func reloadListAfterExternalChange() {
        do {
            try reloadCurrentList(autoSelect: false)
        } catch {
            presentLocalListFailure(error)
        }
    }
}
