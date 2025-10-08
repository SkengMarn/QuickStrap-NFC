import Foundation

/// Simple Gate Cleanup - Addresses your specific concerns about duplicate gates and 0-scan gates
class SimpleGateCleanup: ObservableObject {
    static let shared = SimpleGateCleanup()
    
    private let supabaseService = SupabaseService.shared
    private let gateBindingService = GateBindingService.shared
    
    private init() {}
    
    // MARK: - Main Cleanup Function
    
    /// Clean up gates to match your 4 categories and remove duplicates/0-scan gates
    func performSimpleCleanup(eventId: String) async throws -> SimpleCleanupReport {
        print("🧹 Starting simple gate cleanup for event: \(eventId)")
        
        // Step 1: Get current state
        let allGates = try await gateBindingService.fetchGates()
        let allBindings = try await gateBindingService.fetchAllGateBindings()
        
        print("📊 Before cleanup: \(allGates.count) gates, \(allBindings.count) bindings")
        
        // Step 2: Find gates with 0 scans
        var gatesToDelete: [String] = []
        var gatesKept: [Gate] = []
        
        for gate in allGates {
            let scanCount = try await gateBindingService.getScanCountForGate(gate.id, eventId: eventId)
            
            if scanCount == 0 {
                gatesToDelete.append(gate.id)
                print("🗑️ Marking gate for deletion: \(gate.name) (0 scans)")
            } else {
                gatesKept.append(gate)
                print("✅ Keeping gate: \(gate.name) (\(scanCount) scans)")
            }
        }
        
        // Step 3: Remove duplicate gate names (keep the one with most scans)
        var finalGates: [Gate] = []
        let groupedByName = Dictionary(grouping: gatesKept) { $0.name }
        
        for (gateName, gates) in groupedByName {
            if gates.count > 1 {
                print("🔍 Found \(gates.count) gates named '\(gateName)' - keeping best one")
                
                // Find the gate with most scans
                var bestGate = gates[0]
                var bestScanCount = try await gateBindingService.getScanCountForGate(bestGate.id, eventId: eventId)
                
                for gate in gates.dropFirst() {
                    let scanCount = try await gateBindingService.getScanCountForGate(gate.id, eventId: eventId)
                    if scanCount > bestScanCount {
                        // Mark previous best for deletion
                        gatesToDelete.append(bestGate.id)
                        bestGate = gate
                        bestScanCount = scanCount
                    } else {
                        // Mark this one for deletion
                        gatesToDelete.append(gate.id)
                    }
                }
                
                finalGates.append(bestGate)
                print("✅ Kept best '\(gateName)' gate with \(bestScanCount) scans")
            } else {
                finalGates.append(gates[0])
            }
        }
        
        // Step 4: Delete marked gates
        var deletedCount = 0
        for gateId in gatesToDelete {
            do {
                try await deleteGate(gateId)
                deletedCount += 1
            } catch {
                print("⚠️ Failed to delete gate \(gateId): \(error)")
            }
        }
        
        // Step 5: Clean up orphaned bindings
        var bindingsDeleted = 0
        let remainingGateIds = Set(finalGates.map { $0.id })
        
        for binding in allBindings {
            if !remainingGateIds.contains(binding.gateId) {
                do {
                    try await deleteBinding(gateId: binding.gateId)
                    bindingsDeleted += 1
                    print("🗑️ Deleted orphaned binding for gate: \(binding.gateId.prefix(8))")
                } catch {
                    print("⚠️ Failed to delete binding: \(error)")
                }
            }
        }
        
        let report = SimpleCleanupReport(
            initialGates: allGates.count,
            finalGates: finalGates.count,
            gatesDeleted: deletedCount,
            bindingsDeleted: bindingsDeleted,
            duplicatesRemoved: allGates.count - gatesKept.count,
            zeroScanGatesRemoved: gatesToDelete.count - (allGates.count - gatesKept.count)
        )
        
        print("✅ Simple cleanup complete:")
        print(report.summary)
        
        return report
    }
    
