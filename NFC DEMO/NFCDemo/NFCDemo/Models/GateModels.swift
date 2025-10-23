import Foundation
import CoreLocation

// MARK: - Gate Binding System Models

struct Gate: Codable, Identifiable {
    let id: String
    let eventId: String
    let name: String
    let latitude: Double?
    let longitude: Double?
    let status: GateStatus
    let healthScore: Int?
    let locationDescription: String?
    let seriesId: String?
    let createdAt: Date
    let updatedAt: Date?

    // For deduplication - stores IDs of merged gates
    var mergedGateIds: [String] = []

    enum GateStatus: String, Codable {
        case learning = "learning"
        case active = "active"
        case optimizing = "optimizing"
        case maintenance = "maintenance"
        case paused = "paused"

        var displayName: String {
            switch self {
            case .learning: return "Learning"
            case .active: return "Active"
            case .optimizing: return "Optimizing"
            case .maintenance: return "Maintenance"
            case .paused: return "Paused"
            }
        }

        var color: String {
            switch self {
            case .learning: return "#F59E0B" // Orange
            case .active: return "#10B981" // Green
            case .optimizing: return "#3B82F6" // Blue
            case .maintenance: return "#EF4444" // Red
            case .paused: return "#6B7280" // Gray
            }
        }
    }

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

    // Initialize with all required fields
    init(id: String, eventId: String, name: String, latitude: Double?, longitude: Double?,
         status: GateStatus = .learning, healthScore: Int? = nil, locationDescription: String? = nil,
         seriesId: String? = nil, createdAt: Date = Date(), updatedAt: Date? = nil,
         mergedGateIds: [String] = []) {
        self.id = id
        self.eventId = eventId
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.status = status
        self.healthScore = healthScore
        self.locationDescription = locationDescription
        self.seriesId = seriesId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.mergedGateIds = mergedGateIds.isEmpty ? [id] : mergedGateIds
    }

    enum CodingKeys: String, CodingKey {
        case id
        case eventId = "event_id"
        case name
        case latitude
        case longitude
        case status
        case healthScore = "health_score"
        case locationDescription = "location_description"
        case seriesId = "series_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
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

// MARK: - Autonomous Gate Model

struct AutonomousGate: Codable, Identifiable {
    let gateId: String
    let autonomousStatus: String
    let confidenceScore: Double?
    let decisionsCount: Int?
    let correctDecisions: Int?
    let incorrectDecisions: Int?
    let accuracyRate: Double?
    let lastLearningUpdate: Date?
    let createdAt: Date
    let updatedAt: Date?

    var id: String { gateId }

    enum CodingKeys: String, CodingKey {
        case gateId = "gate_id"
        case autonomousStatus = "autonomous_status"
        case confidenceScore = "confidence_score"
        case decisionsCount = "decisions_count"
        case correctDecisions = "correct_decisions"
        case incorrectDecisions = "incorrect_decisions"
        case accuracyRate = "accuracy_rate"
        case lastLearningUpdate = "last_learning_update"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Gate with Complete Metrics (From v_gates_complete View)

struct GateWithMetrics: Codable, Identifiable {
    let gateId: String
    let eventId: String
    let eventName: String
    let gateName: String
    let gateStatus: String

    // Location
    let latitude: Double?
    let longitude: Double?
    let derivationMethod: String
    let discoveryConfidence: Double
    let healthScore: Double
    let spatialVariance: Double

    // Autonomous enforcement status
    let enforcementStatus: String?
    let enforcementConfidence: Double?
    let learningSamples: Int?
    let enforcementDecisions: Int?
    let lastLearningAt: Date?

    // Category bindings (JSONB from SQL)
    let categoryBindings: [String: CategoryBinding]?

    // Performance metrics
    let totalScans: Int
    let successfulScans: Int
    let failedScans: Int
    let categoryBreakdown: [String: Int]?
    let lastScanAt: Date?

    // Overall status
    let overallStatus: String
    let systemInfo: SystemInfo
    let discoveryMetadata: DiscoveryMetadata?
    let createdAt: Date
    let updatedAt: Date?

    var id: String { gateId }

    enum CodingKeys: String, CodingKey {
        case gateId = "gate_id"
        case eventId = "event_id"
        case eventName = "event_name"
        case gateName = "gate_name"
        case gateStatus = "gate_status"
        case latitude, longitude
        case derivationMethod = "derivation_method"
        case discoveryConfidence = "discovery_confidence"
        case healthScore = "health_score"
        case spatialVariance = "spatial_variance"
        case enforcementStatus = "enforcement_status"
        case enforcementConfidence = "enforcement_confidence"
        case learningSamples = "learning_samples"
        case enforcementDecisions = "enforcement_decisions"
        case lastLearningAt = "last_learning_at"
        case categoryBindings = "category_bindings"
        case totalScans = "total_scans"
        case successfulScans = "successful_scans"
        case failedScans = "failed_scans"
        case categoryBreakdown = "category_breakdown"
        case lastScanAt = "last_scan_at"
        case overallStatus = "overall_status"
        case systemInfo = "system_info"
        case discoveryMetadata = "discovery_metadata"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    // Convert to Gate for compatibility
    func toGate() -> Gate {
        // Parse gate status
        let status: Gate.GateStatus
        switch gateStatus.lowercased() {
        case "learning": status = .learning
        case "active": status = .active
        case "optimizing": status = .optimizing
        case "maintenance": status = .maintenance
        case "paused": status = .paused
        default: status = .learning
        }

        return Gate(
            id: gateId,
            eventId: eventId,
            name: gateName,
            latitude: latitude,
            longitude: longitude,
            status: status,
            healthScore: Int(healthScore),
            locationDescription: derivationMethod,
            seriesId: nil,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    var categoryNames: [String] {
        categoryBindings?.keys.sorted() ?? []
    }

    var displayStatus: String {
        enforcementStatus?.capitalized ?? overallStatus.replacingOccurrences(of: "_", with: " ").capitalized
    }

    var confidence: Double {
        enforcementConfidence ?? discoveryConfidence
    }

    var successRate: Double {
        guard totalScans > 0 else { return 0 }
        return Double(successfulScans) / Double(totalScans) * 100
    }

    var isEnforcing: Bool {
        overallStatus == "enforcing" || overallStatus == "soft_enforcing"
    }

    var needsAttention: Bool {
        overallStatus == "critical" || overallStatus == "low_confidence" || overallStatus == "needs_attention"
    }
}

struct SystemInfo: Codable {
    let discoveryMethod: String
    let hasEnforcement: Bool
    let hasBindings: Bool
    let hasActivity: Bool
    let usingCache: Bool

    enum CodingKeys: String, CodingKey {
        case discoveryMethod = "discovery_method"
        case hasEnforcement = "has_enforcement"
        case hasBindings = "has_bindings"
        case hasActivity = "has_activity"
        case usingCache = "using_cache"
    }
}

struct DiscoveryMetadata: Codable {
    // Flexible metadata - can be extended
    let custom: [String: String]?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let dict = try? container.decode([String: String].self)
        custom = dict
    }
}

struct CategoryBinding: Codable {
    let status: String
    let confidence: Double
    let sampleCount: Int
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case status, confidence
        case sampleCount = "sample_count"
        case updatedAt = "updated_at"
    }
}
