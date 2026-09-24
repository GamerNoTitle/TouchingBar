import Foundation
import Security

public enum WebDAVKeychainError: Error, LocalizedError {
    case status(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .status(let status):
            return "无法访问 macOS 钥匙串（\(status)）。"
        }
    }
}

public struct WebDAVKeychain: Sendable {
    // Keep the legacy service name so existing installs retain their saved
    // WebDAV password after the bundle identifier migration.
    public static let service = "app.touchingbar.webdav"
    public static let account = "default"

    private let service: String
    private let account: String

    public init(service: String = Self.service, account: String = Self.account) {
        self.service = service
        self.account = account
    }

    public func loadPassword() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public func savePassword(_ password: String) throws {
        guard !password.isEmpty else {
            try deletePassword()
            return
        }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let attributes: [CFString: Any] = [
            kSecValueData: Data(password.utf8)
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw WebDAVKeychainError.status(updateStatus)
        }

        var item = query
        item[kSecValueData] = Data(password.utf8)
        item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw WebDAVKeychainError.status(addStatus)
        }
    }

    public func deletePassword() throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw WebDAVKeychainError.status(status)
        }
    }
}
