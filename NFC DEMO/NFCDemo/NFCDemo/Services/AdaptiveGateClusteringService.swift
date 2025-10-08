import Foundation
import CoreLocation

/// Adaptive gate clustering using DBSCAN and machine learning
class AdaptiveGateClusteringService {
    static let shared = AdaptiveGateClusteringService()

    // MARK: - DBSCAN Implementation

    struct DBSCANCluster {
        let corePoints: [CheckinLog]
        let borderPoints: [CheckinLog]
        let centroid: CLLocationCoordinate2D
        let radius: Double  // Learned, not hardcoded
        let density: Double // Scans per square meter
    }

    /// Automatically determines optimal epsilon (ε) from data
    func calculateOptimalEpsilon(from logs: [CheckinLog]) -> Double {
        guard logs.count >= 10 else { return 50.0 } // Fallback for small samples

        // Extract GPS coordinates
        let coordinates = logs.compactMap { log -> CLLocationCoordinate2D? in
            guard let lat = log.appLat, let lon = log.appLon else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }

        guard coordinates.count >= 10 else { return 50.0 }

        // Calculate k-nearest neighbor distances (k=4 is standard)
        var kDistances: [Double] = []

        for coord in coordinates {
            var distances: [Double] = []

            for otherCoord in coordinates where coord.latitude != otherCoord.latitude {
                let distance = LocationMathService.haversineDistance(
                    lat1: coord.latitude, lon1: coord.longitude,
                    lat2: otherCoord.latitude, lon2: otherCoord.longitude
                )
                distances.append(distance)
            }

            // Get 4th nearest neighbor distance
            distances.sort()
            if distances.count >= 4 {
                kDistances.append(distances[3]) // 4th nearest (index 3)
            }
        }

        // Sort k-distances
        kDistances.sort()

        // Find "elbow" using rate of change
        let epsilon = findElbowPoint(distances: kDistances)

        print("📊 Calculated optimal ε: \(Int(epsilon))m (learned from \(coordinates.count) points)")

        return epsilon
    }

    /// Find elbow point in sorted distances (where curve bends)
    private func findElbowPoint(distances: [Double]) -> Double {
        guard distances.count >= 3 else { return distances.last ?? 50.0 }

        var maxCurvature = 0.0
        var elbowIndex = distances.count / 2

        // Calculate curvature at each point (second derivative)
        for i in 1..<(distances.count - 1) {
            let d1 = distances[i] - distances[i - 1]
            let d2 = distances[i + 1] - distances[i]
            let curvature = abs(d2 - d1)

            if curvature > maxCurvature {
                maxCurvature = curvature
                elbowIndex = i
            }
        }

        return distances[elbowIndex]
    }

    /// DBSCAN clustering with learned epsilon
    func clusterWithDBSCAN(
        logs: [CheckinLog],
        epsilon: Double? = nil,
        minPts: Int = 5
    ) -> [DBSCANCluster] {

        // Learn epsilon if not provided
        let ε = epsilon ?? calculateOptimalEpsilon(from: logs)

        print("🔬 Running DBSCAN with ε=\(Int(ε))m, minPts=\(minPts)")

        var clusters: [DBSCANCluster] = []
        var visited = Set<String>()
        var clustered = Set<String>()

        for log in logs {
            guard let lat = log.appLat, let lon = log.appLon else { continue }

            let logId = log.id
            guard !visited.contains(logId) else { continue }

            visited.insert(logId)

            // Find neighbors within ε
            let neighbors = findNeighbors(
                of: log,
                in: logs,
                epsilon: ε
            )

            if neighbors.count < minPts {
                // Not enough neighbors - noise point (skip)
                continue
            }

            // Core point - start new cluster
            var clusterLogs: [CheckinLog] = [log]
            var queue = neighbors

            while !queue.isEmpty {
                let neighbor = queue.removeFirst()
                let neighborId = neighbor.id

                if !visited.contains(neighborId) {
                    visited.insert(neighborId)

                    let neighborNeighbors = findNeighbors(
                        of: neighbor,
                        in: logs,
                        epsilon: ε
                    )

                    if neighborNeighbors.count >= minPts {
                        // Neighbor is also core point - expand cluster
                        queue.append(contentsOf: neighborNeighbors)
                    }
                }

                if !clustered.contains(neighborId) {
                    clusterLogs.append(neighbor)
                    clustered.insert(neighborId)
                }
            }

            // Create cluster from collected points
            if clusterLogs.count >= minPts {
                let cluster = createCluster(from: clusterLogs, epsilon: ε)
                clusters.append(cluster)

                print("✅ Found cluster: \(clusterLogs.count) scans, radius: \(Int(cluster.radius))m")
            }
        }

        print("🎯 DBSCAN complete: \(clusters.count) clusters found")
        return clusters
    }

