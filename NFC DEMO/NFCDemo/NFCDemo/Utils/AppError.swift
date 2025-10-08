import Foundation

/// Comprehensive error handling system
enum AppError: LocalizedError {
    // MARK: - Network Errors
    case networkError(NetworkError)
    case apiError(APIError)

    // MARK: - Authentication Errors
    case authenticationFailed(String)
    case tokenExpired
    case invalidCredentials
    case unauthorized
    case sessionExpired

    // MARK: - Data Errors
    case decodingError(String)
    case encodingError(String)
    case dataCorrupted(String)
    case notFound(String)
    case alreadyExists(String)

    // MARK: - NFC Errors
    case nfcNotAvailable
    case nfcReadFailed(String)
    case invalidNFCData(String)

    // MARK: - Database Errors
    case databaseError(String)
    case syncFailed(String)
    case noEventSelected
    case conflictDetected(String)

    // MARK: - Configuration Errors
    case configurationMissing(String)
    case invalidConfiguration(String)

    // MARK: - Validation Errors
    case validationFailed([ValidationFailure])
    case invalidInput(String)

    // MARK: - General Errors
    case unknown(Error)
    case operationCancelled
    case timeout

    var errorDescription: String? {
        switch self {
        // Network
        case .networkError(let error):
            return error.errorDescription
        case .apiError(let error):
            return error.errorDescription

        // Authentication
        case .authenticationFailed(let reason):
            return "Authentication failed: \(reason)"
        case .tokenExpired:
            return "Your session has expired. Please log in again."
        case .invalidCredentials:
            return "Invalid email or password. Please try again."
        case .unauthorized:
            return "You don't have permission to perform this action."
        case .sessionExpired:
            return "Your session has expired. Please log in again."

        // Data
        case .decodingError(let details):
            return "Failed to process data: \(details)"
        case .encodingError(let details):
            return "Failed to prepare data: \(details)"
        case .dataCorrupted(let details):
            return "Data is corrupted: \(details)"
        case .notFound(let resource):
            return "\(resource) not found."
        case .alreadyExists(let resource):
            return "\(resource) already exists."

        // NFC
        case .nfcNotAvailable:
            return "NFC is not available on this device."
        case .nfcReadFailed(let reason):
            return "Failed to read NFC tag: \(reason)"
        case .invalidNFCData(let details):
            return "Invalid NFC data: \(details)"

        // Database
        case .databaseError(let details):
            return "Database error: \(details)"
        case .syncFailed(let details):
            return "Sync failed: \(details)"
        case .noEventSelected:
            return "No event selected. Please select an event first."
        case .conflictDetected(let details):
            return "Conflict detected: \(details)"

        // Configuration
        case .configurationMissing(let key):
            return "Missing configuration: \(key)"
        case .invalidConfiguration(let details):
            return "Invalid configuration: \(details)"

        // Validation
        case .validationFailed(let failures):
            let messages = failures.map { $0.message }.joined(separator: ", ")
            return "Validation failed: \(messages)"
        case .invalidInput(let details):
            return "Invalid input: \(details)"

        // General
        case .unknown(let error):
            return "An unexpected error occurred: \(error.localizedDescription)"
        case .operationCancelled:
            return "Operation was cancelled."
        case .timeout:
            return "The operation timed out. Please try again."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .networkError(.noConnection):
            return "Please check your internet connection and try again."
        case .networkError(.timeout):
            return "The request timed out. Please try again."
        case .tokenExpired, .sessionExpired:
            return "Please log in again to continue."
        case .authenticationFailed, .invalidCredentials:
            return "Please check your credentials and try again."
        case .nfcNotAvailable:
            return "This feature requires an NFC-capable device."
        case .nfcReadFailed:
            return "Please hold your device closer to the NFC tag and try again."
        case .syncFailed:
            return "Your data will sync when connection is restored."
        default:
            return "Please try again or contact support if the problem persists."
        }
    }

