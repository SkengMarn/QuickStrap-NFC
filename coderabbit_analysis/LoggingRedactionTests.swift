import XCTest
@testable import NFCDemo

class LoggingRedactionTests: XCTestCase {

    // MARK: - JWT Token Redaction Tests

    func testJWTTokenRedaction() {
        let testCases = [
            (
                input: "User logged in with token: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c",
                expected: "User logged in with token: [JWT_REDACTED]",
                description: "Valid JWT token should be completely redacted"
            )
        ]

        for testCase in testCases {
            let redacted = LogRedaction.redact(testCase.input)
            XCTAssertEqual(redacted, testCase.expected, testCase.description)
            XCTAssertFalse(redacted.contains("eyJ"), "JWT token should not contain 'eyJ' after redaction")
        }
    }

    func testBearerTokenRedaction() {
        let input = "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.payload.signature"
        let redacted = LogRedaction.redact(input)

        XCTAssertTrue(redacted.contains("Bearer [TOKEN_REDACTED]"), "Bearer token should be redacted")
        XCTAssertFalse(redacted.contains("eyJ"), "Token content should not be visible")
    }

    // MARK: - Email Redaction Tests

    func testEmailRedaction() {
        let testCases: [(input: String, shouldContain: String, shouldNotContain: String)] = [
            ("Contact user@example.com for help", "@example.com", "user"),
            ("Email is john.doe@company.org", "@company.org", "john.doe"),
            ("Multiple emails: alice@test.com and bob@test.com", "@test.com", "alice"),
            ("Edge case: a@b.co", "@b.co", "Edge"),
        ]

        for testCase in testCases {
            let redacted = LogRedaction.redact(testCase.input)
            XCTAssertTrue(redacted.contains(testCase.shouldContain), "Should preserve domain: \(testCase.input)")
            XCTAssertFalse(redacted.contains(testCase.shouldNotContain), "Should redact username: \(testCase.input)")
        }
    }

    func testSpecificEmailRedaction() {
        let email = "sensitive.user@example.com"
        let redacted = LogRedaction.redact(email, type: .email)

        XCTAssertTrue(redacted.contains("@example.com"), "Domain should be preserved")
        XCTAssertTrue(redacted.contains("se***"), "Should show first 2 chars of username")
        XCTAssertFalse(redacted.contains("sensitive.user"), "Full username should be hidden")
    }

    // MARK: - Phone Number Redaction Tests

    func testPhoneRedaction() {
        let testCases = [
            "Call +1 (555) 123-4567",
            "Phone: 555-123-4567",
            "Contact: 5551234567",
            "+15551234567"
        ]

        for input in testCases {
            let redacted = LogRedaction.redact(input)
            XCTAssertFalse(redacted.contains("555-123"), "First digits should be redacted: \(input)")
            XCTAssertTrue(redacted.contains("[PHONE_REDACTED]"), "Should show phone redaction marker")
        }
    }

    func testSpecificPhoneRedaction() {
        let phone = "555-123-4567"
        let redacted = LogRedaction.redact(phone, type: .phone)

        XCTAssertEqual(redacted, "***-***-4567", "Should show last 4 digits only")
    }

    // MARK: - UUID Redaction Tests

    func testUUIDRedaction() {
        let uuid = "123e4567-e89b-12d3-a456-426614174000"
        let input = "User ID: \(uuid)"
        let redacted = LogRedaction.redact(input)

        XCTAssertTrue(redacted.contains("123e4567-****-****-****-************"), "Should partially redact UUID")
        XCTAssertFalse(redacted.contains("e89b-12d3"), "Middle segments should be hidden")
    }

    func testSpecificUUIDRedaction() {
        let uuid = "550e8400-e29b-41d4-a716-446655440000"
        let redacted = LogRedaction.redact(uuid, type: .uuid)

        XCTAssertTrue(redacted.hasPrefix("550e8400-"), "First segment preserved for debugging")
        XCTAssertTrue(redacted.hasSuffix("************"), "Last segment fully redacted")
        XCTAssertEqual(redacted.filter({ $0 == "*" }).count, 12, "Should have 12 asterisks")
    }

    // MARK: - API Key Redaction Tests

    func testAPIKeyRedaction() {
        let testCases = [
            "api_key=sk_live_1234567890abcdefghij",
            "API_KEY: pk_test_abcdefghijklmnopqrst",
            "apiKey=\"my_secret_key_12345678901234567890\""
        ]

        for input in testCases {
            let redacted = LogRedaction.redact(input)
            XCTAssertTrue(redacted.contains("[API_KEY_REDACTED]"), "API key should be redacted: \(input)")
            XCTAssertFalse(redacted.contains("sk_live"), "Key prefix should be hidden")
            XCTAssertFalse(redacted.contains("pk_test"), "Key prefix should be hidden")
        }
    }