    private func findNeighbors(
        of log: CheckinLog,
        in allLogs: [CheckinLog],
        epsilon: Double
    ) -> [CheckinLog] {

        guard let lat1 = log.appLat, let lon1 = log.appLon else { return [] }

        return allLogs.filter { otherLog in
            guard log.id != otherLog.id else { return false }
            guard let lat2 = otherLog.appLat, let lon2 = otherLog.appLon else { return false }

            let distance = LocationMathService.haversineDistance(
                lat1: lat1, lon1: lon1,
                lat2: lat2, lon2: lon2
            )

            return distance <= epsilon
        }
    }

    private func createCluster(
        from logs: [CheckinLog],
        epsilon: Double
    ) -> DBSCANCluster {

        let coordinates = logs.compactMap { log -> CLLocationCoordinate2D? in
            guard let lat = log.appLat, let lon = log.appLon else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }

        // Calculate centroid (average position)
        let avgLat = coordinates.map { $0.latitude }.reduce(0, +) / Double(coordinates.count)
        let avgLon = coordinates.map { $0.longitude }.reduce(0, +) / Double(coordinates.count)
        let centroid = CLLocationCoordinate2D(latitude: avgLat, longitude: avgLon)

        // Calculate actual radius (max distance from centroid)
        let maxDistance = coordinates.map { coord in
            LocationMathService.haversineDistance(
                lat1: centroid.latitude, lon1: centroid.longitude,
                lat2: coord.latitude, lon2: coord.longitude
            )
        }.max() ?? epsilon

        // Calculate density (scans per square meter)
        let area = Double.pi * maxDistance * maxDistance
        let density = Double(logs.count) / area

        return DBSCANCluster(
            corePoints: logs,
            borderPoints: [],
            centroid: centroid,
            radius: maxDistance,
            density: density
        )
    }

    // MARK: - Gaussian Mixture Model (GMM) for Soft Clustering

    /// GMM assigns probability that scan belongs to each gate (soft clustering)
    struct GaussianComponent {
        var mean: CLLocationCoordinate2D
        var covariance: CovarianceMatrix
        var weight: Double  // Prior probability
    }

    struct CovarianceMatrix {
        var σ_lat: Double   // Variance in latitude
        var σ_lon: Double   // Variance in longitude
        var σ_lat_lon: Double  // Covariance
    }

    /// Fit Gaussian Mixture Model to learn gate distributions
    func fitGaussianMixture(
        logs: [CheckinLog],
        numComponents: Int? = nil
    ) -> [GaussianComponent] {

        // First cluster with DBSCAN to determine number of components
        let clusters = clusterWithDBSCAN(logs: logs)
        let K = numComponents ?? clusters.count

        guard K > 0 else { return [] }

        print("🔬 Fitting GMM with \(K) components...")

        // Initialize components from DBSCAN clusters
        var components: [GaussianComponent] = clusters.prefix(K).map { cluster in
            let variance = calculateVariance(for: cluster.corePoints)

            return GaussianComponent(
                mean: cluster.centroid,
                covariance: variance,
                weight: 1.0 / Double(K)
            )
        }

        // EM Algorithm (Expectation-Maximization)
        let maxIterations = 10
        var previousLogLikelihood = -Double.infinity

        for iteration in 1...maxIterations {
            // E-Step: Calculate responsibilities (probability each point belongs to each component)
            var responsibilities: [[Double]] = []

            for log in logs {
                guard let lat = log.appLat, let lon = log.appLon else { continue }
                let point = CLLocationCoordinate2D(latitude: lat, longitude: lon)

                var pointResponsibilities: [Double] = []

                for component in components {
                    let prob = gaussianProbability(
                        point: point,
                        mean: component.mean,
                        covariance: component.covariance
                    ) * component.weight

                    pointResponsibilities.append(prob)
                }

                // Normalize
                let sum = pointResponsibilities.reduce(0, +)
                if sum > 0 {
                    pointResponsibilities = pointResponsibilities.map { $0 / sum }
                }

                responsibilities.append(pointResponsibilities)
            }

            // M-Step: Update component parameters
            for k in 0..<K {
                let Nk = responsibilities.map { $0[k] }.reduce(0, +)

                if Nk > 0 {
                    // Update weight
                    components[k].weight = Nk / Double(logs.count)

                    // Update mean
                    var sumLat = 0.0
                    var sumLon = 0.0

                    for (i, log) in logs.enumerated() {
                        guard let lat = log.appLat, let lon = log.appLon else { continue }
                        sumLat += responsibilities[i][k] * lat
                        sumLon += responsibilities[i][k] * lon
                    }

                    components[k].mean = CLLocationCoordinate2D(
                        latitude: sumLat / Nk,
                        longitude: sumLon / Nk
                    )

                    // Update covariance
                    components[k].covariance = calculateWeightedCovariance(
                        logs: logs,
                        responsibilities: responsibilities.map { $0[k] },
                        mean: components[k].mean,
                        Nk: Nk
                    )
                }
            }

            // Check convergence
            let logLikelihood = calculateLogLikelihood(logs: logs, components: components)

            print("  Iteration \(iteration): log-likelihood = \(String(format: "%.2f", logLikelihood))")

            if abs(logLikelihood - previousLogLikelihood) < 0.01 {
                print("✅ GMM converged after \(iteration) iterations")
                break
            }

            previousLogLikelihood = logLikelihood
        }

        return components
    }

