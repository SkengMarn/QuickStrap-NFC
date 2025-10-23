import Foundation

/// Enhanced wristband verification service that supports both direct access and multi-series events
/// Maintains backwards compatibility with existing single-event verification
@MainActor
class EnhancedWristbandVerificationService {
    static let shared = EnhancedWristbandVerificationService()
    
    private init() {}
    
    // MARK: - Verification Result Types
    
    enum VerificationResult {
        case directAccess(wristband: Wristband)
        case seriesAccess(wristband: Wristband, seriesName: String)
        case noAccess
        case error(String)
    }
    
    // MARK: - Enhanced Verification Logic
    
    /// Verifies wristband access using backwards-compatible logic:
    /// 1. First tries direct access (existing system)
    /// 2. If no direct access and event has series, checks series access
    /// 3. Returns appropriate result type
    func verifyWristbandAccess(
        nfcId: String,
        eventId: String,
        supabaseService: SupabaseService
    ) async -> VerificationResult {
        
        print("🔍 [ENHANCED] Starting verification for NFC: \(nfcId), Event: \(eventId)")
        
        do {
            // STEP 1: Try Direct Access First (Existing Logic - Backwards Compatible)
            print("🔍 [ENHANCED] Step 1: Checking direct access...")
            
            let directResult = try await checkDirectAccess(
                nfcId: nfcId,
                eventId: eventId,
                supabaseService: supabaseService
            )
            
            if case .directAccess(let wristband) = directResult {
                print("✅ [ENHANCED] Step 1 SUCCESS: Direct access granted")
                return directResult
            }
            
            // STEP 2: Check if Event Uses Series (Only if direct access failed)
            print("🔍 [ENHANCED] Step 2: Direct access failed, checking if event has series...")
            
            let eventHasSeries = try await checkEventHasSeries(
                eventId: eventId,
                supabaseService: supabaseService
            )
            
            if !eventHasSeries {
                print("❌ [ENHANCED] Step 2: Event has no series, verification failed")
                return .noAccess
            }
            
            // STEP 3: Check Series Access (Only for multi-series events)
            print("🔍 [ENHANCED] Step 3: Event has series, checking series access...")
            
            let seriesResult = try await checkSeriesAccess(
                nfcId: nfcId,
                eventId: eventId,
                supabaseService: supabaseService
            )
            
            return seriesResult
            
        } catch {
            print("❌ [ENHANCED] Verification error: \(error)")
            return .error("Verification failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Direct Access Check (Existing Logic)
    
    private func checkDirectAccess(
        nfcId: String,
        eventId: String,
        supabaseService: SupabaseService
    ) async throws -> VerificationResult {
        
        // Build query with proper URL encoding
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "nfc_id", value: "eq.\(nfcId)"),
            URLQueryItem(name: "event_id", value: "eq.\(eventId)")
        ]
        let queryString = components.percentEncodedQuery ?? ""
        
        let wristbands: [Wristband] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/wristbands?\(queryString)",
            method: "GET",
            body: nil,
            responseType: [Wristband].self
        )
        
        if let wristband = wristbands.first {
            print("✅ [ENHANCED] Direct access found for wristband")
            return .directAccess(wristband: wristband)
        }
        
        print("❌ [ENHANCED] No direct access found")
        return .noAccess
    }
    
    // MARK: - Series Detection
    
    private func checkEventHasSeries(
        eventId: String,
        supabaseService: SupabaseService
    ) async throws -> Bool {
        
        // Check if event has any series
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "event_id", value: "eq.\(eventId)"),
            URLQueryItem(name: "select", value: "id"),
            URLQueryItem(name: "limit", value: "1")
        ]
        let queryString = components.percentEncodedQuery ?? ""
        
        let series: [EventSeries] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/event_series?\(queryString)",
            method: "GET",
            body: nil,
            responseType: [EventSeries].self
        )
        
        let hasSeries = !series.isEmpty
        print("🔍 [ENHANCED] Event has series: \(hasSeries)")
        return hasSeries
    }
    
    // MARK: - Series Access Check (New Logic)
    
    private func checkSeriesAccess(
        nfcId: String,
        eventId: String,
        supabaseService: SupabaseService
    ) async throws -> VerificationResult {
        
        // Complex query to check series access:
        // 1. Find wristband by NFC ID
        // 2. Join with event_series_wristbands to find granted series
        // 3. Join with event_series to verify it belongs to current event
        // 4. Check expiration if applicable
        
        let currentTimestamp = ISO8601DateFormatter().string(from: Date())
        
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "select", value: "wristbands(*),event_series(name,event_id),expires_at"),
            URLQueryItem(name: "wristbands.nfc_id", value: "eq.\(nfcId)"),
            URLQueryItem(name: "event_series.event_id", value: "eq.\(eventId)"),
            URLQueryItem(name: "or", value: "(expires_at.is.null,expires_at.gt.\(currentTimestamp))"),
            URLQueryItem(name: "limit", value: "1")
        ]
        let queryString = components.percentEncodedQuery ?? ""
        
        let seriesAccess: [EventSeriesWristbandAccess] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/event_series_wristbands?\(queryString)",
            method: "GET",
            body: nil,
            responseType: [EventSeriesWristbandAccess].self
        )
        
        if let access = seriesAccess.first,
           let wristband = access.wristband,
           let series = access.eventSeries {
            print("✅ [ENHANCED] Series access granted via series: \(series.name)")
            return .seriesAccess(wristband: wristband, seriesName: series.name)
        }
        
        print("❌ [ENHANCED] No series access found")
        return .noAccess
    }
}

// MARK: - Supporting Data Models

struct EventSeries: Codable {
    let id: String
    let eventId: String
    let name: String
    let startDate: Date?
    let endDate: Date?
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case eventId = "event_id"
        case name
        case startDate = "start_date"
        case endDate = "end_date"
        case createdAt = "created_at"
    }
}

struct EventSeriesWristbandAccess: Codable {
    let seriesId: String
    let wristbandId: String
    let grantedAt: Date
    let grantedBy: String
    let expiresAt: Date?
    let wristband: Wristband?
    let eventSeries: EventSeries?
    
    enum CodingKeys: String, CodingKey {
        case seriesId = "series_id"
        case wristbandId = "wristband_id"
        case grantedAt = "granted_at"
        case grantedBy = "granted_by"
        case expiresAt = "expires_at"
        case wristband = "wristbands"
        case eventSeries = "event_series"
    }
}

// MARK: - Enhanced Scan Result

enum EnhancedScanResult {
    case valid(String, ticket: Ticket?)
    case validSeries(String, seriesName: String, ticket: Ticket?)
    case invalid(String)
    case requiresLinking(wristbandId: String, reason: String)
    case requiresSeriesLinking(wristbandId: String, seriesName: String, reason: String)
    
    var isValid: Bool {
        switch self {
        case .valid, .validSeries:
            return true
        case .invalid, .requiresLinking, .requiresSeriesLinking:
            return false
        }
    }
    
    var message: String {
        switch self {
        case .valid(let message, _), .invalid(let message):
            return message
        case .validSeries(let message, let seriesName, _):
            return "\(message) (via \(seriesName))"
        case .requiresLinking(_, let reason), .requiresSeriesLinking(_, _, let reason):
            return reason
        }
    }
}
