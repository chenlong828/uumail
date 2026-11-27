import Foundation
import MailDomain
import Scenes

/// Compose entry points live in their own file so the mailbox state machine stays under
/// the component line budget. Only the scene call and editor seeds are here.
extension MailboxViewModel {
    /// The body HTML a reply/forward may quote: never a sync preview.
    var quotableHTML: String? {
        guard bodyNotice == nil, case .loaded(let html, _) = body else { return nil }
        return html
    }

    /// Reads the locally saved drafts (REQ-0043). Store failures surface as an empty list;
    /// the drafts list has no error banner of its own (compose still works).
    public func loadDrafts() {
        drafts = (try? composeScene.drafts(account: account)) ?? []
    }

    /// Loads the list, then merges with the server Drafts folder in the background and
    /// loads again (REQ-0044). The local list is shown immediately, so a slow or offline
    /// server never blocks the drafts tab.
    public func refreshDrafts() {
        loadDrafts()
        Task {
            _ = await syncScene.syncDrafts()
            loadDrafts()
        }
    }

    public func deleteDraft(_ record: DraftRecord) {
        try? composeScene.deleteDraft(OutboxID(record.id), account: account)
        loadDrafts()
        Task {
            _ = await syncScene.syncDrafts()
            loadDrafts()
        }
    }

    /// Reopens a stored draft in the editor: same row id, so saving updates it and sending
    /// converts it into the queued row instead of creating a duplicate.
    public func compose(draft record: DraftRecord) -> ComposeViewModel {
        ComposeViewModel(
            mode: .draft,
            to: record.to,
            cc: record.cc ?? "",
            subject: record.subject,
            body: record.body,
            bodyHTML: record.bodyHTML ?? "",
            inReplyTo: record.inReplyTo,
            draftID: OutboxID(record.id),
            scene: composeScene,
            account: account,
            onEnqueued: onEnqueued
        )
    }

    public func composeNew() -> ComposeViewModel {
        ComposeViewModel(mode: .new, scene: composeScene, account: account, onEnqueued: onEnqueued)
    }

    public func composeReply() -> ComposeViewModel? {
        guard let message = selectedMessage else { return nil }
        return ComposeViewModel(
            replyTo: message,
            bodyHTML: quotableHTML,
            scene: composeScene,
            account: account,
            onEnqueued: onEnqueued
        )
    }

    /// Reply-all editor: the seed call is the only place addresses are computed.
    public func composeReplyAll() -> ComposeViewModel? {
        guard let message = selectedMessage else { return nil }
        return ComposeViewModel(
            replyingAllTo: message,
            bodyHTML: quotableHTML,
            scene: composeScene,
            account: account,
            onEnqueued: onEnqueued
        )
    }

    public func composeForward() -> ComposeViewModel? {
        guard let message = selectedMessage else { return nil }
        return ComposeViewModel(
            forwarding: message,
            bodyHTML: quotableHTML,
            scene: composeScene,
            account: account,
            onEnqueued: onEnqueued
        )
    }
}
