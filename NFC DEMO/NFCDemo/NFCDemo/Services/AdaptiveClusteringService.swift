import Foundation
import CoreLocation

/// Advanced GPS clustering with adaptive thresholds and accuracy filtering
class AdaptiveClusteringService {
    
    // MARK: - Configuration
    
    struct ClusterConfig {
        let baseThreshold: Double // meters
        let minAccuracy: Double // meters (filter out poor GPS)
        let minSamplesForGate: Int
        let venueType: VenueType
        
        enum VenueType {
            case indoor      // 50m threshold, high tolerance
            case outdoor     // 30m threshold, medium tolerance
            case urban       // 25m threshold, low tolerance
            case hybrid      // 40m threshold, adaptive
        }
        
        var clusteringThreshold: Double {
            switch venueType {
            case .indoor: return 50.0
            case .outdoor: return 30.0
            case .urban: return 25.0
            case .hybrid: return 40.0
            }
        }
    }
    
    // MARK: - Location Cluster Model
    
    class LocationCluster {
        var checkIns: [CheckinLog] = []
        var centerLat: Double = 0.0
        var centerLon: Double = 0.0
        var radius: Double = 0.0 // Standard deviation
        var category: String = ""
        
        var quality: Double {
            // Quality score based on cluster tightness
            guard checkIns.count > 1 else { return 1.0 }
            return max(0.0, min(1.0, 1.0 - (radius / 50.0))) // Penalize loose clusters
        }
        
        init(initialCheckIn: CheckinLog, category: String) {
            self.checkIns = [initialCheckIn]
            self.centerLat = initialCheckIn.appLat ?? 0.0
            self.centerLon = initialCheckIn.appLon ?? 0.0
            self.category = category
        }
        
        func addCheckIn(_ checkIn: CheckinLog) {
            checkIns.append(checkIn)
            recalculateCenter()
        }
        
        func recalculateCenter() {
            guard !checkIns.isEmpty else { return }
            
            // Weighted centroid calculation (weight by GPS accuracy if available)
            var totalWeight = 0.0
            var weightedLat = 0.0
            var weightedLon = 0.0
            
            for checkIn in checkIns {
                guard let lat = checkIn.appLat, let lon = checkIn.appLon else { continue }
                
                // Higher accuracy (lower number) = higher weight
                let accuracy = checkIn.gpsAccuracy ?? 10.0
                let weight = 1.0 / max(accuracy, 1.0)
                
                weightedLat += lat * weight
                weightedLon += lon * weight
                totalWeight += weight
            }
            
            centerLat = weightedLat / totalWeight
            centerLon = weightedLon / totalWeight
            
            // Calculate radius (standard deviation)
            radius = calculateStandardDeviation()
        }
        
        private func calculateStandardDeviation() -> Double {
            guard checkIns.count > 1 else { return 0.0 }
            
            let distances = checkIns.compactMap { checkIn -> Double? in
                guard let lat = checkIn.appLat, let lon = checkIn.appLon else { return nil }
                return AdaptiveClusteringService.haversineDistance(lat1: centerLat, lon1: centerLon, lat2: lat, lon2: lon)
            }
            
            let variance = distances.map { pow($0, 2) }.reduce(0, +) / Double(distances.count)
            return sqrt(variance)
        }
    }
    
    // MARK: - Clustering Algorithm
    
    func clusterCheckIns(
        checkIns: [CheckinLog],
        config: ClusterConfig
    ) -> [LocationCluster] {
        
        // Step 1: Filter by GPS accuracy
        let qualityCheckIns = checkIns.filter { checkIn in
            guard let accuracy = checkIn.gpsAccuracy else { return true }
            return accuracy <= config.minAccuracy
        }
        
        print("📍 Filtered \(checkIns.count) → \(qualityCheckIns.count) check-ins by GPS accuracy")
        
        // Step 2: Group by category first
        let categoryGroups = Dictionary(grouping: qualityCheckIns) { checkIn in
            extractCategory(from: checkIn.wristbandId)
        }
        
        var allClusters: [LocationCluster] = []
        
        // Step 3: Cluster each category separately
        for (category, categoryCheckIns) in categoryGroups {
            let clusters = clusterByLocation(
                checkIns: categoryCheckIns,
                category: category,
                threshold: config.clusteringThreshold
            )
            
            // Filter by minimum sample size
            let validClusters = clusters.filter { $0.checkIns.count >= config.minSamplesForGate }
            allClusters.append(contentsOf: validClusters)
            
            print("  \(category): \(categoryCheckIns.count) check-ins → \(validClusters.count) clusters")
        }
        
        return allClusters
    }
    
