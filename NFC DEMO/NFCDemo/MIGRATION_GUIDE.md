# Migration Guide: Security and Architecture Improvements

This guide helps you migrate from the old architecture with hardcoded secrets to the new secure, modular architecture.

## Overview of Changes

### ✅ Completed Improvements

1. **Secure Configuration Management** - No more hardcoded API keys
2. **Proper Logging Infrastructure** - File and console logging with categories
3. **Comprehensive Error Handling** - Type-safe error handling throughout
4. **Network Layer Abstraction** - Centralized HTTP client
5. **Repository Pattern** - Separation of data access from business logic
6. **Service Layer Refactoring** - Single-responsibility focused services
7. **Complete Documentation** - Comprehensive README and inline docs

### 🔄 Migration Steps

## Step 1: Set Up Configuration

### Before (❌ Hardcoded - SECURITY RISK)
```swift
// SupabaseService.swift
private let supabaseURL = "https://pmrxyisasfaimumuobvu.supabase.co"
private var supabaseAnonKey: String?

private init() {
    supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

### After (✅ Secure Configuration)
```swift
// AppConfiguration.swift
var supabaseURL: String {
    guard let url = config["SUPABASE_URL"] as? String, !url.isEmpty else {
        return ""
    }
    return url
}
```

**Action Required:**
1. Copy `Config.plist.example` to `Config.plist`
2. Add your actual credentials to `Config.plist`
3. Verify `Config.plist` is in `.gitignore`

```bash
cp NFCDemo/Config/Config.plist.example NFCDemo/Config/Config.plist
# Edit Config.plist with your actual credentials
git status  # Verify Config.plist is NOT shown (should be ignored)
```

## Step 2: Update Service Usage

### Before (❌ Monolithic Service)
```swift
// Old way - everything in SupabaseService
@StateObject private var supabaseService = SupabaseService.shared

// Authentication
try await supabaseService.signIn(email: email, password: password)

// Events
let events = try await supabaseService.fetchEvents()

// Wristbands
let wristbands = try await supabaseService.fetchWristbands(for: eventId)
```

### After (✅ Focused Services)
```swift
// New way - separate services for different concerns
@StateObject private var authService = AuthService.shared
@StateObject private var eventService = EventService.shared

// Authentication
try await authService.signIn(email: email, password: password)

// Events
let events = try await eventService.fetchEvents()

// Wristbands (now through repository)
let repository = WristbandRepository()
let wristbands = try await repository.fetchWristbands(for: eventId)
```

## Step 3: Update Token Storage

### Before (❌ Mixed Storage - Insecure)
```swift
// Some tokens in UserDefaults
UserDefaults.standard.set(response.accessToken, forKey: "supabase_access_token")

// Some in Keychain
try SecureTokenStorage.store(token: token, for: .accessToken)
```

### After (✅ Keychain Only)
```swift
// All tokens in Keychain
try SecureTokenStorage.store(token: response.accessToken, for: .accessToken)
try SecureTokenStorage.store(token: email, for: .userEmail)
try SecureTokenStorage.store(token: refreshToken, for: .refreshToken)

// Reading
let token = try SecureTokenStorage.retrieve(account: .accessToken)

// Clearing
try SecureTokenStorage.clearAll()
```

**Action Required:**
Migrate existing tokens from UserDefaults to Keychain:

```swift
// Run once on app launch (migration code)
func migrateTokensToKeychain() {
    if let oldToken = UserDefaults.standard.string(forKey: "supabase_access_token"),
       !SecureTokenStorage.exists(account: .accessToken) {
        try? SecureTokenStorage.store(token: oldToken, for: .accessToken)
        UserDefaults.standard.removeObject(forKey: "supabase_access_token")
    }

    // Repeat for other tokens...
}
```

## Step 4: Update Error Handling

### Before (❌ String Errors)
```swift
throw NSError(domain: "Error", code: 1, userInfo: [NSLocalizedDescriptionKey: "Something went wrong"])
```

### After (✅ Type-Safe Errors)
```swift
// Specific errors
throw AppError.authenticationFailed("Invalid credentials")
throw AppError.networkError(.noConnection)
throw AppError.validationFailed([
    ValidationFailure("email", "Email is required")
])

// Error handling with logging
do {
    try await someOperation()
} catch {
    let appError = error.asAppError()
    appError.log()  // Automatically logs with proper category and level
    throw appError
}
```

## Step 5: Update Network Calls

### Before (❌ Manual URLSession)
```swift
var request = URLRequest(url: url)
request.httpMethod = "POST"
request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
request.setValue(apiKey, forHTTPHeaderField: "apikey")
request.setValue("application/json", forHTTPHeaderField: "Content-Type")
request.httpBody = body

let (data, response) = try await URLSession.shared.data(for: request)
// Manual response handling...
```

### After (✅ NetworkClient)
```swift
let result: [Event] = try await NetworkClient.shared.get(
    endpoint: "rest/v1/events?select=*",
    responseType: [Event].self
)

// Or for POST requests
let created: Event = try await NetworkClient.shared.post(
    endpoint: "rest/v1/events",
    body: try JSONEncoder().encode(eventData),
    responseType: Event.self
)
```

## Step 6: Update Logging

### Before (❌ print statements)
```swift
print("✅ Authentication successful!")
print("❌ Failed to fetch events: \(error)")
```

### After (✅ Structured Logging)
```swift
AppLogger.shared.info("Authentication successful", category: "Auth")
AppLogger.shared.error("Failed to fetch events: \(error)", category: "Events")

