import AppKit
import SwiftUI

/// SwiftUI does not bridge `.help` on toolbar buttons to `NSToolbarItem.toolTip` (measured
/// 2026-11-24 and again 2026-11-26: every item reports a nil toolTip), so hovering the mail
/// toolbar shows nothing. This installer runs after the toolbar exists, fills the missing
/// tooltips from a label map and pins the action group to the trailing edge (REQ-0042).
///
/// Why the trailing pin: on macOS 26 a toolbar declared inside a `NavigationSplitView`
/// lays its `primaryAction` items out right after the title/sidebar-toggle group, not at
/// the trailing edge, and the split view limits that leading group on narrow windows — the
/// remote-image and mark-read buttons collapse into the overflow menu even at 1512pt
/// (measured 2026-11-26: actions at x≈591..862, search at the right edge). Inserting one
/// flexible space before the action group and dropping the system flexible space that sits
/// before the search field moves the group to x≈898..1169, flush with the search field.
struct ToolbarTooltipInstaller: NSViewRepresentable {
    static let tooltips: [String: String] = [
        "新建": "新建邮件",
        "回复": "回复发件人",
        "全部回复": "回复全部收件人",
        "转发": "转发邮件",
        "加载远程图片": "仅对当前邮件放行远程图片",
        "标记为已读": "将当前邮件标记为已读",
        "刷新": "刷新收件箱",
    ]

    /// The mail action group, in toolbar order. Kept in sync with `MailboxToolbar`.
    static let actionLabels: Set<String> = [
        "新建", "回复", "全部回复", "转发", "加载远程图片", "标记为已读", "刷新",
    ]

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        apply(to: view, attempts: 5)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        apply(to: view, attempts: 3)
    }

    private func apply(to view: NSView, attempts: Int) {
        DispatchQueue.main.async {
            if let toolbar = view.window?.toolbar {
                Self.installTooltips(in: toolbar)
                Self.pinActionGroupToTrailingEdge(in: toolbar)
                return
            }
            guard attempts > 1 else { return }
            // The window's toolbar can appear one run-loop turn after the content view.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                apply(to: view, attempts: attempts - 1)
            }
        }
    }

    static func installTooltips(in toolbar: NSToolbar) {
        for item in toolbar.items where (item.toolTip ?? "").isEmpty {
            item.toolTip = tooltips[item.label] ?? item.label
        }
    }

    static func pinActionGroupToTrailingEdge(in toolbar: NSToolbar) {
        guard let first = toolbar.items.firstIndex(where: { actionLabels.contains($0.label) }) else {
            return
        }
        // One flexible space before the group absorbs the slack that the title group
        // leaves; inserting it twice would split the space and defeat the pin.
        if first > 0, toolbar.items[first - 1].itemIdentifier != .flexibleSpace {
            toolbar.insertItem(withItemIdentifier: .flexibleSpace, at: first)
        }
        // The system also places a flexible space right before the search field; with two
        // flexible spaces the slack is split and the actions stop short of the edge.
        guard let last = toolbar.items.lastIndex(where: { actionLabels.contains($0.label) }),
              let search = toolbar.items.firstIndex(where: { isSearchItem($0) }),
              search > last
        else { return }
        var index = search - 1
        while index > last {
            if toolbar.items[index].itemIdentifier == .flexibleSpace {
                toolbar.removeItem(at: index)
                break
            }
            index -= 1
        }
    }

    private static func isSearchItem(_ item: NSToolbarItem) -> Bool {
        let identifier = item.itemIdentifier.rawValue.lowercased()
        return identifier.contains("search") || item.label.lowercased() == "search"
    }
}
