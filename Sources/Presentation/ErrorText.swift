import Foundation
import MailDomain

/// The single `MailError` → 中文文案 mapping. Views never switch on errors: the view
/// models call this and store the resulting text (spec §7 复用归位).
public enum ErrorText {
    public static func text(for error: Error) -> String {
        if let mailError = error as? MailError {
            return text(for: mailError)
        }
        return String(describing: error)
    }

    public static func text(for error: MailError) -> String {
        switch error {
        case .authFailed:
            return "账号或密码不正确，请重新配置"
        case .deviceNotRegistered:
            return "设备未登记：请在网关登记并激活该设备 ID 后重试"
        case .policyBlocked:
            return "服务器策略拒绝了当前设备，请联系管理员"
        case .syncKeyInvalid:
            return "同步状态已失效，请刷新重新拉取"
        case .throttled(let seconds):
            if let seconds {
                return "服务器请求过于频繁，请 \(seconds) 秒后再试"
            }
            return "服务器请求过于频繁，请稍后再试"
        case .offline:
            return "网络连接失败，请检查网络后重试"
        case .unsupported:
            return "网关返回了暂不支持的结果"
        case .storage(let reason):
            return "本地存储失败：\(reason)"
        case .invalidInput(let reason):
            return "输入有误：\(reason)"
        }
    }
}

/// Dates and sender names the mailbox list/status bar render. Formatting lives here,
/// not in the views (spec §7 复用归位).
public enum DisplayFormat {
    /// `"张三" <zhang@corp.com>` → `张三`; a bare address stays as is.
    public static func senderName(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "" }
        guard let angle = raw.firstIndex(of: "<") else { return raw }
        let name = raw[..<angle].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? raw : name.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    /// Envelope `received` (ISO-8601, sometimes with fractional seconds) → `MM-dd HH:mm`.
    public static func messageDate(_ raw: String?) -> String {
        guard let raw else { return "" }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = parser.date(from: raw) else { return String(raw.prefix(16)) }
        return timestamp(date)
    }

    /// A local timestamp for the status bar.
    public static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    /// The line above a quoted reply: `2026年11月9日 20:11，Playasia <…> 写道：`.
    /// The HTML document escapes it; this function only formats the text.
    public static func quoteHeader(sender: String?, receivedRaw: String?) -> String {
        let date = longDate(receivedRaw)
        let who = sender?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch (date.isEmpty, who.isEmpty) {
        case (false, false): return "\(date)，\(who) 写道："
        case (false, true): return "\(date) 写道："
        case (true, false): return "\(who) 写道："
        case (true, true): return "原邮件"
        }
    }

    /// `2026年11月9日 20:11` in the user's time zone; empty when the raw value is absent
    /// or unparseable.
    public static func longDate(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "" }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = parser.date(from: raw)
        if date == nil {
            parser.formatOptions = [.withInternetDateTime]
            date = parser.date(from: raw)
        }
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter.string(from: date)
    }
}
