# Security Fixes Deployment Checklist

## Pre-Deployment Testing

### 1. Local Testing (Required before committing)

#### URL Injection Fixes
- [ ] **DatabaseScannerViewModel Tests**
  ```swift
  // Test with special characters in NFC IDs
  let testIds = [
      "normal-id-123",
      "id?with=query&chars",
      "id with spaces",
      "id%20encoded",
      "id&filter=malicious",
      "id=eq.bypass"
  ]
  // Verify each produces valid, percent-encoded URLs
  ```

- [ ] **TicketService Tests**
  ```swift
  // Test search queries with injection attempts
  let maliciousQueries = [
      "test&status=eq.linked",           // Try to modify status filter
      "test)&event_id=eq.other-event",   // Try to change event
      "test';DROP TABLE tickets;--",     // SQL injection attempt
      "test%26filter%3Dmalicious",       // Pre-encoded attack
      "name@email.com?extra=param"       // Email with special chars
  ]
  // Verify all are properly escaped
  ```

- [ ] **Manual URL Inspection**
  - Set breakpoint in `makeRequest` method
  - Inspect actual URL strings being sent
  - Verify all query parameters are percent-encoded
  - Check for double-encoding issues

#### Keychain Token Management Tests
- [ ] **Sign In Flow**
  ```bash
  # Check Keychain entries after sign in
  # Expected: accessToken, refreshToken, userEmail in Keychain
  # Expected: NO tokens in UserDefaults
  ```

- [ ] **Token Refresh Flow**
  ```swift
  // Force token expiration
  // Trigger refresh
  // Verify:
  // 1. Old tokens removed from Keychain
  // 2. New tokens stored in Keychain
  // 3. No tokens in UserDefaults
  ```

- [ ] **Sign Out Flow**
  ```bash
  # After sign out, verify:
  # 1. All Keychain entries cleared
  # 2. All UserDefaults entries cleared
  # 3. In-memory state cleared
  # 4. No error messages to user
  ```

- [ ] **Error Handling**
  ```swift
  // Simulate Keychain failures:
  // 1. Keychain locked (device locked)
  // 2. Keychain access denied
  // 3. Keychain corruption
  // Verify app doesn't crash, shows appropriate error
  ```

#### Preview Layer Tests
- [ ] **Scanner Start Timing**
  ```swift
  // Test 1: Start scanner before view appears
  // Test 2: Start scanner after view appears
  // Test 3: Start scanner, stop, restart
  // Test 4: Rotate device while scanning
  // Verify preview layer visible in all cases
  ```

### 2. Unit Tests (Create if not exist)

```swift
// DatabaseScannerViewModelTests.swift
func testURLEncodingInWristbandQuery() {
    let specialCharId = "id?with=special&chars"
    // Mock supabaseService
    // Capture actual endpoint string
    // Assert contains percent-encoded values
}

// SupabaseServiceTests.swift
func testSignOutClearsKeychain() {
    // Setup: Store tokens in Keychain
    service.signOut()
    // Assert: Keychain empty
    // Assert: No exceptions thrown
}

func testRefreshTokenUsesKeychain() {
    // Setup: Store refresh token in Keychain only
    // Call refreshToken()
    // Assert: Retrieved from Keychain, not UserDefaults
}

// TicketServiceTests.swift
func testSearchWithInjectionAttempts() {
    let attacks = ["test&status=eq.linked", "test)&limit=999"]
    for attack in attacks {
        let tickets = try await service.searchAvailableTickets(
            eventId: "test-event",
            query: attack,
            method: .search
        )
        // Assert: No unexpected results
        // Assert: URL properly encoded
    }
}
```

### 3. Integration Tests

- [ ] **End-to-End Auth Flow**
  ```
  1. Fresh install
  2. Sign in
  3. Verify tokens in Keychain
  4. Force app restart
  5. Verify auto-login works
  6. Trigger token refresh
  7. Verify new tokens in Keychain
  8. Sign out
  9. Verify Keychain cleared
  ```

- [ ] **Scanner Integration**
  ```
  1. Open ticket scanner
  2. Grant camera permission
  3. Verify preview visible immediately
  4. Background app
  5. Foreground app
  6. Verify preview still visible
  ```

- [ ] **Search Integration**
  ```
  1. Search tickets with special characters in:
     - Name: "O'Brien & Associates"
     - Email: "user+tag@example.com"
     - Phone: "+1 (555) 123-4567"
  2. Verify results returned correctly
  3. Check logs for properly encoded URLs
  ```

## CI/CD Pipeline Changes

### 4. Update CI Configuration

