import Foundation
import MailDomain
import Observation
import Scenes
import MeetingDomain

/// Calendar page state (CMP-PRES): month/week mode, the anchor date, the last query result
/// and the pure grid projections the view binds to. All reads are local; the scene never
/// touches the network.
@MainActor
@Observable
public final class CalendarViewModel {
    public enum Mode: String, Sendable, CaseIterable {
        case month
        case week
    }

    public private(set) var mode: Mode = .month
    public private(set) var anchor: Date
    public private(set) var occurrences: [MeetingOccurrence] = []
    /// One row per source invitation email in the visible range, newest received first
    /// (REQ-0040). Recurring series contribute one row; `occurrence` is the first visible
    /// instance used for selection.
    public private(set) var invitationMails: [CalendarMailItem] = []
    /// Unique meetings whose source email is no longer in the local store; they stay
    /// visible on the calendar grid but cannot be opened as mail (REQ-0040).
    public private(set) var omittedInvitationCount = 0
    private var calendarOnlyKeys: Set<String> = []
    public private(set) var isLoading = false
    public private(set) var errorText: String?
    public private(set) var isTruncated = false
    public private(set) var selectedOccurrence: MeetingOccurrence?

    private let scene: CalendarScene
    private let now: @Sendable () -> Date
    private let calendar: Calendar
    /// Drops results from a superseded query (rapid next/previous clicks).
    private var generation = 0

    public init(
        calendar scene: CalendarScene,
        now: @escaping @Sendable () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.scene = scene
        self.now = now
        var calendar = calendar
        calendar.firstWeekday = 2  // Monday first, independent of system preferences
        self.calendar = calendar
        self.anchor = now()
    }

    // MARK: - Projections

    public var month: MonthGridPresentation {
        CalendarProjection.month(
            anchor: anchor,
            occurrences: occurrences,
            calendar: calendar,
            today: now()
        )
    }

    public var week: WeekGridPresentation {
        CalendarProjection.week(
            anchor: anchor,
            occurrences: occurrences,
            calendar: calendar,
            today: now()
        )
    }

    public var selectedSource: (folderID: String, serverID: String)? {
        guard let occurrence = selectedOccurrence else { return nil }
        return (occurrence.folderID, occurrence.serverID)
    }

    // MARK: - Actions

    public func activate() async {
        await reload()
    }

    public func reload() async {
        generation += 1
        let request = generation
        let range = visibleRange()
        isLoading = true
        defer {
            if request == generation { isLoading = false }
        }
        do {
            let result = try scene.events(from: range.lowerBound, to: range.upperBound)
            guard request == generation else { return }
            occurrences = result.occurrences
            let allInvitations = Self.invitationMails(from: result.occurrences, scene: scene)
            invitationMails = allInvitations.filter { $0.message != nil }
            let omitted = allInvitations.filter { $0.message == nil }
            calendarOnlyKeys = Set(omitted.map(\.id))
            omittedInvitationCount = omitted.count
            isTruncated = result.truncated
            errorText = nil
        } catch {
            guard request == generation else { return }
            errorText = ErrorText.text(for: Self.mailError(error))
        }
    }

    public func setMode(_ mode: Mode) async {
        guard mode != self.mode else { return }
        self.mode = mode
        selectedOccurrence = nil
        await reload()
    }

    public func showPrevious() async {
        shift(by: mode == .month ? -1 : -1, component: mode == .month ? .month : .weekOfYear)
        await reload()
    }

    public func showNext() async {
        shift(by: 1, component: mode == .month ? .month : .weekOfYear)
        await reload()
    }

    public func showToday() async {
        anchor = now()
        await reload()
    }

    public func select(_ occurrence: MeetingOccurrence) {
        selectedOccurrence = occurrence
    }

    /// Whether the occurrence still has its source invitation mail locally. Calendar-only
    /// occurrences stay visible on the grid but cannot open the reader (REQ-0040).
    public func hasSourceMail(for occurrence: MeetingOccurrence) -> Bool {
        !calendarOnlyKeys.contains("\(occurrence.folderID)\u{1F}\(occurrence.serverID)")
    }

    public func clearSelection() {
        selectedOccurrence = nil
    }

    /// iCalendar text for the selected occurrence's series; sets `errorText` on failure.
    public func icsText(for occurrence: MeetingOccurrence) -> String? {
        do {
            return try scene.ics(uid: occurrence.uid)
        } catch {
            errorText = ErrorText.text(for: Self.mailError(error))
            return nil
        }
    }

    /// iCalendar text for a meeting UID (reading pane export); sets `errorText` on failure.
    public func icsText(uid: String) -> String? {
        do {
            return try scene.ics(uid: uid)
        } catch {
            errorText = ErrorText.text(for: Self.mailError(error))
            return nil
        }
    }

    // MARK: - Helpers

    /// Deduplicate an occurrence list to its source mails. The query already sorted by
    /// start, so the first occurrence of a series is the one used for selection.
    private static func invitationMails(
        from occurrences: [MeetingOccurrence],
        scene: CalendarScene
    ) -> [CalendarMailItem] {
        var seen: Set<String> = []
        var items: [CalendarMailItem] = []
        for occurrence in occurrences {
            let ref = MessageRef(folderID: occurrence.folderID, serverID: occurrence.serverID)
            let key = "\(ref.folderID)\u{1F}\(ref.serverID)"
            guard seen.insert(key).inserted else { continue }
            items.append(
                CalendarMailItem(
                    message: try? scene.message(ref),
                    occurrence: occurrence
                )
            )
        }
        return items.sorted { $0.occurrence.start > $1.occurrence.start }
    }

    private func shift(by value: Int, component: Calendar.Component) {
        anchor = calendar.date(byAdding: component, value: value, to: anchor) ?? anchor
        selectedOccurrence = nil
    }

    private func visibleRange() -> ClosedRange<Date> {
        switch mode {
        case .month:
            let grid = CalendarProjection.month(anchor: anchor, occurrences: [], calendar: calendar, today: now())
            guard let first = grid.weeks.first?.days.first?.date,
                  let last = grid.weeks.last?.days.last?.date
            else { return anchor...anchor }
            let end = calendar.date(byAdding: .day, value: 1, to: last)?.addingTimeInterval(-1) ?? last
            return first...end
        case .week:
            let start = CalendarProjection.startOfWeek(anchor, calendar: calendar)
            let end = calendar.date(byAdding: .day, value: 7, to: start)?.addingTimeInterval(-1) ?? start
            return start...end
        }
    }

    private static func mailError(_ error: Error) -> MailError {
        if let mailError = error as? MailError { return mailError }
        return .storage(reason: String(describing: error))
    }
}
