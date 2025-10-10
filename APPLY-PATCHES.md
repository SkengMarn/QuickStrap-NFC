# Security Fixes - Application Guide

## Overview

This directory contains comprehensive security fixes for the QuickStrap NFC application. All changes have been documented in multiple formats for your convenience.

## What's Included

### A) Machine-Parsable JSON Spec
📄 **`security-fixes-spec.json`**
- Complete specification of all changes
- Exact line numbers and file locations
- Vulnerability descriptions and fixes
- Test requirements

### B) Git Patch Files (Unified Diff Format)
📦 **Ready-to-apply patches:**
1. `0001-fix-url-injection-in-DatabaseScannerViewModel.patch`
2. `0002-update-background-location-usage-description.patch`
3. `0003-fix-keychain-token-management-in-SupabaseService.patch`
4. `0004-fix-preview-layer-attachment-in-TicketScannerService.patch`
5. `0005-fix-url-injection-in-TicketService.patch`
6. `0006-add-logging-redaction-utilities.patch` _(Optional enhancement)_

### C) Deployment Checklist
📋 **`DEPLOYMENT-CHECKLIST.md`**
- Pre-deployment testing procedures
- CI/CD configuration
- Staged rollout plan
- Monitoring and alerting setup
- Rollback procedures

### D) Logging Redaction System
🔒 **Security enhancement files:**
- `coderabbit_analysis/LoggingRedaction.swift` - Main implementation
- `coderabbit_analysis/LoggingRedactionTests.swift` - Comprehensive tests
- `LOGGING-REDACTION-INTEGRATION.md` - Integration guide

---

## Quick Start - Apply Patches

### Option 1: Apply All Patches at Once

```bash
# Navigate to your repo root
cd "/Volumes/JEW/NFC DEMO"

# Apply core security fixes (patches 1-5)
for patch in 000{1..5}-*.patch; do
    echo "Applying $patch..."
    git apply --check "$patch" && git apply "$patch" || echo "Failed: $patch"
done

# Optional: Apply logging redaction enhancement
git apply --check 0006-add-logging-redaction-utilities.patch
git apply 0006-add-logging-redaction-utilities.patch

# Review changes
git diff --staged

# Commit if satisfied
git add -A
git commit -m "Security fixes: URL injection, Keychain tokens, preview layer, logging redaction

- Fix URL injection in DatabaseScannerViewModel query builders
- Update NSLocationAlwaysAndWhenInUseUsageDescription for background usage
- Add SecureTokenStorage.clearAll() to signOut()
- Replace UserDefaults with Keychain for token storage
- Fix preview layer attachment in TicketScannerService
- Fix URL injection in TicketService query builders
- Add logging redaction utilities (optional)

🤖 Generated with Claude Code
Co-Authored-By: Claude <noreply@anthropic.com>"
```

### Option 2: Apply Patches Individually

```bash
cd "/Volumes/JEW/NFC DEMO"

# Check if patch can be applied cleanly
git apply --check 0001-fix-url-injection-in-DatabaseScannerViewModel.patch

# Apply the patch
git apply 0001-fix-url-injection-in-DatabaseScannerViewModel.patch

# Review the changes
git diff coderabbit_analysis/DatabaseScannerViewModel.swift

# Repeat for each patch...
```

### Option 3: Manual Application

If patches don't apply cleanly due to line number changes:

```bash
# Apply with 3-way merge (more forgiving)
git apply --3way 0001-fix-url-injection-in-DatabaseScannerViewModel.patch

# Or apply with context (ignores exact line numbers)
patch -p1 < 0001-fix-url-injection-in-DatabaseScannerViewModel.patch
```

---

## Verification After Applying Patches

### 1. Verify All Files Changed

```bash
git status

# Expected changed files:
# modified:   coderabbit_analysis/DatabaseScannerViewModel.swift
# modified:   coderabbit_analysis/Info.plist
# modified:   coderabbit_analysis/SupabaseService.swift
# modified:   coderabbit_analysis/TicketScannerService.swift
# modified:   coderabbit_analysis/TicketService.swift
# new file:   coderabbit_analysis/LoggingRedaction.swift (if applied patch 6)
# new file:   coderabbit_analysis/LoggingRedactionTests.swift (if applied patch 6)
```