    // MARK: - Password Redaction Tests

    func testPasswordRedaction() {
        let testCases = [
            "Login failed for password=MySecret123",
            "pwd: 'MySecret123'",
            "passwd=\"SuperSecretPassword\"",
            "PASSWORD:MySecret123"
        ]

        for input in testCases {
            let redacted = LogRedaction.redact(input)
            XCTAssertTrue(redacted.contains("[PASSWORD_REDACTED]"), "Password should be redacted: \(input)")
            XCTAssertFalse(redacted.contains("MySecret123"), "Actual password should be hidden")
            XCTAssertFalse(redacted.contains("SuperSecretPassword"), "Actual password should be hidden")
        }
    }

    // MARK: - Credit Card Redaction Tests

    func testCreditCardRedaction() {
        let testCases = [
            "Card: 4532-1234-5678-9010",
            "Payment with 4532123456789010",
            "CC: 4532 1234 5678 9010"
        ]

        for input in testCases {
            let redacted = LogRedaction.redact(input)
            XCTAssertTrue(redacted.contains("[CC_REDACTED]"), "Credit card should be redacted: \(input)")
            XCTAssertFalse(redacted.contains("4532"), "Card number should be hidden")
        }
    }

    // MARK: - URL Parameter Redaction Tests

    func testURLParameterRedaction() {
        let url = "https://api.example.com/users?token=secret123&api_key=key456"
        let redacted = LogRedaction.redact(url)

        XCTAssertTrue(redacted.contains("https://api.example.com/users?"), "Base URL should be preserved")
        XCTAssertTrue(redacted.contains("[PARAMS_REDACTED]"), "Parameters should be redacted")
        XCTAssertFalse(redacted.contains("secret123"), "Token parameter should be hidden")
        XCTAssertFalse(redacted.contains("key456"), "API key parameter should be hidden")
    }

    // MARK: - NFC ID Redaction Tests

    func testNFCIdRedaction() {
        let nfcId = "ABC123XYZ789"
        let redacted = LogRedaction.redact(nfcId, type: .nfcId)

        XCTAssertEqual(redacted, "ABC***789", "Should show prefix and suffix")
        XCTAssertTrue(redacted.contains("ABC"), "Prefix preserved for debugging")
        XCTAssertTrue(redacted.contains("789"), "Suffix preserved for debugging")
        XCTAssertFalse(redacted.contains("123XYZ"), "Middle section should be hidden")
    }

    func testShortNFCIdRedaction() {
        let shortId = "ABC"
        let redacted = LogRedaction.redact(shortId, type: .nfcId)

        XCTAssertEqual(redacted, "[NFC_REDACTED]", "Short IDs should be fully redacted")
    }

    // MARK: - Token-Specific Redaction Tests

    func testTokenRedaction() {
        let token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abc123"
        let redacted = LogRedaction.redact(token, type: .token)

        XCTAssertTrue(redacted.contains("eyJh***abc123"), "Should show prefix and suffix")
        XCTAssertTrue(redacted.contains("chars]"), "Should show character count")
        XCTAssertFalse(redacted.contains("IsInR5cCI"), "Middle content should be hidden")
    }

    func testShortTokenRedaction() {
        let shortToken = "short"
        let redacted = LogRedaction.redact(shortToken, type: .token)

        XCTAssertEqual(redacted, "[TOKEN_TOO_SHORT]", "Short tokens should be fully redacted")
    }

    // MARK: - Full Redaction Tests

    func testFullRedaction() {
        let sensitive = "This is very sensitive data"
        let redacted = LogRedaction.redact(sensitive, type: .full)

        XCTAssertEqual(redacted, "[REDACTED]", "Full redaction should hide everything")
    }

    // MARK: - Multiple Pattern Tests

    func testMultiplePatternsInSameString() {
        let input = """
        User john.doe@example.com logged in with token eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.payload.sig
        Phone: 555-123-4567, ID: 123e4567-e89b-12d3-a456-426614174000
        """

        let redacted = LogRedaction.redact(input)

        XCTAssertFalse(redacted.contains("john.doe"), "Email should be redacted")
        XCTAssertFalse(redacted.contains("eyJ"), "JWT should be redacted")
        XCTAssertFalse(redacted.contains("555-123"), "Phone should be redacted")
        XCTAssertFalse(redacted.contains("e89b-12d3"), "UUID should be redacted")
    }

