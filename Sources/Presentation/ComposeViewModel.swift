import Foundation
import MailDomain
import Observation
import Scenes

/// Compose state for new mail, reply and forward (spec §4.11). The editor text lives
/// here; the scene owns the seeding/quoting rules and the outbox write.
@MainActor
@Observable
public final class ComposeViewModel: Identifiable {
    public enum Mode: Equatable, Sendable {
        case new
        case reply
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
    public var body: String
    public private(set) var status: Status = .editing

    private let scene: ComposeScene
    private let account: AccountID
    private let inReplyTo: String?

    public init(
        mode: Mode,
        to: String = "",
        cc: String = "",
        subject: String = "",
        body: String = "",
        inReplyTo: String? = nil,
        scene: ComposeScene,
        account: AccountID
    ) {
        self.mode = mode
        self.to = to
        self.cc = cc
        self.subject = subject
        self.body = body
        self.inReplyTo = inReplyTo
        self.scene = scene
        self.account = account
    }

    /// Reply seed built by `ComposeScene` (address extraction and quoting rules).
    public convenience init(
        replyTo message: Message,
        bodyHTML: String?,
        scene: ComposeScene,
        account: AccountID
    ) {
        let draft = scene.replySeed(to: message, bodyHTML: bodyHTML)
        self.init(
            mode: .reply,
            to: draft.to,
            cc: draft.cc ?? "",
            subject: draft.subject,
            body: draft.body,
            inReplyTo: draft.inReplyTo,
            scene: scene,
            account: account
        )
    }

    /// Forward seed built by `ComposeScene`.
    public convenience init(
        forwarding message: Message,
        bodyHTML: String?,
        scene: ComposeScene,
        account: AccountID
    ) {
        let draft = scene.forwardSeed(from: message, bodyHTML: bodyHTML)
        self.init(
            mode: .forward,
            to: draft.to,
            cc: draft.cc ?? "",
            subject: draft.subject,
            body: draft.body,
            inReplyTo: draft.inReplyTo,
            scene: scene,
            account: account
        )
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
        Draft(
            to: to.trimmingCharacters(in: .whitespacesAndNewlines),
            cc: cc.isEmpty ? nil : cc,
            subject: subject,
            body: body,
            inReplyTo: inReplyTo
        )
    }
}
