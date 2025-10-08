import Foundation
import Combine
import CoreLocation

/// Intelligent gate binding service using real schema and enhanced Supabase functions
class IntelligentGateBindingService: ObservableObject {
    static let shared = IntelligentGateBindingService()
    
    private let supabaseService = SupabaseService.shared
    private let processor = RealSchemaCheckInProcessor.shared
    private let clusteringIntegration = GateClusteringIntegration()
    
    @Published var isAnalyzing = false
    @Published var bindingRecommendations: [BindingRecommendation] = []
    @Published var autoBindingEnabled = false
    @Published var bindingQuality: BindingQuality = .poor
    
    // Configuration
    private let minimumSamplesForBinding = 10
    private let confidenceThreshold = 0.7
    private let maxDistanceForBinding = 75.0
    
    // MARK: - Models
    
    struct BindingRecommendation: Identifiable {
        let id = UUID()
        let gateId: String
        let gateName: String
        let categoryName: String
        let confidence: Double
        let sampleCount: Int
        let averageDistance: Double
        let recommendedAction: RecommendedAction
        let reasoning: String
        
        enum RecommendedAction {
            case createBinding
            case strengthenBinding
            case reviewBinding
            case removeBinding
            
            var displayName: String {
                switch self {
                case .createBinding: return "Create Binding"
                case .strengthenBinding: return "Strengthen"
                case .reviewBinding: return "Review"
                case .removeBinding: return "Remove"
                }
            }
            
            var color: String {
                switch self {
                case .createBinding: return "#4CAF50"
                case .strengthenBinding: return "#2196F3"
                case .reviewBinding: return "#FF9800"
                case .removeBinding: return "#F44336"
                }
            }
            
            var icon: String {
                switch self {
                case .createBinding: return "plus.circle.fill"
                case .strengthenBinding: return "arrow.up.circle.fill"
                case .reviewBinding: return "exclamationmark.triangle.fill"
                case .removeBinding: return "minus.circle.fill"
                }
            }
        }
    }
    
    enum BindingQuality: String, CaseIterable {
        case excellent = "Excellent"
        case good = "Good"
        case fair = "Fair"
        case poor = "Poor"
        
        var color: String {
            switch self {
            case .excellent: return "#4CAF50"
            case .good: return "#8BC34A"
            case .fair: return "#FF9800"
            case .poor: return "#F44336"
            }
        }
        
        var description: String {
            switch self {
            case .excellent: return "90%+ of check-ins properly bound"
            case .good: return "70-89% of check-ins properly bound"
            case .fair: return "50-69% of check-ins properly bound"
            case .poor: return "Less than 50% properly bound"
            }
        }
    }
    
    private init() {}
    
    // MARK: - Intelligent Analysis
    
    /// Analyze event and generate intelligent binding recommendations
    func analyzeEventBindings(eventId: String) async throws {
        guard !isAnalyzing else { return }
        
        await MainActor.run {
            isAnalyzing = true
            bindingRecommendations = []
        }
        
        defer {
            Task { @MainActor in
                isAnalyzing = false
            }
        }
        
        do {
            print("🧠 Starting intelligent binding analysis...")
            
            // Get comprehensive event statistics
            let eventStats = try await supabaseService.fetchComprehensiveEventStats(eventId: eventId)
            
            // Get current gate bindings
            let currentBindings = try await fetchCurrentBindings(eventId: eventId)
            
            // Analyze check-in patterns using clustering
            try await clusteringIntegration.analyzeEventForGates(eventId: eventId, venueType: .hybrid)
            let discoveredGates = await clusteringIntegration.discoveredGates
            
            // Get category distribution
            let categories = try await supabaseService.fetchEventCategories(eventId: eventId)
            
            // Generate recommendations
            let recommendations = await generateIntelligentRecommendations(
                eventStats: eventStats,
                currentBindings: currentBindings,
                discoveredGates: discoveredGates,
                categories: categories,
                eventId: eventId
            )
            
            // Calculate overall binding quality
            let quality = calculateBindingQuality(
                eventStats: eventStats,
                recommendations: recommendations
            )
            
            await MainActor.run {
                self.bindingRecommendations = recommendations
                self.bindingQuality = quality
            }
            
            print("✅ Analysis complete: \(recommendations.count) recommendations generated")
            
        } catch {
            print("❌ Binding analysis failed: \(error)")
            throw error
        }
    }
    
