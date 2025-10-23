# Swift Package Manager Dependency Troubleshooting Guide

## 📊 Current Status: ✅ RESOLVED

**Build Status:** `BUILD SUCCEEDED`
**Supabase Version:** `2.34.0` (unified product)
**Xcode Build System:** Modern (UseAppPreferences)

---

## 🔍 Diagnosis: What Went Wrong

### Root Cause
The project was configured to use **individual Supabase products** (Auth, Functions, PostgREST, Realtime, Storage) from SDK v1.x, but Supabase Swift v2.x consolidated these into a **single unified `Supabase` product**.

### Why Module Dependencies Failed
When SPM tried to resolve individual products that no longer existed:
```
Xcode Project Config (outdated):
├─ NFCDemo
│  ├─ Auth (product) ❌ Doesn't exist in v2.x
│  ├─ Functions (product) ❌ Doesn't exist in v2.x
│  ├─ PostgREST (product) ❌ Doesn't exist in v2.x
│  ├─ Realtime (product) ❌ Doesn't exist in v2.x
│  └─ Storage (product) ❌ Doesn't exist in v2.x
│     └─ HTTPTypes (internal module) ❌ Can't be found
│     └─ Helpers (internal module) ❌ Can't be found
│     └─ ConcurrencyExtras (internal module) ❌ Can't be found

Actual Supabase v2.x Structure:
├─ NFCDemo
│  └─ Supabase (unified product) ✅
│     ├─ Auth (internal module) ✅
│     ├─ Functions (internal module) ✅
│     ├─ PostgREST (internal module) ✅
│     ├─ Realtime (internal module) ✅
│     ├─ Storage (internal module) ✅
│     ├─ Helpers (internal module) ✅
│     └─ HTTPTypes (dependency) ✅
```

**Error Messages You Saw:**
- `Unable to find module dependency: 'ConcurrencyExtras'`
- `Unable to find module dependency: 'Helpers'`
- `Unable to find module dependency: 'HTTPTypes'`
- `Missing package product 'Auth'`
- `Missing package product 'Storage'`

---

## ✅ Fix Applied

### 1. Updated Xcode Project Configuration
Modified `NFCDemo.xcodeproj/project.pbxproj`:

**XCSwiftPackageProductDependency Section (lines 610-616):**
```xml
/* Begin XCSwiftPackageProductDependency section */
    D100A84E2E8411A400B82C8B /* Supabase */ = {
        isa = XCSwiftPackageProductDependency;
        package = D100A84D2E8411A400B82C8B /* XCRemoteSwiftPackageReference "supabase-swift" */;
        productName = Supabase;
    };
/* End XCSwiftPackageProductDependency section */
```

**PBXBuildFile Section (line 10):**
```xml
D100A84F2E8411A400B82C8B /* Supabase in Frameworks */ = {
    isa = PBXBuildFile;
    productRef = D100A84E2E8411A400B82C8B /* Supabase */;
};
```

**packageProductDependencies Array (lines 123-125):**
```xml
packageProductDependencies = (
    D100A84E2E8411A400B82C8B /* Supabase */,
);
```

### 2. Swift Import Statements
All Supabase functionality is now accessed through:
```swift
import Supabase

// All modules available from unified import:
// - Auth
// - Functions
// - PostgREST
// - Realtime
// - Storage
```

---

## 🛠️ Cleanup & Rebuild Routine

If you encounter similar SPM issues in the future, use this sequence:

### Terminal Commands

```bash
# Navigate to project directory
cd "/Volumes/JEW/NFC DEMO/NFC DEMO/NFCDemo"

# Step 1: Clean DerivedData (clears all build artifacts and module caches)
rm -rf ~/Library/Developer/Xcode/DerivedData/NFCDemo-*

# Step 2: Clean SPM cache (resolves corrupted package downloads)
rm -rf ~/Library/Caches/org.swift.swiftpm/repositories/
rm -rf ~/Library/Caches/org.swift.swiftpm/manifests/

# Step 3: Reset Xcode package resolution
xcodebuild -resolvePackageDependencies -scheme NFCDemo

# Step 4: Clean and rebuild
xcodebuild -scheme NFCDemo -destination 'generic/platform=iOS' clean build
```

### Xcode UI Steps

1. **File → Packages → Reset Package Caches**
2. **Product → Clean Build Folder** (⇧⌘K)
3. **File → Packages → Resolve Package Versions**
4. **Product → Build** (⌘B)