### 2. Verify Code Compiles

```bash
# Build the project
xcodebuild -scheme NFCDemo -destination 'platform=iOS Simulator,name=iPhone 15' build

# Or in Xcode: Cmd+B
```

### 3. Run Tests

```bash
# Run all tests
xcodebuild test -scheme NFCDemo -destination 'platform=iOS Simulator,name=iPhone 15'

# Run only redaction tests (if applied patch 6)
xcodebuild test \
  -scheme NFCDemo \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:NFCDemoTests/LoggingRedactionTests
```

### 4. Manual Verification Checklist

#### DatabaseScannerViewModel.swift
- [ ] Line ~177: URLComponents used for wristband query
- [ ] Line ~359: URLComponents used for checkin logs query
- [ ] Line ~643: URLComponents used for stats queries
- [ ] All query parameters properly percent-encoded

#### Info.plist
- [ ] Line 10: NSLocationAlwaysAndWhenInUseUsageDescription updated with background explanation

#### SupabaseService.swift
- [ ] Line ~349: SecureTokenStorage.clearAll() in signOut()
- [ ] Line ~185: Keychain retrieval for refresh token
- [ ] Line ~220: Keychain storage for refreshed tokens

#### TicketScannerService.swift
- [ ] Line ~165: Preview layer attachment check in updateUIView

#### TicketService.swift
- [ ] Line ~148: URLComponents in searchAvailableTickets
- [ ] Line ~218: URLComponents in findTicketByCode

---

## Testing Procedures

### Security Testing

#### Test 1: URL Injection Prevention
```swift
// In a test or playground:
let maliciousId = "normal&status=eq.linked"
// Scan with this ID
// Verify: URL is percent-encoded, query not modified
```

#### Test 2: Keychain Token Management
```bash
# 1. Sign in to app
# 2. Check Keychain Access.app for tokens (search: "supabase")
# 3. Sign out
# 4. Verify Keychain entries removed
```

#### Test 3: Preview Layer
```swift
// 1. Open ticket scanner
// 2. Background app (Cmd+Shift+H in simulator)
// 3. Foreground app
// 4. Verify preview still visible
```

#### Test 4: Logging Redaction (if applied)
```swift
// 1. Run app with Console.app open
// 2. Perform authentication
// 3. Scan NFC tag
// 4. Search for tickets
// 5. Verify no plain emails/tokens in logs
```

---

## Rollback Instructions

### If Issues Arise

```bash
# Option 1: Revert uncommitted changes
git reset --hard HEAD

# Option 2: Revert committed changes
git revert HEAD

# Option 3: Reset to previous commit
git log --oneline  # Find commit hash before changes
git reset --hard <commit-hash>

# Option 4: Revert specific files
git checkout HEAD -- coderabbit_analysis/DatabaseScannerViewModel.swift
git checkout HEAD -- coderabbit_analysis/SupabaseService.swift
```

---

## Integration with Existing Workflow

### If Using Feature Branches

```bash
# Create feature branch
git checkout -b security-fixes-2025-10

# Apply patches
for patch in 000{1..5}-*.patch; do git apply "$patch"; done

# Commit
git add -A
git commit -m "Security fixes for URL injection and token storage"

# Push and create PR
git push origin security-fixes-2025-10
gh pr create --title "Security Fixes" --body "$(cat DEPLOYMENT-CHECKLIST.md)"
```

### CI/CD Integration

Add to `.github/workflows/security.yml`:

