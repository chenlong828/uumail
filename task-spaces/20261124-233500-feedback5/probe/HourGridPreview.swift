// HourGridPreview: renders the production `CalendarHourGrid` for a visual check. It is a
// manual preview, not an automated probe: run it, take a window screenshot, then close.
// The committed hour-grid.png is the dark-scheme capture used by the scenario card.
//
// Run: ./hour-grid-preview   (it prints the window number and exits after 6s)
import AppKit
import SwiftUI

struct PreviewRoot: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            CalendarHourGrid(startHour: 8, endHour: 24, hourHeight: 48, width: 400)
            Rectangle().fill(Color.red).frame(width: 10, height: 10)
        }
        .frame(width: 400, height: 768)
        .preferredColorScheme(.dark)
    }
}

@MainActor
final class PreviewDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let window = NSWindow(
            contentRect: NSRect(x: 80, y: 80, width: 400, height: 768),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "hour-grid-preview"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: PreviewRoot())
        window.makeKeyAndOrderFront(nil)
        self.window = window
        print("WINDOW=\(window.windowNumber)")
        fflush(stdout)
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { NSApp.terminate(nil) }
    }
}

@main
struct PreviewMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = PreviewDelegate()
        app.delegate = delegate
        app.run()
    }
}
