import AppKit
import SwiftUI

struct Root: View {
    var body: some View {
        HSplitView {
            VStack(spacing: 0) { Text("list"); Spacer() }
                .frame(minWidth: 320, idealWidth: 480, maxWidth: 760)
                .background(Color.red.opacity(0.2))
            VStack(spacing: 0) { Text("reading"); Spacer() }
                .frame(minWidth: 360)
                .background(Color.blue.opacity(0.2))
        }
        .frame(minWidth: 900, minHeight: 560)
    }
}

@MainActor
final class Delegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let w = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1440, height: 900), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        w.title = "probe"
        w.contentView = NSHostingView(rootView: Root())
        w.makeKeyAndOrderFront(nil)
        window = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { self.report() }
    }
    private func report() {
        guard let w = window, let content = w.contentView else { exit(0) }
        var splits: [NSSplitView] = []
        self.collect(content, &splits)
        for (i, s) in splits.enumerated() {
            print("split\(i) frame=\(Int(s.frame.width)) cols=\(s.subviews.map { Int($0.frame.width) })")
        }
        for width in [1200.0, 900.0] {
            var f = w.frame; f.size.width = width; w.setFrame(f, display: true); w.layoutIfNeeded()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                print("window=\(Int(width))")
                splits.removeAll(); self.collect(content, &splits)
                for (i, s) in splits.enumerated() {
                    print("  split\(i) frame=\(Int(s.frame.width)) cols=\(s.subviews.map { Int($0.frame.width) })")
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { exit(0) }
    }
    private func collect(_ v: NSView, _ out: inout [NSSplitView]) {
        if let s = v as? NSSplitView { out.append(s) }
        for sub in v.subviews { collect(sub, &out) }
    }
}

@main struct Main { @MainActor static func main() { let app = NSApplication.shared; let d = Delegate(); app.delegate = d; app.run() } }
