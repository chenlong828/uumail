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

    /// A new name for the centered placement (REQ-0035): the old `uumail.reader` frame was
    /// always parked at the mailbox's top-right, so restoring it would keep the old offset.
    private static let frameAutosaveName = "uumail.reader.centered"
    /// Set once the user drags the reader; from then on the saved frame wins over centering.
    private static let userMovedKey = "uumail.reader.userMoved"

    let router = ReaderRouter()

    private weak var mailbox: MailboxViewModel?
    private var model: ReaderViewModel?
    private var window: NSWindow?
    private var isPlacing = false

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
        window.setFrameAutosaveName(Self.frameAutosaveName)
        let restored = window.setFrameUsingName(Self.frameAutosaveName)
        window.contentView = host
        if restored {
            // Keep the user's size and, after a drag, their position. A never-moved window
            // is re-centered on the mailbox every launch (REQ-0035).
            if !UserDefaults.standard.bool(forKey: Self.userMovedKey) {
                centerOnMailbox(window)
            }
        } else {
            window.setContentSize(size)
            centerOnMailbox(window)
        }
        self.window = window
    }

    /// Center the reader on the mailbox window, clamped to that screen's usable area. The
    /// rectangle is computed by `ReaderRouter` so the placement rule stays testable.
    private func centerOnMailbox(_ window: NSWindow) {
        guard let reference = mailboxWindow else { return }
        guard let visible = (reference.screen ?? NSScreen.main)?.visibleFrame else { return }
        isPlacing = true
        window.setFrameOrigin(
            ReaderRouter.centeredOrigin(
                in: reference.frame,
                size: window.frame.size,
                visible: visible
            )
        )
        isPlacing = false
    }

    /// The mailbox window is the app's main window. Identify it by exclusion because its
    /// title changes with the selected folder.
    private var mailboxWindow: NSWindow? {
        if let main = NSApp.mainWindow, main !== window { return main }
        return NSApp.windows.first {
            $0 !== window && $0.isVisible && $0.styleMask.contains(.titled)
        }
    }

    private func reveal() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - NSWindowDelegate

    /// Remember a user drag, but not the programmatic centering above (no current mouse
    /// event during `setFrameOrigin`).
    func windowDidMove(_ notification: Notification) {
        guard !isPlacing, (notification.object as? NSWindow) === window else { return }
        guard NSApp.currentEvent?.type == .leftMouseDragged else { return }
        UserDefaults.standard.set(true, forKey: Self.userMovedKey)
    }

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
