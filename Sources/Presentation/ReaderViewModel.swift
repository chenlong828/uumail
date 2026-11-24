import Foundation
import MailDomain
import MeetingDomain
import MailDomain
import Scenes

/// Reading state for the single floating reader window (SCN-0025).
///
/// This is deliberately a second, independent read model: the mailbox window's selection,
/// body and remote-content permission must not be shared with a window that can be showing
/// another message at the same time. Only `ReadScene` (the data) and `ComposeScene`
/// (the reply seeds) are shared.
@MainActor
@Observable
public final class ReaderViewModel {
    public private(set) var ref: MessageRef?
    public private(set) var message: Message?
    /// The ref is no longer in the local store (deleted, or never synced).
    public private(set) var isMissing = false
    public private(set) var header: MessageHeaderPresentation?
    public private(set) var meetingCard: MeetingCardPresentation?
    public internal(set) var body: BodyPresentation = .none
    public internal(set) var bodyNotice: BodyNotice?
    /// Body HTML with `cid:` sources already rewritten (same projection as the mailbox).
    public internal(set) var inlineImageHTML: String?
    public private(set) var markReadErrorText: String?
    /// Set while the reader is showing a compose editor instead of the message.
    public private(set) var compose: ComposeViewModel?

    public var isComposing: Bool { compose != nil }
    public var canCompose: Bool { message != nil && !isMissing }
    /// The reader loads remote images by default (REQ-0031); the mailbox pane is unaffected.
    public var allowsRemoteContent: Bool { true }

    /// Called after a local 0→1 read transition so the mailbox list can refresh.
    @ObservationIgnored public var onReadChanged: (@MainActor () -> Void)?

    private let read: ReadScene
    private let composeScene: ComposeScene
    private let account: AccountID
    private let onEnqueued: (@MainActor () -> Void)?

    @ObservationIgnored private var bodyTask: Task<Void, Never>?
    @ObservationIgnored private var inlineTask: Task<Void, Never>?
    @ObservationIgnored private var openToken: UInt64 = 0

    public init(
        read: ReadScene,
        compose: ComposeScene,
        account: AccountID,
        onEnqueued: (@MainActor () -> Void)? = nil
    ) {
        self.read = read
        self.composeScene = compose
        self.account = account
        self.onEnqueued = onEnqueued
    }

    /// Loads `ref` and, when it is unread, marks it read (REQ-0031).
    public func load(_ ref: MessageRef) async {
        openToken &+= 1
        let token = openToken
        bodyTask?.cancel()
        bodyTask = nil
        inlineTask?.cancel()
        inlineTask = nil

        self.ref = ref
        message = try? read.message(ref)
        guard let message else {
            isMissing = true
            header = nil
            meetingCard = nil
            body = .none
            bodyNotice = nil
            inlineImageHTML = nil
            markReadErrorText = nil
            return
        }

        isMissing = false
        header = MessageHeaderPresentation(message: message)
        meetingCard = MeetingCardPresentation.make(from: try? read.meeting(for: ref))
        markReadOnOpen(message, ref: ref)

        body = .none
        bodyNotice = nil
        inlineImageHTML = nil

        if let cached = try? read.bodyIfCached(ref), !cached.isEmpty {
            body = .loaded(html: cached, truncated: false)
            startInlineRender(ref: ref, html: cached, token: token)
            return
        }

        if let preview = MailboxViewModel.previewHTML(for: message.bodyPreview) {
            body = .loaded(html: preview, truncated: false)
            bodyNotice = .fetchingFullBody
        } else {
            body = .loading
        }

        let stream = read.open(ref)
        let task = Task { [weak self] in
            for await event in stream {
                guard let self, !Task.isCancelled, self.openToken == token else { break }
                self.apply(event, ref: ref, token: token)
            }
        }
        bodyTask = task
        await task.value
        if openToken == token { bodyTask = nil }
    }

    /// String-keyed load for the app target (no `MessageRef` outside `Presentation`).
    public func load(folderID: String, serverID: String) async {
        await load(MessageRef(folderID: folderID, serverID: serverID))
    }

    /// Re-opens the current message's body (the failure placeholder's retry).
    public func retry() {
        guard let ref else { return }
        Task { await load(ref) }
    }

    // MARK: - Compose seeds (same rules as the mailbox toolbar)

    public func composeReply() {
        guard let message, !isMissing else { return }
        compose = ComposeViewModel(
            replyTo: message,
            bodyHTML: quotableHTML,
            scene: composeScene,
            account: account,
            onEnqueued: onEnqueued
        )
    }

    public func composeReplyAll() {
        guard let message, !isMissing else { return }
        compose = ComposeViewModel(
            replyingAllTo: message,
            bodyHTML: quotableHTML,
            scene: composeScene,
            account: account,
            onEnqueued: onEnqueued
        )
    }

    public func composeForward() {
        guard let message, !isMissing else { return }
        compose = ComposeViewModel(
            forwarding: message,
            bodyHTML: quotableHTML,
            scene: composeScene,
            account: account,
            onEnqueued: onEnqueued
        )
    }

    /// Leaves compose mode (after send, draft save or discard).
    public func endComposing() {
        compose = nil
    }

    /// The body a reply may quote: a sync preview must never be quoted.
    var quotableHTML: String? {
        guard bodyNotice == nil, case .loaded(let html, _) = body else { return nil }
        return html
    }

    // MARK: - Internals

    private func markReadOnOpen(_ message: Message, ref: MessageRef) {
        guard !message.isRead else { return }
        do {
            let changed = try read.markReadLocally(ref)
            markReadErrorText = nil
            if changed {
                self.message?.isRead = true
                onReadChanged?()
                let read = self.read
                Task { _ = await read.writeBackMarkRead(ref) }
            }
        } catch {
            let normalized = (error as? MailError) ?? .storage(reason: String(describing: error))
            markReadErrorText = ErrorText.text(for: normalized)
            self.message?.isRead = false
        }
    }

    private func apply(_ event: BodyEvent, ref: MessageRef, token: UInt64) {
        guard openToken == token, self.ref == ref else { return }
        switch event {
        case .cached(let html):
            body = .loaded(html: html, truncated: false)
            bodyNotice = nil
            startInlineRender(ref: ref, html: html, token: token)
        case .loaded(let fetched):
            body = .loaded(html: fetched.text, truncated: fetched.isTruncated)
            bodyNotice = nil
            startInlineRender(ref: ref, html: fetched.text, token: token)
        case .failed(let error):
            let text = ErrorText.text(for: error)
            if case .loaded(let html, let truncated) = body, bodyNotice != nil {
                body = .loaded(html: html, truncated: truncated)
                bodyNotice = .previewFallback(text: text)
            } else {
                body = .failed(text: text)
                bodyNotice = nil
            }
        }
    }

    private func startInlineRender(ref: MessageRef, html: String, token: UInt64) {
        inlineTask?.cancel()
        inlineImageHTML = nil
        inlineTask = Task { [weak self] in
            guard let self else { return }
            let rendered = await self.read.renderInlineImages(for: ref, html: html)
            guard !Task.isCancelled, self.openToken == token else { return }
            self.inlineImageHTML = rendered
        }
    }
}
