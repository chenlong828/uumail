import AppKit
import Presentation
import SwiftUI

/// Owns the app's single floating reader window (SCN-0025). AppKit, not SwiftUI `Window`:
/// the probe showed a SwiftUI window cannot apply a runtime-computed size before it becomes
/// visible, and the default size (reading-pane width × 85% of the mailbox height) is part of
/// the requirement.
@MainActor
final class ReaderCoordinator: NSObject, NSWindowDelegate {
    /// The app has exactly one mailbox window, so one reader window manager is enough;
    /// a singleton keeps the SwiftUI views free of an Observation dependency (the app
    /// target may not import Observation).
    static let shared = ReaderCoordinator()

    let router = ReaderRouter()

    private weak var mailbox: MailboxViewModel?
    private var model: ReaderViewModel?
    private var window: NSWindow?

    /// Called by the mailbox view when it appears; the reader borrows the same scenes.
    func attach(viewModel: MailboxViewModel) {
        mailbox = viewModel
    }

    /// Reader geometry for the mailbox entry: its measured reading-pane width plus the
    /// current mailbox window and screen.
    func geometry(readingPaneWidth: CGFloat?) -> ReaderGeometry {
        let window = NSApp.keyWindow
        let screen = window?.screen ?? NSScreen.main
        return ReaderGeometry(
            readingPaneWidth: readingPaneWidth ?? (window.map { $0.frame.width * 0.5 } ?? 720),
            windowHeight: window?.frame.height ?? 720,
            screenHeight: screen?.visibleFrame.height ?? 1200
        )
    }

    func show(
        folderID: String,
        serverID: String,
        geometry: ReaderGeometry,
        style: ReaderRouter.ToolbarStyle,
        openInCalendar: (@MainActor () -> Void)? = nil
    ) {
        guard let mailbox else { return }
        let model = self.model ?? mailbox.makeReader()
        self.model = model
        model.onReadChanged = { [weak self] in
            self?.mailbox?.reloadListAfterExternalChange()
        }

        let outcome = router.open(
            folderID: folderID, serverID: serverID,
            geometry: geometry, style: style, openInCalendar: openInCalendar
        )
        if outcome == .blocked {
            reveal()
            return
        }
        if outcome == .created {
            makeWindow(model: model, size: router.targetSize)
        }
        reveal()
        Task { await model.load(folderID: folderID, serverID: serverID) }
    }

    // MARK: - Window

    private func makeWindow(model: ReaderViewModel, size: CGSize) {
        let host = NSHostingView(rootView: ReaderWindowView(model: model, router: router))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "阅读"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.setFrameAutosaveName("uumail.reader")
        window.contentView = host
        window.setContentSize(size)
        position(window)
        self.window = window
    }

    /// Top-right of the mailbox window, inset so the window never covers the list fully.
    private func position(_ window: NSWindow) {
        let reference = NSApp.windows.first { $0.title == "uumail" } ?? NSApp.keyWindow
        guard let reference else { return }
        let frame = reference.frame
        window.setFrameTopLeftPoint(
            CGPoint(x: frame.maxX - 40, y: frame.maxY - 40)
        )
    }

    private func reveal() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard router.isComposing else { return true }
        let alert = NSAlert()
        alert.messageText = "放弃这封邮件？"
        alert.informativeText = "已输入的内容不会保存。"
        alert.addButton(withTitle: "放弃")
        alert.addButton(withTitle: "继续编辑")
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        model?.endComposing()
        router.endComposing()
        return true
    }

    func windowWillClose(_ notification: Notification) {
        router.reset()
        window = nil
    }
}
