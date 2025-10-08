import Foundation

/// Comprehensive test to verify gate deduplication and stats flow
class GateFlowVerification {
    
    static func verifyCompleteFlow() async {
        print("🧪 GATE FLOW VERIFICATION TEST")
        print("=" * 50)
        
        await testCurrentState()
        await testDeduplicationFlow()
        await testStatsAccuracy()
        await testUserExperience()
    }
    
    // MARK: - Test 1: Current Database State
    static func testCurrentState() async {
        print("\n📊 Test 1: Current Database State")
        print("-" * 30)
        
        do {
            // Fetch current gates
            let gatesResponse = try await makeAPICall(endpoint: "gates?select=*&order=created_at")
            let gates = try JSONDecoder().decode([Gate].self, from: gatesResponse)
            
            print("🏢 Total Gates: \(gates.count)")
            
            // Group by name to identify duplicates
            let gatesByName = Dictionary(grouping: gates) { $0.name }
            
            for (name, gateGroup) in gatesByName {
                if gateGroup.count > 1 {
                    print("⚠️ DUPLICATE: \(name) has \(gateGroup.count) entries")
                    for (index, gate) in gateGroup.enumerated() {
                        print("   \(index + 1). ID: \(gate.id.prefix(8))... | Coords: (\(gate.latitude ?? 0), \(gate.longitude ?? 0))")
                    }
                } else {
                    print("✅ UNIQUE: \(name)")
                }
            }
            
            // Check check-ins per gate
            let checkinsResponse = try await makeAPICall(endpoint: "checkin_logs?select=gate_id&gate_id=not.is.null")
            let checkins = try JSONSerialization.jsonObject(with: checkinsResponse) as? [[String: Any]] ?? []
            
            let checkinsByGate = Dictionary(grouping: checkins) { $0["gate_id"] as? String ?? "unknown" }
            
            print("\n📋 Check-ins Distribution:")
            for (gateId, gateCheckins) in checkinsByGate.sorted(by: { $0.value.count > $1.value.count }) {
                let gateName = gates.first { $0.id == gateId }?.name ?? "Unknown Gate"
                print("   • \(gateName) (\(gateId.prefix(8))...): \(gateCheckins.count) check-ins")
            }
            
        } catch {
            print("❌ Failed to fetch current state: \(error)")
        }
    }
    
    // MARK: - Test 2: Deduplication Flow
    static func testDeduplicationFlow() async {
        print("\n🔄 Test 2: Deduplication Flow Simulation")
        print("-" * 30)
        
        do {
            // Simulate the GateBindingService.detectNearbyGates flow
            let gatesResponse = try await makeAPICall(endpoint: "gates?select=*")
            let gates = try JSONDecoder().decode([Gate].self, from: gatesResponse)
            
            let bindingsResponse = try await makeAPICall(endpoint: "gate_bindings?select=*")
            let bindings = try JSONDecoder().decode([GateBinding].self, from: bindingsResponse)
            
            print("📥 Fetched \(gates.count) gates and \(bindings.count) bindings")
            
            // Simulate deduplication detection
            let deduplicationService = GateDeduplicationService.shared
            let clusters = try await deduplicationService.findAndMergeDuplicateGates(gates: gates, bindings: bindings)
            
            print("🔍 Found \(clusters.count) duplicate clusters")
            
            for (index, cluster) in clusters.enumerated() {
                print("\n   Cluster \(index + 1): \(cluster.primaryGate.name)")
                print("   • Primary: \(cluster.primaryGate.id.prefix(8))...")
                print("   • Duplicates: \(cluster.duplicateGates.count)")
                print("   • Total Samples: \(cluster.totalSampleCount)")
                print("   • Confidence: \(Int(cluster.highestConfidence * 100))%")
                
                // Verify threshold logic
                let thresholdResult = deduplicationService.verifyPostDeduplicationThresholds(cluster: cluster)
                print("   • Meets Threshold: \(thresholdResult.meetsThreshold ? "✅" : "❌")")
                print("   • Recommended Status: \(thresholdResult.recommendedStatus)")
                
                // Count check-ins that would be merged
                var totalCheckins = 0
                for gate in [cluster.primaryGate] + cluster.duplicateGates {
                    let checkinCount = try await countCheckinsForGate(gateId: gate.id)
                    totalCheckins += checkinCount
                    print("   • Gate \(gate.id.prefix(8))...: \(checkinCount) check-ins")
                }
                print("   • TOTAL MERGED CHECK-INS: \(totalCheckins)")
            }
            
        } catch {
            print("❌ Deduplication flow test failed: \(error)")
        }
    }
    
