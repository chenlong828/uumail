// WindowCarrierProbe: can a SwiftUI `Window(id:)` scene serve as the single floating
// reader window, with a default size computed from the main window at open time?
//
// Questions (R63 / design D1):
//   1. does opening the same `Window` scene twice produce one window or two?
//   2. does a second open bring the existing window to front (replace-and-raise)?
//   3. can we read the main window frame and set the reader frame after opening?
//   4. is the reader NSWindow identifiable for reuse?
//
// Every line is appended to $PROBE_OUT immediately, and a watchdog terminates the app so
// the probe can never hang a batch run.
import AppKit
import SwiftUI

@main
struct WindowCarrierProbe: App {
    @NSApplicationDelegateAdaptor(ProbeDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("uumail") {
            ProbeMain()
        }
        .defaultSize(width: 1200, height: 800)
        Window("阅读", id: "reader") {
            ProbeReader()
        }
        .defaultSize(width: 700, height: 500)
    }
}

final class ProbeDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        Probe.log("launch: windows=\(NSApp.windows.count) titles=\(NSApp.windows.map(\.title))")
        DispatchQueue.main.asyncAfter(deadline: .now() + 9) {
            Probe.log("watchdog fired: windows=\(NSApp.windows.count) titles=\(NSApp.windows.map(\.title))")
            Probe.finish()
        }
    }
}

struct ProbeReader: View {
    var body: some View {
        Text("reader")
            .frame(minWidth: 480, minHeight: 460)
            .background(ProbeHostProbe())
    }
}

struct ProbeHostProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if let window = view.window {
                Probe.log("reader hosted in window number=\(window.windowNumber) title=\(window.title) " +
                          "frame=\(Probe.fmt(window.frame)) visible=\(window.isVisible)")
            } else {
                Probe.log("reader hosting view has no window yet")
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct ProbeMain: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("main")
            .frame(minWidth: 400, minHeight: 300)
            .task { await run() }
    }

    private func run() async {
        try? await Task.sleep(for: .milliseconds(1200))
        let mainWindow = NSApp.windows.first { $0.title == "uumail" }
        Probe.log("phase0 windows=\(NSApp.windows.count) titles=\(NSApp.windows.map(\.title)) " +
                  "main=\(mainWindow.map { Probe.fmt($0.frame) } ?? "nil")")

        openWindow(id: "reader")
        try? await Task.sleep(for: .milliseconds(900))
        let first = readerWindows()
        Probe.log("phase1 after 1st open: count=\(first.count) " +
                  "frames=\(first.map { Probe.fmt($0.frame) }) " +
                  "numbers=\(first.map(\.windowNumber)) " +
                  "identifiers=\(first.map { String(describing: $0.identifier?.rawValue) })")

        if let main = mainWindow, let reader = first.first {
            let target = CGSize(width: max(480, main.frame.width * 0.4),
                                height: max(460, main.frame.height * 0.85))
            reader.setFrame(NSRect(origin: reader.frame.origin, size: target), display: true)
            try? await Task.sleep(for: .milliseconds(400))
            Probe.log("phase2 sized reader to \(Probe.fmt(reader.frame)) " +
                      "(requested \(Probe.fmt(CGRect(origin: .zero, size: target))))")
        } else {
            Probe.log("phase2 skipped: main=\(mainWindow != nil) reader=\(first.first != nil)")
        }

        openWindow(id: "reader")
        try? await Task.sleep(for: .milliseconds(900))
        let second = readerWindows()
        Probe.log("phase3 after 2nd open: count=\(second.count) numbers=\(second.map(\.windowNumber)) " +
                  "sameAsFirst=\(second.first?.windowNumber == first.first?.windowNumber) " +
                  "isKey=\(second.first?.isKeyWindow ?? false)")

        first.first?.orderOut(nil)
        try? await Task.sleep(for: .milliseconds(400))
        openWindow(id: "reader")
        try? await Task.sleep(for: .milliseconds(900))
        let third = readerWindows()
        Probe.log("phase4 after orderOut+3rd open: count=\(third.count) " +
                  "visible=\(third.first?.isVisible ?? false) " +
                  "sameNumber=\(third.first?.windowNumber == first.first?.windowNumber)")

        Probe.finish()
    }

    private func readerWindows() -> [NSWindow] {
        NSApp.windows.filter { $0.title == "阅读" }
    }
}

enum Probe {
    private static let handle: FileHandle? = {
        let path = ProcessInfo.processInfo.environment["PROBE_OUT"]
            ?? CommandLine.arguments.dropFirst().first
            ?? "window-carrier.txt"
        FileManager.default.createFile(atPath: path, contents: nil)
        return FileHandle(forWritingAtPath: path)
    }()

    static func log(_ line: String) {
        print("PROBE " + line)
        fflush(stdout)
        if let data = ("PROBE " + line + "\n").data(using: .utf8) {
            handle?.write(data)
        }
    }

    static func finish() {
        log("done")
        handle?.closeFile()
        exit(0)
    }

    static func fmt(_ rect: NSRect) -> String {
        String(format: "%.0fx%.0f@%.0f,%.0f", rect.width, rect.height, rect.origin.x, rect.origin.y)
    }
}
