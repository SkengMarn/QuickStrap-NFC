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
        do {
            let profiles: [UserProfile] = try await makeRequest(
                endpoint: "rest/v1/profiles?email=eq.\(email)",
                method: "GET",
                responseType: [UserProfile].self
            )
            
            self.currentUser = profiles.first
            print("✅ User profile loaded successfully: \(profiles.first?.email ?? "Unknown")")
        } catch {
            print("❌ Failed to load user profile: \(error)")
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
        
        do {
            print("📡 Making authenticated request to: rest/v1/events?select=*")
            let events: [Event] = try await makeRequest(
                endpoint: "rest/v1/events?select=*",
                method: "GET",
                responseType: [Event].self
            )
            
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
    
    // MARK: - Wristband Methods
    func fetchWristbands(for eventId: String) async throws -> [Wristband] {
        print("🔍 Fetching wristbands for event: \(eventId)")
        
        // Check if offline - return cached data
        let isOffline = await MainActor.run { !OfflineDataManager.shared.isOnlineSync }
        if isOffline {
            print("📱 Offline mode - returning cached wristbands")
            return await MainActor.run { OfflineDataManager.shared.getCachedWristbands(for: eventId) }
        }
        
        // Ensure token is valid before making request
        try await refreshTokenIfNeeded()
        
        do {
            let wristbands: [Wristband] = try await makeRequest(
                endpoint: "rest/v1/wristbands?event_id=eq.\(eventId)&is_active=eq.true&select=*",
                method: "GET",
                responseType: [Wristband].self
            )
            
            print("✅ Found \(wristbands.count) wristbands for event \(eventId)")
            
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
    func recordCheckIn(wristbandId: String, eventId: String, location: String?, notes: String?, gateId: String? = nil) async throws -> CheckinLog {
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
            probationTagged: nil
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
        let checkinLog = try await recordCheckIn(
            wristbandId: wristbandId,
            eventId: eventId,
            location: location,
            notes: notes,
            gateId: gateId
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
    
    // MARK: - Statistics Methods
    func fetchEventStats(for eventId: String, timeRange: StatsTimeRange) async throws -> EventStats {
        await MainActor.run {
            isLoading = true
        }
        defer { 
            Task { @MainActor in
                isLoading = false
            }
        }
        
        // Fetch all wristbands for this event
        let wristbands = try await fetchWristbands(for: eventId)
        
        // Fetch check-in logs with time range filter
        let (startDate, endDate) = timeRange.dateRange
        let startDateString = dateFormatter.string(from: startDate)
        let endDateString = dateFormatter.string(from: endDate)
        
        let checkinLogs: [CheckinLog] = try await makeRequest(
            endpoint: "rest/v1/checkin_logs?event_id=eq.\(eventId)&timestamp=gte.\(startDateString)&timestamp=lte.\(endDateString)&order=timestamp.desc&select=*",
            method: "GET",
            responseType: [CheckinLog].self
        )
        
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
    func makeRequest<T: Codable>(
        endpoint: String,
        method: String = "GET",
        body: Data? = nil,
        responseType: T.Type,
        headers: [String: String] = [:]
    ) async throws -> T {
        let baseURL = endpoint.contains("auth/v1") ? supabaseURL : "\(supabaseURL)"
        guard let url = URL(string: "\(baseURL)/\(endpoint)") else {
            throw SupabaseServiceError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        
        // Ensure we have an API key
        guard let apiKey = supabaseAnonKey else {
            print("❌ No API key available for request")
            throw SupabaseServiceError.configurationError("API key not available")
        }
        
        // Set default headers based on endpoint type
        if endpoint.contains("auth/v1") {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue(apiKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            print("🔑 Auth request using API key (Bearer \(String(apiKey.prefix(20)))...)")
        } else {
            // REST API requests - use access token if available, otherwise API key
            let authToken = accessToken ?? apiKey
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
            request.setValue(apiKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("return=representation", forHTTPHeaderField: "Prefer")
            
            if accessToken != nil {
                print("🔑 REST request using access token (Bearer \(String(authToken.prefix(20)))...)")
            } else {
                print("🔑 REST request using API key fallback (Bearer \(String(authToken.prefix(20)))...)")
            }
        }
        
        // Apply custom headers (will override defaults if same key)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        if let body = body {
            request.httpBody = body
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseServiceError.invalidResponse
        }
        
        guard 200...299 ~= httpResponse.statusCode else {
            print("❌ HTTP Error: \(httpResponse.statusCode)")
            
            // Log response data for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                print("📄 Response body: \(responseString)")
            }
            
            // Handle authentication errors specifically
            if httpResponse.statusCode == 401 {
                print("🔒 Unauthorized - token may be invalid or expired")
                throw AuthError.authenticationFailed
            }
            
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = errorData["message"] as? String {
                print("📄 API Error message: \(message)")
                throw SupabaseServiceError.apiError(message)
            }
            
            throw SupabaseServiceError.httpError(httpResponse.statusCode)
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let dateString = try container.decode(String.self)
                
                // Try multiple date formats commonly used by PostgreSQL/Supabase
                let isoFormatter1 = ISO8601DateFormatter()
                if let date = isoFormatter1.date(from: dateString) {
                    return date
                }
                
                let isoFormatter2 = ISO8601DateFormatter()
                isoFormatter2.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = isoFormatter2.date(from: dateString) {
                    return date
                }
                
                let dateFormatter1 = DateFormatter()
                dateFormatter1.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSS"
                dateFormatter1.timeZone = TimeZone(secondsFromGMT: 0)
                if let date = dateFormatter1.date(from: dateString) {
                    return date
                }
                
                let dateFormatter2 = DateFormatter()
                dateFormatter2.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
                dateFormatter2.timeZone = TimeZone(secondsFromGMT: 0)
                if let date = dateFormatter2.date(from: dateString) {
                    return date
                }
                
                let dateFormatter3 = DateFormatter()
                dateFormatter3.dateFormat = "yyyy-MM-dd HH:mm:ss"
                dateFormatter3.timeZone = TimeZone(secondsFromGMT: 0)
                if let date = dateFormatter3.date(from: dateString) {
                    return date
                }
                
                print("❌ Failed to parse date: '\(dateString)'")
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format: \(dateString)")
            }
            
            return try decoder.decode(responseType, from: data)
        } catch {
            throw SupabaseServiceError.decodingError(error)
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
