# Logging Redaction Integration Guide

## Overview

The logging redaction system automatically removes sensitive information (PII, tokens, credentials) from all log messages to prevent data leakage in crash reports, analytics, and debug logs.

## Quick Start

### 1. Add Files to Xcode Project

```bash
# Add to your Xcode project:
- coderabbit_analysis/LoggingRedaction.swift
- coderabbit_analysis/LoggingRedactionTests.swift (to test target)
```

### 2. Replace Existing Print Statements

#### Before (Unsafe):
```swift
print("🔐 User logged in: \(email)")
print("📡 Auth token: \(accessToken)")
print("🔍 NFC ID scanned: \(nfcId)")
```

#### After (Safe):
```swift
secureLog("🔐 User logged in: \(email)", level: .info)
secureLog("📡 Auth token: \(accessToken)", level: .debug)
secureLog("🔍 NFC ID scanned: \(nfcId)", level: .info)
```

**Output:**
```
🔐 User logged in: [EMAIL_REDACTED]
📡 Auth token: [JWT_REDACTED]
🔍 NFC ID scanned: ABC***789  // Partial redaction for debugging
```

## Integration with Existing Code

### SupabaseService.swift

#### Before:
```swift
func signIn(email: String, password: String) async throws {
    print("🔐 Starting sign in process for: \(email)")

    do {
        print("📡 Making authentication request...")
        let response: AuthResponse = try await makeRequest(...)

        print("✅ Authentication successful!")
        accessToken = response.accessToken

        print("💾 Refresh token stored: \(response.refreshToken ?? "none")")
    }
}
```

#### After:
```swift
func signIn(email: String, password: String) async throws {
    secureLog("🔐 Starting sign in process for: \(email)", level: .info)

    do {
        secureLog("📡 Making authentication request...", level: .debug)
        let response: AuthResponse = try await makeRequest(...)

        secureLog("✅ Authentication successful!", level: .info)
        accessToken = response.accessToken

        // Use explicit redaction for tokens
        secureLog("💾 Access token stored",
                  redacting: response.accessToken,
                  as: .token,
                  level: .debug)
    }
}
```

### DatabaseScannerViewModel.swift

#### Before:
```swift
private func processNFC(_ nfcId: String) async {
    print("🔍 [DEBUG] Step 1: Starting NFC processing for ID: \(nfcId)")

    guard let supabaseService = supabaseService else {
        print("❌ [DEBUG] Step 1 FAILED: SupabaseService not available")
        return
    }

    guard let eventId = supabaseService.currentEvent?.id else {
        print("❌ [DEBUG] Step 1 FAILED: No event selected")
        return
    }

    print("✅ [DEBUG] Step 1 SUCCESS: Processing for event: \(eventId)")
}
```

#### After:
```swift
private func processNFC(_ nfcId: String) async {
    secureLog("🔍 [DEBUG] Step 1: Starting NFC processing for ID: \(nfcId.redacted(as: .nfcId))",
              level: .debug)

    guard let supabaseService = supabaseService else {
        secureLog("❌ [DEBUG] Step 1 FAILED: SupabaseService not available",
                  level: .error)
        return
    }

    guard let eventId = supabaseService.currentEvent?.id else {
        secureLog("❌ [DEBUG] Step 1 FAILED: No event selected",
                  level: .error)
        return
    }

    secureLog("✅ [DEBUG] Step 1 SUCCESS: Processing for event: \(eventId.redacted(as: .uuid))",
              level: .info)
}
```

### TicketService.swift

#### Before:
```swift
func searchAvailableTickets(eventId: String, query: String, method: TicketCaptureMethod) async throws -> [Ticket] {
    print("🔍 Searching tickets for event: \(eventId), query: \(query)")

    let tickets = try await supabaseService.makeRequest(...)

    print("✅ Found \(tickets.count) tickets")
    return tickets
}
```

#### After:
```swift
func searchAvailableTickets(eventId: String, query: String, method: TicketCaptureMethod) async throws -> [Ticket] {
    secureLog("🔍 Searching tickets for event: \(eventId.redacted(as: .uuid)), query: \(query.redacted)",
              level: .debug)

    let tickets = try await supabaseService.makeRequest(...)

    secureLog("✅ Found \(tickets.count) tickets", level: .info)
    return tickets
}
```

## Redaction Types

### Automatic Redaction (Full)
Use `secureLog()` or `.redacted` for complete automatic redaction:

```swift
let message = "User user@example.com logged in with token eyJhbGci..."
secureLog(message)  // All sensitive patterns automatically redacted
```

### Explicit Redaction Types

#### 1. **Token** - Full redaction with prefix/suffix
```swift
let token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.payload.signature"
secureLog("Token: \(token)", redacting: token, as: .token)
// Output: Token: eyJh***ture [72 chars]
```

#### 2. **Email** - Partial redaction preserving domain
```swift
let email = "john.doe@example.com"
secureLog("Email: \(email)", redacting: email, as: .email)
// Output: Email: jo***@example.com
```

#### 3. **Phone** - Show last 4 digits
```swift
let phone = "555-123-4567"
secureLog("Phone: \(phone)", redacting: phone, as: .phone)
// Output: Phone: ***-***-4567
```

#### 4. **UUID** - Partial redaction preserving first segment
```swift
let uuid = "550e8400-e29b-41d4-a716-446655440000"
secureLog("User ID: \(uuid)", redacting: uuid, as: .uuid)
// Output: User ID: 550e8400-****-****-****-************
```