    // MARK: - Recommendation Generation
    
    private func generateIntelligentRecommendations(
        eventStats: ComprehensiveEventStats,
        currentBindings: [GateBinding],
        discoveredGates: [GateClusteringIntegration.DiscoveredGate],
        categories: [EventCategory],
        eventId: String
    ) async -> [BindingRecommendation] {
        
        var recommendations: [BindingRecommendation] = []
        
        for discoveredGate in discoveredGates {
            let existingBinding = currentBindings.first { binding in
                binding.gateId == discoveredGate.cluster.checkIns.first?.gateId
            }
            
            if existingBinding == nil && discoveredGate.confidence > confidenceThreshold {
                let recommendation = BindingRecommendation(
                    gateId: UUID().uuidString, // Would be actual gate ID
                    gateName: discoveredGate.suggestedName,
                    categoryName: discoveredGate.category,
                    confidence: discoveredGate.confidence,
                    sampleCount: discoveredGate.checkInCount,
                    averageDistance: discoveredGate.cluster.radius,
                    recommendedAction: .createBinding,
                    reasoning: "High-confidence gate discovered through clustering analysis with \(discoveredGate.checkInCount) check-ins"
                )
                recommendations.append(recommendation)
            }
        }
        
        // 2. Analyze existing bindings for improvement opportunities
        for binding in currentBindings {
            let categoryCheckIns = await getCheckInsForCategoryAndGate(
                eventId: eventId,
                category: binding.categoryName,
                gateId: binding.gateId
            )
            
            let recommendation = analyzeExistingBinding(
                binding: binding,
                checkIns: categoryCheckIns
            )
            
            if let rec = recommendation {
                recommendations.append(rec)
            }
        }
        
        // 3. Identify categories without proper gate coverage
        for category in categories {
            let categoryBindings = currentBindings.filter { $0.categoryName == category.name }
            
            if categoryBindings.isEmpty && category.wristbandCount > minimumSamplesForBinding {
                // Look for potential gates for this category
                if let potentialGate = await findPotentialGateForCategory(
                    eventId: eventId,
                    category: category.name
                ) {
                    recommendations.append(potentialGate)
                }
            }
        }
        
        // 4. Sort recommendations by priority
        return recommendations.sorted { rec1, rec2 in
            let priority1 = calculateRecommendationPriority(rec1)
            let priority2 = calculateRecommendationPriority(rec2)
            return priority1 > priority2
        }
    }
    
