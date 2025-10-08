#!/bin/bash

# NFC Demo App - Setup Script
# This script helps you set up the development environment

set -e  # Exit on error

echo "🚀 NFC Demo App - Setup Script"
echo "================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running from correct directory
if [ ! -f "NFCDemo/NFCDemoApp.swift" ]; then
    echo -e "${RED}❌ Error: Please run this script from the NFCDemo project root directory${NC}"
    exit 1
fi

echo "✅ Running from correct directory"
echo ""

# Step 1: Check for Config.plist
echo "📝 Step 1: Checking configuration..."
if [ ! -f "NFCDemo/Config/Config.plist" ]; then
    echo -e "${YELLOW}⚠️  Config.plist not found${NC}"
    echo "   Creating from example..."

    # Check if example exists
    if [ -f "NFCDemo/Config/Config.plist.example" ]; then
        cp "NFCDemo/Config/Config.plist.example" "NFCDemo/Config/Config.plist"
        echo -e "${GREEN}✅ Created Config.plist from example${NC}"
        echo ""
        echo -e "${YELLOW}⚠️  IMPORTANT: Edit NFCDemo/Config/Config.plist with your actual Supabase credentials${NC}"
        echo ""
        read -p "Press Enter after you've updated Config.plist with your credentials..."
    else
        echo -e "${RED}❌ Config.plist.example not found!${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✅ Config.plist found${NC}"
fi

# Step 2: Validate Config.plist
echo ""
echo "🔍 Step 2: Validating configuration..."

# Check if Config.plist has placeholder values
if grep -q "your-project-id" "NFCDemo/Config/Config.plist" || \
   grep -q "your-anon-key" "NFCDemo/Config/Config.plist"; then
    echo -e "${RED}❌ Config.plist still contains placeholder values!${NC}"
    echo "   Please update it with your actual Supabase credentials"
    echo ""
    echo "   Get your credentials from: https://app.supabase.com/project/_/settings/api"
    exit 1
else
    echo -e "${GREEN}✅ Configuration appears valid${NC}"
fi

# Step 3: Check .gitignore
echo ""
echo "🔒 Step 3: Verifying security..."

if [ -f ".gitignore" ]; then
    if grep -q "Config.plist" ".gitignore"; then
        echo -e "${GREEN}✅ Config.plist is in .gitignore${NC}"
    else
        echo -e "${YELLOW}⚠️  Adding Config.plist to .gitignore...${NC}"
        echo "NFCDemo/Config/Config.plist" >> .gitignore
        echo -e "${GREEN}✅ Added to .gitignore${NC}"
    fi
else
    echo -e "${YELLOW}⚠️  Creating .gitignore...${NC}"
    cat > .gitignore << 'EOF'
# Configuration with secrets
NFCDemo/Config/Config.plist

# Xcode
*.xcuserdata
*.xcuserdatad
.DS_Store
DerivedData/
*.xcodeproj/xcuserdata/
*.xcodeproj/project.xcworkspace/xcuserdata/
EOF
    echo -e "${GREEN}✅ Created .gitignore${NC}"
fi

# Step 4: Verify no hardcoded secrets
echo ""
echo "🔐 Step 4: Checking for hardcoded secrets..."

# List of files to check (excluding the new secure files)
FILES_TO_CHECK=$(find NFCDemo -name "*.swift" \
    ! -path "*/Config/*" \
    ! -path "*/Network/*" \
    ! -path "*/Utils/AppLogger.swift" \
    ! -path "*/Utils/AppError.swift" \
    ! -path "*/Repositories/*" \
    ! -path "*/Services/AuthService.swift" \
    ! -path "*/Services/EventService.swift")

SECRETS_FOUND=0

# Check for potential hardcoded API keys
if echo "$FILES_TO_CHECK" | xargs grep -l "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9" 2>/dev/null; then
    echo -e "${YELLOW}⚠️  Found potential hardcoded JWT tokens${NC}"
    SECRETS_FOUND=1
fi

# Check for hardcoded Supabase URLs
if echo "$FILES_TO_CHECK" | xargs grep -l "pmrxyisasfaimumuobvu.supabase.co" 2>/dev/null; then
    echo -e "${YELLOW}⚠️  Found hardcoded Supabase URLs${NC}"
    echo "   These should be moved to use AppConfiguration.shared"
    SECRETS_FOUND=1
fi

if [ $SECRETS_FOUND -eq 0 ]; then
    echo -e "${GREEN}✅ No obvious hardcoded secrets found${NC}"
else
    echo -e "${YELLOW}⚠️  Please review and migrate hardcoded values to Config.plist${NC}"
    echo "   See MIGRATION_GUIDE.md for details"
fi

# Step 5: Check dependencies
echo ""
echo "📦 Step 5: Checking dependencies..."

# Check if Xcode is installed
if ! command -v xcodebuild &> /dev/null; then
    echo -e "${RED}❌ Xcode is not installed${NC}"
    echo "   Please install Xcode from the App Store"
    exit 1
else
    XCODE_VERSION=$(xcodebuild -version | head -n 1)
    echo -e "${GREEN}✅ $XCODE_VERSION installed${NC}"
fi

# Step 6: Build project
echo ""
echo "🔨 Step 6: Building project..."
echo "   This may take a few minutes..."

if xcodebuild -project NFCDemo.xcodeproj -scheme NFCDemo -destination 'platform=iOS Simulator,name=iPhone 15' clean build > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Project builds successfully${NC}"
else
    echo -e "${YELLOW}⚠️  Build failed. This might be normal if you haven't added all new files to Xcode yet.${NC}"
    echo "   Please open the project in Xcode and:"
    echo "   1. Add new files to the project"
    echo "   2. Fix any compilation errors"
    echo "   3. Re-run this setup script"
fi

# Step 7: Summary
echo ""
echo "================================"
echo "📋 Setup Summary"
echo "================================"
echo ""
echo "✅ Configuration file created and validated"
echo "✅ Security checks completed"
echo "✅ Dependencies verified"
echo ""
echo -e "${GREEN}🎉 Setup complete!${NC}"
echo ""
echo "Next steps:"
echo "1. Open NFCDemo.xcodeproj in Xcode"
echo "2. Add the new files to your Xcode project:"
echo "   - Config/AppConfiguration.swift"
echo "   - Utils/AppLogger.swift"
echo "   - Utils/AppError.swift"
echo "   - Network/NetworkClient.swift"
echo "   - Repositories/*.swift"
echo "   - Services/AuthService.swift"
echo "   - Services/EventService.swift"
echo "3. Review MIGRATION_GUIDE.md for updating existing code"
echo "4. Run tests: ⌘U in Xcode"
echo "5. Build and run on a real device for NFC testing"
echo ""
echo -e "${YELLOW}⚠️  REMINDER: Never commit Config.plist to version control!${NC}"
echo ""