```yaml
name: Security Checks

on: [pull_request]

jobs:
  security-tests:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3

      - name: Check for URL injection patterns
        run: |
          # Fail if raw string interpolation found in endpoints
          if git diff origin/main... | grep 'endpoint:.*\\(.*\\)' | grep -v URLComponents; then
            echo "ERROR: Found potential URL injection"
            exit 1
          fi

      - name: Check for insecure token storage
        run: |
          # Fail if UserDefaults used for tokens (except in migration code)
          if git diff origin/main... | grep -i 'UserDefaults.*token' | grep -v '// Migration'; then
            echo "ERROR: Found insecure token storage"
            exit 1
          fi

      - name: Run security tests
        run: |
          xcodebuild test -scheme NFCDemo -destination 'platform=iOS Simulator,name=iPhone 15'
```

---

## Patch Details

### Patch 1: DatabaseScannerViewModel URL Injection
**Vulnerability:** Raw string interpolation in Supabase queries
**Fix:** URLComponents with URLQueryItem for proper percent encoding
**Impact:** Prevents filter injection and malformed URLs
**Files:** 1
**Lines Changed:** +43 -9

### Patch 2: Info.plist Background Location
**Vulnerability:** Vague location usage description
**Fix:** Explicit background monitoring explanation
**Impact:** App Store compliance, user transparency
**Files:** 1
**Lines Changed:** +1 -1

### Patch 3: SupabaseService Keychain Management
**Vulnerability:** Tokens not cleared from Keychain on sign-out, token refresh reads from wrong storage
**Fix:** Add clearAll() to signOut, use Keychain for refresh token retrieval and storage
**Impact:** Prevents token leakage, ensures consistent secure storage
**Files:** 1
**Lines Changed:** +41 -11

### Patch 4: TicketScannerService Preview Layer
**Bug:** Preview layer missing if scanner starts after view creation
**Fix:** Check and attach layer in updateUIView
**Impact:** Reliable scanner preview in all scenarios
**Files:** 1
**Lines Changed:** +9 -1

### Patch 5: TicketService URL Injection
**Vulnerability:** User input in ticket search queries not percent-encoded
**Fix:** URLComponents for all search methods and strategies
**Impact:** Prevents injection in ticket search
**Files:** 1
**Lines Changed:** +62 -16

### Patch 6: Logging Redaction (Optional)
**Enhancement:** Automatic PII/sensitive data redaction in logs
**Fix:** SecureLogger with pattern-based redaction
**Impact:** Prevents accidental data leakage in logs/crashes
**Files:** 2 (new)
**Lines Changed:** +630 -0

---

## Support

### If Patches Fail to Apply

1. **Check your working directory is clean:**
   ```bash
   git status
   # Should show "nothing to commit, working tree clean"
   ```

2. **Ensure you're in the correct directory:**
   ```bash
   pwd
   # Should show: /Volumes/JEW/NFC DEMO
   ```

3. **Check Git version:**
   ```bash
   git --version
   # Should be 2.30 or later
   ```

4. **Try with --reject flag to see conflicts:**
   ```bash
   git apply --reject 0001-*.patch
   # Check *.rej files for conflicts
   ```

5. **Manual application:**
   - Open `security-fixes-spec.json`
   - Find the exact changes needed
   - Apply manually in Xcode
   - Verify against patch file

### Getting Help

- Review `DEPLOYMENT-CHECKLIST.md` for testing procedures
- Review `LOGGING-REDACTION-INTEGRATION.md` for logging examples
- Check `security-fixes-spec.json` for exact specifications
- Consult patch files for detailed diffs

---

## Summary

✅ **Applied Changes:**
- URL injection prevention in 2 files (DatabaseScannerViewModel, TicketService)
- Keychain token management in SupabaseService
- Background location description in Info.plist
- Preview layer fix in TicketScannerService
- Optional: Logging redaction system

🔒 **Security Improvements:**
- Prevents URL/filter injection attacks
- Secures authentication tokens in Keychain
- Prevents token leakage on sign-out
- Optional: Prevents PII leakage in logs

🎯 **Next Steps:**
1. Apply patches (see above)
2. Run tests
3. Review DEPLOYMENT-CHECKLIST.md
4. Plan staged rollout
5. Monitor metrics post-deployment

---

**Generated by Claude Code on 2025-10-11**
