// AppKitWindowProbe: verify the fallback carrier — an AppKit NSWindow hosting SwiftUI
// content — opens at an exact, router-computed content size before it becomes visible,
// and that a single window instance can be reused (replace content + raise).
//
// Run: PROBE_OUT=$PWD/appkit-window.txt ./appkit-window-probe
import AppKit
import SwiftUI

final class ProbeDelegate: NSObject, NSApplicationDelegate {
    private var mainWindow: NSWindow?
    private var reader: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let main = NSWindow(contentRect: NSRect(x: 156, y: 106, width: 1200, height: 800),
                            styleMask: [.titled, .closable, .resizable, .miniaturizable],
                            backing: .buffered, defer: false)
        main.title = "uumail"
        main.isReleasedWhenClosed = false
        main.contentView = NSHostingView(rootView: Text("main").frame(minWidth: 400, minHeight: 300))
        main.makeKeyAndOrderFront(nil)
        mainWindow = main

        // Compute the reader size from the main window (reading-pane width is a fraction of
        // the mailbox window in the real app; 0.4 stands in for it here).
        let target = NSSize(width: max(480, main.frame.width * 0.4),
                            height: max(460, main.frame.height * 0.85))

        // Open at the computed *content* size before ordering front: no resize flash.
        showReader(target: target, offset: NSPoint(x: 40, y: 40))
        let firstNumber = reader?.windowNumber ?? -1
        Probe.log("first open: number=\(firstNumber) frame=\(Probe.fmt(reader!.frame)) " +
                  "content=\(Probe.fmt(reader!.contentLayoutRect)) " +
                  "requestedContent=\(Probe.fmt(CGRect(origin: .zero, size: target)))")

        // Reuse: replace content, resize to a new target, raise — still one reader window.
        let second = NSSize(width: 520, height: 620)
        reader?.setContentSize(second)
        reader?.contentView = NSHostingView(rootView: Text("other mail").frame(maxWidth: .infinity, maxHeight: .infinity))
        reader?.makeKeyAndOrderFront(nil)
        Probe.log("second open: number=\(reader!.windowNumber) " +
                  "sameInstance=\(reader!.windowNumber == firstNumber) " +
                  "content=\(Probe.fmt(reader!.contentLayoutRect)) " +
                  "requestedContent=\(Probe.fmt(CGRect(origin: .zero, size: second))) " +
                  "readerWindows=\(NSApp.windows.filter { $0.title == "阅读" }.count)")

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { Probe.finish() }
    }

    private func showReader(target: NSSize, offset: NSPoint) {
        if let reader {
            reader.setContentSize(target)
            reader.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: target),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "阅读"
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.contentView = NSHostingView(rootView: Text("mail").frame(maxWidth: .infinity, maxHeight: .infinity))
        // Position relative to the mailbox window.
        if let mainWindow {
            window.setFrameTopLeftPoint(NSPoint(x: mainWindow.frame.minX + offset.x,
                                                y: mainWindow.frame.maxY - offset.y))
        }
        window.makeKeyAndOrderFront(nil)
        reader = window
    }
}

enum Probe {
    private static let handle: FileHandle? = {
        let path = ProcessInfo.processInfo.environment["PROBE_OUT"] ?? "appkit-window.txt"
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

    static func fmt(_ rect: NSRect) -> String {
        String(format: "%.0fx%.0f", rect.width, rect.height)
    }
}

let app = NSApplication.shared
let delegate = ProbeDelegate()
app.delegate = delegate
app.run()
