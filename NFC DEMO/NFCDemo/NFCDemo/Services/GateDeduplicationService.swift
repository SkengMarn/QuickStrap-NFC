import Foundation
import CoreLocation

struct GateCluster {
    let primaryGate: Gate
    let duplicateGates: [Gate]
    let mergedBindings: [GateBinding]
    let averageLocation: CLLocationCoordinate2D
    let totalSampleCount: Int
    let highestConfidence: Double
}

struct ThresholdVerificationResult {
    var totalSamples: Int = 0
    var confidence: Double = 0.0
    var qualifiesForBinding: Bool = false
    var qualifiesForEnforced: Bool = false
    var meetsThreshold: Bool = false
    var recommendedStatus: String = "unbound"
    
    var summary: String {
        return """
        📊 Threshold Verification:
        • Total Samples: \(totalSamples)
        • Confidence: \(Int(confidence * 100))%
        • Qualifies for Binding: \(qualifiesForBinding ? "✅" : "❌")
        • Qualifies for Enforced: \(qualifiesForEnforced ? "✅" : "❌")
        • Recommended Status: \(recommendedStatus.capitalized)
        """
    }
}

class GateDeduplicationService: ObservableObject {
    static let shared = GateDeduplicationService()
    
    // MARK: - Smart Thresholds Configuration
    struct SmartThresholds {
        // Venue-specific thresholds
        static let indoorVenue: Double = 20.0      // Hotels, conference centers
        static let urbanVenue: Double = 30.0       // City locations with GPS interference
        static let outdoorVenue: Double = 50.0     // Open spaces, festivals
        
        // GPS accuracy-based thresholds
        static let highAccuracy: Double = 15.0     // GPS accuracy < 10m
        static let mediumAccuracy: Double = 25.0   // GPS accuracy 10-30m
        static let lowAccuracy: Double = 40.0      // GPS accuracy > 30m
        
        // Default fallback
        static let defaultThreshold: Double = 25.0
    }
    
    // Current threshold (will be dynamically determined)
    private var duplicateDistanceThreshold: Double = SmartThresholds.defaultThreshold
    
    @Published var isProcessing = false
    @Published var deduplicationResults: [String: GateCluster] = [:]
    
    private init() {}
    
    /// Find and merge duplicate gates based on location proximity and name similarity
    func findAndMergeDuplicateGates(gates: [Gate], bindings: [GateBinding]) async throws -> [GateCluster] {
        print("🔍 Starting gate deduplication analysis...")
        
        await MainActor.run {
            self.isProcessing = true
        }
        
        defer {
            Task { @MainActor in
                self.isProcessing = false
            }
        }
        
        // Group gates by event and name (with fuzzy matching for similar names)
        let groupedGates = Dictionary(grouping: gates) { gate in
            let normalizedName = gate.name.lowercased()
                .replacingOccurrences(of: " gate", with: "")
                .replacingOccurrences(of: "gate", with: "")
                .trimmingCharacters(in: .whitespaces)
            return "\(gate.eventId)_\(normalizedName)"
        }
        
        print("🔍 Gate grouping analysis:")
        for (key, group) in groupedGates {
            print("  Group '\(key)': \(group.count) gates")
            for gate in group {
                print("    - \(gate.name) at (\(gate.latitude ?? 0), \(gate.longitude ?? 0))")
            }
        }
        
        var clusters: [GateCluster] = []
        
        for (groupKey, gateGroup) in groupedGates {
            if gateGroup.count > 1 {
                print("📍 Found \(gateGroup.count) gates with key: \(groupKey)")
                
                // Find clusters within this group based on location proximity
                let locationClusters = clusterGatesByLocation(gateGroup)
                
                for locationCluster in locationClusters {
                    if locationCluster.count > 1 {
                        let cluster = createGateCluster(
                            duplicateGates: locationCluster,
                            bindings: bindings
                        )
                        clusters.append(cluster)
                        
                        print("🔗 Created cluster with \(locationCluster.count) duplicate gates")
                        print("   Primary Gate: \(cluster.primaryGate.id)")
                        print("   Average Location: \(cluster.averageLocation)")
                        print("   Total Samples: \(cluster.totalSampleCount)")
                        print("   Highest Confidence: \(cluster.highestConfidence)")
                    }
                }
            }
        }
        
        let finalClusters = clusters
        await MainActor.run {
            self.deduplicationResults = Dictionary(uniqueKeysWithValues: finalClusters.map { cluster in
                (cluster.primaryGate.id, cluster)
            })
        }
        
        print("✅ Deduplication complete. Found \(clusters.count) clusters to merge.")
        return clusters
    }
    
