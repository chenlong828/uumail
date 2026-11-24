// ClickCatcherProbe: the calendar block cannot use SwiftUI tap gestures for
// "single click selects / double click opens" (both fire, and Button swallows the
// single tap). The design uses a small AppKit click catcher that reads
// NSEvent.clickCount. This probe hosts it inside SwiftUI and drives synthetic
// mouse events to prove the mapping and the wiring.
//
// Run: PROBE_OUT=$PWD/click-catcher.txt ./click-catcher-probe
import AppKit
import SwiftUI

/// Maps AppKit click counts to calendar actions. Deterministic; no timers.
final class ClickCatcherView: NSView {
    var onSingleClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?

    // A hair taller than the label so the whole chip is clickable.
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        switch event.clickCount {
        case 1: onSingleClick?()
        case 2: onDoubleClick?()
        default: break
        }
    }
}

struct ClickCatcher: NSViewRepresentable {
    let onSingleClick: () -> Void
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> ClickCatcherView {
        let view = ClickCatcherView()
        view.onSingleClick = onSingleClick
        view.onDoubleClick = onDoubleClick
        return view
    }
    func updateNSView(_ nsView: ClickCatcherView, context: Context) {}
}

enum Recorder {
    static var singles = 0
    static var doubles = 0
    static func reset() { singles = 0; doubles = 0 }
}

final class ProbeDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var catcher: ClickCatcherView?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let host = ZStack {
            Color.secondary.opacity(0.2)
            Text("10:00 会议")
            ClickCatcher(onSingleClick: { Recorder.singles += 1 },
                         onDoubleClick: { Recorder.doubles += 1 })
        }
        .frame(width: 240, height: 40)

        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 240, height: 40),
                              styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.title = "chip"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: host)
        window.makeKeyAndOrderFront(nil)
        self.window = window

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.drive() }
    }

    private func drive() {
        guard let window, let content = window.contentView else {
            Probe.log("no window/content"); Probe.finish(); return
        }
        catcher = findCatcher(in: content)
        guard let catcher, let number = Optional(window.windowNumber) else {
            Probe.log("catcher view not found in hosting hierarchy"); Probe.finish(); return
        }

        // 1) single click: select only, no open.
        Recorder.reset()
        catcher.mouseDown(with: event(number: number, clickCount: 1))
        Probe.log("after clickCount=1: singles=\(Recorder.singles) doubles=\(Recorder.doubles)")

        // 2) OS semantics for a double click: one clickCount=1 then one clickCount=2.
        Recorder.reset()
        catcher.mouseDown(with: event(number: number, clickCount: 1))
        catcher.mouseDown(with: event(number: number, clickCount: 2))
        Probe.log("after clickCount=1,2: singles=\(Recorder.singles) doubles=\(Recorder.doubles)")

        // 3) a pure double click (no preceding single) must open, not select.
        Recorder.reset()
        catcher.mouseDown(with: event(number: number, clickCount: 2))
        Probe.log("after clickCount=2: singles=\(Recorder.singles) doubles=\(Recorder.doubles)")

        Probe.finish()
    }

    private func event(number: Int, clickCount: Int) -> NSEvent {
        NSEvent.mouseEvent(with: .leftMouseDown,
                           location: NSPoint(x: 20, y: 20),
                           modifierFlags: [],
                           timestamp: ProcessInfo.processInfo.systemUptime,
                           windowNumber: number,
                           context: nil,
                           eventNumber: 1,
                           clickCount: clickCount,
                           pressure: 1)!
    }

    private func findCatcher(in view: NSView) -> ClickCatcherView? {
        if let catcher = view as? ClickCatcherView { return catcher }
        for sub in view.subviews {
            if let found = findCatcher(in: sub) { return found }
        }
        return nil
    }
}

enum Probe {
    private static let handle: FileHandle? = {
        let path = ProcessInfo.processInfo.environment["PROBE_OUT"] ?? "click-catcher.txt"
        FileManager.default.createFile(atPath: path, contents: nil)
        return FileHandle(forWritingAtPath: path)
    }()

    static func log(_ line: String) {
        if let data = ("PROBE " + line + "\n").data(using: .utf8) { handle?.write(data) }
        fflush(stdout)
    }

    static func finish() {
        log("done")
        handle?.closeFile()
        exit(0)
    }
}

let app = NSApplication.shared
let delegate = ProbeDelegate()
app.delegate = delegate
app.run()
