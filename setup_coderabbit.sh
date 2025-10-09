#!/bin/bash

# QuickStrap NFC - CodeRabbit Setup Script
# This script automates the CodeRabbit setup process

set -e  # Exit on any error

echo "🚀 QuickStrap NFC - CodeRabbit Setup"
echo "===================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Check if we're in the right directory
if [ ! -f "README.md" ] || [ ! -d ".git" ]; then
    print_error "Please run this script from the QuickStrap NFC root directory"
    exit 1
fi

print_info "Checking repository status..."

# Check git status
if ! git status &>/dev/null; then
    print_error "Not in a git repository"
    exit 1
fi

print_status "Git repository detected"

# Check if we have the feature branch
CURRENT_BRANCH=$(git branch --show-current)
print_info "Current branch: $CURRENT_BRANCH"

# Add and commit any remaining files
echo ""
print_info "Adding GitHub templates and CodeRabbit configuration..."

git add .github/ .coderabbit.yml setup_coderabbit.sh

if git diff --staged --quiet; then
    print_info "No new files to commit"
else
    git commit -m "ci: Add GitHub templates and CodeRabbit configuration

- Added pull request template with security checklist
- Added security vulnerability issue template  
- Added CodeRabbit configuration with security focus
- Added automated setup script for CodeRabbit integration"
    
    print_status "Committed GitHub templates and CodeRabbit config"
fi

# Push changes
print_info "Pushing changes to GitHub..."
git push

print_status "Changes pushed successfully"

echo ""
echo "🎯 CodeRabbit Setup Complete!"
echo "=============================="
echo ""

print_info "Next Steps:"
echo "1. 🌐 Go to: https://github.com/SkengMarn/QuickStrap-NFC"
echo "2. 🔧 Install CodeRabbit GitHub App:"
echo "   - Visit: https://github.com/apps/coderabbit-ai"
echo "   - Click 'Install'"
echo "   - Select your QuickStrap-NFC repository"
echo "3. 📝 Create Pull Request:"
echo "   - Go to your repository"
echo "   - Click 'Compare & pull request' for '$CURRENT_BRANCH'"
echo "   - Use the provided template"
echo "4. 🔍 CodeRabbit will automatically analyze your PR"

echo ""
print_info "Security Focus Areas for CodeRabbit:"
echo "   📁 TicketService.swift - SQL injection risks"
echo "   📁 SupabaseService.swift - Authentication security"  
echo "   📁 DatabaseScannerViewModel.swift - Input validation"
echo "   📁 AuthenticationView.swift - Token management"
echo "   📁 SecureTokenStorage.swift - Keychain security"

echo ""
print_info "Expected CodeRabbit Findings:"
echo "   🔥 Critical: SQL injection vulnerabilities"
echo "   ⚠️  High: Input validation gaps"
echo "   🟡 Medium: Error handling improvements"
echo "   🔵 Low: Code style optimizations"

echo ""
print_warning "Important Security Notes:"
echo "   - Remove exposed Telegram bot token from .claude/settings.local.json"
echo "   - Implement query parameterization in search methods"
echo "   - Add comprehensive input validation"
echo "   - Review token refresh logic"

echo ""
print_status "Repository is ready for CodeRabbit analysis!"
echo ""
echo "🔗 Quick Links:"
echo "   Repository: https://github.com/SkengMarn/QuickStrap-NFC"
echo "   CodeRabbit: https://coderabbit.ai/"
echo "   Create PR: https://github.com/SkengMarn/QuickStrap-NFC/compare"
echo ""
echo "Happy coding! 🚀"
