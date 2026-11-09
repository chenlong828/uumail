import Foundation
import MailStore
import Observation

/// Compose state for new mail, reply and forward. Owns the draft text only; delivery
/// goes through `MailSendService`, which is `MailService` in the app.
@MainActor
@Observable
public final class ComposeModel: Identifiable {
    public enum Mode: Equatable, Sendable {
        case new
        case reply
        case forward
    }

    public enum State: Equatable, Sendable {
        case editing
        case sending
        case sent
        case failed(String)
    }

    public var to: String
    public var cc: String
    public var subject: String
    public var body: String
    public private(set) var state: State = .editing

    public let mode: Mode
    public let id = UUID()
    private let inReplyTo: String?

    public init(mode: Mode, to: String = "", cc: String = "", subject: String = "", body: String = "", inReplyTo: String? = nil) {
        self.mode = mode
        self.to = to
        self.cc = cc
        self.subject = subject
        self.body = body
        self.inReplyTo = inReplyTo
    }

    /// Builds the seed for a reply/forward from the message the user is reading.
    public static func replySeed(
        sender: String?,
        subject: String?,
        html: String?
    ) -> ComposeModel {
        let cleanSubject = subject?.isEmpty == false ? subject! : "(无主题)"
        let quoted = plainText(from: html ?? "")
        return ComposeModel(
            mode: .reply,
            to: address(from: sender),
            subject: cleanSubject.lowercased().hasPrefix("re:") ? cleanSubject : "Re: \(cleanSubject)",
            body: "\n\n--- 原邮件 ---\n\(quoted)"
        )
    }

    public static func forwardSeed(subject: String?, html: String?) -> ComposeModel {
        let cleanSubject = subject?.isEmpty == false ? subject! : "(无主题)"
        let quoted = plainText(from: html ?? "")
        return ComposeModel(
            mode: .forward,
            subject: cleanSubject.lowercased().hasPrefix("fwd:") ? cleanSubject : "Fwd: \(cleanSubject)",
            body: "\n\n--- 转发邮件 ---\n\(quoted)"
        )
    }

    public var draft: MailDraft {
        MailDraft(
            to: to.trimmingCharacters(in: .whitespacesAndNewlines),
            cc: cc.isEmpty ? nil : cc,
            subject: subject,
            body: body,
            inReplyTo: inReplyTo
        )
    }

    public var canSend: Bool {
        !to.trimmingCharacters(in: .whitespaces).isEmpty && state != .sending
    }

    public func send(using service: any MailSendService) async {
        guard canSend else { return }
        state = .sending
        do {
            _ = try await service.send(draft)
            state = .sent
        } catch {
            state = .failed(String(describing: error))
        }
    }

    public func saveDraft(using service: any MailSendService) {
        do {
            _ = try service.saveDraft(draft)
            state = .sent
        } catch {
            state = .failed(String(describing: error))
        }
    }

    /// `"张三" <z@corp.com>` / `z@corp.com` → `z@corp.com`.
    static func address(from sender: String?) -> String {
        guard let sender, !sender.isEmpty else { return "" }
        if let open = sender.firstIndex(of: "<"), let close = sender.firstIndex(of: ">"), open < close {
            return String(sender[sender.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
        }
        return sender.trimmingCharacters(in: .whitespaces)
    }

    /// Very small HTML-to-text conversion for quoting; the reading pane keeps the HTML.
    static func plainText(from html: String) -> String {
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
}

public protocol MailSendService: AnyObject, Sendable {
    func send(_ draft: MailDraft) async throws -> String
    func saveDraft(_ draft: MailDraft) throws -> String
}
