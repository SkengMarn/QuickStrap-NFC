#!/bin/bash

# CodeRabbit Analysis Script for NFC Demo
# This script prepares files for CodeRabbit review

echo "🔍 Preparing CodeRabbit Analysis for NFC Demo"
echo "=============================================="

# Create analysis directory
mkdir -p coderabbit_analysis

# Copy critical security files for review
echo "📁 Copying security-critical files..."

# Core service files (highest priority for security review)
cp "NFC DEMO/NFCDemo/NFCDemo/Services/TicketService.swift" coderabbit_analysis/
cp "NFC DEMO/NFCDemo/NFCDemo/Services/SupabaseService.swift" coderabbit_analysis/
cp "NFC DEMO/NFCDemo/NFCDemo/ViewModels/DatabaseScannerViewModel.swift" coderabbit_analysis/

# Authentication and security files
cp "NFC DEMO/NFCDemo/NFCDemo/Views/AuthenticationView.swift" coderabbit_analysis/
cp "NFC DEMO/NFCDemo/NFCDemo/Security/SecureTokenStorage.swift" coderabbit_analysis/

# New ticket linking files
cp "NFC DEMO/NFCDemo/NFCDemo/Services/TicketScannerService.swift" coderabbit_analysis/
cp "NFC DEMO/NFCDemo/NFCDemo/Views/TicketLinkingView.swift" coderabbit_analysis/
cp "NFC DEMO/NFCDemo/NFCDemo/Models/TicketModels.swift" coderabbit_analysis/

# Configuration files
cp "NFC DEMO/NFCDemo/NFCDemo/Info.plist" coderabbit_analysis/

# Create analysis summary
cat > coderabbit_analysis/SECURITY_FOCUS_AREAS.md << 'EOF'
# 🔐 CodeRabbit Security Analysis Focus Areas

## 🚨 Critical Priority Files

### 1. TicketService.swift
**Issues to Review:**
- SQL injection in search queries (lines 154, 158, 163, 167, 171)
- Direct string interpolation in database endpoints
- Input validation gaps

**Example Vulnerable Code:**
```swift
endpoint = "rest/v1/tickets?...&ticket_number.ilike.*\(searchQuery)*"
```

### 2. SupabaseService.swift
**Issues to Review:**
- Token management security
- API key handling
- Authentication flow vulnerabilities

### 3. DatabaseScannerViewModel.swift
**Issues to Review:**
- NFC data validation
- Error handling security
- Force unwrap removal (recently fixed)

## 🔍 Security Patterns to Check

### Input Validation
- [ ] All user inputs properly sanitized
- [ ] SQL injection prevention
- [ ] XSS prevention in web views
- [ ] Path traversal prevention

### Authentication & Authorization
- [ ] Token storage security
- [ ] Session management
- [ ] Permission checks
- [ ] Biometric authentication security

### Data Protection
- [ ] Sensitive data encryption
- [ ] Keychain usage patterns
- [ ] Network communication security
- [ ] Local data storage security

## 🎯 Expected Findings

Based on our audit, CodeRabbit should flag:

1. **Critical**: SQL injection vulnerabilities
2. **High**: Input validation gaps
3. **Medium**: Error handling improvements
4. **Low**: Code style optimizations

## 📋 Remediation Checklist

After CodeRabbit analysis:
- [ ] Fix all Critical security issues
- [ ] Implement proper query parameterization
- [ ] Add comprehensive input validation
- [ ] Review and fix authentication flows
- [ ] Update error handling patterns
EOF

echo "✅ Analysis files prepared in ./coderabbit_analysis/"
echo ""
echo "🚀 Next Steps:"
echo "1. Upload ./coderabbit_analysis/ folder to CodeRabbit web interface"
echo "2. Or push to GitHub and use CodeRabbit GitHub integration"
echo "3. Focus review on files listed in SECURITY_FOCUS_AREAS.md"
echo ""
echo "🔗 CodeRabbit Links:"
echo "   Web: https://coderabbit.ai/"
echo "   Docs: https://docs.coderabbit.ai/"
echo ""
echo "📊 Priority Files for Review:"
ls -la coderabbit_analysis/*.swift | head -5
