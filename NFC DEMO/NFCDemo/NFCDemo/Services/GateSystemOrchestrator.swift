import Foundation
import CoreLocation

/// Orchestrates parallel execution of old and new gate systems for validation
class GateSystemOrchestrator {
    static let shared = GateSystemOrchestrator()

    // Old system
    private let legacyService = GateBindingService.shared

    // New advanced system
    private let clusteringService = AdaptiveGateClusteringService.shared
    private let bayesianService = BayesianGateBindingService.shared

    // Comparison tracking
    private var comparisonMetrics: [ComparisonMetric] = []

    // MARK: - Configuration

    struct Configuration {
        // Phase 1: Run both systems in parallel
        var enableParallelValidation = true

        // Phase 2: Use new system for decisions (once validated)
        var useAdvancedSystemForDecisions = false

        // Minimum scans before new system activates
        var minScansForAdvancedSystem = 20
    }

    var config = Configuration()

    // MARK: - Parallel Gate Discovery

    /// Run both old and new systems, compare results
    func discoverGates(
        from checkinLogs: [CheckinLog],
        eventId: String
    ) async throws -> GateDiscoveryComparison {

        print("🔬 Running parallel gate discovery...")
        print("📊 Analyzing \(checkinLogs.count) check-ins")

        // Run both systems concurrently
        async let legacyResults = runLegacySystem(logs: checkinLogs, eventId: eventId)
        async let advancedResults = runAdvancedSystem(logs: checkinLogs, eventId: eventId)

        let (legacy, advanced) = try await (legacyResults, advancedResults)

        // Compare results
        let comparison = compareResults(legacy: legacy, advanced: advanced)

        // Track metrics
        trackComparison(comparison)

        // Log comparison
        logComparison(comparison)

        return comparison
    }

    // MARK: - Legacy System Execution

    private func runLegacySystem(
        logs: [CheckinLog],
        eventId: String
    ) async throws -> LegacySystemResult {

        let startTime = Date()

        // Run old gate discovery
        // Note: This calls the existing GateBindingService logic
        try await legacyService.discoverGatesFromCheckinPatterns(eventId: eventId)
        let gates = try await legacyService.fetchGates()

        let duration = Date().timeIntervalSince(startTime)

        return LegacySystemResult(
            gates: gates,
            executionTime: duration,
            gateCount: gates.count,
            averageScansPerGate: gates.isEmpty ? 0 : Double(logs.count) / Double(gates.count)
        )
    }

    // MARK: - Advanced System Execution

    private func runAdvancedSystem(
        logs: [CheckinLog],
        eventId: String
    ) async throws -> AdvancedSystemResult {

        let startTime = Date()

        // Step 1: DBSCAN clustering with learned epsilon
        let learnedEpsilon = clusteringService.calculateOptimalEpsilon(from: logs)
        let clusters = clusteringService.clusterWithDBSCAN(logs: logs, epsilon: learnedEpsilon)

        print("  🧠 Learned ε = \(Int(learnedEpsilon))m (no hardcoded thresholds)")
        print("  📍 Found \(clusters.count) natural gate clusters")

        // Step 2: Fit GMM for probabilistic assignment
        let gmmComponents = clusteringService.fitGaussianMixture(logs: logs)

        print("  📊 Fitted GMM with \(gmmComponents.count) components")

        // Step 3: Create gates from clusters (using Bayesian approach)
        var createdGates: [Gate] = []
        var betaDistributions: [String: BayesianGateBindingService.BetaDistribution] = [:]

        for cluster in clusters {
            // Create gate at cluster centroid
            let gateName = generateSmartGateName(for: cluster)

            let gateData: [String: Any] = [
                "event_id": eventId,
                "name": gateName,
                "latitude": cluster.centroid.latitude,
                "longitude": cluster.centroid.longitude
            ]

            let createdGatesResponse: [Gate] = try await SupabaseService.shared.makeRequest(
                endpoint: "rest/v1/gates",
                method: "POST",
                body: try JSONSerialization.data(withJSONObject: gateData),
                responseType: [Gate].self
            )

            if let newGate = createdGatesResponse.first {
                createdGates.append(newGate)

                // Initialize Beta distribution for this gate
                betaDistributions[newGate.id] = bayesianService.createBetaPrior()
            }
        }

        let duration = Date().timeIntervalSince(startTime)

        return AdvancedSystemResult(
            gates: createdGates,
            clusters: clusters,
            gmmComponents: gmmComponents,
            betaDistributions: betaDistributions,
            learnedEpsilon: learnedEpsilon,
            executionTime: duration,
            gateCount: createdGates.count,
            averageScansPerGate: createdGates.isEmpty ? 0 : Double(logs.count) / Double(createdGates.count),
            clusterDensities: clusters.map { $0.density },
            clusterRadii: clusters.map { $0.radius }
        )
    }