---

## 📦 Stable Package Configuration

### Current Locked Versions

```
Supabase: 2.34.0
├─ swift-concurrency-extras: 1.3.2
├─ swift-crypto: 3.15.1
├─ swift-http-types: 1.4.0
├─ swift-clocks: 1.0.6
├─ xctest-dynamic-overlay: 1.7.0
└─ swift-asn1: 1.4.0
```

### Package.swift Recommendation (if using SPM directly)

If you were to create a `Package.swift` (not needed for Xcode projects, but for reference):

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NFCDemo",
    platforms: [
        .iOS(.v17)
    ],
    dependencies: [
        .package(
            url: "https://github.com/supabase-community/supabase-swift",
            exact: "2.34.0"  // Lock to specific version
        )
    ],
    targets: [
        .target(
            name: "NFCDemo",
            dependencies: [
                .product(name: "Supabase", package: "supabase-swift")
            ]
        )
    ]
)
```

### Version Pinning in Xcode

To lock Supabase to a specific version in Xcode:
1. **File → Packages → Manage Swift Packages**
2. Select `supabase-swift`
3. Change "Up to Next Major Version" to "Exact Version: 2.34.0"

---

## 🔄 Migration Checklist (Future SPM Updates)

Before updating any SPM dependency:

- [ ] Check release notes for breaking API changes
- [ ] Verify package product names haven't changed
- [ ] Test in a separate branch first
- [ ] Run full build after updating
- [ ] Check for deprecation warnings
- [ ] Update import statements if needed

---

## 🚨 Common SPM Errors & Quick Fixes

### Error: "Missing package product"
**Cause:** Package renamed or removed product
**Fix:** Check package documentation for current product names

### Error: "Unable to find module dependency"
**Cause:** Internal module not exposed, or product not linked
**Fix:** Verify correct product is added to target dependencies

### Error: "Multiple commands produce Info.plist"
**Cause:** Both physical Info.plist and GENERATE_INFOPLIST_FILE = YES
**Fix:** Remove physical file, use INFOPLIST_KEY_* build settings

### Error: "Packages not supported with legacy build system"
**Cause:** BuildLocationStyle set to "UseTargetSettings"
**Fix:** Change to "UseAppPreferences" in workspace settings

---

## 📈 Build System Configuration

**Current Settings (Working):**
```xml
<!-- NFCDemo.xcodeproj/project.xcworkspace/xcuserdata/jew.xcuserdatad/WorkspaceSettings.xcsettings -->
<key>BuildLocationStyle</key>
<string>UseAppPreferences</string>

<key>BuildSystemType</key>
<string>Latest</string>
```

**Why This Matters:**
- `UseAppPreferences` = Modern build system (supports SPM)
- `UseTargetSettings` = Legacy build system (breaks SPM)

---

## 🎯 Verification Commands

### Check Current Package Versions
```bash
cd "/Volumes/JEW/NFC DEMO/NFC DEMO/NFCDemo"
xcodebuild -resolvePackageDependencies -scheme NFCDemo 2>&1 | grep "Resolved source packages" -A 10
```

### Verify Build Success
```bash
xcodebuild -scheme NFCDemo -destination 'generic/platform=iOS' build 2>&1 | grep "BUILD"
```

### List All Swift Package Dependencies
```bash
xcodebuild -showBuildSettings -scheme NFCDemo 2>&1 | grep SWIFT_PACKAGE
```

---

## 📚 Additional Resources

- [Supabase Swift v2 Migration Guide](https://github.com/supabase-community/supabase-swift/releases/tag/2.0.0)
- [Swift Package Manager Documentation](https://www.swift.org/package-manager/)
- [Xcode Build System Settings](https://developer.apple.com/documentation/xcode/build-system)

---

## 🎉 Success Criteria

Your build is successful if:
- ✅ `xcodebuild` completes with `** BUILD SUCCEEDED **`
- ✅ No "Missing package product" errors
- ✅ No "Unable to find module dependency" errors
- ✅ All packages resolve to stable versions
- ✅ Warnings only (no errors)

**Current Status: All criteria met! ✅**

---

*Last Updated: 2025-10-11*
*Supabase Swift SDK: 2.34.0*
*iOS SDK: 17.0+*
*Xcode: 15.0+*
