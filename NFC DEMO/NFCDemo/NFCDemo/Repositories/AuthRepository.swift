import Foundation

/// Repository for authentication operations
class AuthRepository {
    private let networkClient: NetworkClient
    private let logger = AppLogger.shared

    init(networkClient: NetworkClient = .shared) {
        self.networkClient = networkClient
    }

    // MARK: - Authentication

    func signIn(email: String, password: String) async throws -> AuthResponse {
        logger.info("Attempting sign in for: \(email)", category: "Auth")

        let authData = [
            "email": email,
            "password": password
        ]

        do {
            let response: AuthResponse = try await networkClient.post(
                endpoint: "auth/v1/token?grant_type=password",
                body: try JSONSerialization.data(withJSONObject: authData),
                requiresAuth: false,
                responseType: AuthResponse.self
            )

            logger.info("Sign in successful for: \(email)", category: "Auth")
            return response
        } catch {
            logger.error("Sign in failed for \(email): \(error.localizedDescription)", category: "Auth")
            throw error.asAppError()
        }
    }

    func signUp(email: String, password: String, fullName: String) async throws -> AuthResponse {
        logger.info("Attempting sign up for: \(email)", category: "Auth")

        let authData: [String: Any] = [
            "email": email,
            "password": password,
            "data": [
                "full_name": fullName
            ]
        ]

        do {
            let response: AuthResponse = try await networkClient.post(
                endpoint: "auth/v1/signup",
                body: try JSONSerialization.data(withJSONObject: authData),
                requiresAuth: false,
                responseType: AuthResponse.self
            )

            logger.info("Sign up successful for: \(email)", category: "Auth")
            return response
        } catch {
            logger.error("Sign up failed for \(email): \(error.localizedDescription)", category: "Auth")
            throw error.asAppError()
        }
    }

    func refreshToken(refreshToken: String) async throws -> AuthResponse {
        logger.info("Attempting token refresh", category: "Auth")

        let refreshData = [
            "refresh_token": refreshToken
        ]

        do {
            let response: AuthResponse = try await networkClient.post(
                endpoint: "auth/v1/token?grant_type=refresh_token",
                body: try JSONSerialization.data(withJSONObject: refreshData),
                requiresAuth: false,
                responseType: AuthResponse.self
            )

            logger.info("Token refresh successful", category: "Auth")
            return response
        } catch {
            logger.error("Token refresh failed: \(error.localizedDescription)", category: "Auth")
            throw error.asAppError()
        }
    }

    func fetchUserProfile(email: String) async throws -> UserProfile? {
        logger.info("Fetching profile for: \(email)", category: "Auth")

        do {
            let profiles: [UserProfile] = try await networkClient.get(
                endpoint: "rest/v1/profiles?email=eq.\(email)",
                responseType: [UserProfile].self
            )

            logger.info("Profile fetch successful for: \(email)", category: "Auth")
            return profiles.first
        } catch {
            logger.error("Profile fetch failed for \(email): \(error.localizedDescription)", category: "Auth")
            throw error.asAppError()
        }
    }

    // MARK: - Password Reset

    func sendPasswordResetEmail(email: String) async throws {
        logger.info("Sending password reset email to: \(email)", category: "Auth")

        let resetData = [
            "email": email
        ]

        do {
            // Supabase password reset endpoint
            let _: EmptyResponse = try await networkClient.post(
                endpoint: "auth/v1/recover",
                body: try JSONSerialization.data(withJSONObject: resetData),
                requiresAuth: false,
                responseType: EmptyResponse.self
            )

            logger.info("Password reset email sent to: \(email)", category: "Auth")
        } catch {
            logger.error("Failed to send password reset email to \(email): \(error.localizedDescription)", category: "Auth")
            throw error.asAppError()
        }
    }

    func updatePassword(newPassword: String, accessToken: String) async throws {
        logger.info("Attempting password update", category: "Auth")

        let updateData = [
            "password": newPassword
        ]

        do {
            // Supabase update user endpoint
            let _: EmptyResponse = try await networkClient.patch(
                endpoint: "auth/v1/user",
                body: try JSONSerialization.data(withJSONObject: updateData),
                requiresAuth: true,
                responseType: EmptyResponse.self
            )

            logger.info("Password updated successfully", category: "Auth")
        } catch {
            logger.error("Failed to update password: \(error.localizedDescription)", category: "Auth")
            throw error.asAppError()
        }
    }
}