    /// Cluster gates by location proximity with GPS accuracy awareness
    private func clusterGatesByLocation(_ gates: [Gate]) -> [[Gate]] {
        var clusters: [[Gate]] = []
        var unprocessedGates = gates
        
        // Determine smart threshold based on venue context
        let smartThreshold = determineSmartThreshold(for: gates)
        duplicateDistanceThreshold = smartThreshold
        
        print("🎯 Using smart threshold: \(Int(smartThreshold))m for venue context")
        
        while !unprocessedGates.isEmpty {
            let seedGate = unprocessedGates.removeFirst()
            var currentCluster = [seedGate]
            
            let seedLocation = CLLocation(
                latitude: seedGate.latitude ?? 0.0,
                longitude: seedGate.longitude ?? 0.0
            )
            
            // Find all gates within smart threshold distance
            var i = 0
            while i < unprocessedGates.count {
                let candidateGate = unprocessedGates[i]
                let candidateLocation = CLLocation(
                    latitude: candidateGate.latitude ?? 0.0,
                    longitude: candidateGate.longitude ?? 0.0
                )
                
                let distance = seedLocation.distance(from: candidateLocation)
                let shouldMerge = shouldMergeGates(
                    gate1: seedGate,
                    gate2: candidateGate,
                    distance: distance,
                    threshold: smartThreshold
                )
                
                print("    Distance between \(seedGate.name) and \(candidateGate.name): \(Int(distance))m")
                
                if shouldMerge {
                    print("    ✅ Adding to cluster (smart merge criteria met)")
                    currentCluster.append(candidateGate)
                    unprocessedGates.remove(at: i)
                } else {
                    print("    ❌ Not merging (threshold: \(Int(smartThreshold))m, criteria not met)")
                    i += 1
                }
            }
            
            clusters.append(currentCluster)
        }
        
        return clusters
    }
    
    /// Determine smart threshold based on venue context and GPS patterns
    private func determineSmartThreshold(for gates: [Gate]) -> Double {
        // Analyze GPS coordinate patterns to determine venue type
        let coordinates = gates.compactMap { gate -> (Double, Double)? in
            guard let lat = gate.latitude, let lon = gate.longitude else { return nil }
            return (lat, lon)
        }
        
        guard coordinates.count >= 2 else {
            return SmartThresholds.defaultThreshold
        }
        
        // Calculate coordinate variance to determine venue type
        let latitudes = coordinates.map { $0.0 }
        let longitudes = coordinates.map { $0.1 }
        
        let latRange = latitudes.max()! - latitudes.min()!
        let lonRange = longitudes.max()! - longitudes.min()!
        
        // Convert to approximate meters (rough calculation)
        let latRangeMeters = latRange * 111000 // 1 degree ≈ 111km
        let lonRangeMeters = lonRange * 111000 * cos(latitudes.first! * .pi / 180)
        
        let maxRangeMeters = max(latRangeMeters, lonRangeMeters)
        
        // Determine venue type based on coordinate spread
        if maxRangeMeters < 100 {
            print("🏢 Detected: Indoor venue (range: \(Int(maxRangeMeters))m)")
            return SmartThresholds.indoorVenue
        } else if maxRangeMeters < 500 {
            print("🏙️ Detected: Urban venue (range: \(Int(maxRangeMeters))m)")
            return SmartThresholds.urbanVenue
        } else {
            print("🌳 Detected: Outdoor venue (range: \(Int(maxRangeMeters))m)")
            return SmartThresholds.outdoorVenue
        }
    }
    
