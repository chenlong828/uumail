import Foundation
import MailDomain
import Observation
import Scenes

/// Compose state for new mail, reply, reply-all and forward (spec §4.11). The editor
/// text lives here; the scene owns the seeding/quoting rules and the outbox write.
@MainActor
@Observable
public final class ComposeViewModel: Identifiable {
    public enum Mode: Equatable, Sendable {
        case new
        case reply
        case replyAll
        case forward
    }

    public enum Status: Equatable, Sendable {
        case editing
        case sending
        /// Enqueued locally: the outbox delivers it later, no network on send.
        case queued
        case saved
        case failed(String)
    }

    public let id = UUID()
    public let mode: Mode
    public var to: String
    public var cc: String
    public var subject: String
    /// Plain-text alternative; when `bodyHTML` is non-empty it is regenerated from the
    /// HTML at send time, so the two MIME parts describe the same message.
    public var body: String
    /// The editable mail document. The view captures the WebView's HTML into this
    /// property before sending, saving, cancelling, or checking `hasEdits`.
    public var bodyHTML: String
    public private(set) var status: Status = .editing

    /// Which address field currently owns the suggestion list.
    public enum RecipientField: Equatable, Sendable {
        case to
        case cc
    }

    /// Current recipient candidates, refreshed from the in-memory directory on each
    /// keystroke. Empty means "show nothing"; the view decides whether to render a panel.
    public internal(set) var recipientSuggestions: [ContactAddress] = []
    /// Keyboard selection. `nil` is the required default: Return must not commit a
    /// recipient before the user has explicitly moved the highlight.
    public internal(set) var highlightedSuggestion: Int?

    /// One directory per compose session; `nil` means not loaded yet.
    var recipientDirectory: ContactDirectory?
    var activeRecipientField: RecipientField?
    /// Test seam: how many times the scene was asked for the directory. It must stay at
    /// one no matter how many keystrokes follow the first focus.
    var directoryLoadCount = 0

    let scene: ComposeScene
    let account: AccountID
    private let inReplyTo: String?
    private let initial: Snapshot
    /// Normalised HTML captured when the editor finished loading. Comparing against it
    /// (rather than the seed string) avoids a false "discard?" prompt caused by WebKit's
    /// serialisation.
    private var baselineHTML: String?
    /// Forwarded to the composition's delivery pump: an enqueue is the signal to flush.
    private let onEnqueued: (@MainActor () -> Void)?

    public init(
        mode: Mode,
        to: String = "",
        cc: String = "",
        subject: String = "",
        body: String = "",
        bodyHTML: String = "",
        inReplyTo: String? = nil,
        scene: ComposeScene,
        account: AccountID,
        onEnqueued: (@MainActor () -> Void)? = nil
    ) {
        self.mode = mode
        self.to = to
        self.cc = cc
        self.subject = subject
        self.body = body
        self.bodyHTML = bodyHTML
        self.inReplyTo = inReplyTo
        self.scene = scene
        self.account = account
        self.onEnqueued = onEnqueued
        self.initial = Snapshot(to: to, cc: cc, subject: subject, body: body, bodyHTML: bodyHTML)
    }

    /// Reply seed built by `ComposeScene` (address extraction and quoting rules).
    public convenience init(
        replyTo message: Message,
        bodyHTML: String?,
        scene: ComposeScene,
        account: AccountID,
        onEnqueued: (@MainActor () -> Void)? = nil
    ) {
        let draft = scene.replySeed(
            to: message,
            bodyHTML: bodyHTML,
            quotedHeader: DisplayFormat.quoteHeader(sender: message.sender, receivedRaw: message.receivedRaw)
        )
        self.init(
            mode: .reply,
            to: draft.to,
            cc: draft.cc ?? "",
            subject: draft.subject,
            body: draft.body,
            bodyHTML: draft.bodyHTML ?? "",
            inReplyTo: draft.inReplyTo,
            scene: scene,
            account: account,
            onEnqueued: onEnqueued
        )
    }

