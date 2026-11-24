import AppKit
import SwiftUI

private struct Measured<Content: View>: View {
    let name: String
    @ViewBuilder var content: Content
    var body: some View {
        content.overlay {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { print("COL \(name)=\(Int(proxy.size.width))") }
                    .onChange(of: proxy.size.width) { _, w in print("COL \(name)=\(Int(w))") }
            }
        }
    }
}

struct Root: View {
    var body: some View {
        NavigationSplitView {
            Measured(name: "list") { List { Text("mail") } }
                .navigationSplitViewColumnWidth(min: 320, ideal: 480)
        } detail: {
            Measured(name: "reading") { Text("reading").frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
    }
}

@MainActor final class Delegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1440, height: 900), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        w.title = "probe"; w.contentView = NSHostingView(rootView: Root()); w.makeKeyAndOrderFront(nil); window = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.measure(1440) }
    }
    private var widths: [CGFloat] = [1440, 1200, 1000, 900, 760]
    private func measure(_ width: CGFloat) {
        guard let w = window else { exit(0) }
        var f = w.frame; f.size.width = width; w.setFrame(f, display: true); w.layoutIfNeeded()
        print("WINDOW \(Int(width))")
        widths.removeFirst()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            if let next = self.widths.first { self.measure(next) } else { exit(0) }
        }
    }
}
@main struct Main { @MainActor static func main() { let app = NSApplication.shared; let d = Delegate(); app.delegate = d; app.run() } }
