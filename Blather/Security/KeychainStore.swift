import Foundation
import Security

protocol KeychainStoreProtocol: Sendable {
    func set(ref: String, secret: String) throws
    func get(ref: String) -> String?
    func remove(ref: String)
}

enum KeychainError: Error, LocalizedError {
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return message
            }
            return "Keychain error \(status)"
        }
    }
}

struct MacOSKeychainStore: KeychainStoreProtocol {
    static let servicePrefix = "com.blather"

    func set(ref: String, secret: String) throws {
        let service = "\(Self.servicePrefix).\(ref)"
        let secretData = Data(secret.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: ref,
        ]

        let existing = SecItemCopyMatching(query as CFDictionary, nil)
        if existing == errSecSuccess {
            let update: [String: Any] = [kSecValueData as String: secretData]
            let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
            return
        }

        var add = query
        add[kSecValueData as String] = secretData
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    func get(ref: String) -> String? {
        let service = "\(Self.servicePrefix).\(ref)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: ref,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func remove(ref: String) {
        let service = "\(Self.servicePrefix).\(ref)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: ref,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

final class MemoryKeychainStore: KeychainStoreProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var map: [String: String] = [:]

    func set(ref: String, secret: String) throws {
        lock.lock()
        defer { lock.unlock() }
        map[ref] = secret
    }

    func get(ref: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return map[ref]
    }

    func remove(ref: String) {
        lock.lock()
        defer { lock.unlock() }
        map[ref] = nil
    }
}

enum Keychain {
    static var store: any KeychainStoreProtocol = MacOSKeychainStore()
}
