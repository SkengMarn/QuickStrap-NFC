import Foundation
import Combine
import CoreLocation

enum AuthError: Error {
    case noToken
    case tokenExpired
    case invalidToken
    case authenticationFailed
    
    var localizedDescription: String {
        switch self {
        case .noToken:
            return "No authentication token found"
        case .tokenExpired:
            return "Authentication token has expired"
        case .invalidToken:
            return "Invalid authentication token"
        case .authenticationFailed:
            return "Authentication failed"
        }
    }
}

class SupabaseService: ObservableObject {
    static let shared = SupabaseService()
    
    // Configuration - will be secured in production
    private let supabaseURL = "https://pmrxyisasfaimumuobvu.supabase.co"
    private var supabaseAnonKey: String?
    
    @Published var currentUser: UserProfile?
    @Published var currentEvent: Event?
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var accessToken: String?
    
    private var cancellables = Set<AnyCancellable>()
    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    private init() {
        print("🚀 SupabaseService initializing with enhanced security...")
        
        // For now, use the existing key but prepare for secure configuration
        supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBtcnh5aXNhc2ZhaW11bXVvYnZ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTMyODQ2ODMsImV4cCI6MjA2ODg2MDY4M30.rVsKq08Ynw82RkCntxWFXOTgP8T0cGyhJvqfrnOH4YQ"
        
        // Check for existing session with proper token validation
        checkExistingSession()
    }
    
    private func checkExistingSession() {
        // Check Keychain for stored session with token validation
        do {
            let token = try SecureTokenStorage.retrieve(account: SecureTokenStorage.Account.accessToken)
            let userEmail = try SecureTokenStorage.retrieve(account: SecureTokenStorage.Account.userEmail)
            
            // Check if token is expired
            if isTokenExpired(token) {
                print("🔄 Stored token is expired...")
                
                // Check if we have a refresh token
                if let refreshToken = try? SecureTokenStorage.retrieve(account: SecureTokenStorage.Account.refreshToken) {
                    print("🔄 Attempting token refresh...")
                    Task { @MainActor in
                        do {
                            try await refreshTokenWithStoredRefreshToken(refreshToken)
                            print("✅ Token refreshed successfully for: \(userEmail)")
                            await loadUserProfile(email: userEmail)
                        } catch {
                            print("❌ Token refresh failed: \(error.localizedDescription)")
                            forceLogout()
                        }
                    }
                } else {
                    print("❌ No refresh token available, forcing logout")
                    Task { @MainActor in
                        forceLogout()
                    }
                }
                return
            }
            
            Task { @MainActor in
                accessToken = token
                isAuthenticated = true
                print("✅ Valid session restored for: \(userEmail)")
                // Load user profile
                await loadUserProfile(email: userEmail)
            }
        } catch {
            print("🔒 No valid session found, user must login")
        }
    }
    
    // MARK: - JWT Token Management
    func isTokenExpiredPublic(_ token: String) -> Bool {
        return isTokenExpired(token)
    }
    
