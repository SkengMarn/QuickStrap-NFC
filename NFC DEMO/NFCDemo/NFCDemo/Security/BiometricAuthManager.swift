import Foundation
import LocalAuthentication

/// Biometric authentication manager using Face ID / Touch ID
class BiometricAuthManager {
    static let shared = BiometricAuthManager()

    private let logger = AppLogger.shared
    private let context = LAContext()

    private init() {}

    // MARK: - Biometric Availability

    /// Check if biometric authentication is available
    func isBiometricAvailable() -> Bool {
        var error: NSError?
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)

        if let error = error {
            logger.debug("Biometric not available: \(error.localizedDescription)", category: "Security")
        }

        return canEvaluate
    }

    /// Get the type of biometric authentication available
    func biometricType() -> BiometricType {
        guard isBiometricAvailable() else {
            return .none
        }

        switch context.biometryType {
        case .faceID:
            return .faceID
        case .touchID:
            return .touchID
        case .opticID:
            return .opticID
        case .none:
            return .none
        @unknown default:
            return .unknown
        }
    }

    // MARK: - Authentication

    /// Authenticate user with biometrics
    /// - Parameters:
    ///   - reason: The reason shown to the user
    ///   - fallbackTitle: Optional fallback button title (default: nil shows "Enter Password")
    /// - Returns: True if authentication succeeded
    func authenticate(
        reason: String = "Authenticate to access your account",
        fallbackTitle: String? = nil
    ) async throws -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = fallbackTitle

        // Check availability
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            if let error = error {
                logger.error("Biometric authentication not available: \(error.localizedDescription)", category: "Security")
                throw BiometricError.notAvailable(error.localizedDescription)
            }
            throw BiometricError.notAvailable("Unknown error")
        }

        logger.info("Starting biometric authentication (\(biometricType().displayName))", category: "Security")

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )

            if success {
                logger.info("Biometric authentication succeeded", category: "Security")
            } else {
                logger.warning("Biometric authentication failed", category: "Security")
            }

            return success
        } catch let error as LAError {
            logger.error("Biometric authentication error: \(error.localizedDescription)", category: "Security")
            throw mapLAError(error)
        }
    }

    /// Authenticate with device passcode as fallback
    func authenticateWithPasscode(
        reason: String = "Authenticate to continue"
    ) async throws -> Bool {
        let context = LAContext()

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,  // Allows passcode fallback
                localizedReason: reason
            )

            if success {
                logger.info("Passcode authentication succeeded", category: "Security")
            }

            return success
        } catch let error as LAError {
            logger.error("Passcode authentication error: \(error.localizedDescription)", category: "Security")
            throw mapLAError(error)
        }
    }

    // MARK: - Settings

    /// Check if user has enabled biometric authentication for the app
    func isBiometricEnabled() -> Bool {
        return UserDefaults.standard.bool(forKey: "biometric_auth_enabled")
    }

    /// Enable/disable biometric authentication
    func setBiometricEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "biometric_auth_enabled")
        logger.info("Biometric authentication \(enabled ? "enabled" : "disabled")", category: "Security")
    }

    // MARK: - Error Mapping

    private func mapLAError(_ error: LAError) -> BiometricError {
        switch error.code {
        case .authenticationFailed:
            return .authenticationFailed
        case .userCancel:
            return .userCancelled
        case .userFallback:
            return .userSelectedFallback
        case .biometryNotAvailable:
            return .notAvailable("Biometric authentication is not available on this device")
        case .biometryNotEnrolled:
            return .notEnrolled
        case .biometryLockout:
            return .lockout
        case .appCancel:
            return .systemCancelled
        case .invalidContext:
            return .invalidContext
        case .notInteractive:
            return .notInteractive
        case .passcodeNotSet:
            return .passcodeNotSet
        default:
            return .unknown(error.localizedDescription)
        }
    }
}

// MARK: - Biometric Type

enum BiometricType {
    case faceID
    case touchID
    case opticID
    case none
    case unknown

    var displayName: String {
        switch self {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .opticID:
            return "Optic ID"
        case .none:
            return "None"
        case .unknown:
            return "Unknown"
        }
    }

    var icon: String {
        switch self {
        case .faceID:
            return "faceid"
        case .touchID:
            return "touchid"
        case .opticID:
            return "opticid"
        case .none, .unknown:
            return "lock.fill"
        }
    }
}

// MARK: - Biometric Errors

enum BiometricError: LocalizedError {
    case notAvailable(String)
    case notEnrolled
    case lockout
    case authenticationFailed
    case userCancelled
    case userSelectedFallback
    case systemCancelled
    case passcodeNotSet
    case invalidContext
    case notInteractive
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable(let reason):
            return "Biometric authentication is not available: \(reason)"
        case .notEnrolled:
            return "No biometric data is enrolled. Please set up Face ID or Touch ID in Settings."
        case .lockout:
            return "Biometric authentication is locked. Please try again later or use your passcode."
        case .authenticationFailed:
            return "Authentication failed. Please try again."
        case .userCancelled:
            return "Authentication was cancelled."
        case .userSelectedFallback:
            return "User selected to use passcode instead."
        case .systemCancelled:
            return "Authentication was cancelled by the system."
        case .passcodeNotSet:
            return "No passcode is set on this device."
        case .invalidContext:
            return "Invalid authentication context."
        case .notInteractive:
            return "Authentication is not interactive."
        case .unknown(let message):
            return "An unknown error occurred: \(message)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .notEnrolled:
            return "Go to Settings > Face ID & Passcode (or Touch ID & Passcode) to enroll."
        case .lockout:
            return "Try unlocking your device with your passcode."
        case .authenticationFailed:
            return "Make sure you're using the correct biometric data."
        case .passcodeNotSet:
            return "Set up a passcode in Settings."
        default:
            return nil
        }
    }
}

// MARK: - Convenience Extensions

extension BiometricAuthManager {
    /// Quick check if we should prompt for biometric auth
    func shouldPromptBiometric() -> Bool {
        return isBiometricAvailable() && isBiometricEnabled()
    }

    /// Authenticate and return result with user-friendly error
    func authenticateWithErrorHandling(
        reason: String = "Authenticate to continue"
    ) async -> Result<Bool, BiometricError> {
        do {
            let success = try await authenticate(reason: reason)
            return .success(success)
        } catch let error as BiometricError {
            return .failure(error)
        } catch {
            return .failure(.unknown(error.localizedDescription))
        }
    }
}
