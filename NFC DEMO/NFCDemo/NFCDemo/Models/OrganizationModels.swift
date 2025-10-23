import Foundation

// MARK: - Multi-Organization Support Models (Portal Parity)

/// Organization model for multi-tenancy
struct Organization: Codable, Identifiable {
    let id: String
    let name: String
    let slug: String
    let description: String?
    let logoUrl: String?
    let website: String?
    let primaryColor: String
    let secondaryColor: String
    let customDomain: String?
    let subscriptionTier: SubscriptionTier
    let maxEvents: Int
    let maxWristbands: Int
    let maxTeamMembers: Int
    let settings: OrganizationSettings?
    let createdAt: Date
    let updatedAt: Date
    let createdBy: String?

    enum CodingKeys: String, CodingKey {
        case id, name, slug, description
        case logoUrl = "logo_url"
        case website
        case primaryColor = "primary_color"
        case secondaryColor = "secondary_color"
        case customDomain = "custom_domain"
        case subscriptionTier = "subscription_tier"
        case maxEvents = "max_events"
        case maxWristbands = "max_wristbands"
        case maxTeamMembers = "max_team_members"
        case settings
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case createdBy = "created_by"
    }
}

enum SubscriptionTier: String, Codable {
    case free = "free"
    case starter = "starter"
    case professional = "professional"
    case enterprise = "enterprise"

    var displayName: String {
        rawValue.capitalized
    }

    var features: [String] {
        switch self {
        case .free:
            return ["5 events", "1,000 wristbands", "Basic support"]
        case .starter:
            return ["20 events", "10,000 wristbands", "Email support", "Basic analytics"]
        case .professional:
            return ["Unlimited events", "100,000 wristbands", "Priority support", "Advanced analytics", "API access"]
        case .enterprise:
            return ["Unlimited everything", "24/7 support", "Custom integrations", "White-label", "SLA"]
        }
    }

    var color: String {
        switch self {
        case .free: return "gray"
        case .starter: return "blue"
        case .professional: return "purple"
        case .enterprise: return "gold"
        }
    }
}

struct OrganizationSettings: Codable {
    let features: FeatureFlags?
    let notifications: NotificationSettings?
    let require2FA: Bool?
    let allowedIPRanges: [String]?
    let sessionTimeoutMinutes: Int?
    let dataRetentionDays: Int?
    let autoArchiveEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case features, notifications
        case require2FA = "require_2fa"
        case allowedIPRanges = "allowed_ip_ranges"
        case sessionTimeoutMinutes = "session_timeout_minutes"
        case dataRetentionDays = "data_retention_days"
        case autoArchiveEnabled = "auto_archive_enabled"
    }
}

struct FeatureFlags: Codable {
    let apiAccess: Bool
    let aiInsights: Bool
    let whiteLabel: Bool
    let fraudDetection: Bool
    let customWorkflows: Bool

    enum CodingKeys: String, CodingKey {
        case apiAccess = "api_access"
        case aiInsights = "ai_insights"
        case whiteLabel = "white_label"
        case fraudDetection = "fraud_detection"
        case customWorkflows = "custom_workflows"
    }
}

struct NotificationSettings: Codable {
    let smsEnabled: Bool
    let pushEnabled: Bool
    let emailEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case smsEnabled = "sms_enabled"
        case pushEnabled = "push_enabled"
        case emailEnabled = "email_enabled"
    }
}

/// Organization member with role
struct OrganizationMember: Codable, Identifiable {
    let id: String
    let organizationId: String
    let userId: String
    let role: OrganizationRole
    let permissions: MemberPermissions?
    let status: MemberStatus
    let invitedBy: String?
    let invitedAt: Date?
    let joinedAt: Date
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case organizationId = "organization_id"
        case userId = "user_id"
        case role, permissions, status
        case invitedBy = "invited_by"
        case invitedAt = "invited_at"
        case joinedAt = "joined_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum OrganizationRole: String, Codable {
    case owner = "owner"
    case admin = "admin"
    case manager = "manager"
    case member = "member"
    case scanner = "scanner"

