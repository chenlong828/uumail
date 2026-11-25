// ComposeToolbarProbe: host the production ComposeView in an offscreen-ish AppKit window,
// then snapshot it. Verifies the W-M3-21 title-bar layout at 100% and 225% font size.
//
// Run: PROBE_PNG=$PWD/shot.png PROBE_FONT=100 PROBE_WIDTH=900 ./compose-toolbar-probe
import AppKit
import HTMLSupport
import MailDomain
import MailStore
import Outbox
import Presentation
import Scenes
import SwiftUI
import SyncContract

enum ProbeError: Error { case unused }

struct ProbeGateway: MailGateway {
    func probe() async throws -> ServerCapabilities { throw ProbeError.unused }
    func provisionIfNeeded() async throws { throw ProbeError.unused }
    func fetchFolders(syncKey: String) async throws -> FolderListing { throw ProbeError.unused }
    func fetchMessages(collectionID: String, syncKey: String, window: Int, filterType: Int) async throws -> MessageDelta { throw ProbeError.unused }
    func fetchBody(collectionID: String, serverID: String) async throws -> FetchedBody { throw ProbeError.unused }
    func fetchAttachment(fileReference: String) async throws -> Data { throw ProbeError.unused }
    func send(mime: Data, clientID: String) async throws { throw ProbeError.unused }
}

struct ProbeClock: MailClock {
    var now: Date { Date() }
    func sleep(for duration: Duration) async throws {}
}

enum Probe {
    private static let handle: FileHandle? = {
        let path = ProcessInfo.processInfo.environment["PROBE_OUT"] ?? "compose-toolbar.txt"
        FileManager.default.createFile(atPath: path, contents: nil)
        return FileHandle(forWritingAtPath: path)
    }()

    static func log(_ line: String) {
        if let data = ("PROBE " + line + "\n").data(using: .utf8) { handle?.write(data) }
        print("PROBE " + line)
        fflush(stdout)
    }

    static func finish() {
        handle?.closeFile()
        exit(0)
    }
}

@MainActor
final class ProbeDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let env = ProcessInfo.processInfo.environment
        let width = CGFloat(Double(env["PROBE_WIDTH"] ?? "900") ?? 900)
        let height = CGFloat(Double(env["PROBE_HEIGHT"] ?? "760") ?? 760)
        let font: FontSizePreference = env["PROBE_FONT"] == "225" ? .percent225 : .percent100

        do {
            let path = NSTemporaryDirectory() + "uumail-compose-preview-\(UUID().uuidString).sqlite"
            let store = try MailStore(path: path)
            let outbox = Outbox(store: store, gateway: ProbeGateway(), clock: ProbeClock())
            let scene = ComposeScene(store: store, outbox: outbox)
            let quoted = """
            <div id="uumail-reply-start"><br></div>
            <div style="margin-top:12px;padding-top:12px;border-top:1px solid #ddd">\
            <span style="color:#888;font-size:12px">2026年11月25日 15:43，携程商旅预订部 写道：</span>\
            <p>验卡邀请：2026-11-26 13:30-15:30，中信建投智多鑫、添鑫宝。</p></div>
            """
            let vm = ComposeViewModel(
                mode: .forward,
                to: "dfjjwb@example.com",
                subject: "Fwd: 中信建投智多鑫、添鑫宝需求验卡",
                bodyHTML: quoted,
                scene: scene,
                account: AccountID("preview")
            )
            let window = NSWindow(
                contentRect: NSRect(x: 120, y: 120, width: width, height: height),
                styleMask: [.titled, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "compose preview"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(
                rootView: ComposeView(
                    viewModel: vm,
                    preferredWidth: width,
                    preferredHeight: height,
                    allowRemoteContent: false,
                    onClose: {}
                )
                .environment(\.fontSizePreference, font)
            )
            window.makeKeyAndOrderFront(nil)
            self.window = window
            // Keep the probe in front of the terminal so the toolbar renders in its active
            // (accent-coloured) state while the external screencapture runs.
            for delay in [0.2, 0.8, 1.4, 2.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    NSApp.activate(ignoringOtherApps: true)
                    window.makeKey()
                }
            }
            Probe.log("window=\(window.windowNumber) size=\(width)x\(height) font=\(font.rawValue)%")

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                let content = window.contentLayoutRect
                Probe.log("final-content=\(Int(content.width))x\(Int(content.height))")
                if let path = env["PROBE_PNG"], let view = window.contentView {
                    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
                    if let rep {
                        view.cacheDisplay(in: view.bounds, to: rep)
                        if let png = rep.representation(using: .png, properties: [:]) {
                            try? png.write(to: URL(fileURLWithPath: path))
                            Probe.log("snapshot=\(path)")
                        }
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { Probe.finish() }
            }
        } catch {
            Probe.log("error=\(error)")
            Probe.finish()
        }
    }
}

@main
struct ComposeToolbarProbe {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = ProbeDelegate()
        app.delegate = delegate
        app.run()
    }
}
