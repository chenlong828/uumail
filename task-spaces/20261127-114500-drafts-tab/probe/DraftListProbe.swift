// DraftListProbe: render the production DraftListView with sample drafts.
import AppKit
import MailDomain
import SwiftUI

struct RootView: View {
    @State private var selection: String?
    let drafts: [DraftRecord]
    var body: some View {
        NavigationSplitView {
            DraftListView(drafts: drafts, selection: $selection)
                .navigationSplitViewColumnWidth(min: 320, ideal: 480)
        } detail: {
            EmptyState(
                title: "选择一封草稿",
                systemImage: "square.and.pencil",
                description: "左侧选中草稿后，在这里继续编辑。"
            )
            .navigationTitle("草稿箱")
        }
        .frame(width: 1100, height: 520)
    }
}

@MainActor
final class Delegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let now = Date()
        let drafts = [
            DraftRecord(id: "d1", to: "dfjjwb@orientsec.com.cn",
                        subject: "Re: SBTT66_资产净值公告_明晟跃迁一号",
                        body: "", updatedAt: now.addingTimeInterval(-300)),
            DraftRecord(id: "d2", to: "liuwei09508@hundsun.com",
                        subject: "Fwd: 中信建投智多鑫、添鑫宝需求验卡",
                        body: "", updatedAt: now.addingTimeInterval(-3600)),
            DraftRecord(id: "d3", to: "",
                        subject: "",
                        body: "", updatedAt: now.addingTimeInterval(-86_400)),
        ]
        let window = NSWindow(
            contentRect: NSRect(x: 80, y: 160, width: 1100, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "drafts"
        window.contentView = NSHostingView(rootView: RootView(drafts: drafts))
        window.makeKeyAndOrderFront(nil)
        print("WIN number=\(window.windowNumber)")
        fflush(stdout)
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { exit(0) }
    }
}

@main
struct DraftListProbe {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = Delegate()
        app.delegate = delegate
        app.run()
    }
}
