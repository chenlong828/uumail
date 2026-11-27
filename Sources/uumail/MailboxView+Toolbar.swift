import SwiftUI

/// Toolbar content for the mailbox window, kept out of `MailboxView.swift` for the
/// per-file budget. `sectionToolbar` owns the top switch (REQ-0037/REQ-0043) and
/// `mailboxToolbar` the window-level mail actions (REQ-0042).
extension MailboxView {
    @ToolbarContentBuilder
    var sectionToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Picker("邮箱", selection: $section) {
                Text("收件箱").tag(MailboxSection.inbox)
                Text("发件箱").tag(MailboxSection.sent)
                Text("草稿箱").tag(MailboxSection.drafts)
                Text("日历").tag(MailboxSection.calendar)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 320)
        }
    }

    /// Window-level mail actions (REQ-0042): a column-scoped toolbar renders inside the
    /// split view's leading group, where the buttons collapse into overflow even when the
    /// window has room; `ToolbarTooltipInstaller` pins this group to the trailing edge.
    @ToolbarContentBuilder
    var mailboxToolbar: some ToolbarContent {
        MailboxToolbar(
            state: MailboxToolbar.State(
                hasSelection: viewModel.selectedMessage != nil,
                allowsRemoteContent: viewModel.allowsRemoteContent,
                canAllowRemoteContent: viewModel.canAllowRemoteContent,
                canMarkSelectedRead: viewModel.canMarkSelectedRead,
                isSyncing: viewModel.sync.phase == .syncing),
            actions: MailboxToolbar.Actions(
                newMessage: { compose = viewModel.composeNew() },
                reply: { compose = viewModel.composeReply() },
                replyAll: { compose = viewModel.composeReplyAll() },
                forward: { compose = viewModel.composeForward() },
                setAllowRemoteContent: { viewModel.setAllowsRemoteContent($0) },
                markSelectedRead: { viewModel.markSelectedRead() },
                refresh: {
                    Task {
                        if section == .sent { await viewModel.refreshSent() }
                        else if section == .drafts { viewModel.loadDrafts() }
                        else { await viewModel.refresh() }
                    }
                }
            )
        )
    }
}
