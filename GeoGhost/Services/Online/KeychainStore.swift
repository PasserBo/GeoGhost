import Foundation
import Security

enum KeychainError: Error, Equatable {
    case status(OSStatus)
}

/// Generic-password items for one service. Items stay on this device (never in iCloud Keychain),
/// are readable after the first unlock, and survive deleting and reinstalling the app.
struct KeychainStore: Sendable {
    let service: String

    func data(for account: String) throws -> Data? {
        var query = baseQuery(account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw KeychainError.status(status)
        }
    }

    func set(_ data: Data, for account: String) throws {
        let update = [kSecValueData: data, kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly] as [CFString: Any]
        let status = SecItemUpdate(baseQuery(account) as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery(account)
            add.merge(update) { $1 }
            let added = SecItemAdd(add as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError.status(added) }
        } else if status != errSecSuccess {
            throw KeychainError.status(status)
        }
    }

    func remove(_ account: String) throws {
        let status = SecItemDelete(baseQuery(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.status(status) }
    }

    private func baseQuery(_ account: String) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account,
         kSecAttrSynchronizable: false]
    }
}