    /// Reply-all seed built by `ComposeScene`: sender and original recipients in To,
    /// original Cc kept in Cc, de-duplicated and with the current account excluded.
    public convenience init(
        replyingAllTo message: Message,
        bodyHTML: String?,
        scene: ComposeScene,
        account: AccountID,
        onEnqueued: (@MainActor () -> Void)? = nil
    ) {
        let draft = scene.replyAllSeed(
            to: message,
            bodyHTML: bodyHTML,
            account: account,
            quotedHeader: DisplayFormat.quoteHeader(sender: message.sender, receivedRaw: message.receivedRaw)
        )
        self.init(
            mode: .replyAll,
            to: draft.to,
            cc: draft.cc ?? "",
            subject: draft.subject,
            body: draft.body,
            bodyHTML: draft.bodyHTML ?? "",
            inReplyTo: draft.inReplyTo,
            scene: scene,
            account: account,
            onEnqueued: onEnqueued
        )
    }

    /// Forward seed built by `ComposeScene`.
    public convenience init(
        forwarding message: Message,
        bodyHTML: String?,
        scene: ComposeScene,
        account: AccountID,
        onEnqueued: (@MainActor () -> Void)? = nil
    ) {
        let draft = scene.forwardSeed(
            from: message,
            bodyHTML: bodyHTML,
            quotedHeader: "---------- 转发邮件 ----------"
        )
        self.init(
            mode: .forward,
            to: draft.to,
            cc: draft.cc ?? "",
            subject: draft.subject,
            body: draft.body,
            bodyHTML: draft.bodyHTML ?? "",
            inReplyTo: draft.inReplyTo,
            scene: scene,
            account: account,
            onEnqueued: onEnqueued
        )
    }

    // MARK: - Editor state

    /// Called by the editor once the document is ready. The normalised HTML becomes the
    /// cancel baseline; later captures compare against it.
    public func editorDidLoad(_ html: String) {
        guard baselineHTML == nil else { return }
        bodyHTML = html
        baselineHTML = html
    }

    /// Called before sending/saving/cancelling (and by tests) with the captured HTML.
    public func setEditorHTML(_ html: String) {
        bodyHTML = html
    }

    /// Whether the sheet should ask before discarding. Address fields, the plain-text
    /// fallback and the editor HTML all count; a freshly opened seed returns `false`.
    public var hasEdits: Bool {
        to != initial.to
            || cc != initial.cc
            || subject != initial.subject
            || body != initial.body
            || bodyHTML != (baselineHTML ?? initial.bodyHTML)
    }

    // MARK: - Presentation

    public var isSending: Bool { status == .sending }

    /// Inline status line; `nil` while editing.
    public var statusText: String? {
        switch status {
        case .editing:
            return nil
        case .sending:
            return "正在发送…"
        case .queued:
            return "已加入发件箱"
        case .saved:
            return "草稿已保存"
        case .failed(let text):
            return text
        }
    }

    public var canSend: Bool {
        !to.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && status != .sending
    }

    // MARK: - Actions

    /// Enqueues the draft; the outbox delivers it later. Returns `true` when the local
    /// transaction committed. The editor text is never cleared on failure.
    @discardableResult
    public func send() async -> Bool {
        guard status != .sending else { return false }
        status = .sending
        do {
            _ = try await scene.send(draft, account: account)
            status = .queued
            // The row is committed; the composition's pump decides when to deliver it.
            onEnqueued?()
            return true
        } catch {
            status = .failed(ErrorText.text(for: error))
            return false
        }
    }

    /// Saves a local draft (never queued, never delivered). Returns `true` on success.
    @discardableResult
    public func saveDraft() -> Bool {
        do {
            _ = try scene.saveDraft(draft, account: account)
            status = .saved
            return true
        } catch {
            status = .failed(ErrorText.text(for: error))
            return false
        }
    }

    private var draft: Draft {
        let html = bodyHTML.trimmingCharacters(in: .whitespacesAndNewlines)
        let plain = html.isEmpty ? body : HTMLText.plainText(from: html)
        return Draft(
            to: to.trimmingCharacters(in: .whitespacesAndNewlines),
            cc: cc.isEmpty ? nil : cc,
            subject: subject,
            body: plain,
            inReplyTo: inReplyTo,
            bodyHTML: html.isEmpty ? nil : html
        )
    }

    /// Immutable comparison point for `hasEdits`. A value type keeps the seed and the
    /// editor baseline independent of later mutations.
    private struct Snapshot {
        let to: String
        let cc: String
        let subject: String
        let body: String
        let bodyHTML: String
    }
}
