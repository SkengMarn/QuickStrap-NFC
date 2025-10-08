import Foundation

/// Gate Cleanup Service - Removes duplicate gates and enforces category-based gate management
class GateCleanupService: ObservableObject {
    static let shared = GateCleanupService()
    
    private let supabaseService = SupabaseService.shared
    
    private init() {}
    
    // MARK: - Main Cleanup Function
    
    /// Clean up gates to match your 4 categories and remove duplicates
    func performComprehensiveCleanup(eventId: String) async throws -> CleanupReport {
        print("🧹 Starting comprehensive gate cleanup for event: \(eventId)")
        
        // Step 1: Get current state
        let allGates = try await fetchAllGates(eventId: eventId)
        let allBindings = try await fetchAllBindings(eventId: eventId)
        let categories = try await fetchEventCategories(eventId: eventId)
        
        print("📊 Before cleanup:")
        print("   - Gates: \(allGates.count)")
        print("   - Bindings: \(allBindings.count)")
        print("   - Categories: \(categories.count)")
        
        // Step 2: Identify problems
        let problems = identifyProblems(gates: allGates, bindings: allBindings, categories: categories)
        print("🔍 Found problems:")
        print("   - Duplicate gates: \(problems.duplicateGates.count)")
        print("   - Gates with 0 scans: \(problems.gatesWithZeroScans.count)")
        print("   - Invalid bindings: \(problems.invalidBindings.count)")
        
        // Step 3: Clean up duplicates
        let duplicatesRemoved = try await removeDuplicateGates(problems.duplicateGates, eventId: eventId)
        
        // Step 4: Remove gates with no activity
        let inactiveRemoved = try await removeInactiveGates(problems.gatesWithZeroScans, eventId: eventId)
        
        // Step 5: Clean up invalid bindings
        let bindingsRemoved = try await removeInvalidBindings(problems.invalidBindings, eventId: eventId)
        
        // Step 6: Verify final state
        let finalGates = try await fetchAllGates(eventId: eventId)
        let finalBindings = try await fetchAllBindings(eventId: eventId)
        
        let report = CleanupReport(
            initialGates: allGates.count,
            finalGates: finalGates.count,
            duplicatesRemoved: duplicatesRemoved,
            inactiveGatesRemoved: inactiveRemoved,
            invalidBindingsRemoved: bindingsRemoved,
            categories: categories.count
        )
        
        print("✅ Cleanup complete:")
        print(report.summary)
        
        return report
    }
    
    // MARK: - Problem Identification
    
    private func identifyProblems(gates: [Gate], bindings: [GateBinding], categories: [WristbandCategory]) -> GateProblems {
        let validCategoryNames = Set(categories.map { $0.name })
        
        // Find duplicate gates (same name)
        var gateNameCounts: [String: [Gate]] = [:]
        for gate in gates {
            gateNameCounts[gate.name, default: []].append(gate)
        }
        let duplicateGates = gateNameCounts.values.filter { $0.count > 1 }.flatMap { $0.dropFirst() }
        
        // Find gates with 0 scans (will be checked async)
        let gatesWithZeroScans = gates // Will filter async
        
        // Find invalid bindings (categories that don't exist)
        let invalidBindings = bindings.filter { !validCategoryNames.contains($0.categoryName) }
        
        return GateProblems(
            duplicateGates: Array(duplicateGates),
            gatesWithZeroScans: gatesWithZeroScans,
            invalidBindings: invalidBindings
        )
    }
    
    // MARK: - Cleanup Operations
    
    private func removeDuplicateGates(_ duplicates: [Gate], eventId: String) async throws -> Int {
        var removed = 0
        
        for gate in duplicates {
            do {
                // Check if gate has any scans before deleting
                let scanCount = try await getScanCount(gateId: gate.id, eventId: eventId)
                
                if scanCount == 0 {
                    try await deleteGate(gate.id)
                    print("🗑️ Removed duplicate gate: \(gate.name) (ID: \(gate.id.prefix(8)))")
                    removed += 1
                } else {
                    print("⚠️ Keeping duplicate gate with scans: \(gate.name) (\(scanCount) scans)")
                }
            } catch {
                print("❌ Failed to remove duplicate gate \(gate.id): \(error)")
            }
        }
        
        return removed
    }
    
