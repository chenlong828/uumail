import AppKit
import SwiftUI

@MainActor
final class Delegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let root = RootView()
        let controller = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 900, height: 560))
        window.makeKeyAndOrderFront(nil)
        self.window = window
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.report()
            NSApp.terminate(nil)
        }
    }

    private func report() {
        guard let toolbar = window?.toolbar else {
            print("NO TOOLBAR")
            return
        }
        for item in toolbar.items {
            let view = item.view
            print("ITEM label=\(item.label) toolTip=\(item.toolTip ?? "<nil>") viewToolTip=\(view?.toolTip ?? "<nil>")")
        }
        print("VISIBLE=\(toolbar.visibleItems?.map(\.label) ?? [])")
    }
}

struct RootView: View {
    let state = MailboxToolbar.State(
        hasSelection: true,
        allowsRemoteContent: false,
        canAllowRemoteContent: true,
        canMarkSelectedRead: true,
        isSyncing: false
    )
    let actions = MailboxToolbar.Actions(
        newMessage: {}, reply: {}, replyAll: {}, forward: {},
        setAllowRemoteContent: { _ in }, markSelectedRead: {}, refresh: {}
    )

    var body: some View {
        Text("probe")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ToolbarTooltipInstaller().frame(width: 0, height: 0))
            .toolbar {
                MailboxToolbar(state: state, actions: actions)
            }
    }
}

@main
@MainActor
struct ProbeMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = Delegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
