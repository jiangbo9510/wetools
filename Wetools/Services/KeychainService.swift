import Foundation
import Security

enum KeychainServiceError: LocalizedError {
    case invalidSecret
    case unexpectedData
    case osStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidSecret:
            return "Invalid secret value."
        case .unexpectedData:
            return "Unexpected Keychain data."
        case .osStatus(let status):
            return "Keychain operation failed with status \(status)."
        }
    }
}

final class KeychainService {
    private let service: String

    // TODO: Replace com.yourname.Wetools with the real bundle identifier before release.
    init(service: String = Bundle.main.bundleIdentifier ?? "com.yourname.Wetools") {
        self.service = service
    }

    func saveSecret(_ secret: String, account: String) throws {
        guard let data = secret.data(using: .utf8) else {
            throw KeychainServiceError.invalidSecret
        }

        try deleteSecret(account: account, ignoreMissing: true)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainServiceError.osStatus(status)
        }
    }

    func readSecret(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainServiceError.osStatus(status)
        }

        guard let data = result as? Data else {
            throw KeychainServiceError.unexpectedData
        }

        return String(data: data, encoding: .utf8)
    }

    func updateSecret(_ secret: String, account: String) throws {
        guard let data = secret.data(using: .utf8) else {
            throw KeychainServiceError.invalidSecret
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            try saveSecret(secret, account: account)
            return
        }

        guard status == errSecSuccess else {
            throw KeychainServiceError.osStatus(status)
        }
    }

    func deleteSecret(account: String) throws {
        try deleteSecret(account: account, ignoreMissing: false)
    }

    private func deleteSecret(account: String, ignoreMissing: Bool) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)
        if ignoreMissing, status == errSecItemNotFound {
            return
        }

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainServiceError.osStatus(status)
        }
    }
}
