import Foundation
import os.log

/// Enterprise-grade logging system that replaces print statements
/// Provides structured logging with proper security and performance considerations
enum LogLevel: String, CaseIterable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
    case critical = "CRITICAL"
    
    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        case .critical: return .fault
        }
    }
}

struct Logger {
    private static let subsystem = "com.jawal.nfcdemo"
    private static let maxLogLength = 1000 // Prevent memory issues with large logs
    
    /// Log a message with specified level and category
    /// - Parameters:
    ///   - message: The message to log
    ///   - level: The log level (debug, info, warning, error, critical)
    ///   - category: The category for grouping logs (e.g., "Security", "Network", "Performance")
    ///   - file: Source file (automatically filled)
    ///   - function: Source function (automatically filled)
    ///   - line: Source line (automatically filled)
    static func log(_ message: String,
                   level: LogLevel = .info,
                   category: String = "General",
                   file: String = #file,
                   function: String = #function,
                   line: Int = #line) {
        
        let logger = os.Logger(subsystem: subsystem, category: category)
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let location = "\(fileName):\(function):\(line)"
        
        // Sanitize message to prevent sensitive data leakage
        let sanitizedMessage = sanitizeMessage(message)
        let truncatedMessage = String(sanitizedMessage.prefix(maxLogLength))
        
        let logMessage = "[\(location)] \(truncatedMessage)"
        
        switch level {
        case .debug:
            #if DEBUG
            logger.log(level: level.osLogType, "\(logMessage)")
            #endif
        case .info:
            logger.log(level: level.osLogType, "\(logMessage)")
        case .warning:
            logger.log(level: level.osLogType, "⚠️ \(logMessage)")
        case .error:
            logger.log(level: level.osLogType, "❌ \(logMessage)")
        case .critical:
            logger.log(level: level.osLogType, "🚨 CRITICAL: \(logMessage)")
            
            // For critical errors, also log to crash reporting if available
            #if DEBUG
            assertionFailure("Critical error: \(sanitizedMessage)")
            #endif
        }
    }
    
    /// Sanitize log messages to prevent sensitive data exposure
    private static func sanitizeMessage(_ message: String) -> String {
        var sanitized = message
        
        // Remove common sensitive patterns
        let sensitivePatterns = [
            // Tokens and keys
            ("Bearer [A-Za-z0-9._-]+", "Bearer [REDACTED]"),
            ("token[\"']?\\s*[:=]\\s*[\"']?[A-Za-z0-9._-]+", "token: [REDACTED]"),
            ("key[\"']?\\s*[:=]\\s*[\"']?[A-Za-z0-9._-]+", "key: [REDACTED]"),
            ("password[\"']?\\s*[:=]\\s*[\"']?[^\\s\"']+", "password: [REDACTED]"),
            
            // Email patterns (partial redaction)
            ("([a-zA-Z0-9._%+-]+)@([a-zA-Z0-9.-]+\\.[a-zA-Z]{2,})", "$1@[REDACTED]"),
            
            // Credit card numbers
            ("\\b\\d{4}[\\s-]?\\d{4}[\\s-]?\\d{4}[\\s-]?\\d{4}\\b", "[CARD-REDACTED]"),
            
            // Phone numbers
            ("\\b\\d{3}[-.\\s]?\\d{3}[-.\\s]?\\d{4}\\b", "[PHONE-REDACTED]"),
            
            // JWT tokens
            ("eyJ[A-Za-z0-9_-]*\\.[A-Za-z0-9_-]*\\.[A-Za-z0-9_-]*", "[JWT-REDACTED]")
        ]
        
        for (pattern, replacement) in sensitivePatterns {
            sanitized = sanitized.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }
        
        return sanitized
    }
}

// MARK: - Specialized Logging Methods
extension Logger {
    /// Log authentication events with enhanced security
    static func logAuth(_ message: String, success: Bool, userID: String? = nil) {
        let status = success ? "SUCCESS" : "FAILURE"
        let userInfo = userID.map { "User: \(String($0.prefix(8)))***" } ?? "Unknown user"
        
        log("AUTH \(status): \(message) - \(userInfo)",
            level: success ? .info : .warning,
            category: "Authentication")
    }
    
    /// Log network requests with performance metrics
    static func logNetwork(_ endpoint: String, method: String, duration: TimeInterval, statusCode: Int? = nil) {
        let status = statusCode.map { "Status: \($0)" } ?? "No response"
        let performance = duration > 1.0 ? "SLOW" : "OK"
        
        log("NETWORK [\(performance)] \(method) \(endpoint) - \(status) (\(String(format: "%.2f", duration))s)",
            level: duration > 2.0 ? .warning : .info,
            category: "Network")
    }
    
    /// Log performance metrics
    static func logPerformance(_ operation: String, duration: TimeInterval, memoryUsage: UInt64? = nil) {
        var message = "PERF \(operation): \(String(format: "%.2f", duration))s"
        
        if let memory = memoryUsage {
            let memoryMB = Double(memory) / 1024.0 / 1024.0
            message += ", Memory: \(String(format: "%.1f", memoryMB))MB"
        }
        
        let level: LogLevel = duration > 1.0 ? .warning : .info
        log(message, level: level, category: "Performance")
    }
    
    /// Log security events
    static func logSecurity(_ event: String, severity: SecuritySeverity = .medium) {
        let level: LogLevel = switch severity {
        case .low: .info
        case .medium: .warning
        case .high: .error
        case .critical: .critical
        }
        
        log("SECURITY [\(severity.rawValue.uppercased())]: \(event)", level: level, category: "Security")
    }
    
    /// Log offline operations
    static func logOffline(_ operation: String, queueSize: Int) {
        log("OFFLINE \(operation) - Queue size: \(queueSize)", level: .info, category: "Offline")
    }
}

enum SecuritySeverity: String {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"
}

// MARK: - Log Analytics (for debugging and monitoring)
#if DEBUG
extension Logger {
    /// Collect log statistics for debugging
    static func getLogStatistics() -> LogStatistics {
        // This would integrate with os.log to collect statistics
        // For now, return mock data for debugging
        return LogStatistics(
            totalLogs: 0,
            errorCount: 0,
            warningCount: 0,
            averageLogFrequency: 0
        )
    }
}

struct LogStatistics {
    let totalLogs: Int
    let errorCount: Int
    let warningCount: Int
    let averageLogFrequency: Double
}
#endif
