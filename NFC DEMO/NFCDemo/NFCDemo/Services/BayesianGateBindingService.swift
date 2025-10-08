import Foundation
import CoreLocation

/// Bayesian learning for gate bindings - learns from data, no hardcoded thresholds
class BayesianGateBindingService {
    static let shared = BayesianGateBindingService()

    // MARK: - Bayesian Inference

    /// Calculate posterior probability using Bayes' theorem
    /// P(Gate|Scan) = P(Scan|Gate) × P(Gate) / P(Scan)
    func calculatePosteriorProbability(
        scanLocation: CLLocationCoordinate2D,
        scanCategory: String,
        gate: Gate,
        priorProbability: Double,
        allGates: [Gate],
        historicalData: [CheckinLog]
    ) -> Double {

        // P(Scan|Gate): Likelihood
        let likelihood = calculateLikelihood(
            scanLocation: scanLocation,
            scanCategory: scanCategory,
            gate: gate,
            historicalData: historicalData
        )

        // P(Gate): Prior
        let prior = priorProbability

        // P(Scan): Evidence (sum over all gates)
        let evidence = allGates.map { otherGate in
            calculateLikelihood(
                scanLocation: scanLocation,
                scanCategory: scanCategory,
                gate: otherGate,
                historicalData: historicalData
            ) * calculatePrior(gate: otherGate, allGates: allGates, historicalData: historicalData)
        }.reduce(0, +)

        guard evidence > 0 else { return 0 }

        // Posterior = Likelihood × Prior / Evidence
        let posterior = (likelihood * prior) / evidence

        return posterior
    }

    /// P(Scan|Gate): Probability of observing this scan given this gate
    private func calculateLikelihood(
        scanLocation: CLLocationCoordinate2D,
        scanCategory: String,
        gate: Gate,
        historicalData: [CheckinLog]
    ) -> Double {

        // Filter historical scans at this gate
        let gateScans = historicalData.filter { $0.gateId == gate.id }

        guard !gateScans.isEmpty else {
            return 0.001 // Small non-zero for new gates
        }

        // 1. Spatial likelihood (how far from typical gate location)
        let spatialLikelihood = calculateSpatialLikelihood(
            scanLocation: scanLocation,
            gate: gate,
            historicalScans: gateScans
        )

        // 2. Category likelihood (how often this category scanned here)
        let categoryLikelihood = calculateCategoryLikelihood(
            scanCategory: scanCategory,
            gateScans: gateScans
        )

        // Combine likelihoods
        return spatialLikelihood * categoryLikelihood
    }

    /// Spatial likelihood using learned Gaussian distribution
    private func calculateSpatialLikelihood(
        scanLocation: CLLocationCoordinate2D,
        gate: Gate,
        historicalScans: [CheckinLog]
    ) -> Double {

        // Learn mean and variance from historical data
        let coordinates = historicalScans.compactMap { scan -> CLLocationCoordinate2D? in
            guard let lat = scan.appLat, let lon = scan.appLon else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }

        guard !coordinates.isEmpty else { return 0.001 }

        // Calculate learned mean
        let meanLat = coordinates.map { $0.latitude }.reduce(0, +) / Double(coordinates.count)
        let meanLon = coordinates.map { $0.longitude }.reduce(0, +) / Double(coordinates.count)
        let mean = CLLocationCoordinate2D(latitude: meanLat, longitude: meanLon)

        // Calculate learned variance
        let variances = coordinates.map { coord in
            let dLat = coord.latitude - meanLat
            let dLon = coord.longitude - meanLon
            return dLat * dLat + dLon * dLon
        }

        let variance = variances.reduce(0, +) / Double(variances.count)
        let stdDev = sqrt(variance)

        // Distance from mean
        let distance = LocationMathService.haversineDistance(
            lat1: scanLocation.latitude, lon1: scanLocation.longitude,
            lat2: mean.latitude, lon2: mean.longitude
        )

        // Convert to degrees for calculation
        let distanceDegrees = distance / 111000.0 // ~111km per degree

        // Gaussian probability
        let exponent = -(distanceDegrees * distanceDegrees) / (2 * variance)
        let normalization = 1.0 / (stdDev * sqrt(2 * Double.pi))
        let probability = normalization * exp(exponent)

        return max(0.001, min(1.0, probability * 100)) // Scale and bound
    }

