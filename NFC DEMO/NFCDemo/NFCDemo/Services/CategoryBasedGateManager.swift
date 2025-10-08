import Foundation
import CoreLocation

/// Category-Based Gate Manager - Maps check-ins to actual event gate categories instead of creating virtual gates
class CategoryBasedGateManager: ObservableObject {
    static let shared = CategoryBasedGateManager()
    
    private let supabaseService = SupabaseService.shared
    
    @Published var categoryGates: [CategoryGate] = []
    @Published var checkInMappings: [String: [CheckinLog]] = [:] // Category -> Check-ins
    
    // MARK: - Models
    
    struct CategoryGate: Identifiable, Codable {
        let id: String
        let categoryName: String
        let displayName: String
        let eventId: String
        let checkInCount: Int
        let lastCheckIn: Date?
        let isActive: Bool
        
        var formattedLastCheckIn: String {
            guard let lastCheckIn = lastCheckIn else { return "Never" }
            let formatter = RelativeDateTimeFormatter()
            return formatter.localizedString(for: lastCheckIn, relativeTo: Date())
        }
    }
    
    struct CheckInSummary {
        let totalCheckIns: Int
        let categoriesWithCheckIns: Int
        let mostActiveCategory: String?
        let checkInsByCategory: [String: Int]
    }
    
    private init() {}
    
    // MARK: - Category-Based Gate Management
    
    /// Initialize gates based on actual event categories (should be 4 for your event)
    func initializeCategoryGates(eventId: String) async throws {
        print("🎯 Initializing category-based gates for event: \(eventId)")
        
        // Get actual event categories from wristbands
        let categories = try await fetchEventCategories(eventId: eventId)
        print("📋 Found \(categories.count) actual categories: \(categories.map { $0.name }.joined(separator: ", "))")
        
        // Create category gates and get their check-in counts
        var categoryGates: [CategoryGate] = []
        var checkInMappings: [String: [CheckinLog]] = [:]
        
        for category in categories {
            // Get check-ins for this category
            let checkIns = try await getCheckInsForCategory(category.name, eventId: eventId)
            let lastCheckIn = checkIns.max(by: { ($0.createdAt ?? Date.distantPast) < ($1.createdAt ?? Date.distantPast) })?.createdAt
            
            let categoryGate = CategoryGate(
                id: "\(eventId)_\(category.name)",
                categoryName: category.name,
                displayName: "\(category.displayName) Gate",
                eventId: eventId,
                checkInCount: checkIns.count,
                lastCheckIn: lastCheckIn,
                isActive: checkIns.count > 0
            )
            
            categoryGates.append(categoryGate)
            checkInMappings[category.name] = checkIns
            
            print("✅ Category Gate: \(categoryGate.displayName) - \(checkIns.count) check-ins")
        }
        
        await MainActor.run {
            self.categoryGates = categoryGates
            self.checkInMappings = checkInMappings
        }
        
        print("🎉 Initialized \(categoryGates.count) category gates (filtered from potential hundreds of virtual gates)")
    }
    
    /// Get comprehensive check-in summary
    func getCheckInSummary(eventId: String) async throws -> CheckInSummary {
        let categories = try await fetchEventCategories(eventId: eventId)
        var checkInsByCategory: [String: Int] = [:]
        var totalCheckIns = 0
        
        for category in categories {
            let checkIns = try await getCheckInsForCategory(category.name, eventId: eventId)
            checkInsByCategory[category.name] = checkIns.count
            totalCheckIns += checkIns.count
        }
        
        let categoriesWithCheckIns = checkInsByCategory.values.filter { $0 > 0 }.count
        let mostActiveCategory = checkInsByCategory.max(by: { $0.value < $1.value })?.key
        
        return CheckInSummary(
            totalCheckIns: totalCheckIns,
            categoriesWithCheckIns: categoriesWithCheckIns,
            mostActiveCategory: mostActiveCategory,
            checkInsByCategory: checkInsByCategory
        )
    }
    