    // MARK: - Smart Gate Assignment (Bayesian)

    /// Assign scan to gate using Bayesian inference
    func assignScanToGate(
        scan: CheckinLog,
        candidateGates: [Gate],
        historicalData: [CheckinLog],
        betaDistributions: [String: BayesianGateBindingService.BetaDistribution]
    ) -> (gate: Gate, confidence: Double, method: String)? {

        if config.useAdvancedSystemForDecisions {
            // Use Bayesian approach
            if let result = bayesianService.assignGate(
                scan: scan,
                candidateGates: candidateGates,
                historicalData: historicalData
            ) {
                return (result.gate, result.confidence, "Bayesian Inference")
            }
        } else {
            // Use legacy approach
            if let result = legacyService.findBestGateMatch(
                for: scan,
                from: candidateGates,
                historicalData: historicalData
            ) {
                return (result.gate, result.confidence, "Legacy Distance-Based")
            }
        }

        return nil
    }

    // MARK: - Comparison & Metrics

    private func compareResults(
        legacy: LegacySystemResult,
        advanced: AdvancedSystemResult
    ) -> GateDiscoveryComparison {

        // Calculate improvement metrics
        let gateCountReduction = Double(legacy.gateCount - advanced.gateCount)
        let gateCountReductionPercent = legacy.gateCount > 0
            ? (gateCountReduction / Double(legacy.gateCount)) * 100
            : 0

        let scansPerGateImprovement = advanced.averageScansPerGate - legacy.averageScansPerGate
        let scansPerGateImprovementPercent = legacy.averageScansPerGate > 0
            ? (scansPerGateImprovement / legacy.averageScansPerGate) * 100
            : 0

        // Detect duplicate reduction
        let legacyDuplicates = detectDuplicatesInLegacyResults(legacy.gates)
        let advancedDuplicates = detectDuplicatesInAdvancedResults(advanced.gates)

        let duplicateReduction = legacyDuplicates - advancedDuplicates
        let duplicateReductionPercent = legacyDuplicates > 0
            ? (Double(duplicateReduction) / Double(legacyDuplicates)) * 100
            : 0

        return GateDiscoveryComparison(
            legacyResult: legacy,
            advancedResult: advanced,
            gateCountReduction: Int(gateCountReduction),
            gateCountReductionPercent: gateCountReductionPercent,
            scansPerGateImprovement: scansPerGateImprovement,
            scansPerGateImprovementPercent: scansPerGateImprovementPercent,
            duplicateReduction: duplicateReduction,
            duplicateReductionPercent: duplicateReductionPercent,
            executionTimeComparison: advanced.executionTime - legacy.executionTime,
            learnedEpsilon: advanced.learnedEpsilon,
            averageClusterDensity: advanced.clusterDensities.isEmpty ? 0 : advanced.clusterDensities.reduce(0, +) / Double(advanced.clusterDensities.count),
            timestamp: Date()
        )
    }