    /// Smart gate merging logic with multiple criteria
    private func shouldMergeGates(gate1: Gate, gate2: Gate, distance: Double, threshold: Double) -> Bool {
        // Criterion 1: Name similarity (exact match or very similar)
        let namesSimilar = areNamesSimilar(gate1.name, gate2.name)
        
        // Criterion 2: Distance within threshold
        let withinDistance = distance <= threshold
        
        // Criterion 3: GPS accuracy consideration (if we had accuracy data)
        // For now, use aggressive merging for same names
        let aggressiveMerge = namesSimilar && distance <= (threshold * 1.5)
        
        // Decision logic: "Innocent until proven guilty"
        if namesSimilar && withinDistance {
            return true // Clear case: same name, close distance
        }
        
        if aggressiveMerge {
            print("    🎯 Aggressive merge: Similar names (\(gate1.name) ≈ \(gate2.name)) within \(Int(threshold * 1.5))m")
            return true // Aggressive case: same name, reasonable distance
        }
        
        return false
    }
    
    /// Check if two gate names are similar enough to be considered duplicates
    private func areNamesSimilar(_ name1: String, _ name2: String) -> Bool {
        let normalized1 = name1.lowercased()
            .replacingOccurrences(of: " gate", with: "")
            .replacingOccurrences(of: "gate", with: "")
            .trimmingCharacters(in: .whitespaces)
        
        let normalized2 = name2.lowercased()
            .replacingOccurrences(of: " gate", with: "")
            .replacingOccurrences(of: "gate", with: "")
            .trimmingCharacters(in: .whitespaces)
        
        // Exact match after normalization
        if normalized1 == normalized2 {
            return true
        }
        
        // Check if one contains the other (e.g., "Staff" and "Staff Entrance")
        if normalized1.contains(normalized2) || normalized2.contains(normalized1) {
            return true
        }
        
        return false
    }
    
    /// Create a gate cluster from duplicate gates
    private func createGateCluster(duplicateGates: [Gate], bindings: [GateBinding]) -> GateCluster {
        // Sort by gate ID to keep a consistent primary (IDs are typically chronological)
        let sortedGates = duplicateGates.sorted { gate1, gate2 in
            return gate1.id < gate2.id
        }
        
        let primaryGate = sortedGates.first!
        let duplicates = Array(sortedGates.dropFirst())
        
        // Find all bindings for these gates
        let gateIds = Set(duplicateGates.map { $0.id })
        let relatedBindings = bindings.filter { gateIds.contains($0.gateId) }
        
        // Calculate average location
        let avgLatitude = duplicateGates.reduce(0.0) { $0 + ($1.latitude ?? 0.0) } / Double(duplicateGates.count)
        let avgLongitude = duplicateGates.reduce(0.0) { $0 + ($1.longitude ?? 0.0) } / Double(duplicateGates.count)
        let averageLocation = CLLocationCoordinate2D(latitude: avgLatitude, longitude: avgLongitude)
        
        // Calculate merged statistics
        let totalSampleCount = relatedBindings.reduce(0) { $0 + $1.sampleCount }
        let highestConfidence = relatedBindings.map { $0.confidence }.max() ?? 0.0
        
        return GateCluster(
            primaryGate: primaryGate,
            duplicateGates: duplicates,
            mergedBindings: relatedBindings,
            averageLocation: averageLocation,
            totalSampleCount: totalSampleCount,
            highestConfidence: highestConfidence
        )
    }
    
    /// Execute the deduplication by updating the database
    func executeDuplication(cluster: GateCluster) async throws {
        print("🔄 Executing deduplication for cluster with primary gate: \(cluster.primaryGate.id)")
        
        await MainActor.run {
            self.isProcessing = true
        }
        
        defer {
            Task { @MainActor in
                self.isProcessing = false
            }
        }
        
        // Step 0: Verify thresholds before deduplication
        let thresholdResult = verifyPostDeduplicationThresholds(cluster: cluster)
        print(thresholdResult.summary)
        
        // Step 1: Update primary gate location to average
        try await updatePrimaryGateLocation(cluster: cluster)
        
        // Step 2: Merge all bindings into primary gate
        try await mergeGateBindings(cluster: cluster)
        
        // Step 3: Update any check-in logs that reference duplicate gates
        try await updateCheckinLogs(cluster: cluster)
        
        // Step 4: Delete duplicate gates
        try await deleteDuplicateGates(cluster: cluster)
        
        print("✅ Successfully merged \(cluster.duplicateGates.count) duplicate gates into primary gate")
        print("📊 Final gate has \(cluster.totalSampleCount) total samples and \(Int(cluster.highestConfidence * 100))% confidence")
        
        // Step 5: Verify integrity after deduplication
        await verifyPostDeduplicationIntegrity(eventId: cluster.primaryGate.eventId, primaryGateId: cluster.primaryGate.id)
    }
    
