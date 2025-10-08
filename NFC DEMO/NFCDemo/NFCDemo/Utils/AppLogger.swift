import Foundation
import OSLog

/// Enterprise-grade logging infrastructure
class AppLogger {
    static let shared = AppLogger()

    private let subsystem = Bundle.main.bundleIdentifier ?? "com.jawal.nfcdemo"

    // Category-specific loggers
    private var loggers: [String: OSLog] = [:]

    // File logging for crash analysis
    private var logFileURL: URL?
    private let logQueue = DispatchQueue(label: "com.jawal.nfcdemo.logging", qos: .utility)

    enum LogLevel: Int {
        case debug = 0
        case info = 1
        case warning = 2
        case error = 3
        case critical = 4

        var osLogType: OSLogType {
            switch self {
            case .debug: return .debug
            case .info: return .info
            case .warning: return .default
            case .error: return .error
            case .critical: return .fault
            }
        }

        var emoji: String {
            switch self {
            case .debug: return "🔍"
            case .info: return "ℹ️"
            case .warning: return "⚠️"
            case .error: return "❌"
            case .critical: return "🔥"
            }
        }
    }

    private init() {
        setupFileLogging()
    }

    private func setupFileLogging() {
        let fileManager = FileManager.default
        if let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let logsDirectory = documentsPath.appendingPathComponent("Logs", isDirectory: true)

            try? fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd"
            let filename = "nfc-app-\(dateFormatter.string(from: Date())).log"

            logFileURL = logsDirectory.appendingPathComponent(filename)

            // Cleanup old logs (keep last 7 days)
            cleanupOldLogs(in: logsDirectory)
        }
    }

    private func cleanupOldLogs(in directory: URL) {
        let fileManager = FileManager.default
        let calendar = Calendar.current

        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey]) else {
            return
        }

        for file in files {
            guard let attributes = try? fileManager.attributesOfItem(atPath: file.path),
                  let creationDate = attributes[.creationDate] as? Date else {
                continue
            }

            let daysDiff = calendar.dateComponents([.day], from: creationDate, to: Date()).day ?? 0

            if daysDiff > 7 {
                try? fileManager.removeItem(at: file)
            }
        }
    }

    private func getLogger(for category: String) -> OSLog {
        if let logger = loggers[category] {
            return logger
        }

        let logger = OSLog(subsystem: subsystem, category: category)
        loggers[category] = logger
        return logger
    }

    // MARK: - Public Logging Methods

    func log(_ message: String, level: LogLevel = .info, category: String = "General", file: String = #file, function: String = #function, line: Int = #line) {
        let logger = getLogger(for: category)
        let fileName = (file as NSString).lastPathComponent
        let logMessage = "\(level.emoji) [\(category)] \(message) (\(fileName):\(line))"

        // Log to OSLog
        os_log("%{public}@", log: logger, type: level.osLogType, logMessage)

        // Also write to file for debugging
        writeToFile(logMessage)

        #if DEBUG
        // Print to console in debug builds
        print(logMessage)
        #endif
    }

    func debug(_ message: String, category: String = "General", file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .debug, category: category, file: file, function: function, line: line)
    }

    func info(_ message: String, category: String = "General", file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, category: category, file: file, function: function, line: line)
    }

    func warning(_ message: String, category: String = "General", file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .warning, category: category, file: file, function: function, line: line)
    }

    func error(_ message: String, category: String = "General", file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .error, category: category, file: file, function: function, line: line)
    }

    func critical(_ message: String, category: String = "General", file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .critical, category: category, file: file, function: function, line: line)
    }

    // MARK: - Performance Tracking

    func measure<T>(_ operation: String, category: String = "Performance", block: () throws -> T) rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let duration = CFAbsoluteTimeGetCurrent() - start
            log("\(operation) took \(String(format: "%.3f", duration))s", level: .debug, category: category)
        }
        return try block()
    }

    func measureAsync<T>(_ operation: String, category: String = "Performance", block: () async throws -> T) async rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        defer {
            let duration = CFAbsoluteTimeGetCurrent() - start
            log("\(operation) took \(String(format: "%.3f", duration))s", level: .debug, category: category)
        }
        return try await block()
    }

    // MARK: - File Logging

    private func writeToFile(_ message: String) {
        guard let logFileURL = logFileURL else { return }

        logQueue.async {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let logLine = "[\(timestamp)] \(message)\n"

            if let data = logLine.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: logFileURL.path) {
                    if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                        fileHandle.seekToEndOfFile()
                        fileHandle.write(data)
                        fileHandle.closeFile()
                    }
                } else {
                    try? data.write(to: logFileURL, options: .atomic)
                }
            }
        }
    }

    // MARK: - Log Retrieval (for support/debugging)

    func getLogFileURL() -> URL? {
        return logFileURL
    }

    func getLogContents() -> String? {
        guard let logFileURL = logFileURL else { return nil }
        return try? String(contentsOf: logFileURL, encoding: .utf8)
    }

    func clearLogs() {
        guard let logFileURL = logFileURL else { return }
        try? FileManager.default.removeItem(at: logFileURL)
        setupFileLogging()
    }
}

// MARK: - Convenience Global Functions (Optional)

func logDebug(_ message: String, category: String = "General") {
    AppLogger.shared.debug(message, category: category)
}

func logInfo(_ message: String, category: String = "General") {
    AppLogger.shared.info(message, category: category)
}

func logWarning(_ message: String, category: String = "General") {
    AppLogger.shared.warning(message, category: category)
}

func logError(_ message: String, category: String = "General") {
    AppLogger.shared.error(message, category: category)
}

func logCritical(_ message: String, category: String = "General") {
    AppLogger.shared.critical(message, category: category)
}
