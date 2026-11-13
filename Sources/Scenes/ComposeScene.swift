import Foundation
import MailDomain
import MailStore
import Outbox

/// Compose: reply/forward seeds, draft saving and send intents. Sending only enqueues; the
/// `Outbox` owns delivery (spec §4.10).
public struct ComposeScene: Sendable {
    private let store: MailStore
    private let outbox: Outbox

    public init(store: MailStore, outbox: Outbox) {
        self.store = store
        self.outbox = outbox
    }

    // MARK: - Seeds

    /// Reply seed: subject gets a `Re:` prefix (unless already present), the sender address
    /// becomes the recipient, and the original body is quoted below the editor's cursor.
    public func replySeed(to message: Message, bodyHTML: String?) -> Draft {
        let cleanSubject = Self.cleanSubject(message.subject)
        return Draft(
            to: Self.address(from: message.sender),
            cc: nil,
            subject: cleanSubject.lowercased().hasPrefix("re:") ? cleanSubject : "Re: \(cleanSubject)",
            body: "\n\n--- 原邮件 ---\n\(Self.plainText(from: bodyHTML ?? ""))"
        )
    }

    /// Forward seed: `Fwd:` subject prefix and the `--- 转发邮件 ---` quoting marker.
    public func forwardSeed(from message: Message, bodyHTML: String?) -> Draft {
        let cleanSubject = Self.cleanSubject(message.subject)
        return Draft(
            to: "",
            cc: nil,
            subject: cleanSubject.lowercased().hasPrefix("fwd:") ? cleanSubject : "Fwd: \(cleanSubject)",
            body: "\n\n--- 转发邮件 ---\n\(Self.plainText(from: bodyHTML ?? ""))"
        )
    }

    // MARK: - Drafts and sending

    /// Stores a local draft row. A draft is not queued and is never delivered.
    public func saveDraft(_ draft: Draft, account: AccountID) throws -> OutboxID {
        var stored = draft
        stored.isDraft = true
        do {
            return OutboxID(try store.saveDraft(account: account, draft: stored))
        } catch {
            throw Self.classify(error)
        }
    }

    /// Validates and enqueues. No network here: the row is committed and the id returned;
    /// delivery happens later in `Outbox`.
    public func send(_ draft: Draft, account: AccountID) async throws -> OutboxID {
        var normalized = draft
        normalized.to = draft.to.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.to.isEmpty else {
            throw MailError.invalidInput(reason: "recipient is empty")
        }
        do {
            return try await outbox.enqueue(normalized, account: account)
        } catch {
            throw Self.classify(error)
        }
    }

    public func pending(account: AccountID) async throws -> [OutboxItem] {
        do {
            return try await outbox.pending(account: account)
        } catch {
            throw Self.classify(error)
        }
    }

    public func retry(_ id: OutboxID, account: AccountID) async throws {
        do {
            try await outbox.retry(id, account: account)
        } catch {
            throw Self.classify(error)
        }
    }

    public func cancel(_ id: OutboxID, account: AccountID) async throws {
        do {
            try await outbox.cancel(id, account: account)
        } catch {
            throw Self.classify(error)
        }
    }

    // MARK: - Quoting rules (moved from ComposeModel, behaviour unchanged)

    private static func cleanSubject(_ subject: String?) -> String {
        guard let subject, !subject.isEmpty else { return "(无主题)" }
        return subject
    }

    /// `"张三" <z@corp.com>` / `z@corp.com` → `z@corp.com`.
    private static func address(from sender: String?) -> String {
        guard let sender, !sender.isEmpty else { return "" }
        if let open = sender.firstIndex(of: "<"), let close = sender.firstIndex(of: ">"), open < close {
            return String(sender[sender.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
        }
        return sender.trimmingCharacters(in: .whitespaces)
    }

    /// Very small HTML-to-text conversion for quoting; the reading pane keeps the HTML.
    private static func plainText(from html: String) -> String {
        var text = html
        for tag in ["<br>", "<br/>", "<br />", "</p>", "</div>", "</tr>"] {
            text = text.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive)
        }
        while let open = text.firstIndex(of: "<"), let close = text[open...].firstIndex(of: ">") {
            text.removeSubrange(open...close)
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func classify(_ error: Error) -> MailError {
        (error as? MailError) ?? .storage(reason: String(describing: error))
    }
}
