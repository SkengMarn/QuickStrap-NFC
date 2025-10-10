# Xcode Package Resolution Guide

## Current Status

✅ **Completed:**
- Swift packages resolved and updated to Supabase 2.34.0
- Info.plist restored with security fixes
- Package.resolved file updated

⚠️ **Needs Manual Resolution in Xcode:**

## Issues to Fix in Xcode

### 1. Missing Package Products Error

**Error:** Missing package products 'PostgREST', 'Functions', 'Auth', 'Storage', 'Realtime'

**Root Cause:** The Supabase Swift SDK updated and these products may need to be re-linked.

**Solution:**

1. **In Xcode (now open):**
   - Go to **File → Packages → Reset Package Caches**
   - Wait for cache to clear
   - Then go to **File → Packages → Resolve Package Versions**
   - Wait for resolution to complete

2. **Verify Package Products:**
   - Select the project in the navigator (top of file list)
   - Select the **NFCDemo** target
   - Go to **General** tab → **Frameworks, Libraries, and Embedded Content**
   - Check if these are listed:
     - ✅ Auth
     - ✅ Functions
     - ✅ PostgREST
     - ✅ Realtime
     - ✅ Storage
     - ✅ Supabase

3. **If products are missing:**
   - Click the **+** button under Frameworks
   - From **Supabase** package, add:
     - Auth
     - Functions
     - PostgREST
     - Realtime
     - Storage
     - Supabase (if not already there)

### 2. Info.plist Duplicate Warning

**Warning:** Multiple commands produce Info.plist

**Solution in Xcode:**

Option A (Recommended - Use Auto-Generated):
1. Select project → NFCDemo target → Build Settings
2. Search for "Info.plist File"
3. Delete the value (leave it empty)
4. The INFOPLIST_KEY_* settings will auto-generate it

Option B (Keep Physical File):
1. Select project → NFCDemo target → Build Settings
2. Search for "Generate Info.plist File"
3. Set to **NO**
4. Keep INFOPLIST_FILE = NFCDemo/Info.plist

**Recommended:** Option A, but first copy these keys to Build Settings:
- NSLocationAlwaysAndWhenInUseUsageDescription
- NSLocationWhenInUseUsageDescription
- NSCameraUsageDescription
- NFCReaderUsageDescription

## Quick Fix Commands (Run in Xcode Terminal)

If you prefer command-line:

```bash
cd "/Volumes/JEW/NFC DEMO/NFC DEMO/NFCDemo"

# Reset package caches
rm -rf ~/Library/Caches/org.swift.swiftpm
rm -rf ~/Library/org.swift.swiftpm
rm -rf NFCDemo.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/*.resolved

# Resolve packages
xcodebuild -resolvePackageDependencies -project NFCDemo.xcodeproj

# Try building
xcodebuild -scheme NFCDemo -destination 'platform=iOS Simulator,name=iPhone 16 Pro' clean build
```

## Verification Steps

After fixing:

1. ✅ No red errors in Issue Navigator
2. ✅ Package products visible in Project Navigator under "Package Dependencies"
3. ✅ Build succeeds (Cmd+B)
4. ✅ No duplicate Info.plist warnings

## Alternative: Use Supabase Unified Package

**New Approach (Supabase 2.x):**

Instead of importing individual products, you can import just the main Supabase module:

```swift
// Old approach (separate imports):
import Auth
import PostgREST
import Functions
import Storage
import Realtime

// New approach (unified):
import Supabase
```

Then update code to use:
```swift
let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://your-project.supabase.co")!,
    supabaseKey: "your-anon-key"
)

// All features available through the client:
supabase.auth.signIn(...)
supabase.database.from("table")...
supabase.storage.from("bucket")...
```

## Current Package Version

- **Supabase Swift:** 2.34.0 (updated from 2.33.1)
- **Location:** https://github.com/supabase-community/supabase-swift
- **Revision:** 21425be5a493bb24bfde51808ccfa82a56111430

## Support

If issues persist:
1. Check Xcode Reports Navigator (Cmd+9) for detailed errors
2. Try File → Packages → Update to Latest Package Versions
3. Restart Xcode
4. Clean Build Folder (Cmd+Shift+K, then Cmd+Shift+Option+K)