    private func gaussianProbability(
        point: CLLocationCoordinate2D,
        mean: CLLocationCoordinate2D,
        covariance: CovarianceMatrix
    ) -> Double {

        let dx = point.latitude - mean.latitude
        let dy = point.longitude - mean.longitude

        // Determinant of covariance matrix
        let det = covariance.σ_lat * covariance.σ_lon - covariance.σ_lat_lon * covariance.σ_lat_lon

        guard det > 0 else { return 0 }

        // Inverse of covariance matrix
        let invσ_lat = covariance.σ_lon / det
        let invσ_lon = covariance.σ_lat / det
        let invσ_lat_lon = -covariance.σ_lat_lon / det

        // Mahalanobis distance
        let exponent = -0.5 * (
            dx * dx * invσ_lat +
            2 * dx * dy * invσ_lat_lon +
            dy * dy * invσ_lon
        )

        let normalization = 1.0 / (2 * Double.pi * sqrt(det))

        return normalization * exp(exponent)
    }

    private func calculateVariance(for logs: [CheckinLog]) -> CovarianceMatrix {
        let coordinates = logs.compactMap { log -> CLLocationCoordinate2D? in
            guard let lat = log.appLat, let lon = log.appLon else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }

        guard !coordinates.isEmpty else {
            return CovarianceMatrix(σ_lat: 0.0001, σ_lon: 0.0001, σ_lat_lon: 0)
        }

        let meanLat = coordinates.map { $0.latitude }.reduce(0, +) / Double(coordinates.count)
        let meanLon = coordinates.map { $0.longitude }.reduce(0, +) / Double(coordinates.count)

        var sumSqLat = 0.0
        var sumSqLon = 0.0
        var sumLatLon = 0.0

        for coord in coordinates {
            let dLat = coord.latitude - meanLat
            let dLon = coord.longitude - meanLon

            sumSqLat += dLat * dLat
            sumSqLon += dLon * dLon
            sumLatLon += dLat * dLon
        }

        let n = Double(coordinates.count)

        return CovarianceMatrix(
            σ_lat: sumSqLat / n,
            σ_lon: sumSqLon / n,
            σ_lat_lon: sumLatLon / n
        )
    }

    private func calculateWeightedCovariance(
        logs: [CheckinLog],
        responsibilities: [Double],
        mean: CLLocationCoordinate2D,
        Nk: Double
    ) -> CovarianceMatrix {

        var sumSqLat = 0.0
        var sumSqLon = 0.0
        var sumLatLon = 0.0

        for (i, log) in logs.enumerated() {
            guard let lat = log.appLat, let lon = log.appLon else { continue }

            let dLat = lat - mean.latitude
            let dLon = lon - mean.longitude
            let r = responsibilities[i]

            sumSqLat += r * dLat * dLat
            sumSqLon += r * dLon * dLon
            sumLatLon += r * dLat * dLon
        }

        return CovarianceMatrix(
            σ_lat: sumSqLat / Nk,
            σ_lon: sumSqLon / Nk,
            σ_lat_lon: sumLatLon / Nk
        )
    }

    private func calculateLogLikelihood(
        logs: [CheckinLog],
        components: [GaussianComponent]
    ) -> Double {

        var logLikelihood = 0.0

        for checkin in logs {
            guard let lat = checkin.appLat, let lon = checkin.appLon else { continue }
            let point = CLLocationCoordinate2D(latitude: lat, longitude: lon)

            var prob = 0.0
            for component in components {
                prob += gaussianProbability(
                    point: point,
                    mean: component.mean,
                    covariance: component.covariance
                ) * component.weight
            }

            if prob > 0 {
                logLikelihood += log(prob)
            }
        }

        return logLikelihood
    }

    // MARK: - Bayesian Gate Assignment

    /// Calculate probability that a scan belongs to each gate
    func calculateGateProbabilities(
        scan: CheckinLog,
        gates: [Gate],
        gmmComponents: [GaussianComponent]
    ) -> [String: Double] {

        guard let scanLat = scan.appLat, let scanLon = scan.appLon else {
            return [:]
        }

        let scanPoint = CLLocationCoordinate2D(latitude: scanLat, longitude: scanLon)
        var probabilities: [String: Double] = [:]

        for (i, gate) in gates.enumerated() {
            guard i < gmmComponents.count else { continue }

            let component = gmmComponents[i]

            let prob = gaussianProbability(
                point: scanPoint,
                mean: component.mean,
                covariance: component.covariance
            ) * component.weight

            probabilities[gate.id] = prob
        }

        // Normalize to sum to 1.0
        let total = probabilities.values.reduce(0, +)
        if total > 0 {
            for key in probabilities.keys {
                probabilities[key] = probabilities[key]! / total
            }
        }

        return probabilities
    }
}
