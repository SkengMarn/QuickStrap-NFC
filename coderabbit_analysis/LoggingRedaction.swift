import Foundation

// MARK: - Logging Redaction Utilities

/// Security utility for redacting sensitive information from logs
enum LogRedaction {

    /// Patterns for sensitive data that should be redacted
    private static let sensitivePatterns: [(name: String, pattern: String, replacement: String)] = [
        // Auth tokens
        ("JWT Token", "eyJ[A-Za-z0-9_-]*\\.[A-Za-z0-9_-]*\\.[A-Za-z0-9_-]*", "[JWT_REDACTED]"),
        ("Bearer Token", "Bearer\\s+[A-Za-z0-9_-]+", "Bearer [TOKEN_REDACTED]"),

        // API Keys
        ("Supabase Key", "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9\\.[A-Za-z0-9_-]+", "[SUPABASE_KEY_REDACTED]"),
        ("API Key", "(?i)(api[_-]?key|apikey)\\s*[=:]\\s*['\"]?([A-Za-z0-9_-]{20,})", "$1=[API_KEY_REDACTED]"),

        // Personal Information
        ("Email", "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}", "[EMAIL_REDACTED]"),
        ("Phone", "\\+?1?[-.]?\\(?\\d{3}\\)?[-.]?\\d{3}[-.]?\\d{4}", "[PHONE_REDACTED]"),
        ("SSN", "\\d{3}-\\d{2}-\\d{4}", "[SSN_REDACTED]"),

        // UUIDs (partially redact to keep format recognizable)
        ("UUID", "([0-9a-f]{8})-([0-9a-f]{4})-([0-9a-f]{4})-([0-9a-f]{4})-([0-9a-f]{12})", "$1-****-****-****-************"),

        // Credit Cards
        ("Credit Card", "\\b\\d{4}[-\\s]?\\d{4}[-\\s]?\\d{4}[-\\s]?\\d{4}\\b", "[CC_REDACTED]"),

        // Passwords in logs
        ("Password Field", "(?i)(password|passwd|pwd)\\s*[=:]\\s*['\"]?([^'\"\\s]+)", "$1=[PASSWORD_REDACTED]"),

        // URLs with potential secrets
        ("URL with Token", "(https?://[^/]+/[^?]*\\?)([^\\s]+)", "$1[PARAMS_REDACTED]")
    ]

    /// Redacts sensitive information from a string for safe logging
    /// - Parameter message: The message to redact
    /// - Returns: Redacted message safe for logging
    static func redact(_ message: String) -> String {
        var redacted = message

        for (_, pattern, replacement) in sensitivePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(redacted.startIndex..., in: redacted)
                redacted = regex.stringByReplacingMatches(
                    in: redacted,
                    options: [],
                    range: range,
                    withTemplate: replacement
                )
            }
        }

        return redacted
    }

    /// Redacts a specific type of sensitive data
    /// - Parameters:
    ///   - value: The value to redact
    ///   - type: Type of data (for appropriate redaction level)
    /// - Returns: Redacted value
    static func redact(_ value: String, type: RedactionType) -> String {
        switch type {
        case .token:
            return redactToken(value)
        case .email:
            return redactEmail(value)
        case .phone:
            return redactPhone(value)
        case .uuid:
            return redactUUID(value)
        case .nfcId:
            return redactNFCId(value)
        case .full:
            return "[REDACTED]"
        }
    }

    /// Types of redaction strategies
    enum RedactionType {
        case token      // Full redaction for security tokens
        case email      // Partial redaction showing domain
        case phone      // Partial redaction showing last 4 digits
        case uuid       // Partial redaction showing first segment
        case nfcId      // Partial redaction for debugging
        case full       // Complete redaction
    }

    // MARK: - Specific Redaction Methods

    private static func redactToken(_ token: String) -> String {
        guard token.count > 8 else { return "[TOKEN_TOO_SHORT]" }
        let prefix = String(token.prefix(4))
        let suffix = String(token.suffix(4))
        return "\(prefix)***\(suffix) [\(token.count) chars]"
    }

    private static func redactEmail(_ email: String) -> String {
        let components = email.split(separator: "@")
        guard components.count == 2 else { return "[INVALID_EMAIL]" }

        let username = String(components[0])
        let domain = String(components[1])

        if username.count <= 2 {
            return "**@\(domain)"
        } else {
            let visibleChars = min(2, username.count)
            return "\(username.prefix(visibleChars))***@\(domain)"
        }
    }

    private static func redactPhone(_ phone: String) -> String {
        let digits = phone.filter { $0.isNumber }
        guard digits.count >= 4 else { return "[PHONE_REDACTED]" }
        return "***-***-\(digits.suffix(4))"
    }

    private static func redactUUID(_ uuid: String) -> String {
        let components = uuid.split(separator: "-")
        guard components.count == 5 else { return "[INVALID_UUID]" }
        return "\(components[0])-****-****-****-************"
    }

    private static func redactNFCId(_ nfcId: String) -> String {
        guard nfcId.count > 6 else { return "[NFC_REDACTED]" }
        let prefix = String(nfcId.prefix(3))
        let suffix = String(nfcId.suffix(3))
        return "\(prefix)***\(suffix)"
    }
}

