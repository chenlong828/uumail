import Foundation
import MailDomain

/// Minimal RFC822 builder: UTF-8 text body, optional reply headers.
/// Attachments are not part of M2's first slice.
public enum MimeBuilder {
    public static func build(from: String, draft: Draft, messageID: String, date: Date = Date()) -> Data {
        var lines: [String] = []
        lines.append("From: \(from)")
        lines.append("To: \(draft.to)")
        if let cc = draft.cc, !cc.isEmpty { lines.append("Cc: \(cc)") }
        lines.append("Subject: \(encodeHeader(draft.subject))")
        lines.append("Date: \(dateFormatter.string(from: date))")
        lines.append("Message-ID: <\(messageID)>")
        if let inReplyTo = draft.inReplyTo, !inReplyTo.isEmpty {
            lines.append("In-Reply-To: <\(inReplyTo.trimmingCharacters(in: CharacterSet(charactersIn: "<>")))>")
        }
        if let references = draft.references, !references.isEmpty {
            lines.append("References: \(references)")
        }
        lines.append("MIME-Version: 1.0")
        lines.append("Content-Type: text/plain; charset=utf-8")
        lines.append("Content-Transfer-Encoding: base64")
        lines.append("")
        let encodedBody = Data(draft.body.utf8).base64EncodedString(options: [.lineLength76Characters])
        lines.append(encodedBody)
        return Data((lines.joined(separator: "\r\n") + "\r\n").utf8)
    }

    /// RFC 2047 base64 encoding for non-ASCII headers.
    static func encodeHeader(_ value: String) -> String {
        guard value.unicodeScalars.contains(where: { $0.value > 127 }) else { return value }
        return "=?UTF-8?B?\(Data(value.utf8).base64EncodedString())?="
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter
    }()
}
