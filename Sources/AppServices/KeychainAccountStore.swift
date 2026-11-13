import Foundation
import Security

import MailDomain

/// Credentials live in the Keychain, never in the database or a config file.
/// One account per install for now (design D8). Canonical shape: `ServerConfiguration`.
public typealias StoredAccountConfiguration = ServerConfiguration

public enum KeychainError: Error, Equatable, Sendable {
    case status(OSStatus)
    case malformedData
}

public struct KeychainAccountStore: Sendable {
    private let service: String
    private let key: String

    public init(service: String = "com.uumail.account", key: String = "default") {
        self.service = service
        self.key = key
    }

    public func save(_ configuration: StoredAccountConfiguration) throws {
        let data = try JSONEncoder().encode(configuration)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(base as CFDictionary)

        var attributes = base
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let query = base
            let updates: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(query as CFDictionary, updates as CFDictionary)
            guard updateStatus == errSecSuccess else { throw KeychainError.status(updateStatus) }
            return
        }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    public func load() throws -> StoredAccountConfiguration? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecItemNotFound:
            return nil
        case errSecSuccess:
            guard let data = item as? Data,
                  let configuration = try? JSONDecoder().decode(StoredAccountConfiguration.self, from: data)
            else {
                throw KeychainError.malformedData
            }
            return configuration
        default:
            throw KeychainError.status(status)
        }
    }

    public func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.status(status)
        }
    }
}