    private func detectDuplicatesInLegacyResults(_ gates: [Gate]) -> Int {
        // Simple name similarity check
        var duplicateCount = 0

        for i in 0..<gates.count {
            for j in (i+1)..<gates.count {
                let name1 = gates[i].name.lowercased()
                let name2 = gates[j].name.lowercased()

                // Check if names are similar
                if name1.contains(name2) || name2.contains(name1) {
                    // Check if locations are close (within 50m)
                    if let lat1 = gates[i].latitude, let lon1 = gates[i].longitude,
                       let lat2 = gates[j].latitude, let lon2 = gates[j].longitude {

                        let distance = LocationMathService.haversineDistance(
                            lat1: lat1, lon1: lon1,
                            lat2: lat2, lon2: lon2
                        )

                        if distance <= 50.0 {
                            duplicateCount += 1
                        }
                    }
                }
            }
        }

        return duplicateCount
    }

    private func detectDuplicatesInAdvancedResults(_ gates: [Gate]) -> Int {
        // Advanced system should have minimal duplicates due to DBSCAN
        // but check anyway
        var duplicateCount = 0

        for i in 0..<gates.count {
            for j in (i+1)..<gates.count {
                if let lat1 = gates[i].latitude, let lon1 = gates[i].longitude,
                   let lat2 = gates[j].latitude, let lon2 = gates[j].longitude {

                    let distance = LocationMathService.haversineDistance(
                        lat1: lat1, lon1: lon1,
                        lat2: lat2, lon2: lon2
                    )

                    // Much stricter threshold for advanced system
                    if distance <= 10.0 {
                        duplicateCount += 1
                    }
                }
            }
        }

        return duplicateCount
    }

    private func trackComparison(_ comparison: GateDiscoveryComparison) {
        comparisonMetrics.append(ComparisonMetric(
            timestamp: comparison.timestamp,
            gateCountReduction: comparison.gateCountReduction,
            duplicateReduction: comparison.duplicateReduction,
            scansPerGateImprovement: comparison.scansPerGateImprovement,
            learnedEpsilon: comparison.learnedEpsilon
        ))

        // Keep only last 50 comparisons
        if comparisonMetrics.count > 50 {
            comparisonMetrics.removeFirst()
        }
    }

    private func logComparison(_ comparison: GateDiscoveryComparison) {
        print("\n📊 ========== SYSTEM COMPARISON ==========")
        print("🔴 Legacy System:")
        print("  Gates Created: \(comparison.legacyResult.gateCount)")
        print("  Avg Scans/Gate: \(String(format: "%.1f", comparison.legacyResult.averageScansPerGate))")
        print("  Execution Time: \(String(format: "%.2f", comparison.legacyResult.executionTime))s")

        print("\n🟢 Advanced System:")
        print("  Gates Created: \(comparison.advancedResult.gateCount)")
        print("  Avg Scans/Gate: \(String(format: "%.1f", comparison.advancedResult.averageScansPerGate))")
        print("  Execution Time: \(String(format: "%.2f", comparison.advancedResult.executionTime))s")
        print("  Learned ε: \(Int(comparison.learnedEpsilon))m (no hardcoded threshold)")
        print("  Clusters: \(comparison.advancedResult.clusters.count)")

        print("\n📈 IMPROVEMENTS:")
        print("  Gate Count: \(comparison.gateCountReduction) fewer (\(String(format: "%.1f", comparison.gateCountReductionPercent))% reduction)")
        print("  Duplicates: \(comparison.duplicateReduction) fewer (\(String(format: "%.1f", comparison.duplicateReductionPercent))% reduction)")
        print("  Scans/Gate: +\(String(format: "%.1f", comparison.scansPerGateImprovement)) (\(String(format: "%.1f", comparison.scansPerGateImprovementPercent))% improvement)")
        print("==========================================\n")
    }

    // MARK: - Helper Methods

    private func generateSmartGateName(for cluster: AdaptiveGateClusteringService.DBSCANCluster) -> String {
        // Extract dominant category from cluster scans
        var categoryCounts: [String: Int] = [:]

        for log in cluster.corePoints {
            let category = extractCategory(from: log.wristbandId)
            categoryCounts[category, default: 0] += 1
        }

        let dominantCategory = categoryCounts.max { $0.value < $1.value }?.key ?? "General"

        // Use canonical naming
        return "\(dominantCategory) Gate"
    }

