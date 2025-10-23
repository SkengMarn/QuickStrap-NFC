#!/bin/bash

# Swift Package Manager Cleanup Script
# Resolves corrupted caches and build artifacts
# Usage: ./cleanup-spm.sh [project_directory]
#   project_directory: Optional path to the project root (defaults to git root or current directory)

set -e  # Exit on error
set -o pipefail  # Ensure piped commands fail if any part fails

# Determine project directory from argument, git root, or current directory
PROJECT_DIR="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}/NFC DEMO/NFCDemo"
PROJECT_NAME="NFCDemo"

echo "🧹 Swift Package Manager Cleanup Script"
echo "========================================"
echo ""

# Step 1: Clean DerivedData
echo "📦 Step 1/5: Cleaning DerivedData..."
rm -rf ~/Library/Developer/Xcode/DerivedData/${PROJECT_NAME}-*
echo "✅ DerivedData cleaned"
echo ""

# Step 2: Clean SPM caches
echo "🗑️  Step 2/5: Cleaning SPM repository cache..."
rm -rf ~/Library/Caches/org.swift.swiftpm/repositories/
echo "✅ Repository cache cleaned"
echo ""

echo "🗑️  Step 3/5: Cleaning SPM manifest cache..."
rm -rf ~/Library/Caches/org.swift.swiftpm/manifests/
echo "✅ Manifest cache cleaned"
echo ""

# Step 4: Navigate to project and resolve packages
echo "🔄 Step 4/5: Resolving package dependencies..."
cd "${PROJECT_DIR}"
if xcodebuild -resolvePackageDependencies -scheme "${PROJECT_NAME}" 2>&1 | tee /dev/tty | grep -qE "(error|failed)"; then
  echo "❌ Package resolution failed"
  exit 1
fi
echo "✅ Packages resolved"
echo ""

# Step 5: Clean and verify build
echo "🔨 Step 5/5: Testing clean build..."
BUILD_OUTPUT=$(mktemp)
if ! xcodebuild -scheme "${PROJECT_NAME}" -destination 'generic/platform=iOS' clean build 2>&1 | tee "${BUILD_OUTPUT}"; then
  echo "❌ Build failed. Recent output:"
  grep -E "(BUILD|error:)" "${BUILD_OUTPUT}" | tail -5
  rm -f "${BUILD_OUTPUT}"
  exit 1
fi
grep -E "(BUILD|error:)" "${BUILD_OUTPUT}" | tail -5
rm -f "${BUILD_OUTPUT}"
echo ""

echo "🎉 Cleanup complete!"
echo ""
echo "📊 Current package status:"
xcodebuild -resolvePackageDependencies -scheme "${PROJECT_NAME}" 2>&1 | grep "Resolved source packages" -A 10 || echo "✅ All packages resolved successfully"