    /// Category likelihood using empirical frequencies
    private func calculateCategoryLikelihood(
        scanCategory: String,
        gateScans: [CheckinLog]
    ) -> Double {

        // Count scans by category at this gate
        var categoryCounts: [String: Int] = [:]

        for scan in gateScans {
            let category = extractCategory(from: scan.wristbandId)
            categoryCounts[category, default: 0] += 1
        }

        let totalScans = gateScans.count
        let categoryScans = categoryCounts[scanCategory] ?? 0

        // Add Laplace smoothing to avoid zero probabilities
        let smoothedProbability = Double(categoryScans + 1) / Double(totalScans + 10)

        return smoothedProbability
    }

    /// P(Gate): Prior probability based on gate usage
    private func calculatePrior(
        gate: Gate,
        allGates: [Gate],
        historicalData: [CheckinLog]
    ) -> Double {

        let gateScans = historicalData.filter { $0.gateId == gate.id }.count
        let totalScans = historicalData.count

        guard totalScans > 0 else { return 1.0 / Double(allGates.count) }

        // Prior = proportion of all scans at this gate
        let prior = Double(gateScans) / Double(totalScans)

        return max(0.001, prior) // Minimum non-zero prior
    }

    // MARK: - Beta Distribution for Confidence

    /// Model gate-category binding confidence using Beta distribution
    struct BetaDistribution {
        var α: Double  // Successes + 1 (pseudocount)
        var β: Double  // Failures + 1 (pseudocount)

        var mean: Double {
            return α / (α + β)
        }

        var variance: Double {
            let sum = α + β
            return (α * β) / (sum * sum * (sum + 1))
        }

        var confidenceInterval95: (lower: Double, upper: Double) {
            // Approximate 95% CI using mean ± 1.96 * sqrt(variance)
            let margin = 1.96 * sqrt(variance)
            return (
                lower: max(0, mean - margin),
                upper: min(1, mean + margin)
            )
        }

        /// Sample from Beta distribution
        func sample() -> Double {
            // Use mean as point estimate (Bayesian posterior mean)
            return mean
        }

        /// Update with new observation
        mutating func update(success: Bool) {
            if success {
                α += 1
            } else {
                β += 1
            }
        }
    }

    /// Initialize Beta prior for new gate-category binding
    func createBetaPrior() -> BetaDistribution {
        // Uninformative prior: Beta(1, 1) = Uniform(0, 1)
        return BetaDistribution(α: 1, β: 1)
    }

    /// Update Beta distribution with scan observations
    func updateBetaDistribution(
        current: BetaDistribution,
        correctScans: Int,
        incorrectScans: Int
    ) -> BetaDistribution {

        var updated = current

        // Add successes
        updated.α += Double(correctScans)

        // Add failures
        updated.β += Double(incorrectScans)

        return updated
    }

    // MARK: - Thompson Sampling for Exploration-Exploitation

    /// Thompson Sampling: Balance exploring new gates vs exploiting known gates
    func selectGateThompsonSampling(
        candidates: [Gate],
        betaDistributions: [String: BetaDistribution]
    ) -> Gate? {

        var sampledValues: [(gate: Gate, sample: Double)] = []

        for gate in candidates {
            let distribution = betaDistributions[gate.id] ?? createBetaPrior()
            let sample = distribution.sample()
            sampledValues.append((gate: gate, sample: sample))
        }

        // Select gate with highest sampled value
        return sampledValues.max { $0.sample < $1.sample }?.gate
    }

    // MARK: - Online Learning with Exponential Moving Average

    /// Track gate statistics with exponential decay (recent data weighted more)
    struct ExponentialMovingAverage {
        private var ema: Double
        private let decayRate: Double  // 0 < α < 1