    private func analyzeExistingBinding(
        binding: GateBinding,
        checkIns: [CheckinLog]
    ) -> BindingRecommendation? {
        
        guard !checkIns.isEmpty else { return nil }
        
        // Calculate average distance and accuracy
        let distances = checkIns.compactMap { checkIn -> Double? in
            guard let _ = checkIn.appLat, let _ = checkIn.appLon else { return nil }
            // Would calculate distance to gate location
            return 25.0 // Placeholder
        }
        
        let averageDistance = distances.isEmpty ? 0 : distances.reduce(0, +) / Double(distances.count)
        let confidence = binding.confidence
        
        // Determine recommendation based on binding performance
        let action: BindingRecommendation.RecommendedAction
        let reasoning: String
        
        switch (confidence, averageDistance, binding.sampleCount) {
        case let (conf, _, samples) where conf < 0.5 && samples > 20:
            action = .reviewBinding
            reasoning = "Low confidence (\(Int(conf * 100))%) despite \(samples) samples suggests poor gate placement"
            
        case let (conf, _, samples) where conf > 0.8 && samples < minimumSamplesForBinding:
            action = .strengthenBinding
            reasoning = "High confidence (\(Int(conf * 100))%) but low sample count (\(samples)) - needs more data"
            
        case let (_, dist, _) where dist > maxDistanceForBinding:
            action = .reviewBinding
            reasoning = "Average distance (\(Int(dist))m) exceeds recommended threshold (\(Int(maxDistanceForBinding))m)"
            
        case let (conf, _, samples) where conf < 0.3 && samples > 50:
            action = .removeBinding
            reasoning = "Consistently low confidence (\(Int(conf * 100))%) over \(samples) samples indicates incorrect binding"
            
        default:
            return nil // No recommendation needed
        }
        
        return BindingRecommendation(
            gateId: binding.gateId,
            gateName: "Gate \(binding.gateId.prefix(8))", // Would get actual name
            categoryName: binding.categoryName,
            confidence: confidence,
            sampleCount: binding.sampleCount,
            averageDistance: averageDistance,
            recommendedAction: action,
            reasoning: reasoning
        )
    }
    
    private func findPotentialGateForCategory(
        eventId: String,
        category: String
    ) async -> BindingRecommendation? {
        
        do {
            // Use the enhanced function to find nearby gates
            let nearbyGates = try await supabaseService.findNearbyGatesByCategory(
                latitude: 0.0, // Would use actual coordinates
                longitude: 0.0,
                eventId: eventId,
                category: category,
                radiusMeters: 100.0
            )
            
            guard let bestGate = nearbyGates.first else { return nil }
            
            return BindingRecommendation(
                gateId: bestGate.gateId,
                gateName: bestGate.gateName,
                categoryName: category,
                confidence: 0.6, // Moderate confidence for new binding
                sampleCount: 0,
                averageDistance: bestGate.distanceMeters,
                recommendedAction: .createBinding,
                reasoning: "Category '\(category)' lacks gate coverage. Nearby gate '\(bestGate.gateName)' at \(bestGate.formattedDistance) could serve this category."
            )
            
        } catch {
            print("⚠️ Failed to find potential gate for category \(category): \(error)")
            return nil
        }
    }
    
    // MARK: - Auto-Binding
    
    func enableAutomaticBinding(eventId: String) async throws {
        print("🤖 Enabling automatic binding...")
        
        // Enable the database trigger for real-time gate linking
        _ = try await supabaseService.makeRequest(
            endpoint: "rest/v1/rpc/enable_auto_gate_linking",
            method: "POST",
            body: try JSONSerialization.data(withJSONObject: ["event_id": eventId]),
            responseType: [String: Bool].self
        )
        
        await MainActor.run {
            autoBindingEnabled = true
        }
        
        print("✅ Automatic binding enabled")
    }
    
    func disableAutomaticBinding() async throws {
        print("🛑 Disabling automatic binding...")
        
        // Disable the database trigger
        _ = try await supabaseService.makeRequest(
            endpoint: "rest/v1/rpc/disable_auto_gate_linking",
            method: "POST",
            body: nil,
            responseType: [String: Bool].self
        )
        
        await MainActor.run {
            autoBindingEnabled = false
        }
        
        print("✅ Automatic binding disabled")
    }
    
    // MARK: - Recommendation Implementation
    
    func implementRecommendation(_ recommendation: BindingRecommendation, eventId: String) async throws {
        print("🔧 Implementing recommendation: \(recommendation.recommendedAction.displayName)")
        
        switch recommendation.recommendedAction {
        case .createBinding:
            try await createGateBinding(
                gateId: recommendation.gateId,
                categoryName: recommendation.categoryName,
                eventId: eventId
            )
            
        case .strengthenBinding:
            try await strengthenGateBinding(
                gateId: recommendation.gateId,
                categoryName: recommendation.categoryName
            )
            
        case .reviewBinding:
            // Mark for manual review
            print("📋 Binding marked for manual review")
            
        case .removeBinding:
            try await removeGateBinding(
                gateId: recommendation.gateId,
                categoryName: recommendation.categoryName
            )
        }
        
        // Remove implemented recommendation
        await MainActor.run {
            bindingRecommendations.removeAll { $0.id == recommendation.id }
        }
        
        print("✅ Recommendation implemented successfully")
    }
    
