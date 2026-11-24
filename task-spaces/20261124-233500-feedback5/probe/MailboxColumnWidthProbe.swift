// MailboxColumnWidthProbe: the production mail split (sidebar 180/220, list 320/480)
// hosted at several window widths. `GeometryReader` overlays report the actual column
// widths, so the check does not depend on AppKit's private NavigationSplitView hierarchy.
//
// Run: PROBE_OUT=$PWD/column-width.txt ./mailbox-column-width-probe
import AppKit
import SwiftUI

enum WidthSink {
    static var values: [String: CGFloat] = [:]
    static func record(_ name: String, _ width: CGFloat) {
        values[name] = width
        Probe.log("  column \(name)=\(Int(width))")
    }
    static func dump() {
        let order = ["sidebar", "list", "detail"]
        let text = order.compactMap { name in values[name].map { "\(name)=\(Int($0))" } }
        Probe.log("  measured: \(text.joined(separator: " "))")
    }
}

private struct Measured<Content: View>: View {
    let name: String
    @ViewBuilder var content: Content

    var body: some View {
        content
            .overlay {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { WidthSink.record(name, proxy.size.width) }
                        .onChange(of: proxy.size.width) { _, width in
                            WidthSink.record(name, width)
                        }
                }
            }
    }
}

struct ProbeRoot: View {
    var body: some View {
        NavigationSplitView {
            Measured(name: "sidebar") {
                List { Text("收件箱") }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } content: {
            Measured(name: "list") {
                List { Text("邮件") }
            }
            .navigationSplitViewColumnWidth(min: 320, ideal: 480)
        } detail: {
            Measured(name: "detail") {
                Text("阅读").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

@MainActor
final class ProbeDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var widths: [CGFloat] = [1440, 1200, 1000, 900, 760]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1440, height: 900),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "uumail"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ProbeRoot())
        window.makeKeyAndOrderFront(nil)
        self.window = window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.next() }
    }

    private func next() {
        guard let width = widths.first else { Probe.finish(); return }
        widths.removeFirst()
        guard let window else { Probe.finish(); return }
        var frame = window.frame
        frame.size.width = width
        window.setFrame(frame, display: true)
        window.layoutIfNeeded()
        Probe.log("window width=\(Int(width))")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            WidthSink.dump()
            self.next()
        }
    }
}

enum Probe {
    private static let handle: FileHandle? = {
        let path = ProcessInfo.processInfo.environment["PROBE_OUT"] ?? "column-width.txt"
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