#### 5. **NFC ID** - Show prefix and suffix for debugging
```swift
let nfcId = "ABC123XYZ789"
secureLog("NFC: \(nfcId)", redacting: nfcId, as: .nfcId)
// Output: NFC: ABC***789
```

#### 6. **Full** - Complete redaction
```swift
let sensitive = "highly sensitive data"
secureLog("Data: \(sensitive)", redacting: sensitive, as: .full)
// Output: Data: [REDACTED]
```

## String Extensions

### Convenience Methods

```swift
// Automatic redaction
let message = "Contact admin@example.com".redacted
// Output: "Contact [EMAIL_REDACTED]"

// Specific redaction type
let email = "user@example.com".redacted(as: .email)
// Output: "us***@example.com"

let uuid = "550e8400-e29b-41d4-a716-446655440000".redacted(as: .uuid)
// Output: "550e8400-****-****-****-************"
```

## Log Levels

```swift
public enum LogLevel: Int {
    case debug    // Development only, most verbose
    case info     // General information
    case warning  // Warnings that don't affect functionality
    case error    // Errors that affect functionality
    case critical // Critical errors requiring immediate attention
}

// Usage
secureLog("Debug info", level: .debug)      // Only in DEBUG builds
secureLog("User action", level: .info)      // General logging
secureLog("Unusual behavior", level: .warning)
secureLog("Operation failed", level: .error)
secureLog("Data corruption", level: .critical)
```

## Best Practices

### 1. Always Use Secure Logging for Sensitive Data

❌ **Don't:**
```swift
print("User \(userEmail) failed auth with token \(token)")
```

✅ **Do:**
```swift
secureLog("User \(userEmail) failed auth", level: .warning)
// Email automatically redacted
```

### 2. Use Appropriate Redaction Levels

```swift
// For debugging, use partial redaction to preserve utility
secureLog("Processing NFC: \(nfcId)", redacting: nfcId, as: .nfcId, level: .debug)
// Output: Processing NFC: ABC***789 (still useful for debugging)

// For production logs, use full redaction
secureLog("Auth failed for user: \(email)", redacting: email, as: .full, level: .error)
// Output: Auth failed for user: [REDACTED]
```

### 3. Structured Logging

```swift
// Good: Structured, easy to parse, safe
secureLog("authentication_success user=\(email.redacted(as: .email)) duration=\(duration)ms",
          level: .info)

// Bad: Unstructured, hard to parse
secureLog("User logged in after waiting for \(duration) milliseconds: \(email)",
          level: .info)
```

### 4. Don't Over-Redact

```swift
// ❌ Over-redaction makes debugging impossible
secureLog("Error occurred: \([errorType, errorCode, userId].map { $0.redacted(as: .full) })")
// Output: Error occurred: [[REDACTED], [REDACTED], [REDACTED]]

// ✅ Redact only sensitive fields
secureLog("Error occurred: type=\(errorType) code=\(errorCode) user=\(userId.redacted(as: .uuid))")
// Output: Error occurred: type=ValidationError code=400 user=550e8400-****-****-****-************
```

## Migration Checklist

- [ ] Add LoggingRedaction.swift to project
- [ ] Add LoggingRedactionTests.swift to test target
- [ ] Run tests to verify functionality
- [ ] Replace all `print()` statements in SupabaseService.swift
- [ ] Replace all `print()` statements in DatabaseScannerViewModel.swift
- [ ] Replace all `print()` statements in TicketService.swift
- [ ] Replace all `print()` statements in other service files
- [ ] Review crash reporting integration (ensure using secureLog)
- [ ] Review analytics integration (ensure using secureLog)
- [ ] Update CI to check for raw print statements
- [ ] Document logging policy for team

## Testing

```bash
# Run logging redaction tests
xcodebuild test \
  -scheme NFCDemo \
  -only-testing:NFCDemoTests/LoggingRedactionTests

# Verify no sensitive data in logs
# 1. Run app in simulator
# 2. Perform authentication flow
# 3. Check Console.app for app logs
# 4. Verify no plain emails, tokens, or UUIDs visible
```

## Production Integration

### Crash Reporting (e.g., Crashlytics, Sentry)

```swift
// In SecureLogger.swift - sendToLoggingService method
private func sendToLoggingService(_ message: String, level: LogLevel) {
    #if !DEBUG
    // Send to crash reporting service (already redacted)
    Crashlytics.crashlytics().log(message)

    // Or Sentry
    SentrySDK.capture(message: message) {
        $0.level = level.sentryLevel
    }
    #endif
}
```

### Analytics (e.g., Mixpanel, Amplitude)

```swift
// Always redact before sending to analytics
Analytics.track("user_login", properties: [
    "email": email.redacted(as: .email),  // us***@example.com
    "duration": duration,                  // No redaction needed
    "session_id": sessionId.redacted(as: .uuid)  // Partial UUID
])
```

## Performance Considerations

- Regex operations cached internally
- Thread-safe logging queue
- Debug logs disabled in production builds
- Minimal overhead: ~0.1ms per log message

## Security Notes

1. **Logs are not encrypted** - Redaction prevents leakage but doesn't encrypt
2. **Redacted data still identifiable** - Partial redaction allows correlation
3. **Not a substitute for access control** - Logs should still be access-restricted
4. **Crash dumps may contain memory** - Redaction only affects explicit logs

## Support

For issues or questions about logging redaction:
1. Check test suite for examples
2. Review this integration guide
3. Contact security team for policy questions
