import Foundation
import Scenes

/// The primary window's geometry, supplied by the App layer. `Presentation` never reads
/// `NSWindow`; it only receives the three numbers the reader size rule needs.
public struct ReaderGeometry: Equatable, Sendable {
    /// Width of the mailbox reading pane (the compose sheet already uses this width).
    public var readingPaneWidth: CGFloat
    /// Height of the mailbox window.
    public var windowHeight: CGFloat
    /// Usable height of the screen the mailbox window is on.
    public var screenHeight: CGFloat

    public init(readingPaneWidth: CGFloat, windowHeight: CGFloat, screenHeight: CGFloat) {
        self.readingPaneWidth = readingPaneWidth
        self.windowHeight = windowHeight
        self.screenHeight = screenHeight
    }

    /// Used when the mailbox window has not laid out yet (first launch).
    public static let fallback = ReaderGeometry(readingPaneWidth: 720, windowHeight: 720, screenHeight: 1400)
}

/// Owns the single floating reader's state (SCN-0025): which message it shows, whether it
/// is composing, and why a replace was refused. The window itself is AppKit and lives in
/// `CMP-APP`; this type is UI-framework free so the rules stay testable.
@MainActor
@Observable
public final class ReaderRouter {
    public enum Outcome: Equatable, Sendable {
        /// The window did not exist; the app has to create it at `targetSize`.
        case created
        /// The window exists; the app has to replace the content and raise it.
        case replaced
        /// A draft is being written; the app must only raise the window and show `blockedNotice`.
        case blocked
    }

    /// Which toolbar the window shows: the list entry replies/forwards, the calendar entry
    /// only forwards and exports the invite.
    public enum ToolbarStyle: Equatable, Sendable {
        case mail
        case calendar
    }

    public private(set) var currentRef: MessageRef?
    public private(set) var isComposing = false
    public private(set) var targetSize: CGSize
    /// Non-nil while a compose is in progress and the user asked for another message.
    public private(set) var blockedNotice: String?
    public private(set) var toolbarStyle: ToolbarStyle = .mail
    /// Calendar entry's `.ics` action; the window view calls it from the toolbar.
    @ObservationIgnored public var openInCalendar: (@MainActor () -> Void)?

    public init() {
        targetSize = Self.readerSize(for: .fallback)
    }

    /// Requests the reader to show `ref`.
    ///
    /// - Replaces the current ref and recomputes `targetSize` when not composing.
    /// - Refuses to replace while composing; sets `blockedNotice` instead.
    @discardableResult
    public func open(
        _ ref: MessageRef,
        geometry: ReaderGeometry,
        style: ToolbarStyle = .mail,
        openInCalendar: (@MainActor () -> Void)? = nil
    ) -> Outcome {
        if isComposing {
            blockedNotice = "正在撰写中，请先取消或发送"
            return .blocked
        }
        let existed = currentRef != nil
        currentRef = ref
        blockedNotice = nil
        toolbarStyle = style
        self.openInCalendar = openInCalendar
        targetSize = Self.readerSize(for: geometry)
        return existed ? .replaced : .created
    }

    /// String-keyed entry for the app target, which is not allowed to import `Scenes`.
    @discardableResult
    public func open(
        folderID: String,
        serverID: String,
        geometry: ReaderGeometry,
        style: ToolbarStyle = .mail,
        openInCalendar: (@MainActor () -> Void)? = nil
    ) -> Outcome {
        open(MessageRef(folderID: folderID, serverID: serverID),
             geometry: geometry, style: style, openInCalendar: openInCalendar)
    }

    /// The reader closed (or was hidden): forget the ref so the next open is a create.
    public func reset() {
        currentRef = nil
        blockedNotice = nil
        openInCalendar = nil
    }

    public func beginComposing() {
        isComposing = true
        blockedNotice = nil
    }

    public func endComposing() {
        isComposing = false
        blockedNotice = nil
    }

    /// Reader default size: reading-pane width (min 480) × 85% of the mailbox window
    /// height (min 460, capped by the screen's usable height).
    public static func readerSize(for geometry: ReaderGeometry) -> CGSize {
        let width = max(480, geometry.readingPaneWidth)
        let height = max(460, min(geometry.windowHeight * 0.85, geometry.screenHeight))
        return CGSize(width: width, height: height)
    }

    /// Window origin that centers `size` on `container` (the mailbox window) and keeps the
    /// whole window inside the screen's `visibleFrame` (REQ-0035). The previous placement
    /// pinned the reader to the mailbox's top-right corner, which read as "off to the side"
    /// no matter where the main window was.
    public static func centeredOrigin(
        in container: CGRect,
        size: CGSize,
        visible: CGRect
    ) -> CGPoint {
        let maxX = max(visible.minX, visible.maxX - size.width)
        let maxY = max(visible.minY, visible.maxY - size.height)
        let centeredX = container.midX - size.width / 2
        let centeredY = container.midY - size.height / 2
        return CGPoint(
            x: min(max(centeredX, visible.minX), maxX),
            y: min(max(centeredY, visible.minY), maxY)
        )
    }
}
