import Foundation

/// Test script to verify the deduplication flow works correctly
/// This ensures no duplicate gates are returned and check-ins are properly accounted for

class DeduplicationFlowTest {
    
    static func runComprehensiveTest() async {
        print("🧪 Starting Comprehensive Deduplication Flow Test")
        print("=" * 60)
        
        // Test 1: Verify current state
        await testCurrentDatabaseState()
        
        // Test 2: Verify deduplication logic
        await testDeduplicationLogic()
        
        // Test 3: Verify check-in integrity
        await testCheckinIntegrity()
        
        // Test 4: Verify threshold calculations
        await testThresholdCalculations()
        
        print("🏁 Test Complete!")
    }
    
    // MARK: - Test 1: Current Database State
    static func testCurrentDatabaseState() async {
        print("\n📊 Test 1: Current Database State")
        print("-" * 40)
        
        do {
            // Fetch current gates
            let gatesData = try await makeAPICall(endpoint: "gates?select=*")
            let gates = try JSONDecoder().decode([Gate].self, from: gatesData)
            
            print("📍 Total Gates: \(gates.count)")
            
            // Group by name and location proximity
            let staffGates = gates.filter { $0.name.contains("Staff") }
            print("🏢 Staff Gates: \(staffGates.count)")
            
            if staffGates.count > 1 {
                print("⚠️ ISSUE: Multiple Staff Gates detected (potential duplicates)")
                for (index, gate) in staffGates.enumerated() {
                    print("   \(index + 1). \(gate.id) - (\(gate.latitude), \(gate.longitude))")
                }
            } else {
                print("✅ No duplicate Staff Gates found")
            }
            
            // Fetch gate bindings
            let bindingsData = try await makeAPICall(endpoint: "gate_bindings?select=*")
            let bindings = try JSONDecoder().decode([GateBinding].self, from: bindingsData)
            
            print("🔗 Total Gate Bindings: \(bindings.count)")
            
            // Check for bindings to non-existent gates
            let gateIds = Set(gates.map { $0.id })
            let bindingGateIds = Set(bindings.map { $0.gateId })
            let orphanedBindings = bindingGateIds.subtracting(gateIds)
            
            if orphanedBindings.isEmpty {
                print("✅ All bindings reference valid gates")
            } else {
                print("⚠️ ISSUE: \(orphanedBindings.count) orphaned bindings found")
            }
            
        } catch {
            print("❌ Failed to fetch current state: \(error)")
        }
    }
    
    // MARK: - Test 2: Deduplication Logic
    static func testDeduplicationLogic() async {
        print("\n🔄 Test 2: Deduplication Logic")
        print("-" * 40)
        
        do {
            let gatesData = try await makeAPICall(endpoint: "gates?select=*")
            let gates = try JSONDecoder().decode([Gate].self, from: gatesData)
            
            let bindingsData = try await makeAPICall(endpoint: "gate_bindings?select=*")
            let bindings = try JSONDecoder().decode([GateBinding].self, from: bindingsData)
            
            // Simulate deduplication service logic
            let deduplicationService = GateDeduplicationService.shared
            let clusters = try await deduplicationService.findAndMergeDuplicateGates(
                gates: gates,
                bindings: bindings
            )
            
            print("🔍 Found \(clusters.count) duplicate clusters")
            
            for (index, cluster) in clusters.enumerated() {
                print("\n   Cluster \(index + 1):")
                print("   • Primary Gate: \(cluster.primaryGate.name) (\(cluster.primaryGate.id))")
                print("   • Duplicates: \(cluster.duplicateGates.count)")
                print("   • Total Samples: \(cluster.totalSampleCount)")
                print("   • Confidence: \(Int(cluster.highestConfidence * 100))%")
                print("   • Average Location: (\(cluster.averageLocation.latitude), \(cluster.averageLocation.longitude))")
                
                // Test threshold verification
                let thresholdResult = deduplicationService.verifyPostDeduplicationThresholds(cluster: cluster)
                print("   • Meets Threshold: \(thresholdResult.meetsThreshold ? "✅" : "❌")")
                print("   • Recommended Status: \(thresholdResult.recommendedStatus)")
            }
            
        } catch {
            print("❌ Failed to test deduplication logic: \(error)")
        }
    }
    
