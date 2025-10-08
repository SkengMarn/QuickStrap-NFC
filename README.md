# QuickStrap NFC - Enhanced Event Management System

[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![iOS](https://img.shields.io/badge/iOS-15.0+-blue.svg)](https://developer.apple.com/ios/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## 🎯 Overview

QuickStrap NFC is a comprehensive event management system featuring NFC wristband scanning, intelligent ticket linking, and advanced security features. Built with Swift and SwiftUI, it provides a professional solution for event check-ins, fraud prevention, and real-time analytics.

## ✨ Key Features

### 🎫 Enhanced Ticket Linking System
- **Multiple Capture Methods**: Search, Ticket Number, Phone, Email, Barcode, QR Code
- **Professional Camera Integration**: AVFoundation-based scanning with overlay UI
- **Smart Fallback Logic**: Auto-tries alternative methods if primary fails
- **Configurable Interface**: Admin can set primary capture method
- **Persistent Preferences**: User settings saved across sessions

### 🔐 Security & Fraud Prevention
- **NFC Authentication**: Prevents counterfeit wristband usage
- **One Ticket = One Wristband**: Immutable linking system
- **Real-time Audit Trail**: Complete logging of all operations
- **Role-based Access Control**: Admin/Owner/Scanner permissions
- **Revenue Protection**: Measurable ROI through fraud prevention

### 📊 Intelligent Analytics
- **Re-entry Detection**: 30-minute window prevents duplicate logs
- **Gate Enforcement**: Category-based access control
- **Real-time Statistics**: Live scan counts and success rates
- **Fraud Analytics**: Security metrics and threat detection
- **Performance Monitoring**: System health and optimization

### 🚪 Virtual Gate System
- **Location-based Gates**: GPS and proximity detection
- **Dynamic Gate Creation**: AI-powered gate discovery
- **Gate Deduplication**: Intelligent consolidation of similar gates
- **Flexible Policies**: Customizable access rules per gate

## 🏗️ Architecture

### Core Components
- **MVVM Pattern**: Clean separation of concerns
- **SwiftUI Interface**: Modern, responsive UI
- **Supabase Backend**: Real-time database and authentication
- **Secure Token Storage**: iOS Keychain integration
- **NFC Integration**: Core NFC framework for wristband scanning

### Security Features
- **Encrypted Storage**: All sensitive data in iOS Keychain
- **JWT Authentication**: Secure token-based auth with refresh
- **Input Validation**: Comprehensive sanitization
- **SQL Injection Prevention**: Parameterized queries
- **Biometric Authentication**: Face ID/Touch ID support

## 🚀 Quick Start

### Prerequisites
- Xcode 15.0+
- iOS 15.0+
- Supabase account
- NFC-enabled iOS device for testing

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/SkengMarn/QuickStrap-NFC.git
   cd QuickStrap-NFC
   ```

2. **Configure Supabase**
   ```bash
   # Copy configuration template
   cp "NFC DEMO/NFCDemo/NFCDemo/Config/Config.plist.example" "NFC DEMO/NFCDemo/NFCDemo/Config/Config.plist"
   
   # Edit with your Supabase credentials
   # Add SUPABASE_URL and SUPABASE_ANON_KEY
   ```

3. **Open in Xcode**
   ```bash
   open "NFC DEMO/NFCDemo/NFCDemo.xcodeproj"
   ```

4. **Build and Run**
   - Select your target device
   - Build and run the project
   - Grant NFC and camera permissions when prompted

## 📱 Usage

### Basic Workflow
1. **Authentication**: Sign in with credentials or biometric auth
2. **Event Selection**: Choose your event from the list
3. **Gate Detection**: System automatically detects nearby gates
4. **NFC Scanning**: Scan wristbands for check-in
5. **Ticket Linking**: Link tickets when required by event settings

### Advanced Features
- **Manual Check-in**: Enter wristband IDs manually
- **Bulk Operations**: Process multiple check-ins
- **Analytics Dashboard**: View real-time statistics
- **Gate Management**: Configure access policies
- **Fraud Detection**: Monitor suspicious activities

## 🔧 Configuration

### Event Settings
- **Ticket Linking Mode**: Disabled/Optional/Required
- **Gate Policies**: Category-based access rules
- **Re-entry Window**: Configurable time limits
- **Security Level**: Fraud detection sensitivity

### Admin Controls
- **User Management**: Role assignments and permissions
- **Gate Configuration**: Virtual gate setup and policies
- **Security Settings**: Fraud prevention parameters
- **Analytics Config**: Reporting and monitoring setup

## 🛡️ Security

### Recent Security Audit
This repository includes a comprehensive security audit identifying:
- **SQL Injection Risks**: In search query implementations
- **Input Validation**: Areas needing sanitization
- **Token Management**: Authentication security improvements
- **Code Quality**: Best practices and optimizations

### Security Best Practices
- All sensitive data encrypted in iOS Keychain
- JWT tokens with automatic refresh
- Comprehensive input validation
- SQL injection prevention
- Secure network communication (HTTPS only)

## 📊 Performance

### Optimizations
- **Efficient Database Queries**: Indexed searches and pagination
- **Memory Management**: Proper cleanup and lifecycle handling
- **Background Processing**: Non-blocking operations
- **Caching Strategy**: Smart data caching for offline support

### Monitoring
- Real-time performance metrics
- Error tracking and logging
- Network usage optimization
- Battery usage monitoring

## 🧪 Testing

### Test Coverage
- Unit tests for core business logic
- Integration tests for API interactions
- UI tests for critical user flows
- Security tests for vulnerability assessment

### Running Tests
```bash
# Run unit tests
xcodebuild test -project "NFC DEMO/NFCDemo/NFCDemo.xcodeproj" -scheme NFCDemo -destination 'platform=iOS Simulator,name=iPhone 15'

# Run security tests
xcodebuild test -project "NFC DEMO/NFCDemo/NFCDemo.xcodeproj" -scheme NFCDemo -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:NFCDemoTests/SecurityTests
```

## 📚 Documentation

### API Documentation
- [Supabase Integration Guide](NFC%20DEMO/NFCDemo/SUPABASE_DEPLOYMENT_GUIDE.md)
- [Production Deployment](NFC%20DEMO/NFCDemo/PRODUCTION_DEPLOYMENT_GUIDE.md)
- [Security Best Practices](NFC%20DEMO/NFCDemo/SECURITY_GUIDE.md)

### Development Guides
- [Swift 6 Migration](NFC%20DEMO/NFCDemo/SWIFT6_FIXES_SUMMARY.md)
- [Virtual Gates Implementation](NFC%20DEMO/NFCDemo/VIRTUAL_GATES_IMPLEMENTATION.md)
- [Enhanced Functions Usage](NFC%20DEMO/NFCDemo/ENHANCED_FUNCTIONS_USAGE.md)

## 🤝 Contributing

### Development Setup
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass
6. Commit your changes (`git commit -m 'Add amazing feature'`)
7. Push to the branch (`git push origin feature/amazing-feature`)
8. Open a Pull Request

### Code Standards
- Follow Swift API Design Guidelines
- Maintain test coverage above 80%
- Use SwiftLint for code style consistency
- Document public APIs with Swift DocC
- Security-first development approach

## 🐛 Issues & Support

### Reporting Issues
- Use GitHub Issues for bug reports
- Include device information and iOS version
- Provide steps to reproduce
- Include relevant logs and screenshots

### Security Issues
- Report security vulnerabilities privately
- Email: security@quickstrap.com
- Include detailed reproduction steps
- Allow reasonable time for response

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **Core NFC Framework**: Apple's NFC implementation
- **Supabase**: Backend-as-a-Service platform
- **SwiftUI**: Modern iOS UI framework
- **AVFoundation**: Camera and media processing

## 📈 Roadmap

### Upcoming Features
- [ ] **CSV Ticket Import**: Bulk ticket upload functionality
- [ ] **Multi-language Support**: Internationalization
- [ ] **Apple Watch Integration**: Wrist-based scanning
- [ ] **Advanced Analytics**: Machine learning insights
- [ ] **API Integration**: Third-party ticketing systems

### Performance Improvements
- [ ] **Offline Mode**: Enhanced offline capabilities
- [ ] **Background Sync**: Automatic data synchronization
- [ ] **Memory Optimization**: Reduced memory footprint
- [ ] **Battery Efficiency**: Power usage optimization

---

## 🔗 Quick Links

- **Live Demo**: [Coming Soon]
- **Documentation**: [Wiki](../../wiki)
- **Issues**: [GitHub Issues](../../issues)
- **Discussions**: [GitHub Discussions](../../discussions)
- **Security**: [Security Policy](SECURITY.md)

---

**Built with ❤️ for the event management community**