    private func removeInactiveGates(_ gates: [Gate], eventId: String) async throws -> Int {
        var removed = 0
        
        for gate in gates {
            do {
                let scanCount = try await getScanCount(gateId: gate.id, eventId: eventId)
                
                if scanCount == 0 {
                    try await deleteGate(gate.id)
                    print("🗑️ Removed inactive gate: \(gate.name) (0 scans)")
                    removed += 1
                }
            } catch {
                print("❌ Failed to remove inactive gate \(gate.id): \(error)")
            }
        }
        
        return removed
    }
    
    private func removeInvalidBindings(_ bindings: [GateBinding], eventId: String) async throws -> Int {
        var removed = 0
        
        for binding in bindings {
            do {
                try await deleteBinding(gateId: binding.gateId, categoryName: binding.categoryName)
                print("🗑️ Removed invalid binding: \(binding.categoryName) -> \(binding.gateId.prefix(8))")
                removed += 1
            } catch {
                print("❌ Failed to remove invalid binding: \(error)")
            }
        }
        
        return removed
    }
    
    // MARK: - Database Operations
    
    private func fetchAllGates(eventId: String) async throws -> [Gate] {
        return try await supabaseService.makeRequest(
            endpoint: "rest/v1/gates?event_id=eq.\(eventId)&select=*",
            method: "GET",
            body: nil,
            responseType: [Gate].self
        )
    }
    
    private func fetchAllBindings(eventId: String) async throws -> [GateBinding] {
        return try await supabaseService.makeRequest(
            endpoint: "rest/v1/gate_bindings?event_id=eq.\(eventId)&select=*",
            method: "GET",
            body: nil,
            responseType: [GateBinding].self
        )
    }
    
    private func fetchEventCategories(eventId: String) async throws -> [WristbandCategory] {
        let wristbands: [Wristband] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/wristbands?event_id=eq.\(eventId)&select=category",
            method: "GET",
            body: nil,
            responseType: [Wristband].self
        )
        