```yaml
# .github/workflows/security-tests.yml (create if needed)
name: Security Tests

on: [pull_request]

jobs:
  security-scan:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3

      - name: Run URL Encoding Tests
        run: |
          xcodebuild test \
            -scheme NFCDemo \
            -testPlan SecurityTests \
            -destination 'platform=iOS Simulator,name=iPhone 15'

      - name: Check for hardcoded secrets
        run: |
          # Ensure no UserDefaults token storage in new code
          if git diff origin/main... | grep -i "UserDefaults.*token"; then
            echo "ERROR: Found UserDefaults token storage"
            exit 1
          fi

      - name: Validate Info.plist
        run: |
          # Check background location description is present
          grep -q "continuous background location monitoring" \
            "NFC DEMO/NFCDemo/NFCDemo/Info.plist"
```

### 5. Linter Rules

```yaml
# .swiftlint.yml (add rules)
custom_rules:
  no_string_interpolation_in_urls:
    name: "No String Interpolation in URLs"
    regex: 'endpoint:\s*"[^"]*\\\([^)]+\)[^"]*"'
    message: "Use URLComponents instead of string interpolation for URLs"
    severity: error

  no_userdefaults_tokens:
    name: "No Token Storage in UserDefaults"
    regex: 'UserDefaults.*set.*token'
    message: "Store tokens in Keychain using SecureTokenStorage"
    severity: error
```

## Deployment Steps

### 6. Code Review Checklist

- [ ] All tests passing (unit + integration)
- [ ] No hardcoded credentials
- [ ] No tokens in UserDefaults (except migration/cleanup code)
- [ ] All user input percent-encoded before URL construction
- [ ] Error handling for Keychain operations
- [ ] Logging doesn't expose sensitive data

### 7. Staged Rollout Plan

#### Stage 1: Internal Testing (Day 1-2)
- [ ] Deploy to TestFlight internal group
- [ ] 10 internal testers
- [ ] Test all authentication flows
- [ ] Test with various special characters in data
- [ ] Monitor crash logs for Keychain errors

#### Stage 2: Beta Testing (Day 3-5)
- [ ] Deploy to TestFlight external beta (100 users)
- [ ] Monitor key metrics:
  - Auth success rate
  - Token refresh failures
  - Scanner initialization issues
  - Search result accuracy
- [ ] Check for Keychain access errors on different iOS versions

#### Stage 3: Gradual Production Rollout (Day 6-10)
- [ ] 10% rollout (Day 6)
- [ ] 25% rollout (Day 7)
- [ ] 50% rollout (Day 8)
- [ ] 100% rollout (Day 10)
- [ ] Monitor at each stage for 24 hours before proceeding

### 8. Monitoring & Alerts

```swift
// Add monitoring for critical paths

// In SupabaseService.swift
func signOut() {
    do {
        try SecureTokenStorage.clearAll()
        Analytics.track("keychain_clear_success")
    } catch {
        Analytics.track("keychain_clear_failure", properties: [
            "error": error.localizedDescription
        ])
        // Alert DevOps if > 5% failure rate
    }
}

// In DatabaseScannerViewModel.swift
private func processNFC(_ nfcId: String) async {
    let startTime = Date()
    defer {
        Analytics.track("nfc_scan_duration", properties: [
            "duration": Date().timeIntervalSince(startTime)
        ])
    }
    // ... existing code
}
```

### 9. Post-Deployment Validation

#### Within 1 Hour
- [ ] Check crash rate (should be < 0.1%)
- [ ] Verify auth success rate (should be > 99%)
- [ ] Monitor Keychain error rate (should be < 1%)
- [ ] Check API error rates for malformed URLs (should be 0%)

#### Within 24 Hours
- [ ] Review customer support tickets
- [ ] Check for repeated sign-in issues
- [ ] Verify no session hijacking reports
- [ ] Confirm scanner preview working on all devices

#### Within 1 Week
- [ ] Full security audit of logs
- [ ] Verify no sensitive data leakage
- [ ] Check for unusual authentication patterns
- [ ] Review App Store reviews for issues

### 10. Rollback Plan

If critical issues found:

```bash
# Emergency rollback procedure
git revert HEAD~5..HEAD  # Revert all 5 patches
git push origin main --force-with-lease

# Or revert to specific commit
git reset --hard <previous-stable-commit>
git push origin main --force-with-lease
```

**Rollback Triggers:**
- Auth failure rate > 5%
- Crash rate > 1%
- Keychain error rate > 10%
- Critical security vulnerability discovered
- App Store rejection

### 11. Communication Plan

- [ ] **Pre-Deployment**
  - Email QA team with test plan
  - Notify customer support of changes
  - Prepare incident response team

- [ ] **During Rollout**
  - Post status updates in #deployments
  - Monitor #customer-support for issues
  - Real-time metrics dashboard

- [ ] **Post-Deployment**
  - Send summary email with metrics
  - Update security documentation
  - Schedule retrospective meeting

## Rollout Completion Checklist

- [ ] All stages deployed successfully
- [ ] No critical bugs reported
- [ ] Metrics within acceptable ranges
- [ ] Documentation updated
- [ ] Security team signoff
- [ ] Archive deployment logs
- [ ] Update runbooks with lessons learned