    var displayName: String {
        rawValue.capitalized
    }

    var permissions: [String] {
        switch self {
        case .owner:
            return ["all"]
        case .admin:
            return ["events:write", "users:write", "settings:write", "reports:write"]
        case .manager:
            return ["events:write", "reports:read", "users:read"]
        case .member:
            return ["events:read", "reports:read"]
        case .scanner:
            return ["scan:perform", "events:read"]
        }
    }
}

struct MemberPermissions: Codable {
    let events: String // "read", "write", "admin"
    let reports: String
    let wristbands: String
    let settings: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        events = try container.decodeIfPresent(String.self, forKey: .events) ?? "read"
        reports = try container.decodeIfPresent(String.self, forKey: .reports) ?? "read"
        wristbands = try container.decodeIfPresent(String.self, forKey: .wristbands) ?? "read"
        settings = try container.decodeIfPresent(String.self, forKey: .settings)
    }
}

enum MemberStatus: String, Codable {
    case active = "active"
    case suspended = "suspended"
    case invited = "invited"

    var displayName: String {
        rawValue.capitalized
    }

    var color: String {
        switch self {
        case .active: return "green"
        case .suspended: return "red"
        case .invited: return "orange"
        }
    }
}

// MARK: - Staff Performance Models

/// Staff performance tracking
struct StaffPerformance: Codable, Identifiable {
    let id: String
    let userId: String
    let eventId: String
    let totalScans: Int
    let successfulScans: Int
    let failedScans: Int
    let errorCount: Int
    let scansPerHour: Double
    let avgScanTimeMs: Int
    let efficiencyScore: Double
    let shiftStart: Date?
    let shiftEnd: Date?
    let breakTimeMinutes: Int
    let lastScanAt: Date?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case eventId = "event_id"
        case totalScans = "total_scans"
        case successfulScans = "successful_scans"
        case failedScans = "failed_scans"
        case errorCount = "error_count"
        case scansPerHour = "scans_per_hour"
        case avgScanTimeMs = "avg_scan_time_ms"
        case efficiencyScore = "efficiency_score"
        case shiftStart = "shift_start"
        case shiftEnd = "shift_end"
        case breakTimeMinutes = "break_time_minutes"
        case lastScanAt = "last_scan_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var accuracyRate: Double {
        guard totalScans > 0 else { return 0 }
        return Double(successfulScans) / Double(totalScans) * 100
    }

    var errorRate: Double {
        guard totalScans > 0 else { return 0 }
        return Double(errorCount) / Double(totalScans) * 100
    }

    var performanceGrade: String {
        switch efficiencyScore {
        case 90...100: return "A+"
        case 80..<90: return "A"
        case 70..<80: return "B"
        case 60..<70: return "C"
        default: return "D"
        }
    }
}

/// Active scanner position for real-time tracking
struct ScannerPosition: Codable, Identifiable {
    let id: String
    let userId: String
    let eventId: String
    let latitude: Double
    let longitude: Double
    let accuracy: Double
    let batteryLevel: Int?
    let isScanning: Bool
    let lastSeenAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case eventId = "event_id"
        case latitude, longitude, accuracy
        case batteryLevel = "battery_level"
        case isScanning = "is_scanning"
        case lastSeenAt = "last_seen_at"
    }
}

/// App session tracking
struct AppSession: Codable, Identifiable {
    let id: String
    let userId: String
    let deviceId: String
    let deviceModel: String?
    let osVersion: String?
    let appVersion: String?
    let startedAt: Date
    let endedAt: Date?
    let totalScans: Int
    let offlineDuration: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case deviceId = "device_id"
        case deviceModel = "device_model"
        case osVersion = "os_version"
        case appVersion = "app_version"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case totalScans = "total_scans"
        case offlineDuration = "offline_duration"
    }
}