    private func isTokenExpired(_ token: String) -> Bool {
        // Parse JWT token to check expiration
        let parts = token.components(separatedBy: ".")
        guard parts.count == 3 else {
            print("❌ Invalid JWT token format")
            return true
        }
        
        // Decode payload (second part)
        let payload = parts[1]
        guard let data = Data(base64Encoded: addPadding(payload)) else {
            print("❌ Cannot decode JWT payload")
            return true
        }
        
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let exp = json["exp"] as? TimeInterval else {
                print("❌ Cannot parse JWT expiration")
                return true
            }
            
            let expirationDate = Date(timeIntervalSince1970: exp)
            let currentDate = Date()
            let isExpired = currentDate >= expirationDate
            
            if isExpired {
                print("⏰ JWT token expired at: \(expirationDate), current time: \(currentDate)")
            } else {
                let timeRemaining = expirationDate.timeIntervalSince(currentDate)
                print("✅ JWT token valid for \(Int(timeRemaining)) more seconds")
            }
            
            return isExpired
        } catch {
            print("❌ Error parsing JWT: \(error.localizedDescription)")
            return true
        }
    }
    
    private func addPadding(_ base64: String) -> String {
        let remainder = base64.count % 4
        if remainder > 0 {
            return base64 + String(repeating: "=", count: 4 - remainder)
        }
        return base64
    }
    
    @MainActor
    private func forceLogout() {
        print("🚪 Forcing logout due to invalid/expired token")
        
        // Clear secure storage
        do {
            try SecureTokenStorage.clearAll()
        } catch {
            print("❌ Failed to clear secure storage: \(error)")
        }
        
        accessToken = nil
        currentUser = nil
        currentEvent = nil
        isAuthenticated = false
        errorMessage = nil
    }
    
    private func refreshTokenIfNeeded() async throws {
        guard let token = accessToken else {
            throw AuthError.noToken
        }
        
        if isTokenExpired(token) {
            print("🔄 Token expired, attempting refresh...")
            try await refreshToken()
        }
    }
    
    private func refreshToken() async throws {
        guard let refreshToken = UserDefaults.standard.string(forKey: "supabase_refresh_token") else {
            print("❌ No refresh token available")
            await MainActor.run {
                forceLogout()
            }
            throw AuthError.noToken
        }
        
        try await refreshTokenWithStoredRefreshToken(refreshToken)
    }
    
    func refreshTokenWithStoredRefreshTokenPublic(_ refreshToken: String) async throws {
        try await refreshTokenWithStoredRefreshToken(refreshToken)
    }
    
    private func refreshTokenWithStoredRefreshToken(_ refreshToken: String) async throws {
        let refreshData = [
            "refresh_token": refreshToken
        ]
        
        do {
            print("📡 Making token refresh request...")
            let response: AuthResponse = try await makeRequest(
                endpoint: "auth/v1/token?grant_type=refresh_token",
                method: "POST",
                body: try JSONSerialization.data(withJSONObject: refreshData),
                responseType: AuthResponse.self
            )
            
            await MainActor.run {
                print("✅ Token refresh successful!")
                accessToken = response.accessToken
                UserDefaults.standard.set(response.accessToken, forKey: "supabase_access_token")
                
                if let newRefreshToken = response.refreshToken {
                    UserDefaults.standard.set(newRefreshToken, forKey: "supabase_refresh_token")
                }
                
                isAuthenticated = true
            }
            
            // Reload user profile after token refresh if we don't have it
            let needsProfile = await MainActor.run { currentUser == nil }
            if needsProfile {
                if let email = UserDefaults.standard.string(forKey: "user_email") {
                    print("🔄 Reloading user profile after token refresh...")
                    await loadUserProfile(email: email)
                }
            }
        } catch {
            print("❌ Token refresh failed: \(error.localizedDescription)")
            await MainActor.run {
                forceLogout()
            }
            throw AuthError.tokenExpired
        }
    }
    
    private func isAuthError(_ error: Error) -> Bool {
        // Check if error is authentication related
        if error is AuthError {
            return true
        }
        
        // Check for HTTP 401/403 errors
        let errorString = error.localizedDescription.lowercased()
        return errorString.contains("unauthorized") || 
               errorString.contains("forbidden") ||
               errorString.contains("401") ||
               errorString.contains("403")
    }
    
    // MARK: - Authentication Methods
    @MainActor
    func signIn(email: String, password: String) async throws {
        print("🔐 Starting sign in process for: \(email)")
        isLoading = true
        defer { isLoading = false }
        
        let authData = [
            "email": email,
            "password": password
        ]
        
        do {
            print("📡 Making authentication request...")
            let response: AuthResponse = try await makeRequest(
                endpoint: "auth/v1/token?grant_type=password",
                method: "POST",
                body: try JSONSerialization.data(withJSONObject: authData),
                responseType: AuthResponse.self
            )
            
            print("✅ Authentication successful!")
            accessToken = response.accessToken
            
            // Store tokens securely in Keychain
            do {
                try SecureTokenStorage.store(token: response.accessToken, for: SecureTokenStorage.Account.accessToken)
                try SecureTokenStorage.store(token: email, for: SecureTokenStorage.Account.userEmail)
                
                // Store refresh token if available
                if let refreshToken = response.refreshToken {
                    try SecureTokenStorage.store(token: refreshToken, for: SecureTokenStorage.Account.refreshToken)
                    print("💾 Refresh token stored securely")
                }
            } catch {
                print("❌ Failed to store tokens securely: \(error)")
                // Continue with authentication but log the security issue
            }
            
            // Also store in UserDefaults as fallback
            UserDefaults.standard.set(response.accessToken, forKey: "supabase_access_token")
            UserDefaults.standard.set(email, forKey: "user_email")
            if let refreshToken = response.refreshToken {
                UserDefaults.standard.set(refreshToken, forKey: "supabase_refresh_token")
            }
            
            isAuthenticated = true
            print("🎯 User authenticated, loading profile...")
            await loadUserProfile(email: email)
        } catch {
            print("❌ Authentication failed: \(error)")
            throw error
        }
    }
    
    @MainActor
    func signUp(email: String, password: String, fullName: String) async throws {
        isLoading = true
        defer { isLoading = false }
        
        let authData = [
            "email": email,
            "password": password,
            "data": [
                "full_name": fullName
            ]
        ] as [String: Any]
        
        let response: AuthResponse = try await makeRequest(
            endpoint: "auth/v1/signup",
            method: "POST",
            body: try JSONSerialization.data(withJSONObject: authData),
            responseType: AuthResponse.self
        )
        
        accessToken = response.accessToken
        UserDefaults.standard.set(response.accessToken, forKey: "supabase_access_token")
        UserDefaults.standard.set(email, forKey: "user_email")
        
        // Store refresh token if available
        if let refreshToken = response.refreshToken {
            UserDefaults.standard.set(refreshToken, forKey: "supabase_refresh_token")
        }
        
        isAuthenticated = true
        await loadUserProfile(email: email)
    }
    
    @MainActor
    private func loadUserProfile(email: String) async {
        print("🔍 Loading user profile...")
        do {
            // Use parameterized query to prevent SQL injection
            let profiles: [UserProfile] = try await makeRequest(
                endpoint: "rest/v1/profiles?email=eq.\(email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? email)&select=*",
                method: "GET",
                responseType: [UserProfile].self
            )
            
            print("🔍 Profile query returned \(profiles.count) results")
            
            if let profile = profiles.first {
                self.currentUser = profile
                print("✅ User profile loaded successfully")
                print("   Role: \(profile.role.rawValue)")
                #if DEBUG
                print("   Email: \(profile.email)")
                print("   Full Name: \(profile.fullName ?? "Not set")")
                #endif
            } else {
                print("⚠️ No profile found in database")
                print("⚠️ User profile must be created via database trigger or admin panel")
            }
        } catch {
            print("❌ Failed to load user profile")
            #if DEBUG
            print("❌ Error details: \(error.localizedDescription)")
            #endif
        }
    }
    
    @MainActor
    func signOut() {
        print("🚪 User signing out")
        UserDefaults.standard.removeObject(forKey: "supabase_access_token")
        UserDefaults.standard.removeObject(forKey: "supabase_refresh_token")
        UserDefaults.standard.removeObject(forKey: "user_email")
        accessToken = nil
        currentUser = nil
        currentEvent = nil
        isAuthenticated = false
        errorMessage = nil
    }

    // MARK: - Password Reset

    @MainActor
    func sendPasswordResetEmail(email: String) async throws {
        print("🔑 Sending password reset email to: \(email)")
        isLoading = true
        defer { isLoading = false }

        let resetData = [
            "email": email
        ]

        do {
            // Password reset is a public endpoint, like signIn/signUp
            struct EmptyResponse: Codable {}
            let _: EmptyResponse = try await makeRequest(
                endpoint: "auth/v1/recover",
                method: "POST",
                body: try JSONSerialization.data(withJSONObject: resetData),
                responseType: EmptyResponse.self
            )

            print("✅ Password reset email sent to: \(email)")
        } catch {
            print("❌ Failed to send password reset email: \(error)")
            throw error
        }
    }

    @MainActor
    func updatePassword(newPassword: String) async throws {
        print("🔑 Updating password...")
        isLoading = true
        defer { isLoading = false }

        let updateData = [
            "password": newPassword
        ]

        do {
            struct EmptyResponse: Codable {}
            let _: EmptyResponse = try await makeRequest(
                endpoint: "auth/v1/user",
                method: "PUT",
                body: try JSONSerialization.data(withJSONObject: updateData),
                responseType: EmptyResponse.self
            )

            print("✅ Password updated successfully")
        } catch {
            print("❌ Failed to update password: \(error)")
            throw error
        }
    }

    // MARK: - Event Methods
    func fetchEvents() async throws -> [Event] {
        print("📡 Fetching events from database...")

        // Debug current authentication state
        #if DEBUG
        TokenDebugger.debugAuthState()
        debugServiceState()
        #endif

        // Check if offline - return cached data
        let isOffline = await MainActor.run { !OfflineDataManager.shared.isOnlineSync }
        if isOffline {
            print("📱 Offline mode - returning cached events")
            return await MainActor.run { OfflineDataManager.shared.getCachedEvents() }
        }

        // Ensure token is valid before making request
        try await refreshTokenIfNeeded()

        // Get current user ID for access control
        let userId = await MainActor.run { currentUser?.id }
        guard let userId = userId else {
            print("❌ No user ID available for access control")
            throw AuthError.noToken
        }

        do {
            // Check if user is admin - admins can see all events
            let currentUserProfile = await MainActor.run { currentUser }
            let userRole = currentUserProfile?.role
            let isAdmin = userRole == .admin
            
            print("📡 Fetching events for user: \(userId)")
            print("   User email: \(currentUserProfile?.email ?? "unknown")")
            print("   User role: \(userRole?.rawValue ?? "ROLE NOT SET")")
            print("   Is admin: \(isAdmin)")
            
            let events: [Event]
            
            // ALWAYS fetch all events first to see what's in the database
            print("🔍 DEBUG: Fetching ALL events from database (no filter)...")
            
            let allEvents: [Event]
            do {
                allEvents = try await makeRequest(
                    endpoint: "rest/v1/events?select=*",
                    method: "GET",
                    responseType: [Event].self
                )
                print("🔍 DEBUG: Database contains \(allEvents.count) total events")
                
                // Print first event details for debugging
                if let firstEvent = allEvents.first {
                    print("🔍 First event sample:")
                    print("   Name: \(firstEvent.name)")
                    print("   ID: \(firstEvent.id)")
                    print("   Start Date: \(firstEvent.startDate)")
                }
            } catch {
                print("❌ ERROR fetching events from database:")
                print("   Error: \(error)")
                print("   Error description: \(error.localizedDescription)")
                
                if let decodingError = error as? DecodingError {
                    switch decodingError {
                    case .keyNotFound(let key, let context):
                        print("   Missing key: \(key.stringValue)")
                        print("   Context: \(context.debugDescription)")
                    case .typeMismatch(let type, let context):
                        print("   Type mismatch: expected \(type)")
                        print("   Context: \(context.debugDescription)")
                    case .valueNotFound(let type, let context):
                        print("   Value not found: \(type)")
                        print("   Context: \(context.debugDescription)")
                    case .dataCorrupted(let context):
                        print("   Data corrupted: \(context.debugDescription)")
                    @unknown default:
                        print("   Unknown decoding error")
                    }
                }
                throw error
            }
            
            if isAdmin {
                // Admins can see all events
                print("👑 Admin user - returning all \(allEvents.count) events")
                events = allEvents
            } else {
                // Non-admin users: Query events through event_access table
                print("📡 Fetching events with access control for user: \(userId)")

                // First, get event IDs the user has access to
                struct EventAccess: Codable {
                    let event_id: String
                    let access_level: String
                }

                let accessRecords: [EventAccess] = try await makeRequest(
                    endpoint: "rest/v1/event_access?user_id=eq.\(userId)&select=event_id,access_level",
                    method: "GET",
                    responseType: [EventAccess].self
                )

                print("✅ User has access to \(accessRecords.count) events")

                if accessRecords.isEmpty {
                    print("ℹ️ User has no event access granted yet")
                    return []
                }

                // Get the event IDs
                let eventIds = accessRecords.map { $0.event_id }

                // Fetch the actual events using the IDs
                let eventIdsQuery = eventIds.map { "id.eq.\($0)" }.joined(separator: ",")
                print("📡 Making authenticated request to: rest/v1/events?or=(\(eventIdsQuery))")

                events = try await makeRequest(
                    endpoint: "rest/v1/events?or=(\(eventIdsQuery))&select=*",
                    method: "GET",
                    responseType: [Event].self
                )
            }
            
            print("✅ Database fetch successful! Found \(events.count) events:")
            for (index, event) in events.enumerated() {
                print("   Event \(index + 1): \(event.name) (ID: \(event.id))")
                print("      Date: \(event.date.description)")
                print("      Location: \(event.location ?? "No location")")
            }
            
            // Cache events for offline use
            await OfflineDataManager.shared.cacheEvents(events)
            
            return events
            
        } catch {
            print("❌ Database fetch failed with error: \(error)")
            if let decodingError = error as? DecodingError {
                print("🔍 Decoding error details: \(decodingError)")
            }
            
            // Fallback to cached data if available
            let cachedEvents = await MainActor.run { OfflineDataManager.shared.getCachedEvents() }
            if !cachedEvents.isEmpty {
                print("📱 Returning cached events as fallback")
                return cachedEvents
            }
            
            throw error
        }
    }
    
    
    @MainActor
    func selectEvent(_ event: Event) {
        currentEvent = event
    }
    
    // MARK: - Series Event Methods
    
    /// Fetch all active series events for the organization
    func fetchAllActiveSeries() async throws -> [SeriesWithEvent] {
        print("📡 Fetching all active series events")

        // Ensure token is valid before making request
        try await refreshTokenIfNeeded()

        do {
            // First get all series
            let series: [EventSeries] = try await makeRequest(
                endpoint: "rest/v1/event_series?select=*&order=start_date.asc",
                method: "GET",
                responseType: [EventSeries].self
            )

            // Filter to only non-past series (show scheduled, active, and upcoming)
            // Don't filter by lifecycle_status as it might be draft or other states
            let activeSeries = series.filter { !$0.isPast }

            print("✅ Found \(series.count) total series, \(activeSeries.count) are not past (showing all upcoming and active)")

            // Debug: Print each series
            for s in series {
                print("   Series: \(s.name) - Status: \(s.lifecycleStatus.rawValue) - Start: \(s.startDate) - Past: \(s.isPast)")
            }

            // Fetch parent events for all series
            var seriesWithEvents: [SeriesWithEvent] = []
            for seriesItem in activeSeries {
                do {
                    let eventArray: [Event] = try await makeRequest(
                        endpoint: "rest/v1/events?id=eq.\(seriesItem.mainEventId)&select=*",
                        method: "GET",
                        responseType: [Event].self
                    )

                    if let event = eventArray.first {
                        seriesWithEvents.append(SeriesWithEvent(series: seriesItem, event: event))
                    }
                } catch {
                    print("⚠️ Failed to fetch parent event for series \(seriesItem.id): \(error)")
                }
            }

            print("✅ Successfully loaded \(seriesWithEvents.count) series with parent event info")
            return seriesWithEvents.sorted { $0.startDate < $1.startDate }

        } catch {
            print("❌ Failed to fetch series: \(error)")
            throw error
        }
    }

    /// Check if an event has series (child events in event_series table)
    func fetchSeriesForEvent(_ eventId: String) async throws -> [EventSeries] {
        print("📡 Checking for series in event: \(eventId)")

        // Ensure token is valid before making request
        try await refreshTokenIfNeeded()

        do {
            let series: [EventSeries] = try await makeRequest(
                endpoint: "rest/v1/event_series?main_event_id=eq.\(eventId)&select=*",
                method: "GET",
                responseType: [EventSeries].self
            )

            // Filter to only active and not past series
            let activeSeries = series.filter { $0.isActiveAndCurrent }

            print("✅ Found \(series.count) series, \(activeSeries.count) are active and current")

            return activeSeries.sorted { $0.startDate < $1.startDate }

        } catch {
            print("❌ Failed to fetch series: \(error)")
            throw error
        }
    }
    
    /// Fetch a specific series with its parent event info
    func fetchSeriesWithEvent(_ seriesId: String) async throws -> SeriesWithEvent {
        print("📡 Fetching series details: \(seriesId)")
        
        try await refreshTokenIfNeeded()
        
        do {
            // Fetch the series
            let seriesArray: [EventSeries] = try await makeRequest(
                endpoint: "rest/v1/event_series?id=eq.\(seriesId)&select=*",
                method: "GET",
                responseType: [EventSeries].self
            )
            
            guard let series = seriesArray.first else {
                throw NSError(domain: "SupabaseService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Series not found"])
            }
            
            // Fetch the parent event
            let eventArray: [Event] = try await makeRequest(
                endpoint: "rest/v1/events?id=eq.\(series.mainEventId)&select=*",
                method: "GET",
                responseType: [Event].self
            )
            
            guard let event = eventArray.first else {
                throw NSError(domain: "SupabaseService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Parent event not found"])
            }
            
            return SeriesWithEvent(series: series, event: event)
            
        } catch {
            print("❌ Failed to fetch series with event: \(error)")
            throw error
        }
    }
    
    // MARK: - Wristband Methods
    func fetchWristbands(for eventId: String) async throws -> [Wristband] {
        print("🔍 Fetching wristbands for PARENT event: \(eventId) (series_id IS NULL)")

        // Check if offline - return cached data
        let isOffline = await MainActor.run { !OfflineDataManager.shared.isOnlineSync }
        if isOffline {
            print("📱 Offline mode - returning cached wristbands")
            return await MainActor.run { OfflineDataManager.shared.getCachedWristbands(for: eventId) }
        }

        // Ensure token is valid before making request
        try await refreshTokenIfNeeded()

        do {
            // IMPORTANT: Filter by series_id IS NULL to only get parent event wristbands
            // This prevents double-counting wristbands that belong to series
            let wristbands: [Wristband] = try await makeRequest(
                endpoint: "rest/v1/wristbands?event_id=eq.\(eventId)&is_active=eq.true&series_id=is.null&select=*",
                method: "GET",
                responseType: [Wristband].self
            )

            print("✅ Found \(wristbands.count) parent event wristbands for event \(eventId) (excluding series wristbands)")

            // Cache wristbands for offline use
            await OfflineDataManager.shared.cacheWristbands(wristbands, for: eventId)

            return wristbands

        } catch {
            print("❌ Failed to fetch wristbands: \(error)")

            // Check if it's an authentication error
            if isAuthError(error) {
                await MainActor.run {
                    forceLogout()
                }
                throw AuthError.authenticationFailed
            }

            // Fallback to cached data if available
            let cachedWristbands = await MainActor.run { OfflineDataManager.shared.getCachedWristbands(for: eventId) }
            if !cachedWristbands.isEmpty {
                print("📱 Returning cached wristbands as fallback")
                return cachedWristbands
            }

            throw error
        }
    }

    /// Fetch wristbands assigned to a specific series
    func fetchWristbandsForSeries(_ seriesId: String) async throws -> [Wristband] {
        print("🔍 Fetching wristbands for series: \(seriesId)")

        // Ensure token is valid before making request
        try await refreshTokenIfNeeded()

        do {
            // Query wristbands table directly by series_id
            // The web portal stores wristbands with series_id set directly
            let wristbands: [Wristband] = try await makeRequest(
                endpoint: "rest/v1/wristbands?series_id=eq.\(seriesId)&is_active=eq.true&select=*",
                method: "GET",
                responseType: [Wristband].self
            )

            print("✅ Found \(wristbands.count) wristbands for series \(seriesId)")

            return wristbands

        } catch {
            print("❌ Failed to fetch wristbands for series: \(error)")

            // Check if it's an authentication error
            if isAuthError(error) {
                await MainActor.run {
                    forceLogout()
                }
                throw AuthError.authenticationFailed
            }

            throw error
        }
    }
    
    func fetchDistinctCategories(for eventId: String) async throws -> [WristbandCategory] {
        print("🏷️ Fetching distinct categories for event: \(eventId)")
        
        // Ensure token is valid before making request
        try await refreshTokenIfNeeded()
        
        do {
            // Fetch distinct categories from the database
            let response: [[String: String]] = try await makeRequest(
                endpoint: "rest/v1/wristbands?event_id=eq.\(eventId)&select=category",
                method: "GET",
                responseType: [[String: String]].self
            )
            
            // Extract unique category names
            let categoryNames = Set(response.compactMap { $0["category"] })
            let categories = categoryNames.map { WristbandCategory(name: $0) }
            
            print("✅ Found \(categories.count) distinct categories for event \(eventId):")
            for category in categories {
                print("   - \(category.displayName)")
            }
            
            return categories.sorted { $0.name < $1.name }
            
        } catch {
            print("❌ Failed to fetch categories: \(error)")
            
            // Check if it's an authentication error
            if isAuthError(error) {
                await MainActor.run {
                    forceLogout()
                }
                throw AuthError.authenticationFailed
            }
            
            throw error
        }
    }
    
    func fetchWristbandById(wristbandId: String, eventId: String) async throws -> Wristband? {
        let wristbands: [Wristband] = try await makeRequest(
            endpoint: "rest/v1/wristbands?id=eq.\(wristbandId)&event_id=eq.\(eventId)&select=*",
            method: "GET",
            responseType: [Wristband].self
        )
        return wristbands.first
    }
    
    func fetchWristband(by nfcId: String, eventId: String) async throws -> Wristband? {
        // Check offline first
        let isOffline = await MainActor.run { !OfflineDataManager.shared.isOnlineSync }
        if isOffline {
            let cachedWristbands = await MainActor.run { OfflineDataManager.shared.getCachedWristbands(for: eventId) }
            return cachedWristbands.first { $0.nfcId == nfcId }
        }
        
        let wristbands: [Wristband] = try await makeRequest(
            endpoint: "rest/v1/wristbands?nfc_id=eq.\(nfcId)&event_id=eq.\(eventId)&is_active=eq.true&select=*",
            method: "GET",
            responseType: [Wristband].self
        )
        
        return wristbands.first
    }
    
    // MARK: - Offline Scanning Support
    
    func processOfflineScan(nfcId: String, eventId: String, location: String? = nil, notes: String? = nil) async -> Bool {
        print("📱 Processing offline scan for NFC: \(nfcId)")
        
        // Verify wristband exists in cached data
        let cachedWristbands = await MainActor.run { OfflineDataManager.shared.getCachedWristbands(for: eventId) }
        guard cachedWristbands.contains(where: { $0.nfcId == nfcId }) else {
            print("❌ Wristband not found in cached data")
            return false
        }
        
        // Create offline scan record
        let offlineScan = OfflineScan(
            eventId: eventId,
            nfcId: nfcId,
            location: location,
            notes: notes,
            staffId: currentUser?.id
        )
        
        // Queue for sync when online
        await OfflineDataManager.shared.queueOfflineScanSync(offlineScan)
        
        print("✅ Offline scan queued successfully")
        return true
    }
    
    func createWristband(_ wristband: Wristband) async throws -> Wristband {
        await MainActor.run {
            isLoading = true
        }
        defer { 
            Task { @MainActor in
                isLoading = false
            }
        }
        
        let wristbandData: [String: Any] = [
            "event_id": wristband.eventId,
            "nfc_id": wristband.nfcId,
            "category": wristband.category.name,
            "is_active": wristband.isActive
        ]
        
        let createdWristbands: [Wristband] = try await makeRequest(
            endpoint: "rest/v1/wristbands",
            method: "POST",
            body: try JSONSerialization.data(withJSONObject: wristbandData),
            responseType: [Wristband].self
        )
        
        return createdWristbands.first ?? wristband
    }
    
    // MARK: - Check-in Methods
    func recordCheckIn(wristbandId: String, eventId: String, location: String?, notes: String?, gateId: String? = nil, seriesId: String? = nil) async throws -> CheckinLog {
        // Validate required UUID parameters
        guard !wristbandId.isEmpty else {
            throw NSError(domain: "CheckinError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Wristband ID cannot be empty"])
        }
        guard !eventId.isEmpty else {
            throw NSError(domain: "CheckinError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Event ID cannot be empty"])
        }
        
        print("🔍 Recording check-in - wristbandId: \(wristbandId), eventId: \(eventId)")
        
        await MainActor.run {
            isLoading = true
        }
        defer { 
            Task { @MainActor in
                isLoading = false
            }
        }
        
        // Get current location data (commented out - LocationManager not available)
        // let locationManager = LocationManager.shared
        // let currentLocation = locationManager.currentLocation
        let currentLocation: CLLocation? = nil
        
        let dateFormatter = ISO8601DateFormatter()
        
        var checkinData: [String: Any] = [
            "event_id": eventId,
            "wristband_id": wristbandId,
            "timestamp": dateFormatter.string(from: Date()),
            "location": location as Any,
            "notes": notes as Any
        ]
        
        // Add staff_id only if currentUser exists (avoid empty string UUID error)
        if let staffId = currentUser?.id, !staffId.isEmpty {
            checkinData["staff_id"] = staffId
        }
        
        // Add location data if available
        if let currentLocation = currentLocation {
            checkinData["app_lat"] = currentLocation.coordinate.latitude
            checkinData["app_lon"] = currentLocation.coordinate.longitude
            checkinData["app_accuracy"] = currentLocation.horizontalAccuracy
        }
        
        // Add gate data if provided (avoid empty string UUID error)
        if let gateId = gateId, !gateId.isEmpty {
            checkinData["gate_id"] = gateId
        }
        
        // Add series_id if provided (for series event check-ins)
        if let seriesId = seriesId, !seriesId.isEmpty {
            checkinData["series_id"] = seriesId
        }
        
        // Add empty arrays for BLE and WiFi (to be populated when implemented)
        checkinData["ble_seen"] = []
        checkinData["wifi_ssids"] = []
        checkinData["probation_tagged"] = false
        
        // Debug logging to identify UUID issues
        print("🔍 Check-in data being sent:")
        for (key, value) in checkinData {
            if key.contains("id") {
                print("   \(key): \(value) (type: \(type(of: value)))")
            }
        }
        
        let createdLogs: [CheckinLog] = try await makeRequest(
            endpoint: "rest/v1/checkin_logs",
            method: "POST",
            body: try JSONSerialization.data(withJSONObject: checkinData),
            responseType: [CheckinLog].self
        )
        
        return createdLogs.first ?? CheckinLog(
            id: UUID().uuidString,
            eventId: eventId,
            wristbandId: wristbandId,
            staffId: currentUser?.id,
            timestamp: Date(),
            location: location,
            notes: notes,
            gateId: nil,
            scannerId: nil,
            appLat: nil,
            appLon: nil,
            appAccuracy: nil,
            bleSeen: nil,
            wifiSSIDs: nil,
            probationTagged: nil,
            seriesId: seriesId
        )
    }
    
    /// Gate-aware check-in that evaluates gate binding policies
    func recordGateCheckin(wristbandId: String, eventId: String, gateId: String?, location: String?, notes: String?) async throws -> (CheckinLog, CheckinPolicyResult) {
        await MainActor.run {
            isLoading = true
        }
        defer { 
            Task { @MainActor in
                isLoading = false
            }
        }
        
        // First get the wristband to determine category
        guard let wristband = try await fetchWristbandById(wristbandId: wristbandId, eventId: eventId) else {
            throw NSError(domain: "SupabaseService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Wristband not found"])
        }
        
        // Evaluate gate binding policy if gate is specified
        var policyResult: CheckinPolicyResult
        if let gateId = gateId {
            print("🚪 Evaluating gate binding policy for gate: \(gateId), category: \(wristband.category.name)")
            policyResult = try await GateBindingService.shared.evaluateCheckin(
                wristbandId: wristbandId,
                categoryName: wristband.category.name,
                gateId: gateId
            )
            print("📊 Policy result: \(policyResult.allowed ? "✅ ALLOWED" : "❌ DENIED") - \(policyResult.reason.displayMessage)")
        } else {
            // No gate specified, allow check-in
            policyResult = CheckinPolicyResult(
                allowed: true,
                reason: .okUnbound,
                locationConfidence: 0.0,
                warnings: []
            )
        }
        
        // Record the check-in using unified method
        // Determine seriesId from current event context
        let seriesId = currentEvent?.seriesId
        
        let checkinLog = try await recordCheckIn(
            wristbandId: wristbandId,
            eventId: eventId,
            location: location,
            notes: notes,
            gateId: gateId,
            seriesId: seriesId
        )
        
        // Update probation status if needed
        if !policyResult.allowed {
            // Update the log to mark as probation tagged
            let updateData: [String: Any] = ["probation_tagged": true]
            let _: [CheckinLog] = try await makeRequest(
                endpoint: "rest/v1/checkin_logs?id=eq.\(checkinLog.id)",
                method: "PATCH",
                body: try JSONSerialization.data(withJSONObject: updateData),
                responseType: [CheckinLog].self
            )
        }
        
        return (checkinLog, policyResult)
    }
    
    func fetchCheckinLogs(for eventId: String, limit: Int = 100) async throws -> [CheckinLog] {
        await MainActor.run {
            isLoading = true
        }
        defer { 
            Task { @MainActor in
                isLoading = false
            }
        }
        
        let logs: [CheckinLog] = try await makeRequest(
            endpoint: "rest/v1/checkin_logs?event_id=eq.\(eventId)&order=timestamp.desc&limit=\(limit)&select=*",
            method: "GET",
            responseType: [CheckinLog].self
        )
        
        return logs
    }
    
    /// Fetch check-in logs for a specific series
    func fetchCheckinLogsForSeries(_ seriesId: String, limit: Int = 100) async throws -> [CheckinLog] {
        await MainActor.run {
            isLoading = true
        }
        defer { 
            Task { @MainActor in
                isLoading = false
            }
        }
        
        print("🔍 Fetching check-in logs for series: \(seriesId)")
        
        let logs: [CheckinLog] = try await makeRequest(
            endpoint: "rest/v1/checkin_logs?series_id=eq.\(seriesId)&order=timestamp.desc&limit=\(limit)&select=*",
            method: "GET",
            responseType: [CheckinLog].self
        )
        
        print("✅ Found \(logs.count) check-in logs for series \(seriesId)")
        
        return logs
    }
    
    // MARK: - Statistics Methods
    func fetchEventStats(for eventId: String, seriesId: String? = nil, timeRange: StatsTimeRange) async throws -> EventStats {
        await MainActor.run {
            isLoading = true
        }
        defer { 
            Task { @MainActor in
                isLoading = false
            }
        }
        
        // Fetch wristbands and check-in logs based on whether this is a series or parent event
        let wristbands: [Wristband]
        let checkinLogs: [CheckinLog]
        
        let (startDate, endDate) = timeRange.dateRange
        let startDateString = dateFormatter.string(from: startDate)
        let endDateString = dateFormatter.string(from: endDate)
        
        if let seriesId = seriesId {
            // This is a series event - fetch by series_id
            print("📊 Fetching stats for SERIES: \(seriesId)")
            wristbands = try await fetchWristbandsForSeries(seriesId)
            
            checkinLogs = try await makeRequest(
                endpoint: "rest/v1/checkin_logs?series_id=eq.\(seriesId)&timestamp=gte.\(startDateString)&timestamp=lte.\(endDateString)&order=timestamp.desc&select=*",
                method: "GET",
                responseType: [CheckinLog].self
            )
        } else {
            // This is a parent event - fetch by event_id
            print("📊 Fetching stats for PARENT EVENT: \(eventId)")
            wristbands = try await fetchWristbands(for: eventId)
            
            checkinLogs = try await makeRequest(
                endpoint: "rest/v1/checkin_logs?event_id=eq.\(eventId)&timestamp=gte.\(startDateString)&timestamp=lte.\(endDateString)&order=timestamp.desc&select=*",
                method: "GET",
                responseType: [CheckinLog].self
            )
        }
        
        // Calculate category breakdown using actual categories from wristbands
        var categoryBreakdown: [WristbandCategory: CategoryStats] = [:]
        let actualCategories = Set(wristbands.map { $0.category })
        
        for category in actualCategories {
            let categoryWristbands = wristbands.filter { $0.category == category }
            let categoryCheckins = checkinLogs.filter { log in
                categoryWristbands.contains { $0.id == log.wristbandId }
            }
            
            categoryBreakdown[category] = CategoryStats(
                category: category,
                total: categoryWristbands.count,
                checkedIn: Set(categoryCheckins.map { $0.wristbandId }).count
            )
        }
        
        let todayStart = Calendar.current.startOfDay(for: Date())
        let todayLogs = checkinLogs.filter { $0.timestamp >= todayStart }
        
        return EventStats(
            totalWristbands: wristbands.count,
            totalCheckedIn: Set(checkinLogs.map { $0.wristbandId }).count,
            totalScansToday: todayLogs.count,
            categoryBreakdown: categoryBreakdown,
            recentActivity: Array(checkinLogs.prefix(10))
        )
    }
    
    // MARK: - Search and Filter Methods
    func searchWristbands(filter: WristbandFilter) async throws -> [Wristband] {
        guard let eventId = filter.eventId else { return [] }
        
        let allWristbands = try await fetchWristbands(for: eventId)
        
        return allWristbands.filter { wristband in
            // Search text filter
            let matchesSearch = filter.searchText.isEmpty ||
                wristband.nfcId.localizedCaseInsensitiveContains(filter.searchText) ||
                wristband.category.displayName.localizedCaseInsensitiveContains(filter.searchText)
            
            // Category filter
            let matchesCategory = filter.selectedCategory == nil || wristband.category == filter.selectedCategory
            
            // Status filter (mock implementation)
            let matchesStatus = filter.statusFilter == .all ||
                (filter.statusFilter == .checkedIn && wristband.isCheckedIn) ||
                (filter.statusFilter == .pending && !wristband.isCheckedIn)
            
            return matchesSearch && matchesCategory && matchesStatus
        }
    }
    
    
    // MARK: - Network Helper Methods
    internal func makeRequest<T: Codable>(
        endpoint: String,
        method: String = "GET",
        body: Data? = nil,
        responseType: T.Type,
        headers: [String: String] = [:],
        requiresAuth: Bool = true
    ) async throws -> T {
        // Build the full URL
        let baseURL = endpoint.contains("auth/v1") ? supabaseURL : "\(supabaseURL)"
        let fullEndpoint = endpoint.starts(with: "/") ? String(endpoint.dropFirst()) : endpoint
        let urlString = "\(baseURL)/\(fullEndpoint)"
        
        // Determine HTTP method
        guard let httpMethod = HTTPMethod(rawValue: method.uppercased()) else {
            throw SupabaseServiceError.apiError("Invalid HTTP method: \(method)")
        }
        
        // Set up headers
        var requestHeaders = headers
        
        // Add auth headers if needed
        if requiresAuth, let accessToken = accessToken {
            requestHeaders["Authorization"] = "Bearer \(accessToken)"
        }
        
        // Add content type if not set
        if requestHeaders["Content-Type"] == nil && body != nil {
            requestHeaders["Content-Type"] = "application/json"
        }
        
        // For Supabase, we always need the API key
        if let apiKey = supabaseAnonKey {
            requestHeaders["apikey"] = apiKey
            
            // For auth endpoints, use the API key as the bearer token
            if endpoint.contains("auth/v1") && !requiresAuth {
                requestHeaders["Authorization"] = "Bearer \(apiKey)"
            }
        }
        
        // Log the request
        print("🌐 \(method) \(urlString)")
        if let body = body, let bodyString = String(data: body, encoding: .utf8) {
            print("📦 Request body: \(bodyString)")
        }
        
        do {
            // Use the enhanced NetworkClient with retry logic
            return try await NetworkClient.shared.execute(
                endpoint: urlString,
                method: httpMethod,
                body: body,
                headers: requestHeaders,
                requiresAuth: requiresAuth,
                responseType: responseType
            )
        } catch let error as AppError {
            // Map AppError to SupabaseServiceError
            switch error {
            case .networkError(.timeout):
                throw SupabaseServiceError.apiError("Request timed out")
            case .networkError(.noConnection):
                throw SupabaseServiceError.apiError("No internet connection")
            case .networkError(.sslError):
                throw SupabaseServiceError.apiError("SSL connection failed")
            case .networkError(.invalidResponse):
                throw SupabaseServiceError.invalidResponse
            case .unauthorized, .authenticationFailed:
                throw SupabaseServiceError.authenticationRequired
            case .apiError(let apiError):
                throw SupabaseServiceError.apiError(apiError.errorDescription ?? "API error")
            default:
                throw SupabaseServiceError.apiError(error.errorDescription ?? "Unknown error")
            }
        } catch {
            // For any other error, wrap it in our error type
            throw SupabaseServiceError.apiError(error.localizedDescription)
        }
    }
}

// MARK: - Auth Response Model
struct AuthResponse: Codable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String?
    let user: AuthUser?
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case user
    }
}

struct AuthUser: Codable {
    let id: String
    let email: String
    let emailConfirmedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id, email
        case emailConfirmedAt = "email_confirmed_at"
    }
}

// MARK: - Error Types
enum SupabaseServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case decodingError(Error)
    case authenticationRequired
    case insufficientPermissions
    case apiError(String)
    case configurationError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .authenticationRequired:
            return "Authentication required"
        case .insufficientPermissions:
            return "Insufficient permissions"
        case .apiError(let message):
            return message
        case .configurationError(let message):
            return "Configuration error: \(message)"
        }
    }
}
