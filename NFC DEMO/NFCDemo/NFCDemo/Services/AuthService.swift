import Foundation
import Combine

/// Focused authentication service
class AuthService: ObservableObject {
    static let shared = AuthService()

    private let repository: AuthRepository
    private let logger = AppLogger.shared

    @Published var currentUser: UserProfile?
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var accessToken: String?
    private var refreshToken: String?

    private init(repository: AuthRepository = AuthRepository()) {
        self.repository = repository
        logger.info("AuthService initialized", category: "Auth")
        checkExistingSession()
    }

    // MARK: - Session Management

    private func checkExistingSession() {
        do {
            let token = try SecureTokenStorage.retrieve(account: SecureTokenStorage.Account.accessToken)
            let email = try SecureTokenStorage.retrieve(account: SecureTokenStorage.Account.userEmail)

            if isTokenExpired(token) {
                logger.info("Stored token is expired", category: "Auth")

                if let storedRefreshToken = try? SecureTokenStorage.retrieve(account: SecureTokenStorage.Account.refreshToken) {
                    Task {
                        await refreshSession(refreshToken: storedRefreshToken, email: email)
                    }
                } else {
                    Task { @MainActor in
                        forceLogout()
                    }
                }
            } else {
                Task { @MainActor in
                    self.accessToken = token
                    self.isAuthenticated = true
                    await loadUserProfile(email: email)
                }
            }
        } catch {
            logger.info("No valid session found", category: "Auth")
        }
    }

    private func refreshSession(refreshToken: String, email: String) async {
        do {
            let response = try await repository.refreshToken(refreshToken: refreshToken)
            await MainActor.run {
                self.accessToken = response.accessToken
                self.refreshToken = response.refreshToken
                self.isAuthenticated = true
            }

            // Store new tokens
            try SecureTokenStorage.store(token: response.accessToken, for: SecureTokenStorage.Account.accessToken)
            if let newRefresh = response.refreshToken {
                try SecureTokenStorage.store(token: newRefresh, for: SecureTokenStorage.Account.refreshToken)
            }

            await loadUserProfile(email: email)
        } catch {
            logger.error("Failed to refresh session: \(error.localizedDescription)", category: "Auth")
            await MainActor.run {
                forceLogout()
            }
        }
    }

    // MARK: - Authentication

    @MainActor
    func signIn(email: String, password: String) async throws {
        logger.info("Starting sign in for: \(email)", category: "Auth")

        // Validate input
        var failures: [ValidationFailure] = []
        if email.isEmpty {
            failures.append(ValidationFailure("email", "Email is required"))
        }
        if password.isEmpty {
            failures.append(ValidationFailure("password", "Password is required"))
        }
        if !failures.isEmpty {
            throw AppError.validationFailed(failures)
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await repository.signIn(email: email, password: password)

            accessToken = response.accessToken
            refreshToken = response.refreshToken
            isAuthenticated = true

            // Store tokens securely
            try SecureTokenStorage.store(token: response.accessToken, for: SecureTokenStorage.Account.accessToken)
            try SecureTokenStorage.store(token: email, for: SecureTokenStorage.Account.userEmail)

            if let refreshToken = response.refreshToken {
                try SecureTokenStorage.store(token: refreshToken, for: SecureTokenStorage.Account.refreshToken)
            }

            await loadUserProfile(email: email)
        } catch {
            logger.error("Sign in failed: \(error.localizedDescription)", category: "Auth")
            throw error.asAppError()
        }
    }

    @MainActor
    func signUp(email: String, password: String, fullName: String) async throws {
        logger.info("Starting sign up for: \(email)", category: "Auth")

        // Validate input
        var failures: [ValidationFailure] = []
        if email.isEmpty {
            failures.append(ValidationFailure("email", "Email is required"))
        }
        if password.isEmpty {
            failures.append(ValidationFailure("password", "Password is required"))
        }
        if password.count < 6 {
            failures.append(ValidationFailure("password", "Password must be at least 6 characters"))
        }
        if fullName.isEmpty {
            failures.append(ValidationFailure("fullName", "Full name is required"))
        }
        if !failures.isEmpty {
            throw AppError.validationFailed(failures)
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await repository.signUp(email: email, password: password, fullName: fullName)

            accessToken = response.accessToken
            refreshToken = response.refreshToken
            isAuthenticated = true

            // Store tokens securely
            try SecureTokenStorage.store(token: response.accessToken, for: SecureTokenStorage.Account.accessToken)
            try SecureTokenStorage.store(token: email, for: SecureTokenStorage.Account.userEmail)

            if let refreshToken = response.refreshToken {
                try SecureTokenStorage.store(token: refreshToken, for: SecureTokenStorage.Account.refreshToken)
            }

            await loadUserProfile(email: email)
        } catch {
            logger.error("Sign up failed: \(error.localizedDescription)", category: "Auth")
            throw error.asAppError()
        }
    }

    @MainActor
    func signOut() {
        logger.info("User signing out", category: "Auth")

        // Clear secure storage
        do {
            try SecureTokenStorage.clearAll()
        } catch {
            logger.error("Failed to clear tokens: \(error.localizedDescription)", category: "Auth")
        }

        accessToken = nil
        refreshToken = nil
        currentUser = nil
        isAuthenticated = false
        errorMessage = nil
    }

    @MainActor
    private func forceLogout() {
        logger.warning("Forcing logout due to invalid session", category: "Auth")

        do {
            try SecureTokenStorage.clearAll()
        } catch {
            logger.error("Failed to clear secure storage: \(error)", category: "Auth")
        }

        accessToken = nil
        refreshToken = nil
        currentUser = nil
        isAuthenticated = false
        errorMessage = "Your session has expired. Please log in again."
    }

    private func loadUserProfile(email: String) async {
        do {
            let profile = try await repository.fetchUserProfile(email: email)
            await MainActor.run {
                self.currentUser = profile
            }
        } catch {
            logger.error("Failed to load user profile: \(error.localizedDescription)", category: "Auth")
        }
    }

    // MARK: - Token Management

    func getAccessToken() -> String? {
        return accessToken
    }

    private func isTokenExpired(_ token: String) -> Bool {
        let parts = token.components(separatedBy: ".")
        guard parts.count == 3 else { return true }

        let payload = parts[1]
        guard let data = Data(base64Encoded: addPadding(payload)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? TimeInterval else {
            return true
        }

        return Date() >= Date(timeIntervalSince1970: exp)
    }

    private func addPadding(_ base64: String) -> String {
        let remainder = base64.count % 4
        if remainder > 0 {
            return base64 + String(repeating: "=", count: 4 - remainder)
        }
        return base64
    }

    // MARK: - Token Provider for NetworkClient

    func configureNetworkClient() {
        NetworkClient.shared.tokenProvider = { [weak self] in
            return self?.getAccessToken()
        }
    }
}
