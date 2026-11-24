import Foundation
import MailDomain

/// Developer escape hatch: a plain-text credentials file at `~/.uumail.env` so a rebuilt,
/// re-signed app does not ask the login Keychain for access on every launch.
///
/// Opt-in by design: the app never writes this file on its own. The "开发" menu item
/// exports the current credentials once; after that the startup path reads the file and
/// leaves the Keychain untouched. The file is chmod 0600 and holds a plain-text password,
/// so it is the developer's responsibility to keep it out of version control and backups.
public struct DotEnvCredentialStore: Sendable {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".uumail.env")
    }

    public let url: URL

    public init(url: URL = DotEnvCredentialStore.defaultURL) {
        self.url = url
    }

    /// `nil` for a missing file, an unreadable one, or a file missing a required key; the
    /// caller then falls back to the login Keychain.
    public func load() -> ServerConfiguration? {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        let values = Self.parse(text)
        guard let host = values["EAS_HOST"], !host.isEmpty,
              let account = values["EAS_USER"], !account.isEmpty,
              let password = values["EAS_PASS"], !password.isEmpty,
              let deviceID = values["EAS_DEVICE_ID"], !deviceID.isEmpty
        else { return nil }
        return ServerConfiguration(
            host: host,
            account: account,
            password: password,
            domain: values["EAS_DOMAIN"] ?? "",
            deviceID: deviceID,
            displayName: values["EAS_DISPLAY_NAME"].flatMap { $0.isEmpty ? nil : $0 } ?? account,
            email: values["EAS_EMAIL"] ?? ""
        )
    }

    /// Writes the file through a `0600` temporary file so the password is never readable
    /// by other accounts, even for the instant before the permissions are applied.
    public func save(_ configuration: ServerConfiguration) throws {
        let lines = [
            "# uumail 开发用凭据（明文密码），由「开发」菜单生成。",
            "# 应用启动时优先读取本文件，读到就不再访问登录钥匙串；请勿提交或分享。",
            "EAS_HOST=\(Self.quote(configuration.host))",
            "EAS_USER=\(Self.quote(configuration.account))",
            "EAS_PASS=\(Self.quote(configuration.password))",
            "EAS_DOMAIN=\(Self.quote(configuration.domain))",
            "EAS_DEVICE_ID=\(Self.quote(configuration.deviceID))",
            "EAS_DISPLAY_NAME=\(Self.quote(configuration.displayName))",
            "EAS_EMAIL=\(Self.quote(configuration.email))",
            "",
        ]
        let manager = FileManager.default
        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(".uumail.env.\(UUID().uuidString)")
        guard manager.createFile(
            atPath: temporary.path,
            contents: Data(lines.joined(separator: "\n").utf8),
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw DotEnvCredentialError.writeFailed(path: temporary.path)
        }
        do {
            if manager.fileExists(atPath: url.path) {
                _ = try manager.replaceItemAt(url, withItemAt: temporary)
            } else {
                try manager.moveItem(at: temporary, to: url)
            }
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            try? manager.removeItem(at: temporary)
            throw error
        }
    }

    // MARK: - Parsing

    /// `KEY=VALUE` lines; comments (`#`), blank lines, an optional `export ` prefix and
    /// single/double quoted values are accepted. Unknown keys are ignored.
    static func parse(_ text: String) -> [String: String] {
        var values: [String: String] = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            if line.hasPrefix("export ") {
                line = String(line.dropFirst("export ".count)).trimmingCharacters(in: .whitespaces)
            }
            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            let value = unquote(String(line[line.index(after: separator)...]))
            values[key] = value
        }
        return values
    }

    private static func quote(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func unquote(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespaces)
        guard value.count >= 2, let first = value.first, let last = value.last,
              (first == "\"" && last == "\"") || (first == "'" && last == "'")
        else { return value }
        let body = String(value.dropFirst().dropLast())
        guard first == "\"" else { return body }
        return body
            .replacingOccurrences(of: "\\\\", with: "\\")
            .replacingOccurrences(of: "\\\"", with: "\"")
    }
}

/// Failures of the developer credential file; the menu reports them verbatim.
public enum DotEnvCredentialError: Error, Equatable, CustomStringConvertible {
    case writeFailed(path: String)

    public var description: String {
        switch self {
        case .writeFailed(let path): "无法写入 \(path)"
        }
    }
}