    private func clusterByLocation(
        checkIns: [CheckinLog],
        category: String,
        threshold: Double
    ) -> [LocationCluster] {
        
        var clusters: [LocationCluster] = []
        var processed: Set<String> = []
        
        // Sort by timestamp to maintain temporal ordering
        let sortedCheckIns = checkIns.sorted { ($0.createdAt ?? Date()) < ($1.createdAt ?? Date()) }
        
        for checkIn in sortedCheckIns {
            guard !processed.contains(checkIn.id),
                  let lat = checkIn.appLat,
                  let lon = checkIn.appLon else { continue }
            
            // Find nearest existing cluster
            if let nearestCluster = findNearestCluster(
                lat: lat,
                lon: lon,
                in: clusters,
                maxDistance: threshold
            ) {
                nearestCluster.addCheckIn(checkIn)
                processed.insert(checkIn.id)
            } else {
                // Create new cluster
                let newCluster = LocationCluster(initialCheckIn: checkIn, category: category)
                clusters.append(newCluster)
                processed.insert(checkIn.id)
            }
        }
        
        // Post-processing: Merge very close clusters
        return mergeSimilarClusters(clusters, threshold: threshold * 0.7)
    }
    
    private func findNearestCluster(
        lat: Double,
        lon: Double,
        in clusters: [LocationCluster],
        maxDistance: Double
    ) -> LocationCluster? {
        
        var nearestCluster: LocationCluster?
        var minDistance = Double.infinity
        
        for cluster in clusters {
            let distance = AdaptiveClusteringService.haversineDistance(
                lat1: lat,
                lon1: lon,
                lat2: cluster.centerLat,
                lon2: cluster.centerLon
            )
            
            if distance < maxDistance && distance < minDistance {
                minDistance = distance
                nearestCluster = cluster
            }
        }
        
        return nearestCluster
    }
    
    private func mergeSimilarClusters(_ clusters: [LocationCluster], threshold: Double) -> [LocationCluster] {
        var merged: [LocationCluster] = []
        var processed: Set<Int> = []
        
        for (i, cluster1) in clusters.enumerated() {
            guard !processed.contains(i) else { continue }
            
            let currentCluster = cluster1
            processed.insert(i)
            
            for (j, cluster2) in clusters.enumerated() {
                guard i != j, !processed.contains(j) else { continue }
                
                let distance = AdaptiveClusteringService.haversineDistance(
                    lat1: currentCluster.centerLat,
                    lon1: currentCluster.centerLon,
                    lat2: cluster2.centerLat,
                    lon2: cluster2.centerLon
                )
                
                if distance < threshold && currentCluster.category == cluster2.category {
                    // Merge cluster2 into currentCluster
                    for checkIn in cluster2.checkIns {
                        currentCluster.addCheckIn(checkIn)
                    }
                    processed.insert(j)
                }
            }
            
            merged.append(currentCluster)
        }
        
        return merged
    }
    
    // MARK: - Helper Functions
    
    static func haversineDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let R = 6371000.0 // Earth radius in meters
        let φ1 = lat1 * .pi / 180
        let φ2 = lat2 * .pi / 180
        let Δφ = (lat2 - lat1) * .pi / 180
        let Δλ = (lon2 - lon1) * .pi / 180
        
        let a = sin(Δφ/2) * sin(Δφ/2) + cos(φ1) * cos(φ2) * sin(Δλ/2) * sin(Δλ/2)
        let c = 2 * atan2(sqrt(a), sqrt(1-a))
        
        return R * c
    }
    
    private func extractCategory(from wristbandId: String) -> String {
        let lower = wristbandId.lowercased()
        
        // Pattern matching with priority
        let patterns: [(String, [String])] = [
            ("VVIP", ["vvip"]),
            ("VIP", ["vip", "premium", "exclusivo"]),
            ("Staff", ["staff", "crew", "team", "worker"]),
            ("Press", ["press", "media", "journalist"]),
            ("Artist", ["artist", "performer", "talent"]),
            ("General", ["general", "standard", "regular"])
        ]
        
        for (category, keywords) in patterns {
            for keyword in keywords {
                if lower.contains(keyword) {
                    return category
                }
            }
        }
        
        return "General"
    }
}

// MARK: - CheckinLog Extension for GPS Accuracy

extension CheckinLog {
    var gpsAccuracy: Double? {
        // Return the GPS accuracy from appAccuracy field if available
        return appAccuracy
    }
    
    var createdAt: Date? {
        // Return timestamp as created_at for clustering purposes
        return timestamp
    }
}