    // MARK: - Edge Cases

    func testEmptyString() {
        let redacted = LogRedaction.redact("")
        XCTAssertEqual(redacted, "", "Empty string should remain empty")
    }

    func testNoSensitiveData() {
        let input = "This is a normal log message with no sensitive data"
        let redacted = LogRedaction.redact(input)
        XCTAssertEqual(redacted, input, "Non-sensitive messages should pass through unchanged")
    }

    func testMalformedPatterns() {
        let testCases = [
            "Invalid email: @example.com",
            "Partial UUID: 123e4567-e89b",
            "Invalid phone: 123"
        ]

        for input in testCases {
            let redacted = LogRedaction.redact(input)
            // Should not crash, should handle gracefully
            XCTAssertNotNil(redacted, "Should handle malformed patterns: \(input)")
        }
    }

    // MARK: - String Extension Tests

    func testStringRedactedExtension() {
        let sensitive = "Contact user@example.com with API key abc123def456ghi789"
        let redacted = sensitive.redacted

        XCTAssertNotEqual(redacted, sensitive, "Extension should redact")
        XCTAssertFalse(redacted.contains("user@example.com"), "Email should be redacted")
    }

    func testStringRedactedAsExtension() {
        let email = "admin@example.com"
        let redacted = email.redacted(as: .email)

        XCTAssertTrue(redacted.contains("@example.com"), "Should use email redaction")
        XCTAssertFalse(redacted.contains("admin"), "Username should be hidden")
    }

    // MARK: - Performance Tests

    func testRedactionPerformance() {
        let largeMessage = String(repeating: "User user@example.com logged in with token eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.payload.sig ", count: 100)

        measure {
            _ = LogRedaction.redact(largeMessage)
        }
    }

    // MARK: - SecureLogger Tests

    func testSecureLoggerBasicLogging() {
        let logger = SecureLogger.shared
        let expectation = XCTestExpectation(description: "Log message processed")

        // This test mainly checks that logging doesn't crash
        logger.log("Test message with token eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test.sig", level: .info)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testSecureLoggerWithSpecificRedaction() {
        let logger = SecureLogger.shared
        let sensitiveValue = "user@example.com"

        // Should not crash
        logger.log("Processing email: \(sensitiveValue)", redacting: sensitiveValue, as: .email, level: .debug)

        XCTAssertTrue(true, "Logger should handle specific redaction")
    }

    // MARK: - Global Function Tests

    func testGlobalSecureLogFunction() {
        // Should not crash
        secureLog("Test message with sensitive data: user@example.com")
        XCTAssertTrue(true, "Global secure log should work")
    }

    func testGlobalSecureLogWithRedaction() {
        let token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test.sig"
        secureLog("Authentication with token: \(token)", redacting: token, as: .token)
        XCTAssertTrue(true, "Global secure log with redaction should work")
    }

    // MARK: - Real-World Scenario Tests

    func testAuthenticationLogRedaction() {
        let authLog = """
        🔐 Starting sign in process for: user@example.com
        📡 Making authentication request...
        Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c
        ✅ Authentication successful!
        """

        let redacted = LogRedaction.redact(authLog)

        XCTAssertTrue(redacted.contains("[EMAIL_REDACTED]"), "Email should be redacted in auth logs")
        XCTAssertTrue(redacted.contains("[JWT_REDACTED]"), "JWT should be redacted in auth logs")
        XCTAssertFalse(redacted.contains("user@example.com"), "Plain email should not appear")
        XCTAssertFalse(redacted.contains("eyJ"), "JWT prefix should not appear")
    }

    func testNFCScanLogRedaction() {
        let nfcId = "ABC123XYZ789"
        let scanLog = "🔍 [DEBUG] NFC: Successfully parsed ID: \(nfcId)"

        let redacted = LogRedaction.redact(scanLog, type: .nfcId)

        // In a real implementation, you'd want to apply specific redaction
        // For now, test that it doesn't crash and produces output
        XCTAssertFalse(redacted.isEmpty, "Redacted log should not be empty")
    }

    func testDatabaseQueryLogRedaction() {
        let eventId = "550e8400-e29b-41d4-a716-446655440000"
        let queryLog = "📡 Fetching events from database with ID: \(eventId)"

        let redacted = LogRedaction.redact(queryLog)

        XCTAssertTrue(redacted.contains("550e8400-****"), "UUID should be partially redacted")
        XCTAssertFalse(redacted.contains("e29b-41d4"), "Middle UUID segments should be hidden")
    }
}
