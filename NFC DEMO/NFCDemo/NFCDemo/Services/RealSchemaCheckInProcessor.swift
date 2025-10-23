import Foundation
import Combine

/// Enhanced processor using actual database schema with deployed Supabase functions
/// Categories come from wristbands table, not extracted from IDs
class RealSchemaCheckInProcessor: ObservableObject {
    static let shared = RealSchemaCheckInProcessor()
    
    private let supabaseService = SupabaseService.shared
    
    @Published var isProcessing = false
    @Published var processedCount = 0
    @Published var linkedCount = 0
    @Published var lastProcessedTime: Date?
    @Published var processingEfficiency: ProcessingEfficiency = .poor
    @Published var categoryStats: [String: CategoryProcessingStats] = [:]
    
    // Processing configuration
    private let batchSize = 100
    private let maxDistance = 50.0
    private let processingInterval: TimeInterval = 30.0
    
    // MARK: - Models matching your schema
    
    struct WristbandInfo: Codable {
        let id: String
        let eventId: String
        let nfcId: String
        let category: String
        let isActive: Bool
        
        enum CodingKeys: String, CodingKey {
            case id, category
            case eventId = "event_id"
            case nfcId = "nfc_id"
            case isActive = "is_active"
        }
    }
    
    struct CheckInWithCategory: Codable {
        let id: String
        let eventId: String
        let wristbandId: String
        let appLat: Double?
        let appLon: Double?
        let appAccuracy: Double?
        let category: String  // Joined from wristbands
        let timestamp: Date
        
        enum CodingKeys: String, CodingKey {
            case id, category, timestamp
            case eventId = "event_id"
            case wristbandId = "wristband_id"
            case appLat = "app_lat"
            case appLon = "app_lon"
            case appAccuracy = "app_accuracy"
        }
    }
    
    struct CategoryProcessingStats {
        let categoryName: String
        var totalProcessed: Int = 0
        var totalLinked: Int = 0
        var lastProcessedTime: Date?
        
        var linkingRate: Double {
            totalProcessed > 0 ? Double(totalLinked) / Double(totalProcessed) : 0.0
        }
        
        var efficiency: ProcessingEfficiency {
            switch linkingRate {
            case 0.9...1.0: return .excellent
            case 0.7..<0.9: return .good
            case 0.5..<0.7: return .fair
            default: return .poor
            }
        }
    }
    
    private init() {}
    
    // MARK: - Enhanced Processing with Supabase Functions
    
    /// Process unlinked check-ins using enhanced Supabase functions
    func processUnlinkedCheckInsEnhanced(eventId: String) async throws {
        guard !isProcessing else {
            print("⏭️ Already processing")
            return
        }
        
        await MainActor.run {
            isProcessing = true
        }
        
        defer {
            Task { @MainActor in
                isProcessing = false
            }
        }
        
        do {
            print("🚀 Starting enhanced processing with Supabase functions...")
            
            // Use the deployed batch processing function
            let result = try await supabaseService.processUnlinkedCheckIns(
                eventId: eventId,
                batchLimit: batchSize
            )
            
            await MainActor.run {
                self.processedCount += result.processedCount
                self.linkedCount += result.linkedCount
                self.lastProcessedTime = Date()
                self.processingEfficiency = result.efficiency
            }
            
            print("✅ Enhanced processing complete: \(result.linkedCount)/\(result.processedCount) linked")
            
            // Update category stats
            try await updateCategoryStats(eventId: eventId)
            
        } catch {
            print("❌ Enhanced processing failed: \(error)")
            // Fallback to manual processing
            try await processUnlinkedCheckInsManual(eventId: eventId)
        }
    }
    