    /// Clean up duplicate and virtual gates - keep only category-based gates
    func cleanupVirtualGates(eventId: String) async throws {
        print("🧹 Cleaning up virtual gates and duplicates...")
        
        // Get all current gates
        let allGates = try await GateBindingService.shared.fetchGates()
        let allBindings = try await GateBindingService.shared.fetchAllGateBindings()
        
        print("📊 Before cleanup: \(allGates.count) gates, \(allBindings.count) bindings")
        
        // Get actual categories
        let categories = try await fetchEventCategories(eventId: eventId)
        let validCategoryNames = Set(categories.map { $0.name })
        
        // Find gates/bindings that don't match actual categories or have no activity
        var gatesToDelete: [String] = []
        var bindingsToDelete: [String] = []
        
        for gate in allGates {
            let scanCount = try await GateBindingService.shared.getScanCountForGate(gate.id, eventId: eventId)
            let hasValidBinding = allBindings.contains { binding in
                binding.gateId == gate.id && validCategoryNames.contains(binding.categoryName)
            }
            
            // Delete if: no scans AND (no valid category binding OR duplicate name)
            if scanCount == 0 && !hasValidBinding {
                gatesToDelete.append(gate.id)
                print("🗑️ Marking gate for deletion: \(gate.name) (0 scans, invalid category)")
            }
        }
        
        // Find bindings for non-existent categories or duplicate categories
        for binding in allBindings {
            if !validCategoryNames.contains(binding.categoryName) {
                bindingsToDelete.append(binding.gateId)
                print("🗑️ Marking binding for deletion: \(binding.categoryName) (invalid category)")
            }
        }
        
        // Delete invalid gates and bindings
        try await deleteInvalidGatesAndBindings(
            gateIds: gatesToDelete,
            bindingGateIds: bindingsToDelete,
            eventId: eventId
        )
        
        print("✅ Cleanup complete: Removed \(gatesToDelete.count) gates and \(bindingsToDelete.count) bindings")
    }
    
    /// Map check-in to appropriate category gate
    func mapCheckInToCategoryGate(checkIn: CheckinLog, eventId: String) async throws -> CategoryGate? {
        // Get the wristband to determine category
        guard let wristband = try await getWristband(checkIn.wristbandId) else {
            print("⚠️ Could not find wristband for check-in: \(checkIn.id)")
            return nil
        }
        
        // Find the category gate
        let categoryGate = categoryGates.first { $0.categoryName == wristband.category.name }
        
        if let gate = categoryGate {
            print("✅ Mapped check-in to \(gate.displayName)")
        } else {
            print("⚠️ No category gate found for category: \(wristband.category.name)")
        }
        
        return categoryGate
    }
    
    // MARK: - Data Fetching
    
    private func fetchEventCategories(eventId: String) async throws -> [WristbandCategory] {
        // Get unique categories from wristbands for this event
        let wristbands: [Wristband] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/wristbands?event_id=eq.\(eventId)&select=category",
            method: "GET",
            body: nil,
            responseType: [Wristband].self
        )
        
