import AppKit
import Foundation

/// Hands a generated `text/calendar` body to the system's default calendar application.
/// The app never reads the calendar or asks for calendar permission: it writes a temporary
/// `.ics` and lets the OS pick the handler.
protocol CalendarOpening {
    func open(_ url: URL) -> Bool
}

struct SystemCalendarOpening: CalendarOpening {
    func open(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }
}

enum CalendarExport {
    /// Overridable in tests/probes; production always uses `NSWorkspace`.
    nonisolated(unsafe) static var opener: CalendarOpening = SystemCalendarOpening()

    static func write(_ text: String, uid: String) throws -> URL {
        let safe = uid.filter { $0.isLetter || $0.isNumber }
        let name = "uumail-\(safe.isEmpty ? UUID().uuidString : safe).ics"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Returns whether a handler accepted the file; the temporary file stays so a late
    /// importer can read it.
    @discardableResult
    static func present(_ text: String, uid: String) -> Bool {
        guard let url = try? write(text, uid: uid) else { return false }
        return opener.open(url)
    }
}
