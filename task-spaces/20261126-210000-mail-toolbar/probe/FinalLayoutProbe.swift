// FinalLayoutProbe: the fixed wiring (window-level toolbar + installer) at 1512pt and
// 900pt. Prints item frames and visible counts; the window is captured externally.
import AppKit
import SwiftUI

enum Demo {
    static let state = MailboxToolbar.State(
        hasSelection: true, allowsRemoteContent: false,
        canAllowRemoteContent: true, canMarkSelectedRead: true, isSyncing: false
    )
    static let actions = MailboxToolbar.Actions(
        newMessage: {}, reply: {}, replyAll: {}, forward: {},
        setAllowRemoteContent: { _ in }, markSelectedRead: {}, refresh: {}
    )
}

struct RootView: View {
    @State private var query = ""
    @State private var section = 0
    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(0..<20, id: \.self) { i in Text("Row \(i)") }
                Divider(); Text("status")
            }
            .navigationTitle("收件箱")
            .searchable(text: $query, placement: .toolbar, prompt: "搜索邮件")
            .navigationSplitViewColumnWidth(min: 320, ideal: 480)
        } detail: {
            Text("detail").navigationTitle("阅读")
        }
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Picker("邮箱", selection: $section) {
                    Text("收件箱").tag(0); Text("发件箱").tag(1); Text("日历").tag(2)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 260)
            }
            MailboxToolbar(state: Demo.state, actions: Demo.actions)
        }
        .background(ToolbarTooltipInstaller().frame(width: 0, height: 0))
    }
}

@MainActor
final class Delegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let window = NSWindow(
            contentRect: NSRect(x: 40, y: 160, width: 1512, height: 420),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false
        )
        window.title = "final"
        window.contentView = NSHostingView(rootView: RootView())
        window.makeKeyAndOrderFront(nil)
        self.window = window
        print("WIN number=\(window.windowNumber) width=\(Int(window.frame.width))")
        fflush(stdout)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.dump("1512")
            var frame = window.frame
            frame.size.width = 900
            window.setFrame(frame, display: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                self.dump("900")
                DispatchQueue.main.asyncAfter(deadline: .now() + 25) { exit(0) }
            }
        }
    }

    private func dump(_ label: String) {
        guard let toolbar = window?.toolbar else { return }
        print("LAYOUT \(label) visible=\(toolbar.visibleItems?.count ?? -1)/\(toolbar.items.count)")
        for item in toolbar.items {
            guard let view = item.view else {
                print("LAYOUT   \(label) \(item.label.isEmpty ? "<\(item.itemIdentifier.rawValue.prefix(20))>" : item.label): no view"); continue
            }
            let r = view.convert(view.bounds, to: nil)
            print(String(format: "LAYOUT   %@ %@ x=%.0f..%.0f tip='%@'", label,
                         item.label.isEmpty ? "<\(item.itemIdentifier.rawValue.prefix(20))>" : item.label,
                         r.minX, r.maxX, item.toolTip ?? "nil"))
        }
        fflush(stdout)
    }
}

@main
struct FinalLayoutProbe {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = Delegate()
        app.delegate = delegate
        app.run()
    }
}
