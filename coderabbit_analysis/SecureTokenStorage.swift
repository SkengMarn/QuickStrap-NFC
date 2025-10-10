import Foundation
import Security
import CryptoKit

/// Enterprise-grade secure token storage using iOS Keychain
/// Replaces dangerous UserDefaults storage with encrypted, isolated storage
class SecureTokenStorage {
    private static let service = "com.jawal.nfcdemo.tokens"
    
    enum KeychainError: Error, LocalizedError {
        case storeFailed(OSStatus)
        case retrievalFailed(OSStatus)
        case deletionFailed(OSStatus)
        case invalidData
        case duplicateItem
        
        var errorDescription: String? {
            switch self {
            case .storeFailed(let status):
                return "Failed to store token in Keychain (status: \(status))"
            case .retrievalFailed(let status):
                return "Failed to retrieve token from Keychain (status: \(status))"
            case .deletionFailed(let status):
                return "Failed to delete token from Keychain (status: \(status))"
            case .invalidData:
                return "Invalid token data format"
            case .duplicateItem:
                return "Token already exists in Keychain"
            }
        }
    }
    
    /// Securely store a token in the iOS Keychain
    /// - Parameters:
    ///   - token: The token string to store
    ///   - account: The account identifier (e.g., "access_token", "refresh_token")
    /// - Throws: KeychainError if storage fails
    static func store(token: String, for account: String) throws {
        // Clean the token - remove whitespace and newlines
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !cleanToken.isEmpty else {
            throw KeychainError.invalidData
        }
        
        let tokenData = Data(cleanToken.utf8)
        
        // Delete existing item first to avoid duplicates
        try? delete(account: account)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: tokenData,
            // Critical security settings
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly, // Never backed up
            kSecAttrSynchronizable as String: false // Never sync to iCloud
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            if status == errSecDuplicateItem {
                throw KeychainError.duplicateItem
            }
            throw KeychainError.storeFailed(status)
        }
        
        Logger.log("Token stored securely for account: \(account)", level: .info, category: "Security")
    }
    
    /// Retrieve a token from the iOS Keychain
    /// - Parameter account: The account identifier
    /// - Returns: The decrypted token string
    /// - Throws: KeychainError if retrieval fails
    static func retrieve(account: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            throw KeychainError.retrievalFailed(status)
        }
        
        guard let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        
        return token
    }
    
    /// Delete a token from the iOS Keychain
    /// - Parameter account: The account identifier
    /// - Throws: KeychainError if deletion fails
    static func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deletionFailed(status)
        }
        
        Logger.log("Token deleted for account: \(account)", level: .info, category: "Security")
    }
    
    /// Check if a token exists for the given account
    /// - Parameter account: The account identifier
    /// - Returns: True if token exists, false otherwise
    static func exists(account: String) -> Bool {
        do {
            _ = try retrieve(account: account)
            return true
        } catch {
            return false
        }
    }
    
    /// Clear all tokens for this app
    static func clearAll() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deletionFailed(status)
        }
        
        Logger.log("All tokens cleared from Keychain", level: .info, category: "Security")
    }
}

// MARK: - Token Account Constants
extension SecureTokenStorage {
    enum Account {
        static let accessToken = "supabase_access_token"
        static let refreshToken = "supabase_refresh_token"
        static let userEmail = "user_email"
        static let deviceID = "device_id"
        static let supabaseURL = "supabase_url"
        static let supabaseKey = "supabase_anon_key"
    }
}

// MARK: - Biometric Authentication Support
extension SecureTokenStorage {
    /// Store token with biometric authentication requirement
    /// - Parameters:
    ///   - token: The token to store
    ///   - account: The account identifier
    ///   - requireBiometrics: Whether to require Face ID/Touch ID for access
    static func storeBiometric(token: String, for account: String, requireBiometrics: Bool = true) throws {
        guard !token.isEmpty else {
            throw KeychainError.invalidData
        }
        
        let tokenData = Data(token.utf8)
        
        // Delete existing item first
        try? delete(account: account)
        
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: tokenData,
            kSecAttrSynchronizable as String: false
        ]
        
        if requireBiometrics {
            // Require biometric authentication for access
            let access = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                .biometryAny,
                nil
            )
            query[kSecAttrAccessControl as String] = access
        } else {
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw KeychainError.storeFailed(status)
        }
        
        Logger.log("Biometric token stored for account: \(account)", level: .info, category: "Security")
    }
}