        // Extract unique categories
        let uniqueCategories = Array(Set(wristbands.map { $0.category }))
        return uniqueCategories.sorted { $0.name < $1.name }
    }
    
    private func getCheckInsForCategory(_ categoryName: String, eventId: String) async throws -> [CheckinLog] {
        // Get check-ins for wristbands of this category
        let checkIns: [CheckinLog] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/checkin_logs_with_category?event_id=eq.\(eventId)&wristband_category=eq.\(categoryName)&select=*",
            method: "GET",
            body: nil,
            responseType: [CheckinLog].self
        )
        
        return checkIns
    }
    
    private func getWristband(_ wristbandId: String) async throws -> Wristband? {
        let wristbands: [Wristband] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/wristbands?id=eq.\(wristbandId)&select=*",
            method: "GET",
            body: nil,
            responseType: [Wristband].self
        )
        
        return wristbands.first
    }
    
    private func deleteInvalidGatesAndBindings(gateIds: [String], bindingGateIds: [String], eventId: String) async throws {
        // Delete invalid gates
        for gateId in gateIds {
            do {
                let _: [Gate] = try await supabaseService.makeRequest(
                    endpoint: "rest/v1/gates?id=eq.\(gateId)",
                    method: "DELETE",
                    body: nil,
                    responseType: [Gate].self
                )
                print("🗑️ Deleted gate: \(gateId)")
            } catch {
                print("⚠️ Failed to delete gate \(gateId): \(error)")
            }
        }
        
        // Delete invalid bindings
        for gateId in bindingGateIds {
            do {
                let _: [GateBinding] = try await supabaseService.makeRequest(
                    endpoint: "rest/v1/gate_bindings?gate_id=eq.\(gateId)",
                    method: "DELETE",
                    body: nil,
                    responseType: [GateBinding].self
                )
                print("🗑️ Deleted binding for gate: \(gateId)")
            } catch {
                print("⚠️ Failed to delete binding for gate \(gateId): \(error)")
            }
        }
    }
    
    // MARK: - Validation Queries (SQL-like operations)
    
    /// Validate gate data using your suggested SQL approach
    func validateGateData(eventId: String) async throws -> GateValidationReport {
        print("🔍 Running gate data validation...")
        
        // 1. Get distinct gate names (eliminate duplicates)
        let allGates = try await GateBindingService.shared.fetchGates()
        let distinctGateNames = Array(Set(allGates.map { $0.name }))
        let duplicateCount = allGates.count - distinctGateNames.count
        
        // 2. Group by gate name with scan counts
        var gateNameScanCounts: [String: Int] = [:]
        for gateName in distinctGateNames {
            let gatesWithName = allGates.filter { $0.name == gateName }
            var totalScans = 0
            
            for gate in gatesWithName {
                let scanCount = try await GateBindingService.shared.getScanCountForGate(gate.id, eventId: eventId)
                totalScans += scanCount
            }
            
            gateNameScanCounts[gateName] = totalScans
        }
        
        // 3. Filter gates with scans > 0
        let gatesWithScans = gateNameScanCounts.filter { $0.value > 0 }
        
        // 4. Check check-in to gate mapping
        let totalCheckIns = try await getTotalCheckIns(eventId: eventId)
        let mappedCheckIns = try await getMappedCheckIns(eventId: eventId)
        
        return GateValidationReport(
            totalGates: allGates.count,
            distinctGateNames: distinctGateNames.count,
            duplicateGates: duplicateCount,
            gatesWithScans: gatesWithScans.count,
            gatesWithoutScans: distinctGateNames.count - gatesWithScans.count,
            totalCheckIns: totalCheckIns,
            mappedCheckIns: mappedCheckIns,
            unmappedCheckIns: totalCheckIns - mappedCheckIns,
            gateNameScanCounts: gateNameScanCounts
        )
    }
    
    private func getTotalCheckIns(eventId: String) async throws -> Int {
        let checkIns: [CheckinLog] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/checkin_logs?event_id=eq.\(eventId)&select=id",
            method: "GET",
            body: nil,
            responseType: [CheckinLog].self
        )
        return checkIns.count
    }
    
    private func getMappedCheckIns(eventId: String) async throws -> Int {
        let checkIns: [CheckinLog] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/checkin_logs?event_id=eq.\(eventId)&gate_id=not.is.null&select=id",
            method: "GET",
            body: nil,
            responseType: [CheckinLog].self
        )
        return checkIns.count
    }
}

// MARK: - Validation Report

struct GateValidationReport {
    let totalGates: Int
    let distinctGateNames: Int
    let duplicateGates: Int
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
    
    var duplicatePercentage: Double {
        guard totalGates > 0 else { return 0.0 }
        return Double(duplicateGates) / Double(totalGates) * 100.0
    }
    
    var summary: String {
        return """
        📊 Gate Validation Report:
        • Total Gates: \(totalGates)
        • Distinct Names: \(distinctGateNames)
        • Duplicates: \(duplicateGates) (\(String(format: "%.1f", duplicatePercentage))%)
        • Gates with Scans: \(gatesWithScans)
        • Gates without Scans: \(gatesWithoutScans)
        • Total Check-ins: \(totalCheckIns)
        • Mapped Check-ins: \(mappedCheckIns)
        • Unmapped Check-ins: \(unmappedCheckIns)
        • Mapping Efficiency: \(String(format: "%.1f", mappingEfficiency * 100))%
        """
    }
}
