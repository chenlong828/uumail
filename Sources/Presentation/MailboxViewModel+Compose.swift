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
