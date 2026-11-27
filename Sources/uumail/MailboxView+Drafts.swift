import MailDomain
import Presentation
import SwiftUI

/// Drafts tab (REQ-0043): the left column lists locally saved drafts, the right column
/// hosts the editor in place. Leaving the tab or picking another draft auto-saves the
/// current edits first, so nothing typed here can be lost by navigation.
extension MailboxView {
    var draftListColumn: some View {
        DraftListView(
            drafts: viewModel.drafts,
            selection: $selectedDraftID,
            onDelete: { deleteDraft($0) }
        )
            .onChange(of: selectedDraftID) { _, id in
                guard let id, let record = viewModel.drafts.first(where: { $0.id == id }) else {
                    return
                }
                openDraft(record)
            }
            .onAppear { viewModel.refreshDrafts() }
            .navigationSplitViewColumnWidth(min: 320, ideal: 480)
    }

    @ViewBuilder var draftDetail: some View {
        Group {
            editorOrPlaceholder
        }
        .navigationTitle("草稿箱")
    }

    @ViewBuilder private var editorOrPlaceholder: some View {
        if let compose = draftCompose {
            ComposeView(
                viewModel: compose,
                preferredWidth: 0,
                preferredHeight: 0,
                allowRemoteContent: false,
                isEmbedded: true,
                onDraftSaved: { viewModel.refreshDrafts() },
                onClose: { closeDraftEditor() }
            )
        } else {
            EmptyState(
                title: "选择一封草稿",
                systemImage: "square.and.pencil",
                description: "左侧选中草稿后，在这里继续编辑。"
            )
        }
    }

    /// Auto-save before the editor goes away; a failed save keeps the editor (and its
    /// content) around so the user can retry instead of losing the text.
    func leaveDraftEditor() {
        guard let compose = draftCompose else { return }
        if compose.hasEdits, !compose.saveDraft() { return }
        viewModel.refreshDrafts()
        draftCompose = nil
    }

    func openDraft(_ record: DraftRecord) {
        guard draftCompose?.draftID?.raw != record.id else { return }
        leaveDraftEditor()
        draftCompose = viewModel.compose(draft: record)
    }

    func closeDraftEditor() {
        draftCompose = nil
        selectedDraftID = nil
        viewModel.refreshDrafts()
    }

    func deleteDraft(_ record: DraftRecord) {
        if draftCompose?.draftID?.raw == record.id {
            draftCompose = nil
            selectedDraftID = nil
        }
        viewModel.deleteDraft(record)
    }

    /// True while the drafts tab is showing an editor, so the window toolbar can avoid
    /// offering mail actions that do not apply (the buttons themselves are disabled).
    var isEditingDraft: Bool { section == .drafts && draftCompose != nil }
}
