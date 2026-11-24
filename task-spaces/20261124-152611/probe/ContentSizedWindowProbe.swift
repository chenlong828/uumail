// ContentSizedWindowProbe: can the reader window open directly at a router-computed size
// (no static .defaultSize flash), and does the system remember the user's frame across
// launches?
//
// Run: PROBE_OUT=$PWD/content-sized.txt ./content-sized-probe
import AppKit
import SwiftUI

@main
struct ContentSizedProbe: App {
    @NSApplicationDelegateAdaptor(Probe2Delegate.self) private var delegate

    var body: some Scene {
        WindowGroup("uumail") { ProbeMain() }
            .defaultSize(width: 1200, height: 800)
        // No .defaultSize: the content frame is the only size source.
        Window("阅读2", id: "reader2") {
            Text("reader2")
                .frame(width: Probe2.size.width, height: Probe2.size.height)
                .background(SizeProbe())
        }
        .windowResizability(.contentSize)
    }
}

enum Probe2 {
    static var size = CGSize(width: 660, height: 590)
}

struct SizeProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            if let window = view.window {
                Probe.log("content-sized window frame=\(Probe.fmt(window.frame)) " +
                          "requested=\(Probe.fmt(CGRect(origin: .zero, size: Probe2.size)))")
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

final class Probe2Delegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        Probe.log("launch")
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { Probe.finish() }
    }
}

struct ProbeMain: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text("main").frame(minWidth: 400, minHeight: 300)
            .task {
                try? await Task.sleep(for: .milliseconds(900))
                let main = NSApp.windows.first { $0.title == "uumail" }
                Probe.log("main frame=\(main.map { Probe.fmt($0.frame) } ?? "nil")")
                // Router computes the target from the mailbox window before opening.
                if let main {
                    Probe2.size = CGSize(width: max(480, main.frame.width * 0.4),
                                         height: max(460, main.frame.height * 0.85))
                }
                Probe.log("computed target=\(Probe.fmt(CGRect(origin: .zero, size: Probe2.size)))")
                openWindow(id: "reader2")
                try? await Task.sleep(for: .milliseconds(900))
                Probe.log("after open windows=\(NSApp.windows.map { "\($0.title):\(Probe.fmt($0.frame))" })")
                Probe.finish()
            }
    }
}

enum Probe {
    private static let handle: FileHandle? = {
        let path = ProcessInfo.processInfo.environment["PROBE_OUT"] ?? "content-sized.txt"
        FileManager.default.createFile(atPath: path, contents: nil)
        return FileHandle(forWritingAtPath: path)
    }()

    static func log(_ line: String) {
        fflush(stdout)
        if let data = ("PROBE " + line + "\n").data(using: .utf8) { handle?.write(data) }
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
