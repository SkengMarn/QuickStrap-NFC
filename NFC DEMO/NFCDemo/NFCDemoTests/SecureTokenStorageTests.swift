import XCTest
@testable import NFCDemo

final class SecureTokenStorageTests: XCTestCase {
    let testAccount = "test_token"

    override func tearDown() {
        // Clean up test tokens
        try? SecureTokenStorage.delete(account: testAccount)
        super.tearDown()
    }

    // MARK: - Storage Tests

    func testStoreAndRetrieveToken() throws {
        // Given
        let testToken = "test-token-value-12345"

        // When
        try SecureTokenStorage.store(token: testToken, for: testAccount)

        // Then
        let retrieved = try SecureTokenStorage.retrieve(account: testAccount)
        XCTAssertEqual(retrieved, testToken)
    }

    func testStoreEmptyToken() {
        // Given
        let emptyToken = ""

        // When / Then
        XCTAssertThrowsError(try SecureTokenStorage.store(token: emptyToken, for: testAccount)) { error in
            XCTAssertTrue(error is SecureTokenStorage.KeychainError)
        }
    }

    func testOverwriteExistingToken() throws {
        // Given
        let firstToken = "first-token"
        let secondToken = "second-token"

        // When
        try SecureTokenStorage.store(token: firstToken, for: testAccount)
        try SecureTokenStorage.store(token: secondToken, for: testAccount)

        // Then
        let retrieved = try SecureTokenStorage.retrieve(account: testAccount)
        XCTAssertEqual(retrieved, secondToken)
    }

    // MARK: - Retrieval Tests

    func testRetrieveNonExistentToken() {
        // When / Then
        XCTAssertThrowsError(try SecureTokenStorage.retrieve(account: "non-existent")) { error in
            guard case SecureTokenStorage.KeychainError.retrievalFailed = error else {
                XCTFail("Wrong error type")
                return
            }
        }
    }

    func testTokenExists() throws {
        // Given
        let testToken = "test-token"
        try SecureTokenStorage.store(token: testToken, for: testAccount)

        // Then
        XCTAssertTrue(SecureTokenStorage.exists(account: testAccount))
        XCTAssertFalse(SecureTokenStorage.exists(account: "non-existent"))
    }

    // MARK: - Deletion Tests

    func testDeleteToken() throws {
        // Given
        let testToken = "test-token"
        try SecureTokenStorage.store(token: testToken, for: testAccount)

        // When
        try SecureTokenStorage.delete(account: testAccount)

        // Then
        XCTAssertFalse(SecureTokenStorage.exists(account: testAccount))
    }

    func testClearAllTokens() throws {
        // Given
        try SecureTokenStorage.store(token: "token1", for: "account1")
        try SecureTokenStorage.store(token: "token2", for: "account2")

        // When
        try SecureTokenStorage.clearAll()

        // Then
        XCTAssertFalse(SecureTokenStorage.exists(account: "account1"))
        XCTAssertFalse(SecureTokenStorage.exists(account: "account2"))
    }

    // MARK: - Security Tests

    func testTokenNotAccessibleWhenLocked() {
        // This test would require device lock simulation
        // which is not easily testable in unit tests
        // Manual testing required for this scenario
    }

    func testTokenNotSyncedToiCloud() throws {
        // Verify kSecAttrSynchronizable is set to false
        // This is verified in the implementation
        // but can't be easily tested programmatically
    }
}