        let uniqueCategories = Array(Set(wristbands.map { $0.category }))
        return uniqueCategories.sorted { $0.name < $1.name }
    }
    
    private func getScanCount(gateId: String, eventId: String) async throws -> Int {
        let logs: [CheckinLog] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/checkin_logs?gate_id=eq.\(gateId)&event_id=eq.\(eventId)&select=id",
            method: "GET",
            body: nil,
            responseType: [CheckinLog].self
        )
        return logs.count
    }
    
    private func deleteGate(_ gateId: String) async throws {
        let _: [Gate] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/gates?id=eq.\(gateId)",
            method: "DELETE",
            body: nil,
            responseType: [Gate].self
        )
    }
    
    private func deleteBinding(gateId: String, categoryName: String) async throws {
        let _: [GateBinding] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/gate_bindings?gate_id=eq.\(gateId)&category=eq.\(categoryName)",
            method: "DELETE",
            body: nil,
            responseType: [GateBinding].self
        )
    }
    
    // MARK: - Validation Query (Your SQL Approach)
    
    /// Run validation using your suggested SQL-like approach
    func runValidationQueries(eventId: String) async throws -> ValidationResults {
        print("🔍 Running validation queries...")
        
        // 1. SELECT DISTINCT gate_name to eliminate duplicates
        let allGates = try await fetchAllGates(eventId: eventId)
        let distinctGateNames = Array(Set(allGates.map { $0.name }))
        
        // 2. GROUP BY gate_name with COUNT(scans)
        var gateNameScanCounts: [String: Int] = [:]
        for gateName in distinctGateNames {
            let gatesWithName = allGates.filter { $0.name == gateName }
            var totalScans = 0
            
            for gate in gatesWithName {
                let scanCount = try await getScanCount(gateId: gate.id, eventId: eventId)
                totalScans += scanCount
            }
            
            gateNameScanCounts[gateName] = totalScans
        }
        
        // 3. Filter WHERE scans > 0
        let gatesWithScans = gateNameScanCounts.filter { $0.value > 0 }
        
        // 4. JOIN check-ins to gates
        let totalCheckIns = try await getTotalCheckIns(eventId: eventId)
        let mappedCheckIns = try await getMappedCheckIns(eventId: eventId)
        
        return ValidationResults(
            totalGates: allGates.count,
            distinctGateNames: distinctGateNames.count,
            duplicateCount: allGates.count - distinctGateNames.count,
            gatesWithScans: gatesWithScans.count,
            gatesWithoutScans: distinctGateNames.count - gatesWithScans.count,
            totalCheckIns: totalCheckIns,
            mappedCheckIns: mappedCheckIns,
            unmappedCheckIns: totalCheckIns - mappedCheckIns,
            gateNameScanCounts: gateNameScanCounts
        )
    }
    
    private func getTotalCheckIns(eventId: String) async throws -> Int {
        let logs: [CheckinLog] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/checkin_logs?event_id=eq.\(eventId)&select=id",
            method: "GET",
            body: nil,
            responseType: [CheckinLog].self
        )
        return logs.count
    }
    
    private func getMappedCheckIns(eventId: String) async throws -> Int {
        let logs: [CheckinLog] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/checkin_logs?event_id=eq.\(eventId)&gate_id=not.is.null&select=id",
            method: "GET",
            body: nil,
            responseType: [CheckinLog].self
        )
        return logs.count
    }
}

// MARK: - Data Models

struct GateProblems {
    let duplicateGates: [Gate]
    let gatesWithZeroScans: [Gate]
    let invalidBindings: [GateBinding]
}

struct CleanupReport {
    let initialGates: Int
    let finalGates: Int
    let duplicatesRemoved: Int
    let inactiveGatesRemoved: Int
    let invalidBindingsRemoved: Int
    let categories: Int
    
    var summary: String {
        return """
        🧹 Gate Cleanup Report:
        • Initial Gates: \(initialGates)
        • Final Gates: \(finalGates)
        • Duplicates Removed: \(duplicatesRemoved)
        • Inactive Gates Removed: \(inactiveGatesRemoved)
        • Invalid Bindings Removed: \(invalidBindingsRemoved)
        • Valid Categories: \(categories)
        • Reduction: \(initialGates - finalGates) gates (\(String(format: "%.1f", Double(initialGates - finalGates) / Double(initialGates) * 100))%)
        """
    }
}

struct ValidationResults {
    let totalGates: Int
    let distinctGateNames: Int
    let duplicateCount: Int
    let gatesWithScans: Int
    let gatesWithoutScans: Int
    let totalCheckIns: Int
    let mappedCheckIns: Int
    let unmappedCheckIns: Int
    let gateNameScanCounts: [String: Int]
    
    var mappingEfficiency: Double {
        guard totalCheckIns > 0 else { return 0.0 }
        return Double(mappedCheckIns) / Double(totalCheckIns)
    }
    
    var summary: String {
        return """
        📊 Validation Results (SQL-like Analysis):
        • SELECT DISTINCT gate_name: \(distinctGateNames) unique names
        • Total gates: \(totalGates) (duplicates: \(duplicateCount))
        • GROUP BY gate_name WHERE scans > 0: \(gatesWithScans) active gates
        • Gates with 0 scans: \(gatesWithoutScans)
        • JOIN checkins ON gates: \(mappedCheckIns)/\(totalCheckIns) mapped (\(String(format: "%.1f", mappingEfficiency * 100))%)
        • Unmapped check-ins: \(unmappedCheckIns)
        """
    }
}
