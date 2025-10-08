import Foundation
import CoreLocation

/// Advanced mathematical algorithms for gate binding and location confidence
struct LocationMathService {
    
    // MARK: - 3.1 Haversine Distance Formula
    
    static func haversineDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let earthRadiusM = 6371000.0
        
        let φ1 = lat1 * .pi / 180.0
        let φ2 = lat2 * .pi / 180.0
        let Δφ = (lat2 - lat1) * .pi / 180.0
        let Δλ = (lon2 - lon1) * .pi / 180.0
        
        let a = sin(Δφ / 2) * sin(Δφ / 2) +
                cos(φ1) * cos(φ2) * sin(Δλ / 2) * sin(Δλ / 2)
        
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadiusM * c
    }
    
    // MARK: - 3.2 Wilson Score Interval (Lower Bound)
    
    static func wilsonLowerBound(k: Int, n: Int, z: Double = 2.33) -> Double {
        guard n > 0 else { return 0.0 }
        
        let kDouble = Double(k)
        let nDouble = Double(n)
        let z2 = z * z
        
        let pHat = (kDouble + z2 / 2) / (nDouble + z2)
        let margin = z * sqrt((pHat * (1 - pHat)) / (nDouble + z2))
        let lowerBound = pHat - margin
        
        return max(0.0, min(1.0, lowerBound))
    }
    
    static func shouldCreateBinding(categoryScansAtGate k: Int, totalCategoryScans n: Int, threshold: Double = 0.80) -> Bool {
        return wilsonLowerBound(k: k, n: n) >= threshold
    }
    
    // MARK: - 3.3 Location Confidence Score
    
    struct LocationConfidenceWeights {
        let gps: Double, beacon: Double, wifi: Double
        static let `default` = LocationConfidenceWeights(gps: 0.4, beacon: 0.4, wifi: 0.2)
        static let indoor = LocationConfidenceWeights(gps: 0.2, beacon: 0.5, wifi: 0.3)
        static let outdoor = LocationConfidenceWeights(gps: 0.6, beacon: 0.3, wifi: 0.1)
    }
    
    static func calculateLocationConfidence(
        gpsAccuracyM: Double,
        gpsThresholdM: Double = 20.0,
        matchedBeacons: Int = 0,
        expectedBeacons: Int = 0,
        matchedWiFi: Int = 0,
        expectedWiFi: Int = 0,
        weights: LocationConfidenceWeights = .default
    ) -> Double {
        
        // GPS Trust
        let gpsTrust = gpsAccuracyM > 0 && gpsAccuracyM <= gpsThresholdM ? 
            max(0.0, 1.0 - (gpsAccuracyM / gpsThresholdM)) : 0.0
        
        // Beacon Trust
        let beaconTrust = expectedBeacons > 0 ? 
            min(1.0, Double(matchedBeacons) * 0.3) : 0.5
        
        // WiFi Trust
        let wifiTrust = expectedWiFi > 0 ? 
            min(1.0, Double(matchedWiFi) * 0.4) : 0.3
        
        return max(0.0, min(1.0, weights.gps * gpsTrust + weights.beacon * beaconTrust + weights.wifi * wifiTrust))
    }
    
    enum LocationConfidenceLevel {
        case accept, warning, reject
        
        var description: String {
            switch self {
            case .accept: return "High confidence - Access granted"
            case .warning: return "Medium confidence - Proceed with caution"
            case .reject: return "Low confidence - Access denied"
            }
        }
    }
    
    static func interpretConfidence(_ confidence: Double) -> LocationConfidenceLevel {
        if confidence >= 0.8 { return .accept }
        else if confidence >= 0.6 { return .warning }
        else { return .reject }
    }
    
    // MARK: - 3.4 Sample Validation
    
    static func validateSampleSize(sampleCount: Int, uniqueWristbands: Int, minSamples: Int = 100, minUnique: Int = 50) -> Bool {
        return sampleCount >= minSamples && uniqueWristbands >= minUnique
    }
}
