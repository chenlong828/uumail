import SwiftUI

/// Row-wide click target for the message list (SCN-0025). SwiftUI's
/// `.onTapGesture(count: 2)` attached to a row inside `List(selection:)` does not fire on
/// macOS (the list consumes the click; measured 2026-11-24 while fixing the broken
/// double-click entry), so the row reuses the AppKit click catcher from the calendar.
///
/// The single click selects immediately — a list row should not wait 0.28s the way a
/// calendar block does to avoid a selection flash.
struct MessageRowClick: View {
    let onSelect: () -> Void
    let onOpen: () -> Void

    var body: some View {
        ClickCatcher(
            singleClickDelay: 0,
            onSingleClick: onSelect,
            onDoubleClick: onOpen
        )
    }
}
