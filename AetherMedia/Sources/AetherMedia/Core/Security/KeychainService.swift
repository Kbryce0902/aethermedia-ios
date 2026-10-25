import Foundation
#if canImport(Security)
import Security
#endif

/// Thread-safe, secure storage wrapper for credentials using iOS Keychain Services.
/// Features an in-memory session mirror for zero-latency lookups and resilience against
/// device-locked states (errSecInteractionNotAllowed).
public final class KeychainService: @unchecked Sendable {
    public static let shared = KeychainService()
    
    private let serviceName = "com.antigravity.aethermedia.credentials"
    private let lock = NSLock()
    private var inMemoryVault: [String: String] = [:]
    private let isTestingEnvironment: Bool
    
    public init(isTesting: Bool = false) {
        self.isTestingEnvironment = isTesting
    }
    
    // MARK: - Key Identifiers
    public enum Key: String {
        case rdAccessToken = "rd_access_token"
        case rdRefreshToken = "rd_refresh_token"
        case rdClientId = "rd_client_id"
        case rdClientSecret = "rd_client_secret"
        case redLightConfiguration = "red_light_configuration"
    }
    
    // MARK: - Read / Write / Delete
    
    @discardableResult
    public func save(key: Key, value: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        
        #if os(iOS) || os(macOS)
        if !isTestingEnvironment {
            guard let data = value.data(using: .utf8) else { return false }
            
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: serviceName,
                kSecAttrAccount as String: key.rawValue
            ]
            let attributes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
            
            // Try updating first
            let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if updateStatus == errSecSuccess {
                inMemoryVault[key.rawValue] = value
                return true
            }
            guard updateStatus == errSecItemNotFound else { return false }
            
            // Otherwise add new item
            var addQuery = query
            addQuery.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus == errSecSuccess { inMemoryVault[key.rawValue] = value }
            return addStatus == errSecSuccess
        }
        #endif
        
        inMemoryVault[key.rawValue] = value
        return true
    }
    
    public func get(key: Key) -> String? {
        lock.lock()
        defer { lock.unlock() }
        
        #if os(iOS) || os(macOS)
        if !isTestingEnvironment {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: serviceName,
                kSecAttrAccount as String: key.rawValue,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            if status == errSecSuccess, let data = item as? Data, let string = String(data: data, encoding: .utf8) {
                inMemoryVault[key.rawValue] = string
                return string
            }
            // Only a temporarily locked Keychain may use the last successfully stored value.
            if status == errSecInteractionNotAllowed { return inMemoryVault[key.rawValue] }
            inMemoryVault.removeValue(forKey: key.rawValue)
            return nil
        }
        #endif
        
        return inMemoryVault[key.rawValue]
    }
    
    public func delete(key: Key) {
        lock.lock()
        defer { lock.unlock() }
        
        #if os(iOS) || os(macOS)
        if !isTestingEnvironment {
            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: serviceName,
                kSecAttrAccount as String: key.rawValue
            ]
            SecItemDelete(deleteQuery as CFDictionary)
        }
        #endif
        
        inMemoryVault.removeValue(forKey: key.rawValue)
    }
    
    public func clearAll() {
        for key in [Key.rdAccessToken, .rdRefreshToken, .rdClientId, .rdClientSecret] {
            delete(key: key)
        }
    }
}
