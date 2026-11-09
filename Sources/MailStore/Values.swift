import Foundation

public struct AccountID: Hashable, Sendable, CustomStringConvertible {
    public let raw: String

    public init(_ raw: String) {
        self.raw = raw
    }

    public var description: String { raw }
}

public struct NewAccount: Sendable {
    public var displayName: String
    public var address: String
    public var host: String

    public init(displayName: String, address: String, host: String) {
        self.displayName = displayName
        self.address = address
        self.host = host
    }
}

/// A folder as the store knows it. Deliberately not the protocol layer's type:
/// the store contract must not depend on EAS shapes.
public struct MailFolder: Equatable, Sendable {
    public var serverID: String
    public var parentID: String?
    public var displayName: String
    public var type: Int

    public init(serverID: String, parentID: String?, displayName: String, type: Int) {
        self.serverID = serverID
        self.parentID = parentID
        self.displayName = displayName
        self.type = type
    }
}

public struct StoredFolder: Equatable, Sendable {
    public var serverID: String
    public var parentID: String?
    public var displayName: String
    public var type: Int
}

public enum MailStoreError: Error, Equatable, Sendable {
    case accountNotFound(AccountID)
    case invalidFolder(reason: String)
    case database(String)
}