    var isRecoverable: Bool {
        switch self {
        case .networkError(.noConnection), .networkError(.timeout):
            return true
        case .tokenExpired, .sessionExpired:
            return true
        case .nfcReadFailed:
            return true
        case .syncFailed:
            return true
        case .operationCancelled, .timeout:
            return true
        default:
            return false
        }
    }

    func log() {
        let category = logCategory
        let level: AppLogger.LogLevel = logLevel

        AppLogger.shared.log(
            errorDescription ?? "Unknown error",
            level: level,
            category: category
        )
    }

    private var logCategory: String {
        switch self {
        case .networkError, .apiError:
            return "Network"
        case .authenticationFailed, .tokenExpired, .invalidCredentials, .unauthorized, .sessionExpired:
            return "Authentication"
        case .nfcNotAvailable, .nfcReadFailed, .invalidNFCData:
            return "NFC"
        case .databaseError, .syncFailed, .conflictDetected:
            return "Database"
        default:
            return "General"
        }
    }

    private var logLevel: AppLogger.LogLevel {
        switch self {
        case .networkError(.noConnection), .operationCancelled:
            return .warning
        case .authenticationFailed, .tokenExpired, .sessionExpired:
            return .warning
        case .validationFailed, .invalidInput:
            return .info
        case .unknown:
            return .critical
        default:
            return .error
        }
    }
}

// MARK: - Network Error
enum NetworkError: LocalizedError {
    case noConnection
    case timeout
    case badRequest(String)
    case serverError(Int, String?)
    case invalidResponse
    case sslError

    var errorDescription: String? {
        switch self {
        case .noConnection:
            return "No internet connection available."
        case .timeout:
            return "The request timed out."
        case .badRequest(let message):
            return "Bad request: \(message)"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message ?? "Unknown error")"
        case .invalidResponse:
            return "Received an invalid response from the server."
        case .sslError:
            return "SSL connection failed."
        }
    }
}

// MARK: - API Error
enum APIError: LocalizedError {
    case unauthorized
    case forbidden
    case notFound
    case conflict
    case rateLimited
    case serviceUnavailable
    case custom(Int, String)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Unauthorized. Please log in again."
        case .forbidden:
            return "You don't have permission to access this resource."
        case .notFound:
            return "The requested resource was not found."
        case .conflict:
            return "The resource already exists or conflicts with an existing resource."
        case .rateLimited:
            return "Too many requests. Please wait a moment and try again."
        case .serviceUnavailable:
            return "The service is temporarily unavailable. Please try again later."
        case .custom(let code, let message):
            return "API error (\(code)): \(message)"
        }
    }

    static func fromHTTPStatus(_ status: Int, message: String? = nil) -> APIError {
        switch status {
        case 401:
            return .unauthorized
        case 403:
            return .forbidden
        case 404:
            return .notFound
        case 409:
            return .conflict
        case 429:
            return .rateLimited
        case 503:
            return .serviceUnavailable
        default:
            return .custom(status, message ?? "Unknown error")
        }
    }
}

// MARK: - Validation Failure
struct ValidationFailure {
    let field: String
    let message: String

    init(_ field: String, _ message: String) {
        self.field = field
        self.message = message
    }
}

// MARK: - Result Extension for Error Logging
extension Result {
    func logError() -> Result<Success, Failure> {
        if case .failure(let error) = self {
            if let appError = error as? AppError {
                appError.log()
            } else {
                AppLogger.shared.error("Unhandled error: \(error.localizedDescription)")
            }
        }
        return self
    }
}

// MARK: - Error Conversion Helpers
extension Error {
    func asAppError() -> AppError {
        if let appError = self as? AppError {
            return appError
        }

        if let decodingError = self as? DecodingError {
            return .decodingError(decodingError.localizedDescription)
        }

        if let urlError = self as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return .networkError(.noConnection)
            case .timedOut:
                return .networkError(.timeout)
            case .serverCertificateUntrusted, .secureConnectionFailed:
                return .networkError(.sslError)
            default:
                return .networkError(.invalidResponse)
            }
        }

        return .unknown(self)
    }
}
