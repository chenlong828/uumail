// L2 probe for T-SCN-0024-05/06 (decision D5): drives the *production*
// CalendarSelection.swift click catcher and proves the delayed single-click judgement.
//
// Expected after the 250–300ms decision:
//   single click            → selection only, applied after the delay (no immediate select)
//   clickCount=1 then 2     → the pending selection is cancelled, only "open" fires
//
// Build (from the repo root):
//   xcrun swiftc -o /tmp/calendar-click-probe \
//     Sources/uumail/CalendarSelection.swift \
//     task-spaces/20261124-152611/evidence/calendar-click/main.swift \
//     -framework SwiftUI -framework AppKit
import AppKit
import SwiftUI

enum Log {
    static let handle: FileHandle = {
        let path = ProcessInfo.processInfo.environment["PROBE_OUT"] ?? "calendar-click.txt"
        FileManager.default.createFile(atPath: path, contents: nil)
        return FileHandle(forWritingAtPath: path)!
    }()
    static func line(_ text: String) {
        handle.write(("PROBE " + text + "\n").data(using: .utf8)!)
        fflush(stdout)
    }
    static func done() {
        line("done")
        exit(0)
    }
}

final class Recorder {
    var singles = 0
    var doubles = 0
}

final class ProbeDelegate: NSObject, NSApplicationDelegate {
    let recorder = Recorder()
    var window: NSWindow?
    var catcher: ClickCatcherView?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let host = ZStack {
            Text("10:00 会议")
            ClickCatcher(
                onSingleClick: { [weak self] in self?.recorder.singles += 1 },
                onDoubleClick: { [weak self] in self?.recorder.doubles += 1 }
            )
        }
        .frame(width: 240, height: 40)

        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 240, height: 40),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: host)
        window.makeKeyAndOrderFront(nil)
        self.window = window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.runProbe() }
    }

    private func runProbe() {
        guard let window, let content = window.contentView else {
            Log.line("no window"); Log.done(); return
        }
        catcher = Self.findCatcher(in: content)
        guard let catcher else { Log.line("catcher missing from hosting tree"); Log.done(); return }

        let hit = window.contentView?.hitTest(NSPoint(x: 120, y: 20))
        Log.line("hitTest center -> \(hit.map { String(describing: type(of: $0)) } ?? "nil")")
        Log.line("delay=\(ClickCatcherView.singleClickDelay)s")

        // 1) A single click must NOT select immediately; it lands after the delay.
        catcher.mouseDown(with: event(count: 1))
        Log.line("immediately after clickCount=1: singles=\(recorder.singles) doubles=\(recorder.doubles)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            Log.line("after delay: singles=\(self.recorder.singles) doubles=\(self.recorder.doubles)")

            // 2) A real double click (1 then 2) must cancel the pending selection.
            self.recorder.singles = 0
            self.recorder.doubles = 0
            catcher.mouseDown(with: self.event(count: 1))
            catcher.mouseDown(with: self.event(count: 2))
            Log.line("after clickCount=1,2: singles=\(self.recorder.singles) doubles=\(self.recorder.doubles)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                Log.line("after delay post-double: singles=\(self.recorder.singles) doubles=\(self.recorder.doubles)")
                Log.done()
            }
        }
    }

    private func event(count: Int) -> NSEvent {
        NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 20, y: 20),
                           modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                           windowNumber: window?.windowNumber ?? 0, context: nil,
                           eventNumber: 1, clickCount: count, pressure: 1)!
    }

    static func findCatcher(in view: NSView) -> ClickCatcherView? {
        if let catcher = view as? ClickCatcherView { return catcher }
        for sub in view.subviews {
            if let found = findCatcher(in: sub) { return found }
        }
        return nil
    }
}

let app = NSApplication.shared
let delegate = ProbeDelegate()
app.delegate = delegate
app.run()