    /// Manual processing fallback using original logic
    func processUnlinkedCheckInsManual(eventId: String) async throws {
        print("🔄 Falling back to manual processing...")
        
        do {
            print("🔍 Fetching unlinked check-ins...")
            
            // Fetch unlinked check-ins (without join to avoid ambiguity)
            let basicCheckIns: [CheckinLog] = try await supabaseService.makeRequest(
                endpoint: "rest/v1/checkin_logs?event_id=eq.\(eventId)&gate_id=is.null&app_lat=not.is.null&limit=\(batchSize)",
                method: "GET",
                body: nil,
                responseType: [CheckinLog].self
            )
            
            // Convert to CheckInWithCategory by fetching wristband categories separately
            var checkIns: [CheckInWithCategory] = []
            for checkIn in basicCheckIns {
                // Fetch wristband category separately to avoid SQL ambiguity
                let wristbands: [Wristband] = try await supabaseService.makeRequest(
                    endpoint: "rest/v1/wristbands?id=eq.\(checkIn.wristbandId)&select=category",
                    method: "GET",
                    body: nil,
                    responseType: [Wristband].self
                )
                
                let category = wristbands.first?.category.name ?? "Unknown"
                let checkInWithCategory = CheckInWithCategory(
                    id: checkIn.id,
                    eventId: checkIn.eventId,
                    wristbandId: checkIn.wristbandId,
                    appLat: checkIn.appLat,
                    appLon: checkIn.appLon,
                    appAccuracy: checkIn.appAccuracy,
                    category: category,
                    timestamp: checkIn.timestamp
                )
                checkIns.append(checkInWithCategory)
            }
            
            guard !checkIns.isEmpty else {
                print("✅ No unlinked check-ins to process")
                return
            }
            
            print("📊 Processing \(checkIns.count) check-ins manually...")
            
            // Get all gates for this event
            let gates = try await fetchGates(eventId: eventId)
            let bindings = try await fetchBindings(eventId: eventId)
            
            // Group check-ins by category for efficient processing
            let checkInsByCategory = Dictionary(grouping: checkIns) { $0.category }
            
            var updates: [(checkInId: String, gateId: String)] = []
            var categoryUpdates: [String: CategoryProcessingStats] = [:]
            
            for (category, categoryCheckIns) in checkInsByCategory {
                print("  Processing \(categoryCheckIns.count) \(category) check-ins...")
                
                // Initialize category stats
                var categoryStats = CategoryProcessingStats(categoryName: category)
                categoryStats.totalProcessed = categoryCheckIns.count
                
                // Get gates that serve this category
                let categoryGates = gates.filter { gate in
                    bindings.contains { binding in
                        binding.gateId == gate.id && 
                        binding.categoryName == category &&
                        binding.status != .unbound
                    }
                }
                
                // Link each check-in to nearest gate
                for checkIn in categoryCheckIns {
                    guard let lat = checkIn.appLat, let lon = checkIn.appLon else { continue }
                    
                    if let nearestGate = findNearestGate(
                        lat: lat,
                        lon: lon,
                        in: categoryGates,
                        maxDistance: maxDistance
                    ) {
                        updates.append((checkIn.id, nearestGate.id))
                        categoryStats.totalLinked += 1
                    }
                }
                
                categoryStats.lastProcessedTime = Date()
                categoryUpdates[category] = categoryStats
            }
            
            // Batch update using enhanced batch operations
            if !updates.isEmpty {
                try await supabaseService.batchUpdateCheckInGates(updates: updates)
                
                await MainActor.run {
                    self.linkedCount += updates.count
                    self.processedCount += checkIns.count
                    self.lastProcessedTime = Date()
                    
                    // Update category stats
                    for (category, stats) in categoryUpdates {
                        self.categoryStats[category] = stats
                    }
                    
                    // Calculate overall efficiency
                    let overallRate = Double(updates.count) / Double(checkIns.count)
                    self.processingEfficiency = ProcessingEfficiency.from(rate: overallRate)
                }
                
                print("✅ Manually linked \(updates.count)/\(checkIns.count) check-ins")
            }
            
        } catch {
            print("❌ Manual processing failed: \(error)")
            throw error
        }
    }
    
    // MARK: - Category Statistics
    
    private func updateCategoryStats(eventId: String) async throws {
        do {
            // Use enhanced function to get category stats
            let categories = try await supabaseService.fetchEventCategories(eventId: eventId)
            
            await MainActor.run {
                for category in categories {
                    if var existingStats = self.categoryStats[category.name] {
                        existingStats.lastProcessedTime = Date()
                        self.categoryStats[category.name] = existingStats
                    } else {
                        let newStats = CategoryProcessingStats(categoryName: category.name)
                        self.categoryStats[category.name] = newStats
                    }
                }
            }
            
        } catch {
            print("⚠️ Failed to update category stats: \(error)")
        }
    }
    
    // MARK: - Smart Processing Strategy
    
