// MessageRowClickProbe: production `MessageRowClick` (AppKit click catcher) hosted in a
// `List(selection:)` row exactly as `MailboxView` wires it. The bug (2026-11-24): SwiftUI
// `.onTapGesture(count: 2)` on a row never fired on macOS, so only Enter opened the reader.
//
// Run: PROBE_OUT=$PWD/message-row-click.txt ./message-row-click-probe
import AppKit
import SwiftUI

struct ProbeRoot: View {
    @State private var selection: String?
    let log: (String) -> Void

    var body: some View {
        List(selection: $selection) {
            ForEach(["a", "b", "c"], id: \.self) { id in
                Text("mail \(id)")
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                    .tag(id)
                    .overlay {
                        MessageRowClick(
                            onSelect: {
                                log("select \(id)")
                                selection = id
                            },
                            onOpen: { log("open \(id)") }
                        )
                    }
            }
        }
        .frame(width: 360, height: 240)
    }
}

@MainActor
final class ProbeDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let log: (String) -> Void = { Probe.log($0) }
        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 360, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "list"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ProbeRoot(log: log))
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(window.contentView)
        self.window = window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.drive() }
    }

    private func drive() {
        guard let window, let content = window.contentView else {
            Probe.log("no window/content"); Probe.finish(); return
        }
        let catchers = findCatchers(in: content)
        Probe.log("catchers=\(catchers.count)")
        guard catchers.count >= 3 else { Probe.finish(); return }
        let number = window.windowNumber

        // 1) Single click selects the row and does not open.
        catchers[0].mouseDown(with: event(number: number, clickCount: 1))
        Probe.log("after row0 clickCount=1")

        // 2) OS double-click semantics: clickCount=1 then clickCount=2 → select + open.
        catchers[1].mouseDown(with: event(number: number, clickCount: 1))
        catchers[1].mouseDown(with: event(number: number, clickCount: 2))
        Probe.log("after row1 clickCount=1,2")

        // 3) A pure double click opens even when the row was not selected first.
        catchers[2].mouseDown(with: event(number: number, clickCount: 2))
        Probe.log("after row2 clickCount=2")

        // 4) Dispatch through the window's hit testing, not by calling the catcher directly.
        if let third = catchers.last {
            let point = third.convert(NSPoint(x: 10, y: 10), to: nil)
            let event = NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: point,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: number,
                context: nil,
                eventNumber: 7,
                clickCount: 1,
                pressure: 1
            )!
            window.sendEvent(event)
            Probe.log("after window.sendEvent hitTest at \(Int(point.x)),\(Int(point.y))")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { Probe.finish() }
    }

    private func event(number: Int, clickCount: Int) -> NSEvent {
        NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 10, y: 10),
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: number,
            context: nil,
            eventNumber: 1,
            clickCount: clickCount,
            pressure: 1
        )!
    }

    private func findCatchers(in view: NSView) -> [ClickCatcherView] {
        var result: [ClickCatcherView] = []
        if let catcher = view as? ClickCatcherView { result.append(catcher) }
        for sub in view.subviews { result += findCatchers(in: sub) }
        return result.sorted { lhs, rhs in
            lhs.convert(lhs.bounds.origin, to: nil).y > rhs.convert(rhs.bounds.origin, to: nil).y
        }
    }
}

enum Probe {
    private static let handle: FileHandle? = {
        let path = ProcessInfo.processInfo.environment["PROBE_OUT"] ?? "message-row-click.txt"
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

@main
struct ProbeMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = ProbeDelegate()
        app.delegate = delegate
        app.run()
    }
}
