import Foundation
import Combine
import SwiftUI

// Helper struct for minimal check-in data
private struct MinimalCheckIn: Codable {
    let id: String
}

@MainActor
class GatesViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var gatesWithMetrics: [GateWithMetrics] = []
    @Published var isLoading = false
    @Published var isProcessing = false
    @Published var selectedTimeRange: TimeRange = .all
    @Published var errorMessage: String?
    @Published var processedCount = 0
    @Published var lastProcessedTime: Date?
    @Published var gateStatistics: [String: GateDetailStats] = [:]
    @Published var activityTimeline: [TimelinePoint] = []
    @Published var duplicateGatesCount = 0
    @Published var categoryStats: [CategoryStat] = []

    // Computed from gatesWithMetrics
    var activeGates: [Gate] {
        gatesWithMetrics.map { $0.toGate() }
    }

    var totalCheckins: Int {
        gatesWithMetrics.reduce(0) { $0 + ($1.totalScans ?? 0) }
    }

    var dataQuality: Double {
        guard !gatesWithMetrics.isEmpty else { return 0 }
        let avgConfidence = gatesWithMetrics.map { $0.confidence }.reduce(0, +) / Double(gatesWithMetrics.count)
        return avgConfidence * 100
    }

    var dataQualityDescription: String {
        let quality = dataQuality
        let rating = quality >= 85 ? "Excellent" : quality >= 70 ? "Good" : "Needs attention"
        return "\(Int(quality))% - \(rating)"
    }

    var dataQualityStatus: HealthStatus {
        if dataQuality >= 85 { return .good }
        if dataQuality >= 70 { return .warning }
        return .attention
    }

    var linkingPercentage: Double {
        guard totalCheckins > 0 else { return 0 }
        // All gates with check-ins are linked by SQL
        return 100.0
    }
    
    enum TimeRange: String, CaseIterable {
        case today = "Today"
        case week = "This Week"
        case month = "This Month"
        case all = "All Time"
        
        var icon: String {
            switch self {
            case .today: return "calendar"
            case .week: return "calendar.badge.clock"
            case .month: return "calendar.badge.plus"
            case .all: return "calendar.badge.exclamationmark"
            }
        }
        
        var dateRange: (start: Date, end: Date) {
            let calendar = Calendar.current
            let now = Date()
            
            switch self {
            case .today:
                let startOfDay = calendar.startOfDay(for: now)
                return (startOfDay, now)
            case .week:
                let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
                return (startOfWeek, now)
            case .month:
                let startOfMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
                return (startOfMonth, now)
            case .all:
                return (Date.distantPast, now)
            }
        }
    }
    
    // MARK: - Private Properties

    private let supabaseService = SupabaseService.shared
    private let processor = RealSchemaCheckInProcessor.shared
    private let orchestrator = GateSystemOrchestrator.shared
    private var refreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Advanced System Properties

    @Published var systemComparison: GateDiscoveryComparison?
    @Published var useAdvancedSystem = false
    @Published var showComparisonMetrics = false
    
    // MARK: - Computed Properties

    var filteredGates: [Gate] {
        // Gates are already filtered by SQL view (only active gates with check-ins)
        // Sort by scan count (descending - highest first)
        return gatesWithMetrics
            .sorted { ($0.totalScans ?? 0) > ($1.totalScans ?? 0) }
            .map { $0.toGate() }
    }
    
    var enforcedGatesCount: Int {
        // Count enforced bindings from gate metrics
        gatesWithMetrics.reduce(0) { count, gate in
            let enforced = gate.categoryBindings?.values.filter { $0.status.lowercased() == "enforced" }.count ?? 0
            return count + enforced
        }
    }

    var probationGatesCount: Int {
        // Count probation bindings from gate metrics
        gatesWithMetrics.reduce(0) { count, gate in
            let probation = gate.categoryBindings?.values.filter { $0.status.lowercased() == "probation" }.count ?? 0
            return count + probation
        }
    }

    var checkinChange: String {
        // Calculate 24h change
        let change = calculateCheckinChange()
        let prefix = change >= 0 ? "+" : ""
        return "\(prefix)\(change)%"
    }

    var unlinkedCount: Int {
        // With SQL automation, all gates with check-ins are linked
        return 0
    }

    var gateBindings: [GateBinding] {
        // Extract bindings from gatesWithMetrics
        var bindings: [GateBinding] = []
        for gate in gatesWithMetrics {
            if let categoryBindings = gate.categoryBindings {
                for (categoryName, binding) in categoryBindings {
                    let gateBinding = GateBinding(
                        gateId: gate.gateId,
                        categoryName: categoryName,
                        status: binding.status == "enforced" ? .enforced : (binding.status == "probation" ? .probation : .unbound),
                        confidence: binding.confidence,
                        sampleCount: binding.sampleCount,
                        eventId: gate.eventId
                    )
                    bindings.append(gateBinding)
                }
            }
        }
        return bindings
    }
    
    // MARK: - Initialization
    
    init() {
        setupProcessorObservation()
    }
    
    private func setupProcessorObservation() {
        processor.$isProcessing
            .receive(on: DispatchQueue.main)
            .assign(to: &$isProcessing)
        
        processor.$processedCount
            .receive(on: DispatchQueue.main)
            .assign(to: &$processedCount)
        
        processor.$lastProcessedTime
            .receive(on: DispatchQueue.main)
            .assign(to: &$lastProcessedTime)
    }
    
    // MARK: - Public Methods
    
    func startMonitoring() {
        Task {
            await loadAllData()
        }
        
        // Refresh every 30 seconds
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task {
                await self?.refreshData()
            }
        }
        
        // Start background processing
        startBackgroundProcessing()
    }
    
    func stopMonitoring() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    func refreshData() async {
        print("🔄 Refreshing data for time range: \(selectedTimeRange.rawValue)")
        await MainActor.run {
            self.isLoading = true
            // Clear existing data to force complete refresh
            self.gateStatistics.removeAll()
            self.categoryStats.removeAll()
            self.activityTimeline.removeAll()
        }
        await loadAllData()
    }
    
    func updateTimeRange(_ range: TimeRange) {
        selectedTimeRange = range
        Task {
            await refreshData()
        }
    }
    
    func filterByTimeRange(_ range: TimeRange) {
        Task {
            await loadActivityTimeline(for: range)
        }
    }
    
    func exportData() {
        Task {
            await performDataExport()
        }
    }

    // MARK: - Advanced System Methods

    /// Run parallel validation comparing legacy and advanced systems
    func runSystemComparison() async {
        guard let eventId = supabaseService.currentEvent?.id else {
            print("❌ No event selected")
            return
        }

        await MainActor.run {
            isProcessing = true
        }

        do {
            // Fetch all check-in logs
            let logs: [CheckinLog] = try await supabaseService.makeRequest(
                endpoint: "rest/v1/checkin_logs?event_id=eq.\(eventId)&select=*",
                method: "GET",
                body: nil,
                responseType: [CheckinLog].self
            )

            print("🔬 Running system comparison with \(logs.count) check-ins...")

            // Run parallel comparison
            let comparison = try await orchestrator.discoverGates(
                from: logs,
                eventId: eventId
            )

            await MainActor.run {
                self.systemComparison = comparison
                self.isProcessing = false
                self.showComparisonMetrics = true
            }

            print("✅ System comparison complete")

        } catch {
            print("❌ System comparison failed: \(error)")
            await MainActor.run {
                self.isProcessing = false
            }
        }
    }

    /// Toggle between legacy and advanced system
    func toggleSystemMode() {
        useAdvancedSystem.toggle()
        orchestrator.config.useAdvancedSystemForDecisions = useAdvancedSystem

        print("🔄 Switched to \(useAdvancedSystem ? "Advanced" : "Legacy") system")
    }

    /// Get average improvement metrics across all comparisons
    func getAverageImprovements() -> (gateReduction: Double, duplicateReduction: Double, scansPerGateIncrease: Double) {
        return orchestrator.getAverageImprovement()
    }
    
    func getGateStats(for gate: Gate) -> GateStats {
        // Find the metrics for this gate
        guard let metrics = gatesWithMetrics.first(where: { $0.gateId == gate.id }) else {
            return GateStats(
                status: .unbound,
                confidence: 0,
                totalScans: 0,
                lastHourScans: 0,
                avgPerHour: 0,
                peakHour: 0,
                categories: []
            )
        }

        // Determine binding status from category bindings
        let hasEnforced = metrics.categoryBindings?.values.contains { $0.status == "enforced" } ?? false
        let hasProbation = metrics.categoryBindings?.values.contains { $0.status == "probation" } ?? false
        let bindingStatus: GateBindingStatus = hasEnforced ? .enforced : (hasProbation ? .probation : .unbound)

        return GateStats(
            status: bindingStatus,
            confidence: metrics.confidence,
            totalScans: metrics.totalScans,
            lastHourScans: 0, // Not provided by view yet
            avgPerHour: 0,    // Not provided by view yet
            peakHour: 0,      // Not provided by view yet
            categories: metrics.categoryNames
        )
    }
    
    // MARK: - UUID Validation
    
    private func validateEventId(_ eventId: String) throws {
        print("🔍 Validating event ID: '\(eventId)' (length: \(eventId.count))")
        
        // Check for common issues
        if eventId.isEmpty {
            print("❌ Event ID is empty")
            throw NSError(domain: "GatesViewModel", code: 400, userInfo: [NSLocalizedDescriptionKey: "Event ID is empty"])
        }
        
        if eventId.contains(" ") {
            print("❌ Event ID contains spaces")
            throw NSError(domain: "GatesViewModel", code: 400, userInfo: [NSLocalizedDescriptionKey: "Event ID contains invalid characters (spaces)"])
        }
        
        guard UUID(uuidString: eventId) != nil else {
            print("❌ Invalid UUID format for event ID: '\(eventId)'")
            print("   Expected format: XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX")
            throw NSError(domain: "GatesViewModel", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid event ID format: \(eventId)"])
        }
        
        print("✅ Event ID validation passed")
    }
    
    // MARK: - Data Loading (Simplified - Uses SQL View)

    private func loadAllData() async {
        guard let currentEvent = supabaseService.currentEvent else {
            print("❌ No event selected")
            return
        }
        
        let eventId = currentEvent.id
        let seriesId = currentEvent.seriesId

        // Validate UUID format
        do {
            try validateEventId(eventId)
        } catch {
            print("❌ Event ID validation failed: \(error.localizedDescription)")
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = "Invalid event ID"
            }
            return
        }

        // Determine query based on series vs parent event
        let endpoint: String
        if let seriesId = seriesId {
            print("🔄 Fetching gates from v_gates_complete view for SERIES: \(seriesId)")
            endpoint = "rest/v1/v_gates_complete?series_id=eq.\(seriesId)&select=*"
        } else {
            print("🔄 Fetching gates from v_gates_complete view for PARENT EVENT: \(eventId)")
            endpoint = "rest/v1/v_gates_complete?event_id=eq.\(eventId)&series_id=is.null&select=*"
        }

        do {
            // Fetch all gate data from the comprehensive SQL view
            let gates: [GateWithMetrics] = try await supabaseService.makeRequest(
                endpoint: endpoint,
                method: "GET",
                responseType: [GateWithMetrics].self
            )

            print("✅ Loaded \(gates.count) gates from v_gates_complete")
            print("   - Enforcing: \(gates.filter { $0.isEnforcing }.count)")
            print("   - Needs attention: \(gates.filter { $0.needsAttention }.count)")
            print("   - Total scans: \(gates.reduce(0) { $0 + $1.totalScans })")

            await MainActor.run {
                self.gatesWithMetrics = gates
                self.isLoading = false
                self.errorMessage = nil
                print("📊 Updated UI with \(gates.count) gates")
            }

        } catch {
            print("❌ Failed to fetch gates: \(error)")
            await MainActor.run {
                self.gatesWithMetrics = []
                self.isLoading = false
                self.errorMessage = "Failed to load gates: \(error.localizedDescription)"
            }
        }
    }
    
    private func fetchGates(eventId: String) async throws -> [Gate] {
        // Validate UUID format before making request
        try validateEventId(eventId)

        do {
            print("🔍 Fetching gates with check-ins for event: \(eventId)")

            // Only fetch gates that have at least one check-in
            // This ensures we only show SQL-automated gates that are actually in use
            struct GateWithCheckinCount: Codable {
                let id: String
                let eventId: String
                let name: String
                let latitude: Double?
                let longitude: Double?
                let status: Gate.GateStatus
                let healthScore: Int?
                let locationDescription: String?
                let seriesId: String?
                let createdAt: Date
                let updatedAt: Date?
                let checkinCount: Int?

                enum CodingKeys: String, CodingKey {
                    case id
                    case eventId = "event_id"
                    case name, latitude, longitude, status
                    case healthScore = "health_score"
                    case locationDescription = "location_description"
                    case seriesId = "series_id"
                    case createdAt = "created_at"
                    case updatedAt = "updated_at"
                    case checkinCount = "checkin_count"
                }

                func toGate() -> Gate {
                    return Gate(
                        id: id,
                        eventId: eventId,
                        name: name,
                        latitude: latitude,
                        longitude: longitude,
                        status: status,
                        healthScore: healthScore,
                        locationDescription: locationDescription,
                        seriesId: seriesId,
                        createdAt: createdAt,
                        updatedAt: updatedAt
                    )
                }
            }

            // Determine query based on series vs parent event context
            let currentEvent = supabaseService.currentEvent
            let endpoint: String
            if let seriesId = currentEvent?.seriesId {
                endpoint = "rest/v1/gates?series_id=eq.\(seriesId)&select=*,checkin_count:checkin_logs(count)&order=created_at.desc"
            } else {
                endpoint = "rest/v1/gates?event_id=eq.\(eventId)&series_id=is.null&select=*,checkin_count:checkin_logs(count)&order=created_at.desc"
            }
            
            // Fetch gates with check-in counts using a join query
            let gatesWithCounts: [GateWithCheckinCount] = try await supabaseService.makeRequest(
                endpoint: endpoint,
                method: "GET",
                body: nil,
                responseType: [GateWithCheckinCount].self
            )

            // Filter to only gates with at least one check-in
            let gatesWithCheckins = gatesWithCounts
                .filter { ($0.checkinCount ?? 0) > 0 }
                .map { $0.toGate() }

            print("✅ Successfully fetched \(gatesWithCounts.count) total gates, \(gatesWithCheckins.count) with check-ins")
            return gatesWithCheckins

        } catch {
            print("❌ Failed to fetch gates: \(error)")
            // Fallback to simple fetch without count filter
            do {
                let currentEvent = supabaseService.currentEvent
                let fallbackEndpoint: String
                if let seriesId = currentEvent?.seriesId {
                    fallbackEndpoint = "rest/v1/gates?series_id=eq.\(seriesId)&select=*&order=created_at.desc"
                } else {
                    fallbackEndpoint = "rest/v1/gates?event_id=eq.\(eventId)&series_id=is.null&select=*&order=created_at.desc"
                }
                
                let gates: [Gate] = try await supabaseService.makeRequest(
                    endpoint: fallbackEndpoint,
                    method: "GET",
                    body: nil,
                    responseType: [Gate].self
                )
                print("⚠️ Using fallback fetch, got \(gates.count) gates")
                return gates
            } catch {
                print("❌ Fallback fetch also failed: \(error)")
                return []
            }
        }
    }
    
    private func fetchBindings(eventId: String) async throws -> [GateBinding] {
        // Validate UUID format before making request
        try validateEventId(eventId)
        
        return try await supabaseService.makeRequest(
            endpoint: "rest/v1/gate_bindings?event_id=eq.\(eventId)&select=*",
            method: "GET",
            body: nil,
            responseType: [GateBinding].self
        )
    }
    
    private func fetchCategoryStats(eventId: String) async throws -> [CategoryStat] {
        // Validate UUID format before making request
        try validateEventId(eventId)
        
        // Apply time range filter
        let dateRange = selectedTimeRange.dateRange
        let formatter = ISO8601DateFormatter()
        let startDateString = formatter.string(from: dateRange.start)
        
        struct CheckinData: Codable {
            let wristbandId: String
            let timestamp: Date
            
            enum CodingKeys: String, CodingKey {
                case wristbandId = "wristband_id"
                case timestamp
            }
        }
        
        struct WristbandData: Codable {
            let id: String
            let category: String
        }
        
        // Get check-ins within time range
        let checkins: [CheckinData] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/checkin_logs?event_id=eq.\(eventId)&timestamp=gte.\(startDateString)&select=wristband_id,timestamp&order=timestamp.asc",
            method: "GET",
            body: nil,
            responseType: [CheckinData].self
        )
        
        // Get wristband categories
        let wristbands: [WristbandData] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/wristbands?event_id=eq.\(eventId)&select=id,category",
            method: "GET",
            body: nil,
            responseType: [WristbandData].self
        )
        
        // Create wristband to category mapping
        let wristbandCategories = Dictionary(uniqueKeysWithValues: wristbands.map { ($0.id, $0.category) })
        
        // Get unique wristbands per category (first scans only)
        var categoryFirstScans: [String: Set<String>] = [:]
        var seenWristbands: Set<String> = []
        
        for checkin in checkins {
            // Only count first scan of each wristband
            if !seenWristbands.contains(checkin.wristbandId) {
                seenWristbands.insert(checkin.wristbandId)
                
                // Get category for this wristband
                if let category = wristbandCategories[checkin.wristbandId] {
                    if categoryFirstScans[category] == nil {
                        categoryFirstScans[category] = Set<String>()
                    }
                    categoryFirstScans[category]?.insert(checkin.wristbandId)
                }
            }
        }
        
        return categoryFirstScans.map { CategoryStat(category: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }
    
    private func fetchTimeFilteredStats(eventId: String) async throws -> ComprehensiveEventStats {
        // Validate UUID format before making request
        try validateEventId(eventId)
        
        // Apply time range filter
        let dateRange = selectedTimeRange.dateRange
        let formatter = ISO8601DateFormatter()
        let startDateString = formatter.string(from: dateRange.start)
        
        struct CheckinData: Codable {
            let wristbandId: String
            let gateId: String?
            let timestamp: Date
            
            enum CodingKeys: String, CodingKey {
                case wristbandId = "wristband_id"
                case gateId = "gate_id"
                case timestamp
            }
        }
        
        // Get check-ins within time range
        let checkins: [CheckinData] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/checkin_logs?event_id=eq.\(eventId)&timestamp=gte.\(startDateString)&select=wristband_id,gate_id,timestamp",
            method: "GET",
            body: nil,
            responseType: [CheckinData].self
        )
        
        // Calculate unique wristbands (first scans only)
        var firstCheckins: [String: Date] = [:]
        for checkin in checkins.sorted(by: { $0.timestamp < $1.timestamp }) {
            if firstCheckins[checkin.wristbandId] == nil {
                firstCheckins[checkin.wristbandId] = checkin.timestamp
            }
        }
        
        let totalCheckins = firstCheckins.count
        let linkedCheckins = checkins.filter { $0.gateId != nil }.count
        let unlinkedCheckins = totalCheckins - linkedCheckins
        
        // Get total gates (not time-filtered)
        let gates: [Gate] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/gates?event_id=eq.\(eventId)&select=id",
            method: "GET",
            body: nil,
            responseType: [Gate].self
        )
        
        return ComprehensiveEventStats(
            totalWristbands: firstCheckins.count,
            totalCheckins: totalCheckins,
            uniqueCheckins: totalCheckins,
            linkedCheckins: linkedCheckins,
            unlinkedCheckins: unlinkedCheckins,
            totalGates: gates.count,
            activeGates: gates.count,
            categoriesCount: 4, // Estimate
            avgCheckinsPerGate: gates.count > 0 ? Double(totalCheckins) / Double(gates.count) : 0.0,
            linkingRate: totalCheckins > 0 ? Double(linkedCheckins) / Double(totalCheckins) : 0.0
        )
    }
    
    private func fetchTotalCheckinsCount(eventId: String) async throws -> Int {
        // Validate UUID format before making request
        try validateEventId(eventId)
        
        let checkins: [MinimalCheckIn] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/checkin_logs?event_id=eq.\(eventId)&select=id",
            method: "GET",
            body: nil,
            responseType: [MinimalCheckIn].self
        )
        return checkins.count
    }
    
    private func fetchUnlinkedCount(eventId: String) async throws -> Int {
        // Validate UUID format before making request
        try validateEventId(eventId)
        
        let checkins: [MinimalCheckIn] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/checkin_logs?event_id=eq.\(eventId)&gate_id=is.null&select=id",
            method: "GET",
            body: nil,
            responseType: [MinimalCheckIn].self
        )
        return checkins.count
    }
    
    private func fetchActivityTimeline(eventId: String) async throws -> [TimelinePoint] {
        // Validate UUID format before making request
        try validateEventId(eventId)
        
        struct CheckInTimestamp: Codable {
            let timestamp: Date
        }
        
        // Get check-ins based on selected time range
        let dateRange = selectedTimeRange.dateRange
        let formatter = ISO8601DateFormatter()
        let startDateString = formatter.string(from: dateRange.start)
        
        let checkins: [CheckInTimestamp] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/checkin_logs?event_id=eq.\(eventId)&timestamp=gte.\(startDateString)&select=timestamp&order=timestamp",
            method: "GET",
            body: nil,
            responseType: [CheckInTimestamp].self
        )
        
        // Group by hour
        var hourlyData: [Date: Int] = [:]
        let calendar = Calendar.current
        
        for checkin in checkins {
            let hour = calendar.date(bySetting: .minute, value: 0, of: checkin.timestamp) ?? checkin.timestamp
            hourlyData[hour, default: 0] += 1
        }
        
        return hourlyData.map { TimelinePoint(timestamp: $0.key, count: $0.value) }
            .sorted { $0.timestamp < $1.timestamp }
    }
    
    private func fetchGateStatistics(for gates: [Gate], eventId: String) async -> [String: GateDetailStats] {
        // Validate UUID format before making request
        do {
            try validateEventId(eventId)
        } catch {
            print("❌ Invalid event ID in fetchGateStatistics: \(error.localizedDescription)")
            return [:]
        }
        
        var statistics: [String: GateDetailStats] = [:]
        
        // Get all check-ins for this event
        do {
            let allCheckins: [CheckinLog] = try await supabaseService.makeRequest(
                endpoint: "rest/v1/checkin_logs?event_id=eq.\(eventId)&select=*",
                method: "GET",
                body: nil,
                responseType: [CheckinLog].self
            )
            
            print("📊 Found \(allCheckins.count) total check-ins for gate statistics")
            
            // For each gate, find check-ins that should be linked to it
            for gate in gates {
                let gateCheckins = allCheckins.filter { checkin in
                    // Link check-ins to gates based on location or category patterns
                    if let gateId = checkin.gateId, gateId == gate.id {
                        return true
                    }
                    
                    // If no direct gate link, try to match by location/category
                    if let location = checkin.location {
                        return gate.name.contains(location) || location.contains(gate.name.replacingOccurrences(of: "Virtual Gate - ", with: ""))
                    }
                    
                    return false
                }
                
                let stats = GateDetailStats(
                    totalScans: gateCheckins.count,
                    lastHourScans: gateCheckins.filter { 
                        $0.timestamp > Date().addingTimeInterval(-3600) 
                    }.count,
                    avgPerHour: gateCheckins.count > 0 ? Int(Double(gateCheckins.count) / 24.0) : 0,
                    peakHour: findPeakHour(for: gateCheckins) ?? 0
                )
                
                statistics[gate.id] = stats
                print("✅ Gate '\(gate.name)': \(stats.totalScans) scans")
            }
            
        } catch {
            print("❌ Failed to fetch gate statistics: \(error)")
        }
        
        return statistics
    }
    
    private func findPeakHour(for checkins: [CheckinLog]) -> Int? {
        guard !checkins.isEmpty else { return nil }
        
        let calendar = Calendar.current
        var hourlyCount: [Int: Int] = [:]
        
        for checkin in checkins {
            let hour = calendar.component(.hour, from: checkin.timestamp)
            hourlyCount[hour, default: 0] += 1
        }
        
        return hourlyCount.max { $0.value < $1.value }?.key
    }
    
    private func fetchStatsForGate(_ gateId: String, eventId: String) async throws -> GateDetailStats {
        // Validate UUID format before making request
        try validateEventId(eventId)
        
        struct ScanData: Codable {
            let timestamp: Date
            let wristbandId: String
            
            enum CodingKeys: String, CodingKey {
                case timestamp
                case wristbandId = "wristband_id"
            }
        }
        
        // Apply time range filter
        let dateRange = selectedTimeRange.dateRange
        let formatter = ISO8601DateFormatter()
        let startDateString = formatter.string(from: dateRange.start)
        
        // Get scans for this gate within the selected time range
        let scans: [ScanData] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/checkin_logs?event_id=eq.\(eventId)&gate_id=eq.\(gateId)&timestamp=gte.\(startDateString)&select=timestamp,wristband_id&order=timestamp",
            method: "GET",
            body: nil,
            responseType: [ScanData].self
        )
        
        // Count unique wristbands instead of total scans
        let uniqueWristbands = Set(scans.map { $0.wristbandId })
        let totalScans = uniqueWristbands.count
        
        print("🎯 Gate \(gateId) (\(selectedTimeRange.rawValue)): \(scans.count) total scans, \(totalScans) unique wristbands")
        
        // Calculate last hour unique wristbands
        let oneHourAgo = Date().addingTimeInterval(-3600)
        let lastHourUniqueWristbands = Set(scans.filter { $0.timestamp >= oneHourAgo }.map { $0.wristbandId })
        let lastHourScans = lastHourUniqueWristbands.count
        
        // Calculate average per hour (event duration)
        let eventStart = supabaseService.currentEvent?.startDate ?? Date()
        let hoursSinceStart = max(1, Date().timeIntervalSince(eventStart) / 3600)
        let avgPerHour = Double(totalScans) / hoursSinceStart
        
        // Find peak hour (unique wristbands per hour)
        let calendar = Calendar.current
        var hourlyUniqueWristbands: [Int: Set<String>] = [:]
        
        for scan in scans {
            let hour = calendar.component(.hour, from: scan.timestamp)
            if hourlyUniqueWristbands[hour] == nil {
                hourlyUniqueWristbands[hour] = Set<String>()
            }
            hourlyUniqueWristbands[hour]?.insert(scan.wristbandId)
        }
        
        let peakHour = hourlyUniqueWristbands.max(by: { $0.value.count < $1.value.count })?.value.count ?? 0
        
        return GateDetailStats(
            totalScans: totalScans,
            lastHourScans: lastHourScans,
            avgPerHour: Int(avgPerHour),
            peakHour: peakHour
        )
    }
    
    private func loadActivityTimeline(for range: TimeRange) async {
        guard let eventId = supabaseService.currentEvent?.id else { return }
        
        let dateRange = range.dateRange
        
        // Fetch and update timeline
        do {
            let timeline = try await fetchActivityTimeline(eventId: eventId)
            await MainActor.run {
                self.activityTimeline = timeline.filter { 
                    $0.timestamp >= dateRange.start && $0.timestamp <= dateRange.end 
                }
            }
        } catch {
            print("❌ Failed to load activity timeline: \(error)")
        }
    }
    
    private func startBackgroundProcessing() {
        guard let eventId = supabaseService.currentEvent?.id else { return }
        
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task {
                try? await self?.processor.smartProcess(eventId: eventId)
                await self?.refreshData()
            }
        }
        
        // Process immediately
        Task {
            try? await processor.smartProcess(eventId: eventId)
        }
    }
    
    // MARK: - Calculations
    
    private func calculateDataQuality() -> Double {
        var score = 100.0
        
        // Penalty for unlinked check-ins
        if totalCheckins > 0 {
            let unlinkedPercentage = Double(unlinkedCount) / Double(totalCheckins)
            score -= unlinkedPercentage * 30 // Up to 30 points penalty
        }
        
        // Penalty for low confidence bindings
        let lowConfidenceCount = gateBindings.filter { $0.confidence < 0.6 }.count
        score -= Double(lowConfidenceCount) * 5
        
        // Penalty for duplicate gates
        score -= Double(duplicateGatesCount) * 8
        
        // Penalty for stuck probation gates
        let stuckProbation = gateBindings.filter {
            $0.status == .probation && $0.sampleCount >= 20 && $0.confidence >= 0.7
        }.count
        score -= Double(stuckProbation) * 6
        
        return max(0, min(100, score))
    }
    
    /// Link unlinked check-ins to existing gates based on patterns
    private func linkUnlinkedCheckinsToGates(eventId: String) async {
        do {
            // Validate UUID format before making request
            try validateEventId(eventId)
            
            print("🔗 Linking unlinked check-ins to gates...")
            
            // Get unlinked check-ins
            let unlinkedCheckins: [CheckinLog] = try await supabaseService.makeRequest(
                endpoint: "rest/v1/checkin_logs?event_id=eq.\(eventId)&gate_id=is.null&select=*",
                method: "GET",
                body: nil,
                responseType: [CheckinLog].self
            )
            
            // Get all gates
            let gates: [Gate] = try await supabaseService.makeRequest(
                endpoint: "rest/v1/gates?event_id=eq.\(eventId)&select=*",
                method: "GET",
                body: nil,
                responseType: [Gate].self
            )
            
            print("📊 Found \(unlinkedCheckins.count) unlinked check-ins and \(gates.count) gates")
            
            var linkedCount = 0
            
            for checkin in unlinkedCheckins {
                // Try to find a matching gate based on location or category
                let matchingGate = gates.first { gate in
                    if let location = checkin.location {
                        // Match by location patterns
                        let gateArea = gate.name.replacingOccurrences(of: "Virtual Gate - ", with: "")
                        return location.contains(gateArea) || gateArea.contains(location)
                    }
                    return false
                }
                
                if let gate = matchingGate {
                    // Update the check-in to link it to the gate
                    do {
                        
                        let _: CheckinLog = try await supabaseService.makeRequest(
                            endpoint: "rest/v1/checkin_logs?id=eq.\(checkin.id)",
                            method: "PATCH",
                            body: try JSONEncoder().encode(["gate_id": gate.id]),
                            responseType: CheckinLog.self
                        )
                        
                        linkedCount += 1
                        print("✅ Linked check-in to gate '\(gate.name)'")
                        
                    } catch {
                        print("❌ Failed to link check-in \(checkin.id): \(error)")
                    }
                }
            }
            
            print("🎯 Successfully linked \(linkedCount) check-ins to gates")
            
            // Refresh data to show updated statistics
            if linkedCount > 0 {
                await refreshData()
            }
            
        } catch {
            print("❌ Failed to link check-ins to gates: \(error)")
        }
    }
    
    private func detectDuplicates() -> Int {
        // Simple duplicate detection based on location proximity
        var duplicates = 0
        let threshold = 0.001 // ~100 meters
        
        for i in 0..<activeGates.count {
            for j in (i+1)..<activeGates.count {
                let gate1 = activeGates[i]
                let gate2 = activeGates[j]
                
                guard let lat1 = gate1.latitude, let lon1 = gate1.longitude,
                      let lat2 = gate2.latitude, let lon2 = gate2.longitude else {
                    continue
                }
                
                let latDiff = abs(lat1 - lat2)
                let lonDiff = abs(lon1 - lon2)
                
                if latDiff < threshold && lonDiff < threshold {
                    duplicates += 1
                }
            }
        }
        
        return duplicates
    }
    
    /// Create virtual gates based on check-in patterns when no gates exist
    private func createVirtualGatesFromCheckins(eventId: String) async {
        do {
            // Validate UUID format before making request
            try validateEventId(eventId)
            
            print("🏗️ Creating virtual gates from check-in patterns...")
            
            // First check if gates already exist to avoid duplicates
            struct GateCount: Codable {
                let count: Int?
            }
            
            let gateCountResponse: [GateCount] = try await supabaseService.makeRequest(
                endpoint: "rest/v1/gates?event_id=eq.\(eventId)&select=count()",
                method: "GET",
                body: nil,
                responseType: [GateCount].self
            )
            
            let existingGateCount = gateCountResponse.first?.count ?? 0
            if existingGateCount > 0 {
                print("⚠️ Gates already exist (\(existingGateCount)), skipping virtual gate creation")
                return
            }
            
            // Get all check-ins for this event
            let checkins: [CheckinLog] = try await supabaseService.makeRequest(
                endpoint: "rest/v1/checkin_logs?event_id=eq.\(eventId)&select=*",
                method: "GET",
                body: nil,
                responseType: [CheckinLog].self
            )
            
            print("Found \(checkins.count) check-ins to analyze")
            
            if checkins.isEmpty {
                print("No check-ins found, cannot create virtual gates")
                return
            }
            
            // Group check-ins by location patterns
            let locationGroups = Dictionary(grouping: checkins) { checkin in
                checkin.location ?? "Unknown Location"
            }
            
            print("Found \(locationGroups.count) unique locations")
            
            // Create virtual gates for each location group
            for (location, locationCheckins) in locationGroups {
                let gateId = UUID().uuidString
                let gateName = location.contains("Manual Check-in") ? 
                    "Virtual Gate - \(location.replacingOccurrences(of: "Manual Check-in - ", with: ""))" : 
                    "Virtual Gate - \(location)"
                
                // Use current location or a default location
                let latitude = 0.35416277942747953 // From your location update
                let longitude = 32.599798487906966
                
                let virtualGate = Gate(
                    id: gateId,
                    eventId: eventId,
                    name: gateName,
                    latitude: latitude,
                    longitude: longitude
                )
                
                // Create the gate in the database
                let createdGates: [Gate] = try await supabaseService.makeRequest(
                    endpoint: "rest/v1/gates",
                    method: "POST",
                    body: try JSONEncoder().encode(virtualGate),
                    responseType: [Gate].self
                )
                
                guard createdGates.first != nil else {
                    print("❌ No gate returned from creation")
                    continue
                }
                
                print("✅ Created virtual gate: \(gateName) with \(locationCheckins.count) check-ins")
            }
            
            // Reload data to show the new gates
            await refreshData()
            
        } catch {
            print("Failed to create virtual gates: \(error)")
        }
    }
    
    private func calculateCheckinChange() -> Int {
        // Calculate percentage change from previous day
        // This is a placeholder - implement actual calculation
        return 0
    }
    private func haversineDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let R = 6371000.0
        let φ1 = lat1 * .pi / 180
        let φ2 = lat2 * .pi / 180
        let Δφ = (lat2 - lat1) * .pi / 180
        let Δλ = (lon2 - lon1) * .pi / 180
        
        let a = sin(Δφ/2) * sin(Δφ/2) + cos(φ1) * cos(φ2) * sin(Δλ/2) * sin(Δλ/2)
        let c = 2 * atan2(sqrt(a), sqrt(1-a))
        
        return R * c
    }
    
    private func twentyFourHoursAgo() -> String {
        let date = Date().addingTimeInterval(-86400)
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: date)
    }
    
    // MARK: - Export
    
    private func performDataExport() async {
        // Create comprehensive CSV export
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        
        var csvContent = "Gate Name,Category,Latitude,Longitude,Status,Confidence,Unique Wristbands,Total Scans,Last Hour,Avg/Hour,Time Range\n"
        
        for gate in activeGates {
            let bindings = gateBindings.filter { $0.gateId == gate.id }
            let stats = gateStatistics[gate.id]
            
            if bindings.isEmpty {
                // Gate without bindings
                let row = [
                    "\"" + gate.name + "\"",
                    "Unbound",
                    "\(gate.latitude ?? 0)",
                    "\(gate.longitude ?? 0)",
                    "Unbound",
                    "0",
                    "\(stats?.totalScans ?? 0)",
                    "0", // No raw scan count in current structure
                    "\(stats?.lastHourScans ?? 0)",
                    "\(stats?.avgPerHour ?? 0)",
                    selectedTimeRange.rawValue
                ].joined(separator: ",")
                csvContent += row + "\n"
            } else {
                for binding in bindings {
                    let row = [
                        "\"" + gate.name + "\"",
                        "\"" + binding.categoryName + "\"",
                        "\(gate.latitude ?? 0)",
                        "\(gate.longitude ?? 0)",
                        binding.status.rawValue,
                        String(format: "%.2f", binding.confidence),
                        "\(stats?.totalScans ?? 0)",
                        "\(binding.sampleCount)",
                        "\(stats?.lastHourScans ?? 0)",
                        "\(stats?.avgPerHour ?? 0)",
                        selectedTimeRange.rawValue
                    ].joined(separator: ",")
                    csvContent += row + "\n"
                }
            }
        }
        
        // Add summary section
        csvContent += "\n--- SUMMARY ---\n"
        csvContent += "Total Gates,\(activeGates.count)\n"
        csvContent += "Total Check-ins,\(totalCheckins)\n"
        csvContent += "Unlinked Check-ins,\(unlinkedCount)\n"
        csvContent += "Data Quality,\(String(format: "%.1f%%", dataQuality * 100))\n"
        csvContent += "Export Time,\(Date())\n"
        csvContent += "Time Range,\(selectedTimeRange.rawValue)\n"
        
        // Save to Documents directory
        await MainActor.run {
            let filename = "NFC_Gates_Export_\(timestamp).csv"
            
            if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let fileURL = documentsPath.appendingPathComponent(filename)
                
                do {
                    try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
                    print("✅ Export saved to: \(fileURL.path)")
                    
                    // Show share sheet
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let window = windowScene.windows.first,
                       let rootViewController = window.rootViewController {
                        
                        let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
                        
                        // For iPad
                        if let popover = activityVC.popoverPresentationController {
                            popover.sourceView = rootViewController.view
                            popover.sourceRect = CGRect(x: rootViewController.view.bounds.midX, y: rootViewController.view.bounds.midY, width: 0, height: 0)
                            popover.permittedArrowDirections = []
                        }
                        
                        rootViewController.present(activityVC, animated: true)
                    }
                    
                } catch {
                    print("❌ Export failed: \(error)")
                }
            }
        }
    }
}

// MARK: - Supporting Models

// Types are now in GateManagementModels.swift
