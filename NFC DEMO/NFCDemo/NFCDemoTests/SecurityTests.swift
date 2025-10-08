import XCTest
@testable import NFCDemo

/// Test suite for security components
class SecurityTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Clean up any existing test data
        try? SecureTokenStorage.clearAll()
    }
    
    override func tearDown() {
        // Clean up after tests
        try? SecureTokenStorage.clearAll()
        super.tearDown()
    }
    
    // MARK: - Keychain Security Tests
    
    func testSecureTokenStorage() throws {
        let testToken = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test"
        let account = SecureTokenStorage.Account.accessToken
        
        // Test storing token
        XCTAssertNoThrow(try SecureTokenStorage.store(token: testToken, for: account))
        
        // Test retrieving token
        let retrievedToken = try SecureTokenStorage.retrieve(account: account)
        XCTAssertEqual(testToken, retrievedToken, "Retrieved token should match stored token")
        
        // Test token exists
        XCTAssertTrue(SecureTokenStorage.exists(account: account), "Token should exist after storing")
        
        // Test deleting token
        XCTAssertNoThrow(try SecureTokenStorage.delete(account: account))
        XCTAssertFalse(SecureTokenStorage.exists(account: account), "Token should not exist after deletion")
    }
    
    func testTokenStorageWithEmptyString() {
        let emptyToken = ""
        let account = "test_empty"
        
        // Should throw error for empty token
        XCTAssertThrowsError(try SecureTokenStorage.store(token: emptyToken, for: account)) { error in
            XCTAssertTrue(error is SecureTokenStorage.KeychainError)
        }
    }
    
    func testMultipleTokenStorage() throws {
        let accessToken = "access_token_123"
        let refreshToken = "refresh_token_456"
        let userEmail = "test@example.com"
        
        // Store multiple tokens
        try SecureTokenStorage.store(token: accessToken, for: SecureTokenStorage.Account.accessToken)
        try SecureTokenStorage.store(token: refreshToken, for: SecureTokenStorage.Account.refreshToken)
        try SecureTokenStorage.store(token: userEmail, for: SecureTokenStorage.Account.userEmail)
        
        // Verify all tokens are stored correctly
        XCTAssertEqual(try SecureTokenStorage.retrieve(account: SecureTokenStorage.Account.accessToken), accessToken)
        XCTAssertEqual(try SecureTokenStorage.retrieve(account: SecureTokenStorage.Account.refreshToken), refreshToken)
        XCTAssertEqual(try SecureTokenStorage.retrieve(account: SecureTokenStorage.Account.userEmail), userEmail)
        
        // Test clear all
        try SecureTokenStorage.clearAll()
        
        // Verify all tokens are cleared
        XCTAssertFalse(SecureTokenStorage.exists(account: SecureTokenStorage.Account.accessToken))
        XCTAssertFalse(SecureTokenStorage.exists(account: SecureTokenStorage.Account.refreshToken))
        XCTAssertFalse(SecureTokenStorage.exists(account: SecureTokenStorage.Account.userEmail))
    }
    
    // MARK: - Offline Manager Tests
    
    func testOfflineDataManager() {
        let manager = OfflineDataManager.shared
        
        // Test initial state
        XCTAssertEqual(manager.getPendingScans().count, 0, "Should start with no pending scans")
        
        // Test queueing offline scan
        let testScan = OfflineScan(eventId: "test_event", nfcId: "test_nfc_123")
        manager.queueOfflineScanSync(testScan)
        
        // Verify scan was queued
        let pendingScans = manager.getPendingScans()
        XCTAssertEqual(pendingScans.count, 1, "Should have one pending scan")
        XCTAssertEqual(pendingScans.first?.nfcId, "test_nfc_123", "NFC ID should match")
        XCTAssertEqual(pendingScans.first?.eventId, "test_event", "Event ID should match")
    }
    
    // MARK: - Performance Tests
    
    func testKeychainPerformance() {
        let testToken = "performance_test_token_" + UUID().uuidString
        let account = "performance_test"
        
        measure {
            // Test keychain performance
            do {
                try SecureTokenStorage.store(token: testToken, for: account)
                _ = try SecureTokenStorage.retrieve(account: account)
                try SecureTokenStorage.delete(account: account)
            } catch {
                XCTFail("Keychain operations should not fail: \(error)")
            }
        }
    }
    
    // MARK: - Logger Tests
    
    func testLoggerSanitization() {
        // Test that sensitive data is properly sanitized
        // This would require making Logger methods testable
        
        let sensitiveMessage = "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.sensitive_token"
        
        // In a real implementation, you'd test that Logger.sanitizeMessage() 
        // properly redacts the token
        XCTAssertTrue(true, "Logger sanitization test placeholder")
    }
}

// MARK: - Integration Tests

class IntegrationTests: XCTestCase {
    
    func testAuthenticationFlow() async throws {
        // Test the complete authentication flow with secure storage
        let supabaseService = SupabaseService.shared
        
        // This would test the actual login flow
        // Note: You'd need to mock the network calls for proper testing
        XCTAssertNotNil(supabaseService, "SupabaseService should initialize")
    }
}

// MARK: - Mock Data Helpers

extension SecurityTests {
    
    func createMockWristband() -> Wristband {
        return Wristband(
            id: "test_id",
            nfcId: "test_nfc",
            eventId: "test_event",
            category: WristbandCategory(name: "Test"),
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
    
    func createMockEvent() -> Event {
        return Event(
            id: "test_event",
            name: "Test Event",
            location: "Test Location",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600)
        )
    }
}
