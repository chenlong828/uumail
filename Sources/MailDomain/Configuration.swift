import Foundation

/// Everything needed to reach one account. Credentials live in the Keychain, never
/// in the database; this is the shape both the Keychain and the setup scene use.
public struct ServerConfiguration: Codable, Equatable, Sendable {
    public var host: String
    public var account: String
    public var password: String
    public var domain: String
    public var deviceID: String
    public var displayName: String
    /// The From address the account actually uses. Empty means "derive account@host"
    /// (the pre-REQ-0039 behavior); the setup form and `.env` can set it explicitly
    /// because Exchange hosts are often `mail.example.com` while the address is
    /// `user@example.com`.
    public var email: String
    public var deviceType: String
    public var protocolVersion: String
    public var allowInsecureTLS: Bool

    public init(
        host: String,
        account: String,
        password: String,
        domain: String,
        deviceID: String,
        displayName: String,
        email: String = "",
        deviceType: String = "iPhone",
        protocolVersion: String = "16.1",
        allowInsecureTLS: Bool = false
    ) {
        self.host = host
        self.account = account
        self.password = password
        self.domain = domain
        self.deviceID = deviceID
        self.displayName = displayName
        self.email = email
        self.deviceType = deviceType
        self.protocolVersion = protocolVersion
        self.allowInsecureTLS = allowInsecureTLS
    }

    // Keychain entries written before 2026-11-13 lack the three protocol fields;
    // decode them with defaults so an existing install keeps working.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        host = try container.decode(String.self, forKey: .host)
        account = try container.decode(String.self, forKey: .account)
        password = try container.decode(String.self, forKey: .password)
        domain = try container.decode(String.self, forKey: .domain)
        deviceID = try container.decode(String.self, forKey: .deviceID)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? account
        email = try container.decodeIfPresent(String.self, forKey: .email) ?? ""
        deviceType = try container.decodeIfPresent(String.self, forKey: .deviceType) ?? "iPhone"
        protocolVersion = try container.decodeIfPresent(String.self, forKey: .protocolVersion) ?? "16.1"
        allowInsecureTLS = try container.decodeIfPresent(Bool.self, forKey: .allowInsecureTLS) ?? false
    }

    /// The address put in the MIME `From` header and the account row. Old configurations
    /// (no `email`) keep the historical `account@host` derivation.
    public var resolvedEmail: String {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "\(account)@\(host)" : trimmed
    }
}
