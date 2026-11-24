import AppKit
import SwiftUI

struct Root: View {
    @State private var section = 0
    var body: some View {
        NavigationSplitView {
            List { Text("mail") }
                .navigationSplitViewColumnWidth(min: 320, ideal: 480)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("刷新") {}
                    }
                }
        } detail: {
            Text("reading")
        }
        .toolbar(removing: .sidebarToggle)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Picker("邮箱", selection: $section) {
                    Text("收件箱").tag(0)
                    Text("发件箱").tag(1)
                    Text("日历").tag(2)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)
            }
        }
    }
}

@MainActor final class Delegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1000, height: 600), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        w.title = "uumail"; w.contentView = NSHostingView(rootView: Root()); w.makeKeyAndOrderFront(nil); window = w
        print("WINDOW=\(w.windowNumber)"); fflush(stdout)
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { exit(0) }
    }
}
@main struct Main { @MainActor static func main() { let app = NSApplication.shared; let d = Delegate(); app.delegate = d; app.run() } }
