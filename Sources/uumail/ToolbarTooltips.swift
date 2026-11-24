import AppKit
import SwiftUI

/// SwiftUI does not bridge `.help` on toolbar buttons to `NSToolbarItem.toolTip` (measured
/// 2026-11-24: all seven items report a nil toolTip), so hovering the mail toolbar shows
/// nothing. This installer runs after the toolbar exists and fills the missing tooltips
/// from a label map; it is inert for items that already have one.
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
                for item in toolbar.items where (item.toolTip ?? "").isEmpty {
                    item.toolTip = Self.tooltips[item.label] ?? item.label
                }
                return
            }
            guard attempts > 1 else { return }
            // The window's toolbar can appear one run-loop turn after the content view.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                apply(to: view, attempts: attempts - 1)
            }
        }
    }
}