    /// Verify data integrity after deduplication
    private func verifyPostDeduplicationIntegrity(eventId: String, primaryGateId: String) async {
        do {
            // Check that no orphaned check-ins exist
            let orphanedResponse = try await makeSupabaseRequest(
                endpoint: "rest/v1/checkin_logs?event_id=eq.\(eventId)&gate_id=not.is.null&select=gate_id",
                method: "GET"
            )
            
            if let data = orphanedResponse.data,
               let checkins = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                
                // Verify all gate_ids exist
                let gatesResponse = try await makeSupabaseRequest(
                    endpoint: "rest/v1/gates?event_id=eq.\(eventId)&select=id",
                    method: "GET"
                )
                
                if let gatesData = gatesResponse.data,
                   let gates = try? JSONSerialization.jsonObject(with: gatesData) as? [[String: Any]] {
                    
                    let validGateIds = Set(gates.compactMap { $0["id"] as? String })
                    let checkinGateIds = Set(checkins.compactMap { $0["gate_id"] as? String })
                    let orphanedGateIds = checkinGateIds.subtracting(validGateIds)
                    
                    if orphanedGateIds.isEmpty {
                        print("✅ Integrity verification passed: No orphaned check-ins found")
                    } else {
                        print("⚠️ Found \(orphanedGateIds.count) orphaned gate references: \(orphanedGateIds)")
                    }
                }
            }
        } catch {
            print("⚠️ Failed to verify post-deduplication integrity: \(error)")
        }
    }
    
    /// Update primary gate location to the calculated average
    private func updatePrimaryGateLocation(cluster: GateCluster) async throws {
        let updateData: [String: Any] = [
            "latitude": cluster.averageLocation.latitude,
            "longitude": cluster.averageLocation.longitude
        ]
        
        let url = URL(string: "https://pmrxyisasfaimumuobvu.supabase.co/rest/v1/gates?id=eq.\(cluster.primaryGate.id)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBtcnh5aXNhc2ZhaW11bXVvYnZ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTMyODQ2ODMsImV4cCI6MjA2ODg2MDY4M30.rVsKq08Ynw82RkCntxWFXOTgP8T0cGyhJvqfrnOH4YQ", forHTTPHeaderField: "apikey")
        request.setValue("Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBtcnh5aXNhc2ZhaW11bXVvYnZ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTMyODQ2ODMsImV4cCI6MjA2ODg2MDY4M30.rVsKq08Ynw82RkCntxWFXOTgP8T0cGyhJvqfrnOH4YQ", forHTTPHeaderField: "Authorization")
        
        request.httpBody = try JSONSerialization.data(withJSONObject: updateData)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "GateDeduplicationError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid response type"])
        }
        
        if httpResponse.statusCode != 204 && httpResponse.statusCode != 200 {
            let responseBody = String(data: data, encoding: .utf8) ?? "No response body"
            print("❌ Gate update failed - Status: \(httpResponse.statusCode), Body: \(responseBody)")
            throw NSError(domain: "GateDeduplicationError", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Failed to update primary gate location: HTTP \(httpResponse.statusCode) - \(responseBody)"])
        }
        
        print("✅ Updated primary gate location to average coordinates")
    }
    
    /// Merge all gate bindings into the primary gate
    private func mergeGateBindings(cluster: GateCluster) async throws {
        // Create a single merged binding for the primary gate
        let mergedBinding: [String: Any] = [
            "gate_id": cluster.primaryGate.id,
            "category": cluster.mergedBindings.first?.categoryName ?? "General",
            "bound_at": ISO8601DateFormatter().string(from: Date()),
            "status": cluster.highestConfidence > 0.7 ? "confirmed" : "probation",
            "sample_count": cluster.totalSampleCount,
            "confidence": cluster.highestConfidence,
            "event_id": cluster.primaryGate.eventId
        ]
        
        // Delete existing bindings for all gates in cluster
        for gate in [cluster.primaryGate] + cluster.duplicateGates {
            try await deleteGateBinding(gateId: gate.id)
        }
        
        // Insert new merged binding
        try await insertGateBinding(bindingData: mergedBinding)
        
        print("✅ Merged \(cluster.mergedBindings.count) bindings into single binding with \(cluster.totalSampleCount) total samples")
    }
    
    /// Update check-in logs to reference the primary gate instead of duplicates
    private func updateCheckinLogs(cluster: GateCluster) async throws {
        var totalUpdatedCheckins = 0
        
        for duplicateGate in cluster.duplicateGates {
            // First, count how many check-ins will be updated
            let countResponse = try await makeSupabaseRequest(
                endpoint: "rest/v1/checkin_logs?gate_id=eq.\(duplicateGate.id)&select=id",
                method: "GET"
            )
            
            if let countData = countResponse.data,
               let checkins = try? JSONSerialization.jsonObject(with: countData) as? [[String: Any]] {
                let checkinCount = checkins.count
                totalUpdatedCheckins += checkinCount
                
                if checkinCount > 0 {
                    print("📝 Updating \(checkinCount) check-ins from duplicate gate \(duplicateGate.id) to primary gate \(cluster.primaryGate.id)")
                    
                    // Update the check-ins
                    let updateData: [String: Any] = [
                        "gate_id": cluster.primaryGate.id
                    ]
                    
                    let _ = try await makeSupabaseRequest(
                        endpoint: "rest/v1/checkin_logs?gate_id=eq.\(duplicateGate.id)",
                        method: "PATCH",
                        body: try JSONSerialization.data(withJSONObject: updateData)
                    )
                }
            }
        }
        
        print("✅ Updated \(totalUpdatedCheckins) check-in logs to reference primary gate \(cluster.primaryGate.id)")
    }
    
    /// Verify that scan thresholds are met after deduplication
    func verifyPostDeduplicationThresholds(cluster: GateCluster) -> ThresholdVerificationResult {
        let totalSamples = cluster.totalSampleCount
        let confidence = cluster.highestConfidence
        
        // Define thresholds (should match GateBindingService.GateThresholds)
        let minScansForBinding = 5
        let minScansForEnforced = 15
        let confidenceThresholdEnforced = 0.8
        
        var result = ThresholdVerificationResult()
        result.totalSamples = totalSamples
        result.confidence = confidence
        
        // Check if gate qualifies for binding
        if totalSamples >= minScansForBinding {
            result.qualifiesForBinding = true
            
            // Check if gate qualifies for enforced status
            if totalSamples >= minScansForEnforced && confidence >= confidenceThresholdEnforced {
                result.qualifiesForEnforced = true
                result.recommendedStatus = "enforced"
            } else {
                result.qualifiesForEnforced = false
                result.recommendedStatus = "probation"
            }
        } else {
            result.qualifiesForBinding = false
            result.recommendedStatus = "unbound"
        }
        
        result.meetsThreshold = result.qualifiesForBinding
        
        return result
    }
    
    /// Helper method for consistent Supabase API calls
    private func makeSupabaseRequest(endpoint: String, method: String, body: Data? = nil) async throws -> (data: Data?, response: URLResponse) {
        let url = URL(string: "https://pmrxyisasfaimumuobvu.supabase.co/\(endpoint)")!
        var request = URLRequest(url: url)
        request.httpMethod = method
        
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.setValue("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBtcnh5aXNhc2ZhaW11bXVvYnZ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTMyODQ2ODMsImV4cCI6MjA2ODg2MDY4M30.rVsKq08Ynw82RkCntxWFXOTgP8T0cGyhJvqfrnOH4YQ", forHTTPHeaderField: "apikey")
        request.setValue("Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBtcnh5aXNhc2ZhaW11bXVvYnZ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTMyODQ2ODMsImV4cCI6MjA2ODg2MDY4M30.rVsKq08Ynw82RkCntxWFXOTgP8T0cGyhJvqfrnOH4YQ", forHTTPHeaderField: "Authorization")
        
        if let body = body {
            request.httpBody = body
        }
        
        return try await URLSession.shared.data(for: request)
    }
    
    /// Delete duplicate gates from the database
    private func deleteDuplicateGates(cluster: GateCluster) async throws {
        for duplicateGate in cluster.duplicateGates {
            let url = URL(string: "https://pmrxyisasfaimumuobvu.supabase.co/rest/v1/gates?id=eq.\(duplicateGate.id)")!
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.setValue("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBtcnh5aXNhc2ZhaW11bXVvYnZ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTMyODQ2ODMsImV4cCI6MjA2ODg2MDY4M30.rVsKq08Ynw82RkCntxWFXOTgP8T0cGyhJvqfrnOH4YQ", forHTTPHeaderField: "apikey")
            request.setValue("Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBtcnh5aXNhc2ZhaW11bXVvYnZ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTMyODQ2ODMsImV4cCI6MjA2ODg2MDY4M30.rVsKq08Ynw82RkCntxWFXOTgP8T0cGyhJvqfrnOH4YQ", forHTTPHeaderField: "Authorization")
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 204 else {
                throw NSError(domain: "GateDeduplicationError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to delete duplicate gate: \(duplicateGate.id)"])
            }
        }
        
        print("✅ Deleted \(cluster.duplicateGates.count) duplicate gates")
    }
    
    /// Helper method to delete a gate binding
    private func deleteGateBinding(gateId: String) async throws {
        let url = URL(string: "https://pmrxyisasfaimumuobvu.supabase.co/rest/v1/gate_bindings?gate_id=eq.\(gateId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBtcnh5aXNhc2ZhaW11bXVvYnZ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTMyODQ2ODMsImV4cCI6MjA2ODg2MDY4M30.rVsKq08Ynw82RkCntxWFXOTgP8T0cGyhJvqfrnOH4YQ", forHTTPHeaderField: "apikey")
        request.setValue("Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBtcnh5aXNhc2ZhaW11bXVvYnZ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTMyODQ2ODMsImV4cCI6MjA2ODg2MDY4M30.rVsKq08Ynw82RkCntxWFXOTgP8T0cGyhJvqfrnOH4YQ", forHTTPHeaderField: "Authorization")
        
        let (_, _) = try await URLSession.shared.data(for: request)
    }
    
    /// Helper method to insert a gate binding
    private func insertGateBinding(bindingData: [String: Any]) async throws {
        let url = URL(string: "https://pmrxyisasfaimumuobvu.supabase.co/rest/v1/gate_bindings")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBtcnh5aXNhc2ZhaW11bXVvYnZ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTMyODQ2ODMsImV4cCI6MjA2ODg2MDY4M30.rVsKq08Ynw82RkCntxWFXOTgP8T0cGyhJvqfrnOH4YQ", forHTTPHeaderField: "apikey")
        request.setValue("Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBtcnh5aXNhc2ZhaW11bXVvYnZ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTMyODQ2ODMsImV4cCI6MjA2ODg2MDY4M30.rVsKq08Ynw82RkCntxWFXOTgP8T0cGyhJvqfrnOH4YQ", forHTTPHeaderField: "Authorization")
        
        request.httpBody = try JSONSerialization.data(withJSONObject: bindingData)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 201 else {
            throw NSError(domain: "GateDeduplicationError", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to insert merged gate binding"])
        }
    }
    
    /// Get deduplication summary for display
    func getDeduplicationSummary() -> String {
        let totalClusters = deduplicationResults.count
        let totalDuplicatesFound = deduplicationResults.values.reduce(0) { $0 + $1.duplicateGates.count }
        
        return """
        📊 Gate Deduplication Summary:
        • Found \(totalClusters) clusters requiring deduplication
        • Total duplicate gates: \(totalDuplicatesFound)
        • Potential space savings: \(totalDuplicatesFound) gates
        """
    }
}
