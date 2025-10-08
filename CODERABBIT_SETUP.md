# CodeRabbit Setup Instructions

## 🚀 Quick Setup Guide

### 1. Create GitHub Repository
1. Go to https://github.com/new
2. Repository name: `nfc-demo-enhanced`
3. Make it **Private** (recommended)
4. **Don't** initialize with README
5. Click "Create repository"

### 2. Connect Local Repository
```bash
cd "/Volumes/JEW/NFC DEMO"

# Add your GitHub repository as origin (replace with your actual repo URL)
git remote add origin https://github.com/YOUR-USERNAME/nfc-demo-enhanced.git

# Push main branch
git branch -M main
git push -u origin main

# Push the CodeRabbit feature branch
git push origin feature/coderabbit-security-enhancements
```

### 3. Install CodeRabbit
1. Go to https://coderabbit.ai/
2. Click "Sign up with GitHub"
3. Install the CodeRabbit GitHub App
4. Select your `nfc-demo-enhanced` repository
5. Grant necessary permissions

### 4. Create Pull Request for Review
1. Go to your GitHub repository
2. Click "Compare & pull request" for `feature/coderabbit-security-enhancements`
3. Title: "Enhanced Ticket Linking System + Security Improvements"
4. Add description (see below)
5. Create the pull request

### 5. Pull Request Description Template
```markdown
## 🎯 Enhanced Ticket Linking System

This PR implements a comprehensive multi-method ticket capture system with security improvements.

### 🚀 New Features
- **Multiple Capture Methods**: Search, Ticket Number, Phone, Email, Barcode, QR Code
- **Professional Camera Integration**: AVFoundation-based scanning with overlay UI
- **Smart Fallback Logic**: Auto-tries alternative methods if primary fails
- **Configurable Interface**: Admin can set primary capture method

### 🔐 Security Improvements
- Fixed camera permission crashes
- Enhanced error handling and crash prevention
- Removed dangerous force unwraps
- Fixed invalid SF Symbol usage

### ⚠️ Security Review Needed
- **SQL Injection Risks**: Search queries need parameterization
- **Exposed Secrets**: Telegram bot token in config files
- **Input Validation**: User inputs need sanitization

### 📁 Files Added
- `TicketScannerService.swift` - Camera scanning service
- `TicketCaptureSettingsView.swift` - Admin configuration
- Enhanced `TicketModels.swift` - Capture method enums

### 🎯 CodeRabbit Focus Areas
Please review for:
- Security vulnerabilities (especially SQL injection)
- Input validation improvements
- Token management security
- Code quality and best practices
```

## 🔍 What CodeRabbit Will Analyze

### Security Issues
- SQL injection vulnerabilities in search queries
- Exposed secrets and tokens
- Input validation gaps
- Authentication weaknesses

### Code Quality
- Swift best practices
- Memory management
- Error handling patterns
- Performance optimizations

### Architecture
- MVVM pattern compliance
- Separation of concerns
- Dependency management
- Code organization

## 📊 Expected CodeRabbit Findings

Based on our security audit, CodeRabbit should identify:

1. **Critical**: Exposed Telegram bot token in `.claude/settings.local.json`
2. **High**: SQL injection risks in `TicketService.swift` search methods
3. **Medium**: Input validation improvements needed
4. **Low**: Code style and optimization suggestions

## 🛠️ After CodeRabbit Review

1. **Address Critical Issues** immediately
2. **Implement High Priority** fixes
3. **Consider Medium Priority** improvements
4. **Apply Code Style** suggestions as appropriate

## 📞 Need Help?

If you encounter issues:
1. Check CodeRabbit documentation: https://docs.coderabbit.ai/
2. Ensure GitHub App permissions are correct
3. Verify repository access settings
4. Contact CodeRabbit support if needed
