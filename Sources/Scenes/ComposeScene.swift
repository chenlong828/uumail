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
    /// becomes the recipient, and the original mail is appended at full width under a
    /// date/sender header. `quotedHeader` is formatted by Presentation; a missing one
    /// falls back to the neutral `原邮件` marker.
    public func replySeed(to message: Message, bodyHTML: String?, quotedHeader: String? = nil) -> Draft {
        let cleanSubject = Self.cleanSubject(message.subject)
        return Self.seed(
            to: Self.address(from: message.sender),
            cc: nil,
            subject: cleanSubject.lowercased().hasPrefix("re:") ? cleanSubject : "Re: \(cleanSubject)",
            header: quotedHeader ?? "原邮件",
            bodyHTML: bodyHTML
        )
    }

    /// Reply-all seed: the same subject and quote rules as `replySeed`, with the original
    /// sender and recipients merged into `to` and the original Cc kept in `cc`. Addresses
    /// are parsed and de-duplicated by `AddressList`, the current account is excluded, and
    /// Cc drops anything already in To. A missing or unreadable account only disables
    /// self-exclusion; it is not an error here.
    public func replyAllSeed(
        to message: Message,
        bodyHTML: String?,
        account: AccountID,
        quotedHeader: String? = nil
    ) -> Draft {
        let reply = replySeed(to: message, bodyHTML: bodyHTML, quotedHeader: quotedHeader)
        let ownAddress: String?
        do {
            ownAddress = try store.account(account)?.address
        } catch {
            ownAddress = nil
        }

        let recipients = AddressList([message.sender, message.recipients]).removing(ownAddress)
        let cc = AddressList(message.cc).removing(ownAddress).subtracting(recipients)

        return Draft(
            to: recipients.text,
            cc: cc.isEmpty ? nil : cc.text,
            subject: reply.subject,
            body: reply.body,
            bodyHTML: reply.bodyHTML
        )
    }

    /// Forward seed: `Fwd:` subject prefix and the same full-width quoting layout.
    public func forwardSeed(
        from message: Message,
        bodyHTML: String?,
        quotedHeader: String? = nil
    ) -> Draft {
        let cleanSubject = Self.cleanSubject(message.subject)
        return Self.seed(
            to: "",
            cc: nil,
            subject: cleanSubject.lowercased().hasPrefix("fwd:") ? cleanSubject : "Fwd: \(cleanSubject)",
            header: quotedHeader ?? "---------- 转发邮件 ----------",
            bodyHTML: bodyHTML
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

    /// Builds the HTML document and its plain-text alternative from the same quoted
    /// content, so the two MIME parts never disagree about what was included.
    private static func seed(to: String, cc: String?, subject: String, header: String, bodyHTML: String?) -> Draft {
        let html = HTMLText.quotedEmail(header: header, originalHTML: bodyHTML)
        return Draft(
            to: to,
            cc: cc,
            subject: subject,
            body: HTMLText.plainText(from: html),
            bodyHTML: html
        )
    }

    private static func classify(_ error: Error) -> MailError {
        (error as? MailError) ?? .storage(reason: String(describing: error))
    }
}
