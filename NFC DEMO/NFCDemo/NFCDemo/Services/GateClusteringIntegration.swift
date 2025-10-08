import Foundation
import CoreLocation

/// Integration service that connects adaptive clustering with gate processing
class GateClusteringIntegration: ObservableObject {
    
    // MARK: - Dependencies
    
    private let clusteringService = AdaptiveClusteringService()
    private let supabaseService = SupabaseService.shared
    
    // MARK: - Published Properties
    
    @Published var discoveredGates: [DiscoveredGate] = []
    @Published var clusteringProgress: Double = 0.0
    @Published var isProcessing = false
    
    // MARK: - Models
    
    struct DiscoveredGate: Identifiable {
        let id = UUID()
        let cluster: AdaptiveClusteringService.LocationCluster
        let suggestedName: String
        let confidence: Double
        let category: String
        
        var location: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: cluster.centerLat, longitude: cluster.centerLon)
        }
        
        var checkInCount: Int {
            cluster.checkIns.count
        }
        
        var qualityScore: Double {
            cluster.quality
        }
    }
    
    // MARK: - Main Processing Methods
    
    /// Analyze check-ins for an event and discover potential gate locations
    func analyzeEventForGates(eventId: String, venueType: AdaptiveClusteringService.ClusterConfig.VenueType = .hybrid) async throws {
        await MainActor.run {
            isProcessing = true
            clusteringProgress = 0.0
            discoveredGates = []
        }
        
        defer {
            Task { @MainActor in
                isProcessing = false
                clusteringProgress = 1.0
            }
        }
        
        print("🔍 Starting gate discovery analysis for event: \(eventId)")
        
        // Step 1: Fetch all check-ins for the event
        await MainActor.run { clusteringProgress = 0.1 }
        let checkIns = try await supabaseService.fetchCheckinLogs(for: eventId, limit: 10000)
        
        print("📊 Analyzing \(checkIns.count) check-ins for gate discovery")
        
        // Step 2: Filter check-ins with GPS data
        await MainActor.run { clusteringProgress = 0.2 }
        let gpsCheckIns = checkIns.filter { $0.appLat != nil && $0.appLon != nil }
        
        print("📍 Found \(gpsCheckIns.count) check-ins with GPS coordinates")
        
        guard !gpsCheckIns.isEmpty else {
            print("❌ No GPS data available for clustering")
            return
        }
        
        // Step 3: Configure clustering based on venue type
        await MainActor.run { clusteringProgress = 0.3 }
        let config = AdaptiveClusteringService.ClusterConfig(
            baseThreshold: 30.0,
            minAccuracy: 50.0, // Accept GPS accuracy up to 50 meters
            minSamplesForGate: 5, // Minimum 5 check-ins to consider a gate
            venueType: venueType
        )
        
        // Step 4: Perform clustering
        await MainActor.run { clusteringProgress = 0.5 }
        let clusters = clusteringService.clusterCheckIns(checkIns: gpsCheckIns, config: config)
        
        print("🎯 Discovered \(clusters.count) potential gate locations")
        
        // Step 5: Convert clusters to discovered gates
        await MainActor.run { clusteringProgress = 0.7 }
        let gates = clusters.map { cluster in
            DiscoveredGate(
                cluster: cluster,
                suggestedName: generateGateName(for: cluster),
                confidence: calculateConfidence(for: cluster),
                category: cluster.category
            )
        }
        
        // Step 6: Sort by quality and confidence
        await MainActor.run { clusteringProgress = 0.9 }
        let sortedGates = gates.sorted { gate1, gate2 in
            let score1 = gate1.confidence * gate1.qualityScore
            let score2 = gate2.confidence * gate2.qualityScore
            return score1 > score2
        }
        
        await MainActor.run {
            discoveredGates = sortedGates
            clusteringProgress = 1.0
        }
        
        print("✅ Gate discovery completed. Found \(sortedGates.count) high-quality gate candidates")
    }
    
    /// Create actual gates from discovered gate candidates
    func createGatesFromDiscovery(selectedGates: [DiscoveredGate], eventId: String) async throws -> [Gate] {
        var createdGates: [Gate] = []
        
        for discoveredGate in selectedGates {
            let gate = Gate(
                id: UUID().uuidString,
                eventId: eventId,
                name: discoveredGate.suggestedName,
                latitude: discoveredGate.cluster.centerLat,
                longitude: discoveredGate.cluster.centerLon
            )
            
            // TODO: If you have a gate creation API, call it here
            // let createdGate = try await supabaseService.createGate(gate)
            
            createdGates.append(gate)
            print("✅ Created gate: \(gate.name) at (\(gate.latitude ?? 0), \(gate.longitude ?? 0))")
        }
        
        return createdGates
    }
    
    // MARK: - Helper Methods
    
    private func generateGateName(for cluster: AdaptiveClusteringService.LocationCluster) -> String {
        let category = cluster.category
        let checkInCount = cluster.checkIns.count
        
        // Generate name based on category and activity level
        let activityLevel = checkInCount > 50 ? "Main" : checkInCount > 20 ? "Secondary" : "Minor"
        
        switch category {
        case "VIP", "VVIP":
            return "\(category) \(activityLevel) Gate"
        case "Staff":
            return "Staff \(activityLevel) Entrance"
        case "Press":
            return "Media \(activityLevel) Gate"
        case "Artist":
            return "Artist \(activityLevel) Entrance"
        default:
            return "General \(activityLevel) Gate"
        }
    }
    
    private func calculateConfidence(for cluster: AdaptiveClusteringService.LocationCluster) -> Double {
        let checkInCount = Double(cluster.checkIns.count)
        let qualityScore = cluster.quality
        
        // Confidence based on sample size and cluster tightness
        let sampleConfidence = min(1.0, checkInCount / 20.0) // Max confidence at 20+ samples
        let overallConfidence = (sampleConfidence * 0.7) + (qualityScore * 0.3)
        
        return overallConfidence
    }
    
    /// Get clustering recommendations for venue setup
    func getVenueRecommendations(checkIns: [CheckinLog]) -> VenueRecommendation {
        let gpsCheckIns = checkIns.filter { $0.appLat != nil && $0.appLon != nil }
        
        guard !gpsCheckIns.isEmpty else {
            return VenueRecommendation(
                recommendedVenueType: .hybrid,
                confidence: 0.0,
                reasoning: "No GPS data available for analysis"
            )
        }
        
        // Analyze GPS accuracy distribution
        let accuracies = gpsCheckIns.compactMap { $0.gpsAccuracy }
        let avgAccuracy = accuracies.isEmpty ? 50.0 : accuracies.reduce(0, +) / Double(accuracies.count)
        
        // Analyze spatial distribution
        let latitudes = gpsCheckIns.compactMap { $0.appLat }
        let longitudes = gpsCheckIns.compactMap { $0.appLon }
        
        let latRange = (latitudes.max() ?? 0) - (latitudes.min() ?? 0)
        let lonRange = (longitudes.max() ?? 0) - (longitudes.min() ?? 0)
        
        // Convert to approximate meters (rough calculation)
        let latMeters = latRange * 111000 // 1 degree lat ≈ 111km
        let lonMeters = lonRange * 111000 * cos(latitudes.first ?? 0 * .pi / 180)
        
        let maxSpread = max(latMeters, lonMeters)
        
        // Determine venue type based on spread and accuracy
        let venueType: AdaptiveClusteringService.ClusterConfig.VenueType
        let reasoning: String
        
        if avgAccuracy > 30 && maxSpread < 200 {
            venueType = .indoor
            reasoning = "High GPS uncertainty (\(Int(avgAccuracy))m) and compact area suggest indoor venue"
        } else if maxSpread > 1000 {
            venueType = .outdoor
            reasoning = "Large area spread (\(Int(maxSpread))m) suggests outdoor venue"
        } else if avgAccuracy < 10 && maxSpread < 500 {
            venueType = .urban
            reasoning = "High GPS accuracy (\(Int(avgAccuracy))m) in compact area suggests urban setting"
        } else {
            venueType = .hybrid
            reasoning = "Mixed characteristics suggest hybrid venue type"
        }
        
        let confidence = min(1.0, Double(gpsCheckIns.count) / 100.0) // Higher confidence with more data
        
        return VenueRecommendation(
            recommendedVenueType: venueType,
            confidence: confidence,
            reasoning: reasoning
        )
    }
}