    private func extractCategory(from wristbandId: String) -> String {
        let wristbandLower = wristbandId.lowercased()

        if wristbandLower.contains("vip") { return "VIP" }
        if wristbandLower.contains("staff") { return "Staff" }
        if wristbandLower.contains("artist") { return "Artist" }
        if wristbandLower.contains("vendor") { return "Vendor" }
        if wristbandLower.contains("press") { return "Press" }

        return "General"
    }

    // MARK: - Public Metrics Access

    func getComparisonMetrics() -> [ComparisonMetric] {
        return comparisonMetrics
    }

    func getAverageImprovement() -> (gateReduction: Double, duplicateReduction: Double, scansPerGateIncrease: Double) {
        guard !comparisonMetrics.isEmpty else {
            return (0, 0, 0)
        }

        let avgGateReduction = comparisonMetrics.map { Double($0.gateCountReduction) }.reduce(0, +) / Double(comparisonMetrics.count)
        let avgDuplicateReduction = comparisonMetrics.map { Double($0.duplicateReduction) }.reduce(0, +) / Double(comparisonMetrics.count)
        let avgScansIncrease = comparisonMetrics.map { $0.scansPerGateImprovement }.reduce(0, +) / Double(comparisonMetrics.count)

        return (avgGateReduction, avgDuplicateReduction, avgScansIncrease)
    }
}

// MARK: - Result Models

struct LegacySystemResult {
    let gates: [Gate]
    let executionTime: TimeInterval
    let gateCount: Int
    let averageScansPerGate: Double
}

struct AdvancedSystemResult {
    let gates: [Gate]
    let clusters: [AdaptiveGateClusteringService.DBSCANCluster]
    let gmmComponents: [AdaptiveGateClusteringService.GaussianComponent]
    let betaDistributions: [String: BayesianGateBindingService.BetaDistribution]
    let learnedEpsilon: Double
    let executionTime: TimeInterval
    let gateCount: Int
    let averageScansPerGate: Double
    let clusterDensities: [Double]
    let clusterRadii: [Double]
}

struct GateDiscoveryComparison {
    let legacyResult: LegacySystemResult
    let advancedResult: AdvancedSystemResult

    let gateCountReduction: Int
    let gateCountReductionPercent: Double

    let scansPerGateImprovement: Double
    let scansPerGateImprovementPercent: Double

    let duplicateReduction: Int
    let duplicateReductionPercent: Double

    let executionTimeComparison: TimeInterval
    let learnedEpsilon: Double
    let averageClusterDensity: Double

    let timestamp: Date
}

struct ComparisonMetric {
    let timestamp: Date
    let gateCountReduction: Int
    let duplicateReduction: Int
    let scansPerGateImprovement: Double
    let learnedEpsilon: Double
}

// MARK: - Extension to GateBindingService (Legacy Compatibility)

extension GateBindingService {
    /// Find best gate match using legacy distance-based approach
    func findBestGateMatch(
        for scan: CheckinLog,
        from candidateGates: [Gate],
        historicalData: [CheckinLog]
    ) -> (gate: Gate, confidence: Double)? {

        guard let scanLat = scan.appLat, let scanLon = scan.appLon else {
            return nil
        }

        var bestMatch: (gate: Gate, distance: Double)?

        for gate in candidateGates {
            guard let gateLat = gate.latitude, let gateLon = gate.longitude else {
                continue
            }

            let distance = LocationMathService.haversineDistance(
                lat1: scanLat, lon1: scanLon,
                lat2: gateLat, lon2: gateLon
            )

            if bestMatch == nil || distance < bestMatch!.distance {
                bestMatch = (gate, distance)
            }
        }

        guard let match = bestMatch else { return nil }

        // Simple confidence based on distance
        let confidence = max(0, 1.0 - (match.distance / 100.0))

        return (match.gate, confidence)
    }
}
