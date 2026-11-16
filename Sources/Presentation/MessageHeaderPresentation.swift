import Foundation
import MailDomain

/// What the reading-pane header shows for the selected message: a subject headline and
/// the envelope rows that have a value. Pure mapping — no I/O, no network, no view.
/// Empty envelope fields are dropped here so the view never renders an empty label.
public struct MessageHeaderPresentation: Equatable, Sendable {
    /// One rendered envelope line. `label` doubles as the row identity: labels are unique.
    public struct Row: Equatable, Sendable, Identifiable {
        public let label: String
        public let value: String
        /// Visual line cap; long subjects/recipient lists truncate instead of squeezing
        /// the body out of the reading pane (R27).
        public let lineLimit: Int

        public var id: String { label }

        public init(label: String, value: String, lineLimit: Int) {
            self.label = label
            self.value = value
            self.lineLimit = lineLimit
        }
    }

    public let subject: String
    public let rows: [Row]

    public init(message: Message) {
        self.subject = Self.clean(message.subject) ?? "(无主题)"

        var rows: [Row] = []
        if let sender = Self.clean(message.sender) {
            rows.append(Row(label: "发件人", value: sender, lineLimit: 1))
        }
        if let recipients = Self.clean(message.recipients) {
            rows.append(Row(label: "收件人", value: recipients, lineLimit: 2))
        }
        if let cc = Self.clean(message.cc) {
            rows.append(Row(label: "抄送", value: cc, lineLimit: 2))
        }
        let date = DisplayFormat.messageDate(message.receivedRaw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !date.isEmpty {
            rows.append(Row(label: "时间", value: date, lineLimit: 1))
        }
        self.rows = rows
    }

    /// Envelope values keep the server's display name (`"张三" <zhang@…>`) and only lose
    /// surrounding whitespace; nil/blank becomes nil so the row disappears.
    private static func clean(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
