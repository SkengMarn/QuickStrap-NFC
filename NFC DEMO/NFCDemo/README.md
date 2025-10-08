# NFC Event Management System

A comprehensive iOS application for managing event check-ins using NFC technology, built with SwiftUI and Supabase.

## 📋 Table of Contents

- [Features](#features)
- [Architecture](#architecture)
- [Setup Instructions](#setup-instructions)
- [Configuration](#configuration)
- [Project Structure](#project-structure)
- [Security](#security)
- [Development](#development)
- [Testing](#testing)
- [Deployment](#deployment)
- [Troubleshooting](#troubleshooting)

## ✨ Features

### Core Functionality
- ✅ **NFC Wristband Scanning**: Scan NFC-enabled wristbands for event check-ins
- ✅ **User Authentication**: Secure JWT-based authentication with Supabase
- ✅ **Multi-Event Support**: Manage multiple events from a single app
- ✅ **Offline Mode**: Continue scanning even without internet connection
- ✅ **Location Tracking**: GPS-based check-in verification
- ✅ **Gate Management**: Intelligent gate binding and deduplication
- ✅ **Analytics Dashboard**: Real-time statistics and insights
- ✅ **Role-Based Access**: Admin, Owner, and Scanner user roles

### Advanced Features
- 🔒 **Secure Token Storage**: Keychain-based credential management
- 📊 **Comprehensive Logging**: File and console logging with categories
- 🔄 **Automatic Sync**: Background synchronization of offline data
- 🎯 **Smart Gate Detection**: Location-based gate identification
- 📱 **Adaptive UI**: SwiftUI-based responsive interface
- ⚡ **Performance Optimized**: Efficient data caching and batch operations

## 🏗 Architecture

### Clean Architecture Layers

```
┌─────────────────────────────────────────┐
│           Presentation Layer            │
│      (Views, ViewModels, UI Logic)      │
├─────────────────────────────────────────┤
│            Service Layer                │
│    (Business Logic, Orchestration)      │
├─────────────────────────────────────────┤
│          Repository Layer               │
│    (Data Access, API Abstraction)       │
├─────────────────────────────────────────┤
│           Network Layer                 │
│   (HTTP Client, Request Building)       │
├─────────────────────────────────────────┤
│          Infrastructure                 │
│  (Storage, Logging, Configuration)      │
└─────────────────────────────────────────┘
```

### Key Components

#### Services
- **AuthService**: Handles authentication, session management, token refresh
- **EventService**: Manages event selection and retrieval
- **WristbandService**: Wristband operations and category management
- **CheckinService**: Check-in recording and log management
- **GateBindingService**: Smart gate detection and binding
- **OfflineDataManager**: Offline data caching and sync

#### Repositories
- **AuthRepository**: Authentication API calls
- **EventRepository**: Event data access
- **WristbandRepository**: Wristband CRUD operations
- **CheckinRepository**: Check-in log operations

#### Infrastructure
- **NetworkClient**: Centralized HTTP client with logging
- **AppLogger**: OSLog-based logging with file persistence
- **SecureTokenStorage**: Keychain wrapper for secure storage
- **AppConfiguration**: Environment-based configuration

## 🚀 Setup Instructions

### Prerequisites

- **Xcode 15.0+**
- **iOS 16.0+** target device/simulator
- **Swift 6.0+**
- **Supabase Account** (for backend)
- **NFC-capable iPhone** (for testing NFC features)

### Step 1: Clone the Repository

```bash
git clone <repository-url>
cd "NFC DEMO/NFCDemo"
```

### Step 2: Configure Supabase

1. Create a new Supabase project at [supabase.com](https://supabase.com)
2. Set up the database schema (see `schema_check.sql`)
3. Note your project URL and anon key

### Step 3: Configure the App

**Option A: Using Config.plist (Recommended)**

1. Copy the example configuration:
```bash
cp NFCDemo/Config/Config.plist.example NFCDemo/Config/Config.plist
```

2. Edit `Config.plist` with your credentials:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>SUPABASE_URL</key>
    <string>https://your-project-id.supabase.co</string>
    <key>SUPABASE_ANON_KEY</key>
    <string>your-actual-anon-key-here</string>
</dict>
</plist>
```

3. **IMPORTANT**: Never commit `Config.plist` to version control (already in `.gitignore`)

**Option B: Using Environment Variables (CI/CD)**

Set the following environment variables:
```bash
export SUPABASE_URL="https://your-project-id.supabase.co"
export SUPABASE_ANON_KEY="your-anon-key"
```

**Option C: Using Keychain (Development Only)**

```swift
#if DEBUG
try AppConfiguration.shared.storeConfigurationInKeychain(
    url: "https://your-project-id.supabase.co",
    key: "your-anon-key"
)
#endif
```

### Step 4: Build and Run

1. Open `NFCDemo.xcodeproj` in Xcode
2. Select your target device (must be a real iPhone for NFC features)
3. Build and run (⌘R)

## ⚙️ Configuration

### App Configuration

The app uses a three-tier configuration system:

1. **Config.plist** (highest priority) - for local development
2. **Environment Variables** - for CI/CD and automation
3. **Keychain Storage** - for development convenience

### NFC Configuration

Add NFC entitlements to your app:

1. Open your project in Xcode
2. Select your target → Signing & Capabilities
3. Add "Near Field Communication Tag Reading"
4. Update `Info.plist`:

```xml
<key>NFCReaderUsageDescription</key>
<string>This app uses NFC to scan event wristbands</string>
<key>com.apple.developer.nfc.readersession.formats</key>
<array>
    <string>NDEF</string>
</array>
```

### Location Services

Add location permissions to `Info.plist`:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Location is used to verify gate check-ins</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>Location helps identify which gate you're scanning at</string>
```

## 📁 Project Structure

```
NFCDemo/
├── NFCDemo/
│   ├── NFCDemoApp.swift          # App entry point
│   ├── ContentView.swift          # Root view with navigation
│   │
│   ├── Config/                    # Configuration files
│   │   ├── AppConfiguration.swift
│   │   └── Config.plist.example
│   │
│   ├── Models/                    # Data models
│   │   ├── DatabaseModels.swift
│   │   ├── GateModels.swift
│   │   └── TicketModels.swift
│   │
│   ├── Views/                     # SwiftUI views
│   │   ├── AuthenticationView.swift
│   │   ├── EventSelectionView.swift
│   │   ├── DatabaseScanView.swift
│   │   ├── GatesView.swift
│   │   └── ...
│   │
│   ├── ViewModels/                # View models
│   │   ├── DatabaseScannerViewModel.swift
│   │   └── GatesViewModel.swift
│   │
│   ├── Services/                  # Business logic
│   │   ├── AuthService.swift
│   │   ├── EventService.swift
│   │   ├── NFCReaderService.swift
│   │   ├── GateBindingService.swift
│   │   └── OfflineDataManager.swift
│   │
│   ├── Repositories/              # Data access layer
│   │   ├── AuthRepository.swift
│   │   ├── EventRepository.swift
│   │   ├── WristbandRepository.swift
│   │   └── CheckinRepository.swift
│   │
│   ├── Network/                   # Network layer
│   │   └── NetworkClient.swift
│   │
│   ├── Utils/                     # Utilities
│   │   ├── AppLogger.swift
│   │   ├── AppError.swift
│   │   └── DesignSystem.swift
│   │
│   └── Security/                  # Security utilities
│       ├── SecureTokenStorage.swift
│       └── Logger.swift
│
├── NFCDemoTests/                  # Unit tests
├── NFCDemoUITests/                # UI tests
└── README.md                      # This file
```

## 🔒 Security

### Best Practices Implemented

✅ **No Hardcoded Secrets**: All credentials stored securely
✅ **Keychain Storage**: iOS Keychain for sensitive data
✅ **JWT Token Management**: Automatic refresh and expiration handling
✅ **Secure Network Layer**: HTTPS only, proper error handling
✅ **Input Validation**: All user inputs validated before processing
✅ **Role-Based Access**: User permissions enforced at service layer

### Security Checklist

- [ ] Never commit `Config.plist` with real credentials
- [ ] Use environment variables in CI/CD pipelines
- [ ] Regularly rotate API keys
- [ ] Enable App Transport Security (ATS)
- [ ] Implement certificate pinning for production
- [ ] Use biometric authentication for sensitive operations
- [ ] Audit logs regularly for suspicious activity

## 🛠 Development

### Running in Debug Mode

Debug builds include:
- Verbose logging to console
- File logging enabled
- Network request/response logging
- Performance measurements

### Code Style

The project follows these conventions:
- Swift API Design Guidelines
- MARK comments for code organization
- Descriptive variable and function names
- Comprehensive error handling

### Git Workflow

```bash
# Create feature branch
git checkout -b feature/your-feature-name

# Make changes and commit
git add .
git commit -m "feat: Add your feature description"

# Push to remote
git push origin feature/your-feature-name

# Create pull request
```

### Commit Message Format

```
<type>: <description>

[optional body]

[optional footer]
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`

## 🧪 Testing

### Running Tests

```bash
# Run all tests
xcodebuild test -scheme NFCDemo -destination 'platform=iOS Simulator,name=iPhone 15'

# Run specific test class
xcodebuild test -scheme NFCDemo -only-testing:NFCDemoTests/AuthServiceTests
```

### Test Coverage

Current test coverage: **[TBD]%**

Priority testing areas:
- [ ] Authentication flows
- [ ] NFC scanning logic
- [ ] Offline data sync
- [ ] Gate binding algorithms
- [ ] Data validation

### Writing Tests

Example test structure:

```swift
import XCTest
@testable import NFCDemo

class AuthServiceTests: XCTestCase {
    var sut: AuthService!
    var mockRepository: MockAuthRepository!

    override func setUp() {
        super.setUp()
        mockRepository = MockAuthRepository()
        sut = AuthService(repository: mockRepository)
    }

    func testSignInSuccess() async throws {
        // Given
        let email = "test@example.com"
        let password = "password123"

        // When
        try await sut.signIn(email: email, password: password)

        // Then
        XCTAssertTrue(sut.isAuthenticated)
        XCTAssertNotNil(sut.currentUser)
    }
}
```

## 🚀 Deployment

### Build for Production

1. **Update version number**:
   - Target → General → Version
   - Increment build number

2. **Archive the app**:
   ```
   Product → Archive
   ```

3. **Distribute**:
   - App Store Connect
   - TestFlight (for beta testing)
   - Ad-Hoc (for internal distribution)

### Environment Configuration

**Production**:
```bash
export SUPABASE_URL="https://prod-project.supabase.co"
export SUPABASE_ANON_KEY="prod-anon-key"
```

**Staging**:
```bash
export SUPABASE_URL="https://staging-project.supabase.co"
export SUPABASE_ANON_KEY="staging-anon-key"
```

### Pre-deployment Checklist

- [ ] All tests passing
- [ ] Security audit completed
- [ ] Performance testing done
- [ ] Crashlytics/Analytics configured
- [ ] App icons and assets updated
- [ ] Privacy policy and terms updated
- [ ] App Store screenshots prepared
- [ ] Release notes written

## 🐛 Troubleshooting

### Common Issues

**Issue**: App crashes on launch
- **Solution**: Check that `Config.plist` exists and has valid credentials

**Issue**: NFC scanning not working
- **Solution**: Ensure you're running on a real device (NFC doesn't work in simulator)
- **Solution**: Verify NFC entitlements are added

**Issue**: "Configuration not found" error
- **Solution**: Set up `Config.plist` or environment variables

**Issue**: Network requests failing
- **Solution**: Check internet connection
- **Solution**: Verify Supabase URL and API key are correct

**Issue**: Offline sync not working
- **Solution**: Check `OfflineDataManager` logs
- **Solution**: Ensure proper network connectivity for sync

### Logging

View logs:
```swift
// Get log file
if let logURL = AppLogger.shared.getLogFileURL() {
    print("Logs at: \(logURL.path)")
}

// Get log contents
if let logs = AppLogger.shared.getLogContents() {
    print(logs)
}
```

### Debug Menu

Enable debug features in development:
1. Shake device to open debug menu
2. View current configuration
3. Clear cache
4. View logs
5. Force sync

## 📞 Support

For issues and questions:
- Create an issue on GitHub
- Contact: [your-email@example.com]
- Documentation: [link-to-docs]

## 📄 License

[Your License Here]

## 🙏 Acknowledgments

- SwiftUI for the amazing UI framework
- Supabase for the backend infrastructure
- CoreNFC for NFC capabilities
- iOS Security Framework for Keychain access

---

**Version**: 1.0.0
**Last Updated**: 2025-01-04
**Minimum iOS**: 16.0