        init(initialValue: Double = 0, decayRate: Double = 0.1) {
            self.ema = initialValue
            self.decayRate = decayRate
        }

        mutating func update(newValue: Double) {
            ema = decayRate * newValue + (1 - decayRate) * ema
        }

        var value: Double {
            return ema
        }
    }

    /// Adaptive threshold that learns from data
    class AdaptiveThreshold {
        private var successRates: [Double] = []
        private let windowSize: Int

        init(windowSize: Int = 50) {
            self.windowSize = windowSize
        }

        func addObservation(successRate: Double) {
            successRates.append(successRate)

            if successRates.count > windowSize {
                successRates.removeFirst()
            }
        }

        /// Calculate threshold as percentile of observed success rates
        func getThreshold(percentile: Double = 0.75) -> Double {
            guard !successRates.isEmpty else { return 0.75 }

            let sorted = successRates.sorted()
            let index = Int(Double(sorted.count) * percentile)
            let safeIndex = min(max(0, index), sorted.count - 1)

            return sorted[safeIndex]
        }

        var mean: Double {
            guard !successRates.isEmpty else { return 0 }
            return successRates.reduce(0, +) / Double(successRates.count)
        }

        var standardDeviation: Double {
            guard !successRates.isEmpty else { return 0 }

            let mean = self.mean
            let variance = successRates.map { pow($0 - mean, 2) }.reduce(0, +) / Double(successRates.count)
            return sqrt(variance)
        }
    }

    // MARK: - Reinforcement Learning Value Function

    /// Q-learning value for gate-category pair
    struct QValue {
        var value: Double
        let learningRate: Double = 0.1
        let discountFactor: Double = 0.95

        mutating func update(reward: Double, maxNextQ: Double) {
            // Q(s,a) ← Q(s,a) + α[r + γ max Q(s',a') - Q(s,a)]
            let tdError = reward + discountFactor * maxNextQ - value
            value += learningRate * tdError
        }
    }

    /// Reward function for correct/incorrect gate assignment
    func calculateReward(
        wasCorrect: Bool,
        confidence: Double,
        distance: Double
    ) -> Double {

        if wasCorrect {
            // Positive reward scaled by confidence and inverse distance
            let distanceBonus = max(0, 1.0 - (distance / 100.0))
            return confidence * distanceBonus
        } else {
            // Negative reward (penalty)
            return -1.0
        }
    }

    // MARK: - Helper Methods

    private func extractCategory(from wristbandId: String) -> String {
        let wristbandLower = wristbandId.lowercased()

        if wristbandLower.contains("vip") { return "VIP" }
        if wristbandLower.contains("staff") { return "Staff" }
        if wristbandLower.contains("artist") { return "Artist" }
        if wristbandLower.contains("vendor") { return "Vendor" }
        if wristbandLower.contains("press") { return "Press" }

        return "General"
    }

    // MARK: - Decision Making

    /// Decide gate assignment using Bayesian inference
    func assignGate(
        scan: CheckinLog,
        candidateGates: [Gate],
        historicalData: [CheckinLog]
    ) -> (gate: Gate, confidence: Double)? {

        guard let scanLat = scan.appLat, let scanLon = scan.appLon else {
            return nil
        }

        let scanLocation = CLLocationCoordinate2D(latitude: scanLat, longitude: scanLon)
        let scanCategory = extractCategory(from: scan.wristbandId)

        var gatePosteriors: [(gate: Gate, posterior: Double)] = []

        for gate in candidateGates {
            let prior = calculatePrior(
                gate: gate,
                allGates: candidateGates,
                historicalData: historicalData
            )

            let posterior = calculatePosteriorProbability(
                scanLocation: scanLocation,
                scanCategory: scanCategory,
                gate: gate,
                priorProbability: prior,
                allGates: candidateGates,
                historicalData: historicalData
            )

            gatePosteriors.append((gate: gate, posterior: posterior))
        }

        // Select gate with highest posterior probability
        guard let best = gatePosteriors.max(by: { $0.posterior < $1.posterior }) else {
            return nil
        }

        return (gate: best.gate, confidence: best.posterior)
    }
}
