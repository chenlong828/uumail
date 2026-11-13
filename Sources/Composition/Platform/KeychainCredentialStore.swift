import Foundation
import MailDomain
import Security

/// Keychain-backed credentials (the only place a password is stored). One account per
/// install for now (design D8); the payload is `ServerConfiguration`, matching the
/// entries written before this refactor.
public struct KeychainCredentialStore: CredentialStore {
    private let service: String
    private let key: String

    public init(service: String = "com.uumail.account", key: String = "default") {
        self.service = service
        self.key = key
    }

    public func save(_ configuration: ServerConfiguration) throws {
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
            let updateStatus = SecItemUpdate(
                base as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            guard updateStatus == errSecSuccess else { throw KeychainCredentialError.status(updateStatus) }
            return
        }
        guard status == errSecSuccess else { throw KeychainCredentialError.status(status) }
    }

    public func load() throws -> ServerConfiguration? {
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
                  let configuration = try? JSONDecoder().decode(ServerConfiguration.self, from: data)
            else {
                throw KeychainCredentialError.malformedData
            }
            return configuration
        default:
            throw KeychainCredentialError.status(status)
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
            throw KeychainCredentialError.status(status)
        }
    }
}

enum KeychainCredentialError: Error, Equatable {
    case status(OSStatus)
    case malformedData
}
