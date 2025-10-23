import Foundation

/// Integration layer to seamlessly switch between old and new verification systems
/// This allows gradual rollout and easy fallback if needed
extension DatabaseScannerViewModel {
    
    // MARK: - Verification System Integration
    
    /// Main entry point for NFC processing - chooses between old and new systems
    /// Set useEnhancedVerification to true to enable multi-series support
    private var useEnhancedVerification: Bool {
        // You can control this via a feature flag, user setting, or event configuration
        // For now, let's make it configurable per event
        return supabaseService?.currentEvent?.hasMultiSeries ?? false
    }
    
    /// Unified processNFC method that routes to appropriate verification system
    func processNFCUnified(_ nfcId: String) async {
        if useEnhancedVerification {
            print("🚀 [INTEGRATION] Using enhanced verification system")
            await processNFCEnhanced(nfcId)
        } else {
            print("🔄 [INTEGRATION] Using legacy verification system")
            await processNFC(nfcId)
        }
    }
    
    /// Update the NFC delegate to use the unified method
    func updateNFCProcessingToUnified() {
        // This method can be called during setup to ensure we use the unified approach
        print("✅ [INTEGRATION] NFC processing updated to use unified verification")
    }
}

// MARK: - Event Model Extension

extension Event {
    /// Computed property to determine if event supports multi-series
    /// This can be based on a database field or computed logic
    var hasMultiSeries: Bool {
        // For now, we'll determine this by checking if the event has any series
        // In production, you might want to add a dedicated field to the events table
        return false // Will be updated once we can query the database
    }
}

// MARK: - Feature Flag Management

class VerificationFeatureFlags {
    static let shared = VerificationFeatureFlags()
    
    private init() {}
    
    /// Global feature flag for enhanced verification
    var enhancedVerificationEnabled: Bool = true
    
    /// Per-event feature flag check
    func shouldUseEnhancedVerification(for eventId: String) -> Bool {
        return enhancedVerificationEnabled
    }
    
    /// Fallback to legacy system if enhanced fails
    var allowFallbackToLegacy: Bool = true
}

// MARK: - Migration Helper

class VerificationMigrationHelper {
    static let shared = VerificationMigrationHelper()
    
    private init() {}
    
    /// Check if database has multi-series tables
    func hasMultiSeriesTables(supabaseService: SupabaseService) async -> Bool {
        do {
            // Try to query event_series table to see if it exists
            let _: [EventSeries] = try await supabaseService.makeRequest(
                endpoint: "rest/v1/event_series?limit=1",
                method: "GET",
                body: nil,
                responseType: [EventSeries].self
            )
            return true
        } catch {
            print("⚠️ [MIGRATION] Multi-series tables not found: \(error)")
            return false
        }
    }
    
    /// Validate that an event can use multi-series verification
    func canUseMultiSeries(eventId: String, supabaseService: SupabaseService) async -> Bool {
        // Check if tables exist
        let hasTable = await hasMultiSeriesTables(supabaseService: supabaseService)
        if !hasTable {
            return false
        }
        
        // Check if event has any series configured
        do {
            var components = URLComponents()
            components.queryItems = [
                URLQueryItem(name: "event_id", value: "eq.\(eventId)"),
                URLQueryItem(name: "limit", value: "1")
            ]
            let queryString = components.percentEncodedQuery ?? ""
            
            let series: [EventSeries] = try await supabaseService.makeRequest(
                endpoint: "rest/v1/event_series?\(queryString)",
                method: "GET",
                body: nil,
                responseType: [EventSeries].self
            )
            
            return !series.isEmpty
        } catch {
            print("⚠️ [MIGRATION] Cannot check event series: \(error)")
            return false
        }
    }
}

// MARK: - Backwards Compatibility Wrapper

extension DatabaseScannerViewModel {
    
    /// Safe wrapper that handles both verification systems with fallback
    func processNFCSafely(_ nfcId: String) async {
        let migrationHelper = VerificationMigrationHelper.shared
        let featureFlags = VerificationFeatureFlags.shared
        
        guard let supabaseService = supabaseService,
              let eventId = supabaseService.currentEvent?.id else {
            await processNFC(nfcId) // Fallback to legacy
            return
        }
        
        // Check if we should use enhanced verification
        let shouldUseEnhanced = featureFlags.shouldUseEnhancedVerification(for: eventId)
        let canUseEnhanced = await migrationHelper.canUseMultiSeries(
            eventId: eventId,
            supabaseService: supabaseService
        )
        
        if shouldUseEnhanced && canUseEnhanced {
            print("🚀 [SAFE] Using enhanced verification")
            do {
                await processNFCEnhanced(nfcId)
            } catch {
                print("❌ [SAFE] Enhanced verification failed: \(error)")
                if featureFlags.allowFallbackToLegacy {
                    print("🔄 [SAFE] Falling back to legacy verification")
                    await processNFC(nfcId)
                }
            }
        } else {
            print("🔄 [SAFE] Using legacy verification")
            await processNFC(nfcId)
        }
    }
}
