import AppKit
import SwiftUI

/// Calendar blocks need "single click selects, double click opens". SwiftUI's tap gestures
/// do not give that: `Button` swallows the single tap, and attaching count:1 + count:2 makes
/// a double click fire both. A tiny AppKit view reads `NSEvent.clickCount` instead.
///
/// Probe evidence (2026-11-24): the OS sends clickCount 1 and then 2 for a real double
/// click. A double click must not flash the selection first, so a single click is applied
/// only after the double-click interval (decision D5, 250–300ms); a second click cancels
/// the pending selection and opens immediately.
final class ClickCatcherView: NSView {
    /// 0.28s sits inside the agreed 250–300ms window and matches the system default.
    /// List rows pass 0 so the first click selects immediately and the second opens.
    static let singleClickDelay: TimeInterval = 0.28

    /// Override for hosts that must not defer the single click. Calendar blocks keep the
    /// default so a double click does not flash the selection first.
    var singleClickDelay: TimeInterval = ClickCatcherView.singleClickDelay

    var onSingleClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?

    private var pendingSingleClick: DispatchWorkItem?

    override var isOpaque: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        switch event.clickCount {
        case 1:
            pendingSingleClick?.cancel()
            if singleClickDelay > 0 {
                let work = DispatchWorkItem { [weak self] in self?.onSingleClick?() }
                pendingSingleClick = work
                DispatchQueue.main.asyncAfter(deadline: .now() + singleClickDelay, execute: work)
            } else {
                pendingSingleClick = nil
                onSingleClick?()
            }
        case 2:
            pendingSingleClick?.cancel()
            pendingSingleClick = nil
            onDoubleClick?()
        default:
            break
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            pendingSingleClick?.cancel()
            pendingSingleClick = nil
        }
        super.viewWillMove(toWindow: newWindow)
    }
}

struct ClickCatcher: NSViewRepresentable {
    var singleClickDelay: TimeInterval = ClickCatcherView.singleClickDelay
    var onSingleClick: () -> Void = {}
    var onDoubleClick: () -> Void = {}

    func makeNSView(context: Context) -> ClickCatcherView {
        let view = ClickCatcherView()
        view.singleClickDelay = singleClickDelay
        view.onSingleClick = onSingleClick
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ nsView: ClickCatcherView, context: Context) {
        nsView.singleClickDelay = singleClickDelay
        nsView.onSingleClick = onSingleClick
        nsView.onDoubleClick = onDoubleClick
    }
}
