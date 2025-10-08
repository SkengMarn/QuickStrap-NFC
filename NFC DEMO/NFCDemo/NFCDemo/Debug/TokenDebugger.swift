import Foundation

/// Debug utility to help diagnose JWT token issues
struct TokenDebugger {
    
    /// Debug JWT token format and content
    static func debugToken(_ token: String, label: String = "Token") {
        print("🔍 \(label) Debug Analysis:")
        print("   Length: \(token.count) characters")
        print("   First 20 chars: \(String(token.prefix(20)))...")
        print("   Last 20 chars: ...\(String(token.suffix(20)))")
        
        // Check JWT format
        let parts = token.components(separatedBy: ".")
        print("   JWT Parts: \(parts.count) (should be 3)")
        
        if parts.count == 3 {
            print("   Header length: \(parts[0].count)")
            print("   Payload length: \(parts[1].count)")
            print("   Signature length: \(parts[2].count)")
            
            // Try to decode header
            if let headerData = decodeBase64URL(parts[0]),
               let headerString = String(data: headerData, encoding: .utf8) {
                print("   Header: \(headerString)")
            } else {
                print("   ❌ Header decode failed")
            }
            
            // Try to decode payload
            if let payloadData = decodeBase64URL(parts[1]),
               let payloadString = String(data: payloadData, encoding: .utf8) {
                print("   Payload: \(payloadString)")
                
                // Parse expiration
                if let jsonData = payloadString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                   let exp = json["exp"] as? TimeInterval {
                    let expirationDate = Date(timeIntervalSince1970: exp)
                    let timeUntilExpiry = expirationDate.timeIntervalSinceNow
                    print("   Expires: \(expirationDate)")
                    print("   Time until expiry: \(timeUntilExpiry) seconds")
                    print("   Is expired: \(timeUntilExpiry <= 0)")
                }
            } else {
                print("   ❌ Payload decode failed")
            }
        }
        
        // Check for common issues
        if token.contains(" ") {
            print("   ⚠️ Token contains spaces")
        }
        if token.contains("\n") {
            print("   ⚠️ Token contains newlines")
        }
        if !token.starts(with: "eyJ") {
            print("   ⚠️ Token doesn't start with 'eyJ' (typical JWT header)")
        }
        
        print("🔍 End \(label) Debug\n")
    }
    
    /// Decode base64URL (JWT format)
    private static func decodeBase64URL(_ base64url: String) -> Data? {
        var base64 = base64url
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        // Add padding if needed
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        
        return Data(base64Encoded: base64)
    }
    
    /// Compare two tokens
    static func compareTokens(token1: String, label1: String, token2: String, label2: String) {
        print("🔍 Comparing \(label1) vs \(label2):")
        print("   Same length: \(token1.count == token2.count)")
        print("   Are identical: \(token1 == token2)")
        
        if token1 != token2 {
            // Find first difference
            let chars1 = Array(token1)
            let chars2 = Array(token2)
            let minLength = min(chars1.count, chars2.count)
            
            for i in 0..<minLength {
                if chars1[i] != chars2[i] {
                    print("   First difference at position \(i): '\(chars1[i])' vs '\(chars2[i])'")
                    break
                }
            }
        }
        print("")
    }
    
    /// Test Keychain storage and retrieval
    static func testKeychainRoundTrip() {
        print("🔍 Testing Keychain Round Trip:")
        
        let testToken = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ0ZXN0IjoidmFsdWUifQ.test_signature"
        let testAccount = "debug_test_token"
        
        do {
            // Store
            try SecureTokenStorage.store(token: testToken, for: testAccount)
            print("   ✅ Store successful")
            
            // Retrieve
            let retrievedToken = try SecureTokenStorage.retrieve(account: testAccount)
            print("   ✅ Retrieve successful")
            
            // Compare
            if testToken == retrievedToken {
                print("   ✅ Tokens match perfectly")
            } else {
                print("   ❌ Tokens don't match!")
                compareTokens(token1: testToken, label1: "Original", 
                            token2: retrievedToken, label2: "Retrieved")
            }
            
            // Cleanup
            try SecureTokenStorage.delete(account: testAccount)
            print("   ✅ Cleanup successful")
            
        } catch {
            print("   ❌ Keychain test failed: \(error)")
        }
        
        print("")
    }
    
    /// Debug current authentication state
    static func debugAuthState() {
        print("🔍 Current Authentication State:")
        
        // Check stored tokens
        let accounts = [
            SecureTokenStorage.Account.accessToken,
            SecureTokenStorage.Account.refreshToken,
            SecureTokenStorage.Account.userEmail
        ]
        
        for account in accounts {
            if SecureTokenStorage.exists(account: account) {
                do {
                    let token = try SecureTokenStorage.retrieve(account: account)
                    print("   ✅ \(account): exists (\(token.count) chars)")
                    
                    if account == SecureTokenStorage.Account.accessToken {
                        debugToken(token, label: "Access Token")
                    }
                } catch {
                    print("   ❌ \(account): exists but can't retrieve - \(error)")
                }
            } else {
                print("   ❌ \(account): not found")
            }
        }
        
        print("")
    }
}

// MARK: - SupabaseService Debug Extension
extension SupabaseService {
    
    /// Debug current service state
    func debugServiceState() {
        print("🔍 SupabaseService Debug State:")
        print("   isAuthenticated: \(isAuthenticated)")
        print("   isLoading: \(isLoading)")
        print("   currentUser: \(currentUser?.email ?? "nil")")
        print("   currentEvent: \(currentEvent?.name ?? "nil")")
        print("   errorMessage: \(errorMessage ?? "nil")")
        
        if let accessToken = accessToken {
            print("   accessToken: exists (\(accessToken.count) chars)")
            TokenDebugger.debugToken(accessToken, label: "Current Access Token")
        } else {
            print("   accessToken: nil")
        }
        
        // Note: supabaseAnonKey is private, so we can't access it directly from here
        print("   supabaseAnonKey: [private - check service logs]")
        
        print("")
    }
    
    /// Force clear all authentication and start fresh
    func debugClearAndRestart() {
        print("🔍 Debug: Clearing all auth state...")
        
        Task { @MainActor in
            // Clear Keychain
            do {
                try SecureTokenStorage.clearAll()
                print("   ✅ Keychain cleared")
            } catch {
                print("   ❌ Keychain clear failed: \(error)")
            }
            
            // Reset service state
            accessToken = nil
            currentUser = nil
            currentEvent = nil
            isAuthenticated = false
            errorMessage = nil
            
            print("   ✅ Service state reset")
            print("   ℹ️ Please login again")
        }
    }
}