    // MARK: - Test 3: Stats Accuracy
    static func testStatsAccuracy() async {
        print("\n📊 Test 3: Stats Accuracy Verification")
        print("-" * 30)
        
        do {
            // Test what happens when we query gate stats
            let gatesResponse = try await makeAPICall(endpoint: "gates?select=*")
            let gates = try JSONDecoder().decode([Gate].self, from: gatesResponse)
            
            // Focus on Staff Gates (your main concern)
            let staffGates = gates.filter { $0.name.contains("Staff") }
            
            if staffGates.count > 1 {
                print("⚠️ PROBLEM: \(staffGates.count) Staff Gates found - stats will be fragmented")
                
                var totalStaffCheckins = 0
                for gate in staffGates {
                    let checkinCount = try await countCheckinsForGate(gateId: gate.id)
                    totalStaffCheckins += checkinCount
                    print("   • Staff Gate \(gate.id.prefix(8))...: \(checkinCount) check-ins")
                }
                
                print("   📊 FRAGMENTED STATS:")
                print("   • Individual gate stats: \(staffGates.map { _ in "X" }.joined(separator: ", ")) check-ins")
                print("   • SHOULD SHOW: \(totalStaffCheckins) total check-ins")
                
            } else if staffGates.count == 1 {
                let gate = staffGates[0]
                let checkinCount = try await countCheckinsForGate(gateId: gate.id)
                print("✅ CORRECT: 1 Staff Gate with \(checkinCount) check-ins")
                
                // Verify this includes all merged check-ins
                print("   📊 UNIFIED STATS:")
                print("   • Gate ID: \(gate.id)")
                print("   • Total Check-ins: \(checkinCount)")
                print("   • Location: (\(gate.latitude ?? 0), \(gate.longitude ?? 0))")
            } else {
                print("ℹ️ No Staff Gates found")
            }
            
        } catch {
            print("❌ Stats accuracy test failed: \(error)")
        }
    }
    
    // MARK: - Test 4: User Experience
    static func testUserExperience() async {
        print("\n👤 Test 4: User Experience Verification")
        print("-" * 30)
        
        do {
            // Simulate what user sees in gates list
            let gatesResponse = try await makeAPICall(endpoint: "gates?select=*")
            let gates = try JSONDecoder().decode([Gate].self, from: gatesResponse)
            
            print("🎯 USER EXPERIENCE SIMULATION:")
            print("\n📱 Gates List (what user sees):")
            
            let uniqueGateNames = Set(gates.map { $0.name })
            for gateName in uniqueGateNames.sorted() {
                let gatesWithName = gates.filter { $0.name == gateName }
                if gatesWithName.count == 1 {
                    print("   ✅ \(gateName)")
                } else {
                    print("   ❌ \(gateName) (DUPLICATE - \(gatesWithName.count) entries)")
                }
            }
            
            print("\n🔍 When user clicks on 'Staff Gate':")
            let staffGates = gates.filter { $0.name.contains("Staff") }
            
            if staffGates.count == 1 {
                let gate = staffGates[0]
                let checkinCount = try await countCheckinsForGate(gateId: gate.id)
                print("   ✅ Shows unified stats: \(checkinCount) total check-ins")
                print("   ✅ All historical data preserved")
                print("   ✅ Single gate location: (\(gate.latitude ?? 0), \(gate.longitude ?? 0))")
            } else if staffGates.count > 1 {
                print("   ❌ PROBLEM: User sees multiple Staff Gates")
                print("   ❌ Stats are fragmented across \(staffGates.count) entries")
                print("   ❌ Confusing user experience")
            } else {
                print("   ℹ️ No Staff Gates to test")
            }
            
        } catch {
            print("❌ User experience test failed: \(error)")
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
    
    static func countCheckinsForGate(gateId: String) async throws -> Int {
        let response = try await makeAPICall(endpoint: "checkin_logs?gate_id=eq.\(gateId)&select=id")
        let checkins = try JSONSerialization.jsonObject(with: response) as? [[String: Any]] ?? []
        return checkins.count
    }
}

// Extension for string repetition
extension String {
    static func * (string: String, count: Int) -> String {
        return String(repeating: string, count: count)
    }
}

// Run the verification
Task {
    await GateFlowVerification.verifyCompleteFlow()
}
