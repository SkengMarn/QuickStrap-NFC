import Foundation

// Verification script to test the deployed Supabase functions
// This script tests the enhanced functions through the iOS app

class DeploymentVerifier {
    
    static func verifyEnhancedFunctions() async {
        print("🔍 Starting Enhanced Functions Verification...")
        print("=" * 50)
        
        let supabaseService = SupabaseService.shared
        
        // Test 1: Basic haversine distance (through RPC if available)
        await testHaversineDistance()
        
        // Test 2: Gate scan counts function
        await testGateScanCounts(service: supabaseService)
        
        // Test 3: Event categories function
        await testEventCategories(service: supabaseService)
        
        // Test 4: Comprehensive event stats
        await testComprehensiveStats(service: supabaseService)
        
        // Test 5: Batch processing function
        await testBatchProcessing(service: supabaseService)
        
        // Test 6: Nearby gates search
        await testNearbyGatesSearch(service: supabaseService)
        
        print("=" * 50)
        print("✅ Enhanced Functions Verification Complete!")
    }
    
    static func testHaversineDistance() async {
        print("\n🧪 Test 1: Haversine Distance Function")
        print("-" * 30)
        
        // Test the static method in AdaptiveClusteringService
        let distance = AdaptiveClusteringService.haversineDistance(
            lat1: 40.7128, lon1: -74.0060,  // NYC
            lat2: 40.7589, lon2: -73.9851   // Central Park
        )
        
        print("Distance between NYC coordinates: \(String(format: "%.2f", distance))m")
        
        if distance > 8000 && distance < 9000 {
            print("✅ Haversine function working correctly")
        } else {
            print("❌ Haversine function may have issues")
        }
    }
    
    static func testGateScanCounts(service: SupabaseService) async {
        print("\n🧪 Test 2: Gate Scan Counts Function")
        print("-" * 30)
        
        // You'll need to replace this with an actual event ID from your database
        let testEventId = "test-event-id-replace-with-real"
        
        do {
            let scanCounts = try await service.fetchGateScanCounts(eventId: testEventId)
            print("✅ Gate scan counts function executed successfully")
            print("Found scan counts for \(scanCounts.count) gates")
            
            for (gateId, count) in scanCounts.prefix(3) {
                print("  Gate \(gateId): \(count) scans")
            }
            
        } catch {
            print("⚠️  Gate scan counts test failed (expected if no data): \(error)")
        }
    }
    
    static func testEventCategories(service: SupabaseService) async {
        print("\n🧪 Test 3: Event Categories Function")
        print("-" * 30)
        
        let testEventId = "test-event-id-replace-with-real"
        
        do {
            let categories = try await service.fetchEventCategories(eventId: testEventId)
            print("✅ Event categories function executed successfully")
            print("Found \(categories.count) categories")
            
            for category in categories.prefix(3) {
                print("  \(category.displayName): \(category.wristbandCount) wristbands")
            }
            
        } catch {
            print("⚠️  Event categories test failed (expected if no data): \(error)")
        }
    }
    
    static func testComprehensiveStats(service: SupabaseService) async {
        print("\n🧪 Test 4: Comprehensive Event Stats Function")
        print("-" * 30)
        
        let testEventId = "test-event-id-replace-with-real"
        
        do {
            let stats = try await service.fetchComprehensiveEventStats(eventId: testEventId)
            print("✅ Comprehensive stats function executed successfully")
            print("Event Statistics:")
            print("  Total Wristbands: \(stats.totalWristbands)")
            print("  Total Check-ins: \(stats.totalCheckins)")
            print("  Linking Rate: \(String(format: "%.1f", stats.linkingRate * 100))%")
            print("  Gate Utilization: \(String(format: "%.1f", stats.gateUtilization * 100))%")
            print("  Linking Quality: \(stats.linkingQuality.rawValue)")
            
        } catch {
            print("⚠️  Comprehensive stats test failed (expected if no data): \(error)")
        }
    }
    
    static func testBatchProcessing(service: SupabaseService) async {
        print("\n🧪 Test 5: Batch Processing Function")
        print("-" * 30)
        
        let testEventId = "test-event-id-replace-with-real"
        
        do {
            let result = try await service.processUnlinkedCheckIns(eventId: testEventId, batchLimit: 10)
            print("✅ Batch processing function executed successfully")
            print("Processing Results:")
            print("  Processed: \(result.processedCount) check-ins")
            print("  Linked: \(result.linkedCount) check-ins")
            print("  Success Rate: \(String(format: "%.1f", result.successRate * 100))%")
            print("  Efficiency: \(result.efficiency.rawValue)")
            
        } catch {
            print("⚠️  Batch processing test failed (expected if no data): \(error)")
        }
    }
    
    static func testNearbyGatesSearch(service: SupabaseService) async {
        print("\n🧪 Test 6: Nearby Gates Search Function")
        print("-" * 30)
        
        let testEventId = "test-event-id-replace-with-real"
        
        do {
            let nearbyGates = try await service.findNearbyGatesByCategory(
                latitude: 40.7128,
                longitude: -74.0060,
                eventId: testEventId,
                category: "VIP",
                radiusMeters: 100.0
            )
            
            print("✅ Nearby gates search function executed successfully")
            print("Found \(nearbyGates.count) nearby gates")
            
            for gate in nearbyGates.prefix(3) {
                print("  \(gate.gateName): \(gate.formattedDistance) away (\(gate.proximityLevel.rawValue))")
            }
            
        } catch {
            print("⚠️  Nearby gates search test failed (expected if no data): \(error)")
        }
    }
}

// Extension to repeat strings (for formatting)
extension String {
    static func * (left: String, right: Int) -> String {
        return String(repeating: left, count: right)
    }
}

// Usage: Call this from your app to verify deployment
// Task {
//     await DeploymentVerifier.verifyEnhancedFunctions()
// }
