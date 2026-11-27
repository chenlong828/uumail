// EmbeddedComposeProbe: the production ComposeView in embedded (drafts-pane) mode.
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

@MainActor
final class Delegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        do {
            let path = NSTemporaryDirectory() + "uumail-draft-preview-\(UUID().uuidString).sqlite"
            let store = try MailStore(path: path)
            let outbox = Outbox(store: store, gateway: ProbeGateway(), clock: ProbeClock())
            let scene = ComposeScene(store: store, outbox: outbox)
            let vm = ComposeViewModel(
                mode: .draft,
                to: "dfjjwb@example.com",
                subject: "Re: SBTT66_资产净值公告_明晟跃迁一号",
                bodyHTML: "<div id=\"uumail-reply-start\"><br></div><div style=\"margin-top:12px;padding-top:12px;border-top:1px solid #ddd\"><p>验卡邀请：2026-11-26 13:30-15:30，中信建投智多鑫、添鑫宝。</p></div>",
                draftID: OutboxID("preview-draft"),
                scene: scene,
                account: AccountID("preview")
            )
            let window = NSWindow(
                contentRect: NSRect(x: 100, y: 120, width: 820, height: 700),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered, defer: false
            )
            window.title = "embedded"
            window.contentView = NSHostingView(
                rootView: ComposeView(
                    viewModel: vm,
                    preferredWidth: 0,
                    preferredHeight: 0,
                    allowRemoteContent: false,
                    isEmbedded: true,
                    onDraftSaved: {},
                    onClose: {}
                )
                .environment(\.fontSizePreference, .percent100)
            )
            window.makeKeyAndOrderFront(nil)
            print("WIN number=\(window.windowNumber)")
            fflush(stdout)
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { exit(0) }
        } catch {
            print("ERR \(error)")
            exit(1)
        }
    }
}

@main
struct EmbeddedComposeProbe {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = Delegate()
        app.delegate = delegate
        app.run()
    }
}