    // MARK: - Helper Methods
    
    private func fetchCurrentBindings(eventId: String) async throws -> [GateBinding] {
        try await supabaseService.makeRequest(
            endpoint: "rest/v1/gate_bindings?event_id=eq.\(eventId)&select=*",
            method: "GET",
            body: nil,
            responseType: [GateBinding].self
        )
    }
    
    private func getCheckInsForCategoryAndGate(
        eventId: String,
        category: String,
        gateId: String
    ) async -> [CheckinLog] {
        
        do {
            // Use the enhanced view to get check-ins with category info
            return try await supabaseService.makeRequest(
                endpoint: "rest/v1/checkin_logs_with_category?event_id=eq.\(eventId)&gate_id=eq.\(gateId)&wristband_category=eq.\(category)&select=*",
                method: "GET",
                body: nil,
                responseType: [CheckinLog].self
            )
        } catch {
            print("⚠️ Failed to get check-ins for category \(category) and gate \(gateId): \(error)")
            return []
        }
    }
    
    private func calculateBindingQuality(
        eventStats: ComprehensiveEventStats,
        recommendations: [BindingRecommendation]
    ) -> BindingQuality {
        
        let linkingRate = eventStats.linkingRate
        let criticalRecommendations = recommendations.filter {
            $0.recommendedAction == .removeBinding || $0.recommendedAction == .reviewBinding
        }.count
        
        // Adjust quality based on linking rate and critical issues
        let adjustedRate = linkingRate - (Double(criticalRecommendations) * 0.1)
        
        switch adjustedRate {
        case 0.9...1.0: return .excellent
        case 0.7..<0.9: return .good
        case 0.5..<0.7: return .fair
        default: return .poor
        }
    }
    
    private func calculateRecommendationPriority(_ recommendation: BindingRecommendation) -> Double {
        var priority = recommendation.confidence
        
        // Boost priority based on action type
        switch recommendation.recommendedAction {
        case .removeBinding: priority += 0.3
        case .createBinding: priority += 0.2
        case .reviewBinding: priority += 0.1
        case .strengthenBinding: priority += 0.05
        }
        
        // Boost priority based on sample count
        priority += min(Double(recommendation.sampleCount) / 100.0, 0.2)
        
        return priority
    }
    
    private func createGateBinding(gateId: String, categoryName: String, eventId: String) async throws {
        let binding = [
            "gate_id": gateId,
            "category": categoryName,
            "event_id": eventId,
            "status": "probation",
            "confidence": 0.5,
            "sample_count": 0
        ] as [String: Any]
        
        let _: [GateBinding] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/gate_bindings",
            method: "POST",
            body: try JSONSerialization.data(withJSONObject: binding),
            responseType: [GateBinding].self
        )
    }
    
    private func strengthenGateBinding(gateId: String, categoryName: String) async throws {
        let update = [
            "confidence": 0.8,
            "status": "enforced"
        ] as [String: Any]
        
        let _: [GateBinding] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/gate_bindings?gate_id=eq.\(gateId)&category=eq.\(categoryName)",
            method: "PATCH",
            body: try JSONSerialization.data(withJSONObject: update),
            responseType: [GateBinding].self
        )
    }
    
    private func removeGateBinding(gateId: String, categoryName: String) async throws {
        let _: [GateBinding] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/gate_bindings?gate_id=eq.\(gateId)&category=eq.\(categoryName)",
            method: "DELETE",
            body: nil,
            responseType: [GateBinding].self
        )
    }
}