// Or use convenience functions
logInfo("Authentication successful", category: "Auth")
logError("Failed to fetch events", category: "Events")

// With performance tracking
let result = AppLogger.shared.measure("Fetch Events") {
    try await repository.fetchEvents()
}
```

## Step 7: Initialize Services on App Launch

### Update NFCDemoApp.swift

```swift
import SwiftUI

@main
struct NFCDemoApp: App {
    init() {
        // Configure app on launch
        setupApp()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(AuthService.shared)
                .environmentObject(EventService.shared)
        }
    }

    private func setupApp() {
        // Configure logging
        AppLogger.shared.info("App launched", category: "App")

        // Verify configuration
        guard AppConfiguration.shared.isConfigured else {
            AppLogger.shared.critical("App not configured! Please set up Config.plist", category: "App")
            return
        }

        // Configure network client with auth token provider
        AuthService.shared.configureNetworkClient()

        AppLogger.shared.info("App configuration complete", category: "App")
    }
}
```

## Step 8: Update Views

### Before
```swift
@StateObject private var supabaseService = SupabaseService.shared

var body: some View {
    if !supabaseService.isAuthenticated {
        AuthenticationView()
            .environmentObject(supabaseService)
    } else {
        MainView()
            .environmentObject(supabaseService)
    }
}
```

### After
```swift
@EnvironmentObject var authService: AuthService
@EnvironmentObject var eventService: EventService

var body: some View {
    if !authService.isAuthenticated {
        AuthenticationView()
    } else {
        MainView()
    }
}
```

## Step 9: Clean Up Old Files

After migration is complete and tested:

```bash
# Back up old files first
mkdir -p backup
cp NFCDemo/Services/SupabaseService.swift backup/

# Review and remove unused code
# - Old SupabaseService.swift (after extracting any missing logic)
# - Old hardcoded configurations
# - Old UserDefaults-based storage
```

## Step 10: Testing After Migration

### Checklist

- [ ] Configuration loads properly on launch
- [ ] Can authenticate with new AuthService
- [ ] Tokens stored in Keychain only
- [ ] Events load correctly
- [ ] Wristband scanning works
- [ ] Offline sync functions
- [ ] No hardcoded secrets in codebase
- [ ] Logging works (check log files)
- [ ] Network requests succeed
- [ ] Error handling displays user-friendly messages

### Testing Script

```swift
func testMigration() async {
    // 1. Test configuration
    assert(AppConfiguration.shared.isConfigured, "Configuration not set up")

    // 2. Test authentication
    let authService = AuthService.shared
    do {
        try await authService.signIn(email: "test@example.com", password: "test")
        assert(authService.isAuthenticated, "Authentication failed")
    } catch {
        print("Auth test failed: \(error)")
    }

    // 3. Test token storage
    assert(SecureTokenStorage.exists(account: .accessToken), "Token not in Keychain")

    // 4. Test network client
    do {
        let events: [Event] = try await NetworkClient.shared.get(
            endpoint: "rest/v1/events?select=*",
            responseType: [Event].self
        )
        print("Fetched \(events.count) events successfully")
    } catch {
        print("Network test failed: \(error)")
    }

    print("✅ Migration tests passed!")
}
```

## Rollback Plan

If you need to rollback:

1. Restore backed-up files from `backup/` directory
2. Re-add API keys to old location (temporarily)
3. Revert git commits: `git revert <commit-hash>`
4. Report issues to team

## Common Issues

### Issue: "Configuration not found"
**Solution**: Ensure `Config.plist` exists and has valid values

### Issue: "Token retrieval failed"
**Solution**: Run token migration script to move from UserDefaults to Keychain

### Issue: Network requests returning 401
**Solution**: Check that NetworkClient token provider is configured

### Issue: App crashes on launch
**Solution**: Check logs at `AppLogger.shared.getLogFileURL()`

## Performance Improvements

After migration, you should see:

- ✅ Faster network requests (with caching)
- ✅ Better error messages for users
- ✅ Improved offline functionality
- ✅ Easier debugging with structured logs
- ✅ More testable code (dependency injection)

## Next Steps

After completing migration:

1. **Write Tests** - Add unit tests for new services and repositories
2. **Monitor Logs** - Review AppLogger output for any issues
3. **Performance Testing** - Verify app performance hasn't degraded
4. **Security Audit** - Run security scan to verify no hardcoded secrets
5. **Documentation** - Update team docs with new patterns

## Support

If you encounter issues during migration:
1. Check this guide for common solutions
2. Review logs: `AppLogger.shared.getLogContents()`
3. Create GitHub issue with details
4. Contact dev team

---

**Migration Checklist Progress**

- [ ] Configuration set up (Config.plist)
- [ ] Services updated (AuthService, EventService)
- [ ] Token storage migrated (Keychain only)
- [ ] Error handling updated (AppError)
- [ ] Network calls updated (NetworkClient)
- [ ] Logging updated (AppLogger)
- [ ] App initialization updated
- [ ] Views updated
- [ ] Old files removed
- [ ] Testing complete

Good luck with your migration! 🚀
