import SwiftUI

/// The mailbox window toolbar. It owns no state: the view model supplies the values and
/// the actions, so every control is a pure binding and the layout can be probed headlessly.
/// This is an internal `CMP-APP` file, not a new component (decision N6).
struct MailboxToolbar: ToolbarContent {
    struct State: Equatable {
        var hasSelection: Bool
        var allowsRemoteContent: Bool
        var canAllowRemoteContent: Bool
        var canMarkSelectedRead: Bool
        var isSyncing: Bool
    }

    struct Actions {
        var newMessage: () -> Void
        var reply: () -> Void
        var replyAll: () -> Void
        var forward: () -> Void
        var setAllowRemoteContent: (Bool) -> Void
        var markSelectedRead: () -> Void
        var refresh: () -> Void
    }

    let state: State
    let actions: Actions

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: actions.newMessage) {
                Label("新建", systemImage: "square.and.pencil")
            }
            .help("新建邮件")
            Button(action: actions.reply) {
                Label("回复", systemImage: "arrowshape.turn.up.left")
            }
            .help("回复发件人")
            .disabled(!state.hasSelection)
            Button(action: actions.replyAll) {
                Label("全部回复", systemImage: "arrowshape.turn.up.left.2")
            }
            .help("回复全部收件人")
            .disabled(!state.hasSelection)
            Button(action: actions.forward) {
                Label("转发", systemImage: "arrowshape.turn.up.right")
            }
            .help("转发邮件")
            .disabled(!state.hasSelection)
            // Remote images are a per-message, session-only permission: a stateful icon
            // button (not a toggle or menu) keeps the on/off state visible in the toolbar.
            Button {
                actions.setAllowRemoteContent(!state.allowsRemoteContent)
            } label: {
                Label(
                    "加载远程图片",
                    systemImage: state.allowsRemoteContent ? "photo.fill" : "photo"
                )
            }
            .disabled(!state.canAllowRemoteContent)
            .help(
                state.allowsRemoteContent
                    ? "关闭当前邮件的远程图片"
                    : "仅对当前邮件放行远程图片"
            )
            .accessibilityLabel("加载远程图片")
            .accessibilityValue(state.allowsRemoteContent ? "已开启" : "已关闭")
            Button(action: actions.markSelectedRead) {
                Label("标记为已读", systemImage: "envelope.open")
            }
            .disabled(!state.canMarkSelectedRead)
            .help("将当前邮件标记为已读")
            Button(action: actions.refresh) {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .help("刷新收件箱")
            .disabled(state.isSyncing)
        }
    }
}
