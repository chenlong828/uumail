// StabilityProbe: state churn must not duplicate flexible spaces or un-pin the group.
import AppKit
import SwiftUI

struct RootView: View {
    @State private var enabled = true
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
            MailboxToolbar(
                state: MailboxToolbar.State(
                    hasSelection: enabled, allowsRemoteContent: false,
                    canAllowRemoteContent: enabled, canMarkSelectedRead: enabled,
                    isSyncing: false),
                actions: MailboxToolbar.Actions(
                    newMessage: {}, reply: {}, replyAll: {}, forward: {},
                    setAllowRemoteContent: { _ in }, markSelectedRead: {}, refresh: {})
            )
        }
        .background(ToolbarTooltipInstaller().frame(width: 0, height: 0))
        .onReceive(Timer.publish(every: 0.3, on: .main, in: .common).autoconnect()) { _ in
            enabled.toggle()
        }
    }
}

@MainActor
final class Delegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let window = NSWindow(
            contentRect: NSRect(x: 40, y: 160, width: 1512, height: 360),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "stability"
        window.contentView = NSHostingView(rootView: RootView())
        window.makeKeyAndOrderFront(nil)
        self.window = window
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { self.dump("t3") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) { self.dump("t6"); exit(0) }
    }

    private func dump(_ label: String) {
        guard let toolbar = window?.toolbar else { return }
        let flex = toolbar.items.filter { $0.itemIdentifier == .flexibleSpace }.count
        let firstAction = toolbar.items.first { ["新建", "回复", "刷新"].contains($0.label) }
        var x: CGFloat = -1
        if let view = firstAction?.view { x = view.convert(view.bounds, to: nil).minX }
        print("STAB \(label) items=\(toolbar.items.count) flex=\(flex) firstActionX=\(Int(x))")
        fflush(stdout)
    }
}

@main
struct StabilityProbe {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = Delegate()
        app.delegate = delegate
        app.run()
    }
}