    /// Intelligent processing that chooses the best strategy
    func smartProcess(eventId: String) async throws {
        // Get comprehensive stats first
        let stats = try await supabaseService.fetchComprehensiveEventStats(eventId: eventId)
        
        print("📊 Event Analysis:")
        print("  Unlinked check-ins: \(stats.unlinkedCheckins)")
        print("  Linking rate: \(String(format: "%.1f", stats.linkingRate * 100))%")
        print("  Active gates: \(stats.activeGates)")
        
        // Choose processing strategy based on data size and complexity
        if stats.unlinkedCheckins > 500 {
            print("🚀 Large dataset detected - using enhanced batch processing")
            try await processUnlinkedCheckInsEnhanced(eventId: eventId)
        } else if stats.unlinkedCheckins > 0 {
            print("🔧 Small dataset - using manual processing for precision")
            try await processUnlinkedCheckInsManual(eventId: eventId)
        } else {
            print("✅ No unlinked check-ins to process")
        }
    }
    
    // MARK: - Continuous Processing
    
    private var processingTimer: Timer?
    
    func startContinuousProcessing(eventId: String) {
        stopContinuousProcessing()
        
        print("🔄 Starting continuous processing every \(processingInterval)s")
        
        // Process immediately
        Task {
            try? await smartProcess(eventId: eventId)
        }
        
        // Then schedule regular processing
        processingTimer = Timer.scheduledTimer(withTimeInterval: processingInterval, repeats: true) { _ in
            Task {
                try? await self.smartProcess(eventId: eventId)
            }
        }
    }
    
    func stopContinuousProcessing() {
        processingTimer?.invalidate()
        processingTimer = nil
        print("⏹️ Stopped continuous processing")
    }
    
    // MARK: - Helper Methods
    
    private func fetchGates(eventId: String) async throws -> [Gate] {
        try await supabaseService.makeRequest(
            endpoint: "rest/v1/gates?event_id=eq.\(eventId)&select=*",
            method: "GET",
            body: nil,
            responseType: [Gate].self
        )
    }
    
    private func fetchBindings(eventId: String) async throws -> [GateBinding] {
        try await supabaseService.makeRequest(
            endpoint: "rest/v1/gate_bindings?event_id=eq.\(eventId)&select=*",
            method: "GET",
            body: nil,
            responseType: [GateBinding].self
        )
    }
    
    private func findNearestGate(
        lat: Double,
        lon: Double,
        in gates: [Gate],
        maxDistance: Double
    ) -> Gate? {
        var nearestGate: Gate?
        var minDistance = Double.infinity
        
        for gate in gates {
            guard let gateLat = gate.latitude,
                  let gateLon = gate.longitude else { continue }
            
            let distance = AdaptiveClusteringService.haversineDistance(
                lat1: lat, lon1: lon,
                lat2: gateLat, lon2: gateLon
            )
            
            if distance < maxDistance && distance < minDistance {
                minDistance = distance
                nearestGate = gate
            }
        }
        
        return nearestGate
    }
    
    // MARK: - Analytics and Reporting
    
    func generateProcessingReport(eventId: String) async throws -> ProcessingReport {
        let stats = try await supabaseService.fetchComprehensiveEventStats(eventId: eventId)
        
        return ProcessingReport(
            eventId: eventId,
            totalProcessed: processedCount,
            totalLinked: linkedCount,
            overallEfficiency: processingEfficiency,
            categoryStats: Array(categoryStats.values),
            lastProcessedTime: lastProcessedTime,
            eventStats: stats
        )
    }
}

// MARK: - Supporting Models

struct ProcessingReport {
    let eventId: String
    let totalProcessed: Int
    let totalLinked: Int
    let overallEfficiency: ProcessingEfficiency
    let categoryStats: [RealSchemaCheckInProcessor.CategoryProcessingStats]
    let lastProcessedTime: Date?
    let eventStats: ComprehensiveEventStats
    
    var linkingRate: Double {
        totalProcessed > 0 ? Double(totalLinked) / Double(totalProcessed) : 0.0
    }
    
    var formattedLastProcessed: String {
        guard let lastProcessedTime = lastProcessedTime else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        return formatter.localizedString(for: lastProcessedTime, relativeTo: Date())
    }
}

extension ProcessingEfficiency {
    static func from(rate: Double) -> ProcessingEfficiency {
        switch rate {
        case 0.9...1.0: return .excellent
        case 0.7..<0.9: return .good
        case 0.5..<0.7: return .fair
        default: return .poor
        }
    }
}