    /// Get a summary of current gate issues
    func analyzeGateIssues(eventId: String) async throws -> GateIssueAnalysis {
        print("🔍 Analyzing gate issues...")
        
        let allGates = try await gateBindingService.fetchGates()
        let allBindings = try await gateBindingService.fetchAllGateBindings()
        
        // Count gates with 0 scans
        var zeroScanGates = 0
        var totalScans = 0
        
        for gate in allGates {
            let scanCount = try await gateBindingService.getScanCountForGate(gate.id, eventId: eventId)
            if scanCount == 0 {
                zeroScanGates += 1
            }
            totalScans += scanCount
        }
        
        // Count duplicate names
        let gateNames = allGates.map { $0.name }
        let uniqueNames = Set(gateNames)
        let duplicateCount = gateNames.count - uniqueNames.count
        
        // Count "Staff Gate" specifically
        let staffGateCount = gateNames.filter { $0.contains("Staff") }.count
        
        // Get confirmed gates count
        let confirmedCount = allBindings.filter { $0.status == .enforced }.count
        
        return GateIssueAnalysis(
            totalGates: allGates.count,
            uniqueGateNames: uniqueNames.count,
            duplicateGates: duplicateCount,
            zeroScanGates: zeroScanGates,
            staffGateCount: staffGateCount,
            confirmedGates: confirmedCount,
            totalScans: totalScans,
            totalBindings: allBindings.count
        )
    }
    
    // MARK: - Database Operations
    
    private func deleteGate(_ gateId: String) async throws {
        let _: [Gate] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/gates?id=eq.\(gateId)",
            method: "DELETE",
            body: nil,
            responseType: [Gate].self
        )
    }
    
    private func deleteBinding(gateId: String) async throws {
        let _: [GateBinding] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/gate_bindings?gate_id=eq.\(gateId)",
            method: "DELETE",
            body: nil,
            responseType: [GateBinding].self
        )
    }
}

// MARK: - Data Models

struct SimpleCleanupReport {
    let initialGates: Int
    let finalGates: Int
    let gatesDeleted: Int
    let bindingsDeleted: Int
    let duplicatesRemoved: Int
    let zeroScanGatesRemoved: Int
    
    var summary: String {
        return """
        🧹 Simple Gate Cleanup Report:
        • Initial Gates: \(initialGates)
        • Final Gates: \(finalGates)
        • Gates Deleted: \(gatesDeleted)
        • Bindings Deleted: \(bindingsDeleted)
        • Duplicates Removed: \(duplicatesRemoved)
        • Zero-Scan Gates Removed: \(zeroScanGatesRemoved)
        • Reduction: \(String(format: "%.1f", Double(gatesDeleted) / Double(initialGates) * 100))%
        """
    }
}

struct GateIssueAnalysis {
    let totalGates: Int
    let uniqueGateNames: Int
    let duplicateGates: Int
    let zeroScanGates: Int
    let staffGateCount: Int
    let confirmedGates: Int
    let totalScans: Int
    let totalBindings: Int
    
    var summary: String {
        return """
        📊 Gate Issue Analysis:
        • Total Gates: \(totalGates) (should be ≤ 4 for your event)
        • Unique Names: \(uniqueGateNames)
        • Duplicate Gates: \(duplicateGates)
        • Gates with 0 Scans: \(zeroScanGates)
        • "Staff Gate" Entries: \(staffGateCount) (you mentioned up to 90!)
        • "Confirmed" Gates: \(confirmedGates) (you mentioned 207!)
        • Total Scans: \(totalScans)
        • Total Bindings: \(totalBindings)
        
        🎯 Issues Found:
        • \(duplicateGates) duplicate gate entries need removal
        • \(zeroScanGates) gates with no activity should be deleted
        • \(confirmedGates) "confirmed" gates is way too many for 4 categories
        """
    }
}