    // MARK: - Test 3: Check-in Integrity
    static func testCheckinIntegrity() async {
        print("\n📝 Test 3: Check-in Integrity")
        print("-" * 40)
        
        do {
            // Fetch all check-ins
            let checkinsData = try await makeAPICall(endpoint: "checkin_logs?select=*")
            let checkins = try JSONDecoder().decode([CheckinLog].self, from: checkinsData)
            
            print("📋 Total Check-ins: \(checkins.count)")
            
            // Group check-ins by gate_id
            let checkinsByGate = Dictionary(grouping: checkins) { $0.gateId ?? "no_gate" }
            
            print("🏢 Check-ins by Gate:")
            for (gateId, gateCheckins) in checkinsByGate.sorted(by: { $0.value.count > $1.value.count }) {
                if gateId == "no_gate" {
                    print("   • No Gate: \(gateCheckins.count) check-ins")
                } else {
                    print("   • Gate \(gateId.prefix(8))...: \(gateCheckins.count) check-ins")
                }
            }
            
            // Verify gate references exist
            let gatesData = try await makeAPICall(endpoint: "gates?select=id")
            let gates = try JSONDecoder().decode([Gate].self, from: gatesData)
            let validGateIds = Set(gates.map { $0.id })
            
            let checkinGateIds = Set(checkins.compactMap { $0.gateId })
            let orphanedCheckins = checkinGateIds.subtracting(validGateIds)
            
            if orphanedCheckins.isEmpty {
                print("✅ All check-ins reference valid gates")
            } else {
                print("⚠️ ISSUE: \(orphanedCheckins.count) check-ins reference non-existent gates")
                for orphanedId in orphanedCheckins {
                    let count = checkins.filter { $0.gateId == orphanedId }.count
                    print("   • \(orphanedId.prefix(8))...: \(count) orphaned check-ins")
                }
            }
            
        } catch {
            print("❌ Failed to test check-in integrity: \(error)")
        }
    }
    
    // MARK: - Test 4: Threshold Calculations
    static func testThresholdCalculations() async {
        print("\n🎯 Test 4: Threshold Calculations")
        print("-" * 40)
        
        // Test various sample counts and confidence levels
        let testCases = [
            (samples: 3, confidence: 0.4, expectedBinding: false, expectedEnforced: false),
            (samples: 8, confidence: 0.6, expectedBinding: true, expectedEnforced: false),
            (samples: 20, confidence: 0.85, expectedBinding: true, expectedEnforced: true),
            (samples: 60, confidence: 0.65, expectedBinding: true, expectedEnforced: false), // Your actual case
        ]
        
        for (index, testCase) in testCases.enumerated() {
            print("\n   Test Case \(index + 1): \(testCase.samples) samples, \(Int(testCase.confidence * 100))% confidence")
            
            // Create mock cluster for testing
            let mockGate = Gate(
                id: "test-gate-\(index)",
                eventId: "test-event",
                name: "Test Gate \(index)",
                latitude: 0.0,
                longitude: 0.0,
                createdAt: Date(),
                updatedAt: Date()
            )
            
            let mockCluster = GateCluster(
                primaryGate: mockGate,
                duplicateGates: [],
                mergedBindings: [],
                averageLocation: CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0),
                totalSampleCount: testCase.samples,
                highestConfidence: testCase.confidence
            )
            
            let result = GateDeduplicationService.shared.verifyPostDeduplicationThresholds(cluster: mockCluster)
            
            let bindingMatch = result.qualifiesForBinding == testCase.expectedBinding
            let enforcedMatch = result.qualifiesForEnforced == testCase.expectedEnforced
            
            print("   • Qualifies for Binding: \(result.qualifiesForBinding ? "✅" : "❌") \(bindingMatch ? "" : "⚠️ MISMATCH")")
            print("   • Qualifies for Enforced: \(result.qualifiesForEnforced ? "✅" : "❌") \(enforcedMatch ? "" : "⚠️ MISMATCH")")
            print("   • Recommended Status: \(result.recommendedStatus)")
        }
    }
    
    // MARK: - Helper Methods
    static func makeAPICall(endpoint: String) async throws -> Data {
        let url = URL(string: "https://pmrxyisasfaimumuobvu.supabase.co/rest/v1/\(endpoint)")!
        var request = URLRequest(url: url)
        request.setValue("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBtcnh5aXNhc2ZhaW11bXVvYnZ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTMyODQ2ODMsImV4cCI6MjA2ODg2MDY4M30.rVsKq08Ynw82RkCntxWFXOTgP8T0cGyhJvqfrnOH4YQ", forHTTPHeaderField: "apikey")
        request.setValue("Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBtcnh5aXNhc2ZhaW11bXVvYnZ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTMyODQ2ODMsImV4cCI6MjA2ODg2MDY4M30.rVsKq08Ynw82RkCntxWFXOTgP8T0cGyhJvqfrnOH4YQ", forHTTPHeaderField: "Authorization")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }
}

// Extension for string repetition
extension String {
    static func * (string: String, count: Int) -> String {
        return String(repeating: string, count: count)
    }
}

// Run the test
Task {
    await DeduplicationFlowTest.runComprehensiveTest()
}
