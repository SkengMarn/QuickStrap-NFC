import Foundation

/// Secure configuration management
/// IMPORTANT: Never commit Config.plist with real secrets to version control
class AppConfiguration {
    static let shared = AppConfiguration()

    private var config: [String: Any] = [:]

    private init() {
        loadConfiguration()
    }

    private func loadConfiguration() {
        // Try to load from Config.plist (gitignored)
        if let configPath = Bundle.main.path(forResource: "Config", ofType: "plist"),
           let configDict = NSDictionary(contentsOfFile: configPath) as? [String: Any] {
            config = configDict
            AppLogger.shared.log("Configuration loaded from Config.plist", level: .info, category: "Configuration")
            return
        }

        // Fallback to environment variables (for CI/CD)
        if let supabaseURL = ProcessInfo.processInfo.environment["SUPABASE_URL"],
           let supabaseKey = ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"] {
            config = [
                "SUPABASE_URL": supabaseURL,
                "SUPABASE_ANON_KEY": supabaseKey
            ]
            AppLogger.shared.log("Configuration loaded from environment variables", level: .info, category: "Configuration")
            return
        }

        // Development fallback - load from Keychain if available
        if let storedURL = try? SecureTokenStorage.retrieve(account: SecureTokenStorage.Account.supabaseURL),
           let storedKey = try? SecureTokenStorage.retrieve(account: SecureTokenStorage.Account.supabaseKey) {
            config = [
                "SUPABASE_URL": storedURL,
                "SUPABASE_ANON_KEY": storedKey
            ]
            AppLogger.shared.log("Configuration loaded from Keychain", level: .info, category: "Configuration")
            return
        }

        AppLogger.shared.log("⚠️ No configuration found! Please set up Config.plist", level: .warning, category: "Configuration")
    }

    // MARK: - Public Accessors

    var supabaseURL: String {
        guard let url = config["SUPABASE_URL"] as? String, !url.isEmpty else {
            AppLogger.shared.log("❌ SUPABASE_URL not configured", level: .error, category: "Configuration")
            return ""
        }
        return url
    }

    var supabaseAnonKey: String {
        guard let key = config["SUPABASE_ANON_KEY"] as? String, !key.isEmpty else {
            AppLogger.shared.log("❌ SUPABASE_ANON_KEY not configured", level: .error, category: "Configuration")
            return ""
        }
        return key
    }

    var isConfigured: Bool {
        return !supabaseURL.isEmpty && !supabaseAnonKey.isEmpty
    }

    // MARK: - Development Helper (Remove in production)

    #if DEBUG
    func storeConfigurationInKeychain(url: String, key: String) throws {
        try SecureTokenStorage.store(token: url, for: SecureTokenStorage.Account.supabaseURL)
        try SecureTokenStorage.store(token: key, for: SecureTokenStorage.Account.supabaseKey)
        loadConfiguration()
        AppLogger.shared.log("Configuration stored in Keychain for development", level: .info, category: "Configuration")
    }
    #endif
}

// MARK: - Configuration Error
enum ConfigurationError: LocalizedError {
    case missingConfiguration(String)
    case invalidConfiguration(String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration(let key):
            return "Missing configuration: \(key)"
        case .invalidConfiguration(let message):
            return "Invalid configuration: \(message)"
        }
    }
}
