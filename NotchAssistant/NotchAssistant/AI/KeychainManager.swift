import Foundation
import Security
import os.log

enum KeychainManager {
    private static let logger = Logger(subsystem: "com.notchassistant.app", category: "KeychainManager")
    private static let service = "com.notchassistant.app"
    
    enum KeychainKey: String {
        case anthropicAPIKey = "anthropic_api_key"
    }
    
    static func save(_ data: Data, for key: KeychainKey) -> Bool {
        delete(key)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecValueData as String: data
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecSuccess {
            logger.info("Saved key to keychain: \(key.rawValue)")
            return true
        } else {
            logger.error("Failed to save to keychain: \(status)")
            return false
        }
    }
    
    static func save(_ string: String, for key: KeychainKey) -> Bool {
        guard let data = string.data(using: .utf8) else { return false }
        return save(data, for: key)
    }
    
    static func load(_ key: KeychainKey) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess {
            return result as? Data
        } else {
            logger.debug("Key not found in keychain: \(key.rawValue)")
            return nil
        }
    }
    
    static func loadString(_ key: KeychainKey) -> String? {
        guard let data = load(key) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    @discardableResult
    static func delete(_ key: KeychainKey) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    static func hasKey(_ key: KeychainKey) -> Bool {
        load(key) != nil
    }
}
