#!/bin/bash

# Fix Xcode Indexing Issues
# Run this script when Xcode shows false errors but builds succeed

echo "🔧 Fixing Xcode indexing issues..."
echo ""

# Kill Xcode processes
echo "1️⃣ Stopping Xcode processes..."
killall Xcode 2>/dev/null || true
killall com.apple.dt.SKAgent 2>/dev/null || true
killall sourcekit-lsp 2>/dev/null || true
killall SourceKitService 2>/dev/null || true
sleep 2

# Clear caches
echo "2️⃣ Clearing caches..."
rm -rf ~/Library/Developer/Xcode/DerivedData/NFCDemo-*
rm -rf ~/Library/Caches/com.apple.dt.Xcode/ModuleCache.noindex/*
rm -rf ~/Library/Caches/org.swift.swiftpm/
rm -rf ~/Library/Developer/Xcode/UserData/IDEEditorInteractivityHistory/*

# Touch project files to trigger re-indexing
echo "3️⃣ Touching Swift files..."
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
find "$SCRIPT_DIR/NFCDemo" -name "*.swift" -type f -exec touch {} \;

echo ""
echo "✅ Done!"
echo ""
echo "Next steps:"
echo "  1. Open Xcode"
echo "  2. Open your project: NFCDemo.xcodeproj"
echo "  3. Wait for indexing (watch the top bar)"
echo "  4. Build (⌘B)"
echo ""
echo "Errors should be resolved!"