// MARK: - Secure Logger

/// Thread-safe logger with automatic redaction
class SecureLogger {
    static let shared = SecureLogger()

    private let queue = DispatchQueue(label: "com.nfcdemo.securelogger", qos: .utility)
    private var isEnabled = true

    #if DEBUG
    private var logLevel: LogLevel = .debug
    #else
    private var logLevel: LogLevel = .info
    #endif

    enum LogLevel: Int, Comparable {
        case debug = 0
        case info = 1
        case warning = 2
        case error = 3
        case critical = 4

        static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }

        var prefix: String {
            switch self {
            case .debug: return "🔍 DEBUG"
            case .info: return "ℹ️ INFO"
            case .warning: return "⚠️ WARN"
            case .error: return "❌ ERROR"
            case .critical: return "🔥 CRITICAL"
            }
        }
    }

    /// Logs a message with automatic redaction
    func log(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        queue.async { [weak self] in
            guard let self = self, self.isEnabled, level >= self.logLevel else { return }

            let fileName = (file as NSString).lastPathComponent
            let redactedMessage = LogRedaction.redact(message)
            let timestamp = ISO8601DateFormatter().string(from: Date())

            let logEntry = "[\(timestamp)] \(level.prefix) [\(fileName):\(line)] \(function) - \(redactedMessage)"

            #if DEBUG
            print(logEntry)
            #else
            // In production, send to secure logging service
            self.sendToLoggingService(logEntry, level: level)
            #endif
        }
    }

    /// Logs with specific redaction type for a value
    func log(_ message: String, redacting value: String, as type: LogRedaction.RedactionType, level: LogLevel = .info) {
        let redactedValue = LogRedaction.redact(value, type: type)
        let fullMessage = message.replacingOccurrences(of: value, with: redactedValue)
        log(fullMessage, level: level)
    }

    private func sendToLoggingService(_ message: String, level: LogLevel) {
        // TODO: Implement secure logging service integration
        // Options: CloudWatch, Datadog, Sentry, etc.
        // Ensure logging service connection is encrypted
        // Never send unredacted messages to external services
    }
}

// MARK: - Convenience Extensions

extension String {
    /// Returns a redacted version of this string safe for logging
    var redacted: String {
        LogRedaction.redact(self)
    }

    /// Returns a redacted version with specific redaction type
    func redacted(as type: LogRedaction.RedactionType) -> String {
        LogRedaction.redact(self, type: type)
    }
}

// MARK: - Global Logging Functions

/// Secure logging function with automatic redaction
func secureLog(_ message: String, level: SecureLogger.LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
    SecureLogger.shared.log(message, level: level, file: file, function: function, line: line)
}

/// Secure logging with explicit redaction
func secureLog(_ message: String, redacting value: String, as type: LogRedaction.RedactionType, level: SecureLogger.LogLevel = .info) {
    SecureLogger.shared.log(message, redacting: value, as: type, level: level)
}
