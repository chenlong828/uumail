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
        deviceType = try container.decodeIfPresent(String.self, forKey: .deviceType) ?? "iPhone"
        protocolVersion = try container.decodeIfPresent(String.self, forKey: .protocolVersion) ?? "16.1"
        allowInsecureTLS = try container.decodeIfPresent(Bool.self, forKey: .allowInsecureTLS) ?? false
    }
}
