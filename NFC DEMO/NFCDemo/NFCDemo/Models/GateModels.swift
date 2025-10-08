import Foundation
import CoreLocation

// MARK: - Gate Binding System Models

struct Gate: Codable, Identifiable {
    let id: String
    let eventId: String
    let name: String
    let latitude: Double?
    let longitude: Double?
    
    // For deduplication - stores IDs of merged gates
    var mergedGateIds: [String] = []
    
    // Computed property for location
    var location: GateLocation? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return GateLocation(
            latitude: lat,
            longitude: lon,
            radius: 50.0, // Default radius
            beaconIds: nil,
            wifiSSIDs: nil
        )
    }
    
    // Initialize with merged gate IDs
    init(id: String, eventId: String, name: String, latitude: Double?, longitude: Double?, mergedGateIds: [String] = []) {
        self.id = id
        self.eventId = eventId
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.mergedGateIds = mergedGateIds.isEmpty ? [id] : mergedGateIds
    }
    
    enum CodingKeys: String, CodingKey {
        case id, eventId = "event_id", name, latitude, longitude
    }
}

struct GateLocation: Codable {
    let latitude: Double
    let longitude: Double
    let radius: Double
    let beaconIds: [String]?
    let wifiSSIDs: [String]?
    
    enum CodingKeys: String, CodingKey {
        case latitude, longitude, radius
        case beaconIds = "beacon_ids", wifiSSIDs = "wifi_ssids"
    }
}

enum GateBindingStatus: String, Codable {
    case unbound = "unbound"
    case probation = "probation"
    case enforced = "enforced"
    
    var displayName: String {
        switch self {
        case .unbound: return "Unbound"
        case .probation: return "Learning"
        case .enforced: return "Enforced"
        }
    }
}

struct GateBinding: Codable, Identifiable {
    let gateId: String
    let categoryName: String
    let status: GateBindingStatus
    let confidence: Double
    let sampleCount: Int
    let eventId: String?
    
    // Computed property for Identifiable conformance
    var id: String {
        return "\(gateId)_\(categoryName)"
    }
    
    enum CodingKeys: String, CodingKey {
        case gateId = "gate_id", categoryName = "category"
        case status, confidence, sampleCount = "sample_count", eventId = "event_id"
    }
}

struct CheckinPolicyResult: Codable {
    let allowed: Bool
    let reason: CheckinReason
    let locationConfidence: Double
    let warnings: [String]
    
    enum CodingKeys: String, CodingKey {
        case allowed, reason, locationConfidence = "location_confidence", warnings
    }
}

enum CheckinReason: String, Codable {
    case okEnforced = "OK_ENFORCED"
    case okProbation = "OK_PROBATION"
    case okUnbound = "OK_UNBOUND"
    case categoryMismatchEnforced = "CATEGORY_MISMATCH_ENFORCED"
    case outOfRange = "OUT_OF_RANGE"
    case lowLocationConfidence = "LOW_LOCATION_CONFIDENCE"
    
    var displayMessage: String {
        switch self {
        case .okEnforced: return "✅ Access granted - Category verified"
        case .okProbation: return "⚠️ Access granted - Learning mode"
        case .okUnbound: return "✅ Access granted - Gate not configured"
        case .categoryMismatchEnforced: return "❌ Wrong category for this gate"
        case .outOfRange: return "❌ Too far from gate location"
        case .lowLocationConfidence: return "❌ Location verification failed"
        }
    }
}

struct LocationContext: Codable {
    let latitude: Double
    let longitude: Double
    let accuracy: Double
    let timestamp: Date
    let nearbyBeacons: [String]
    let nearbyWiFi: [String]
}