// MARK: - Supporting Models

struct VenueRecommendation {
    let recommendedVenueType: AdaptiveClusteringService.ClusterConfig.VenueType
    let confidence: Double
    let reasoning: String
}

// MARK: - Analytics Extensions

extension GateClusteringIntegration {
    
    /// Generate clustering analytics report
    func generateClusteringReport(for eventId: String) async throws -> ClusteringReport {
        let checkIns = try await supabaseService.fetchCheckinLogs(for: eventId, limit: 10000)
        let gpsCheckIns = checkIns.filter { $0.appLat != nil && $0.appLon != nil }
        
        let venueRecommendation = getVenueRecommendations(checkIns: checkIns)
        
        let config = AdaptiveClusteringService.ClusterConfig(
            baseThreshold: 30.0,
            minAccuracy: 50.0,
            minSamplesForGate: 3, // Lower threshold for analysis
            venueType: venueRecommendation.recommendedVenueType
        )
        
        let clusters = clusteringService.clusterCheckIns(checkIns: gpsCheckIns, config: config)
        
        return ClusteringReport(
            eventId: eventId,
            totalCheckIns: checkIns.count,
            gpsCheckIns: gpsCheckIns.count,
            clustersFound: clusters.count,
            venueRecommendation: venueRecommendation,
            clusters: clusters,
            averageClusterQuality: clusters.isEmpty ? 0.0 : clusters.map { $0.quality }.reduce(0, +) / Double(clusters.count)
        )
    }
}

struct ClusteringReport {
    let eventId: String
    let totalCheckIns: Int
    let gpsCheckIns: Int
    let clustersFound: Int
    let venueRecommendation: VenueRecommendation
    let clusters: [AdaptiveClusteringService.LocationCluster]
    let averageClusterQuality: Double
    
    var gpsDataCoverage: Double {
        totalCheckIns > 0 ? Double(gpsCheckIns) / Double(totalCheckIns) : 0.0
    }
}
