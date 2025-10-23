import Foundation

// MARK: - Enhanced Fraud Detection Models (Portal Parity)

/// Fraud case management
struct FraudCase: Codable, Identifiable {
    let id: String
    let eventId: String
    let fraudDetectionId: String?
    let caseNumber: String
    let title: String
    let description: String?
    let status: FraudCaseStatus
    let priority: FraudPriority
    let assignedTo: String?
    let assignedAt: Date?
    let resolutionNotes: String?
    let resolvedBy: String?
    let resolvedAt: Date?
    let evidence: [FraudEvidence]?
    let wristbandIds: [String]?
    let userIds: [String]?
    let createdBy: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case eventId = "event_id"
        case fraudDetectionId = "fraud_detection_id"
        case caseNumber = "case_number"
        case title, description, status, priority
        case assignedTo = "assigned_to"
        case assignedAt = "assigned_at"
        case resolutionNotes = "resolution_notes"
        case resolvedBy = "resolved_by"
        case resolvedAt = "resolved_at"
        case evidence
        case wristbandIds = "wristband_ids"
        case userIds = "user_ids"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum FraudCaseStatus: String, Codable, CaseIterable {
    case open = "open"
    case investigating = "investigating"
    case resolved = "resolved"
    case closed = "closed"
    case falsePositive = "false_positive"

    var displayName: String {
        switch self {
        case .open: return "Open"
        case .investigating: return "Investigating"
        case .resolved: return "Resolved"
        case .closed: return "Closed"
        case .falsePositive: return "False Positive"
        }
    }

    var color: String {
        switch self {
        case .open: return "red"
        case .investigating: return "orange"
        case .resolved: return "blue"
        case .closed: return "gray"
        case .falsePositive: return "green"
        }
    }

    var icon: String {
        switch self {
        case .open: return "exclamationmark.shield"
        case .investigating: return "magnifyingglass"
        case .resolved: return "checkmark.shield"
        case .closed: return "lock.shield"
        case .falsePositive: return "xmark.shield"
        }
    }
}

enum FraudPriority: String, Codable, CaseIterable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"

    var displayName: String {
        rawValue.capitalized
    }

    var color: String {
        switch self {
        case .low: return "blue"
        case .medium: return "orange"
        case .high: return "red"
        case .critical: return "purple"
        }
    }
}

struct FraudEvidence: Codable, Identifiable {
    var id: String { UUID().uuidString }
    let type: String
    let description: String
    let dataUrl: String?
    let metadata: [String: String]?
    let recordedAt: Date
    let recordedBy: String?
}

/// Fraud rules configuration
struct FraudRule: Codable, Identifiable {
    let id: String
    let organizationId: String?
    let eventId: String?
    let name: String
    let description: String?
    let ruleType: FraudRuleType
    let config: FraudRuleConfig
    let riskScore: Int
    let autoBlock: Bool
    let autoAlert: Bool
    let alertSeverity: AlertSeverity
    let isActive: Bool
    let createdBy: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case organizationId = "organization_id"
        case eventId = "event_id"
        case name, description
        case ruleType = "rule_type"
        case config
        case riskScore = "risk_score"
        case autoBlock = "auto_block"
        case autoAlert = "auto_alert"
        case alertSeverity = "alert_severity"
        case isActive = "is_active"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum FraudRuleType: String, Codable {
    case multipleCheckins = "multiple_checkins"
    case velocityCheck = "velocity_check"
    case impossibleLocation = "impossible_location"
    case timePattern = "time_pattern"
    case categoryMismatch = "category_mismatch"
    case blacklistCheck = "blacklist_check"
    case custom = "custom"

    var displayName: String {
        switch self {
        case .multipleCheckins: return "Multiple Check-ins"
        case .velocityCheck: return "Velocity Check"
        case .impossibleLocation: return "Impossible Location"
        case .timePattern: return "Time Pattern"
        case .categoryMismatch: return "Category Mismatch"
        case .blacklistCheck: return "Blacklist Check"
        case .custom: return "Custom Rule"
        }
    }
}

struct FraudRuleConfig: Codable {
    let threshold: Int?
    let timeWindowSeconds: Int?
    let maxDistance: Double?
    let customConditions: [String: String]?

    enum CodingKeys: String, CodingKey {
        case threshold
        case timeWindowSeconds = "time_window_seconds"
        case maxDistance = "max_distance"
        case customConditions = "custom_conditions"
    }
}

enum AlertSeverity: String, Codable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"

    var displayName: String {
        rawValue.capitalized
    }

    var color: String {
        switch self {
        case .low: return "blue"
        case .medium: return "orange"
        case .high: return "red"
        case .critical: return "purple"
        }
    }
}

/// Watchlist for security
struct WatchlistEntry: Codable, Identifiable {
    let id: String
    let organizationId: String?
    let entityType: WatchlistEntityType
    let entityValue: String
    let reason: String
    let riskLevel: RiskLevel
    let autoBlock: Bool
    let autoFlag: Bool
    let relatedCaseIds: [String]?
    let isActive: Bool
    let expiresAt: Date?
    let addedBy: String?
    let notes: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case organizationId = "organization_id"
        case entityType = "entity_type"
        case entityValue = "entity_value"
        case reason
        case riskLevel = "risk_level"
        case autoBlock = "auto_block"
        case autoFlag = "auto_flag"
        case relatedCaseIds = "related_case_ids"
        case isActive = "is_active"
        case expiresAt = "expires_at"
        case addedBy = "added_by"
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum WatchlistEntityType: String, Codable {
    case wristband = "wristband"
    case email = "email"
    case phone = "phone"
    case ipAddress = "ip_address"

    var displayName: String {
        switch self {
        case .wristband: return "Wristband"
        case .email: return "Email"
        case .phone: return "Phone"
        case .ipAddress: return "IP Address"
        }
    }

    var icon: String {
        switch self {
        case .wristband: return "person.badge.shield.checkmark"
        case .email: return "envelope.badge.shield.half.filled"
        case .phone: return "phone.badge.shield.checkmark"
        case .ipAddress: return "network.badge.shield.half.filled"
        }
    }
}

enum RiskLevel: String, Codable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case critical = "critical"

    var displayName: String {
        rawValue.capitalized
    }

    var color: String {
        switch self {
        case .low: return "blue"
        case .medium: return "orange"
        case .high: return "red"
        case .critical: return "purple"
        }
    }
}
