import Foundation

// MARK: - Emergency Management Models (Portal Parity)

/// Emergency incident tracking
struct EmergencyIncident: Codable, Identifiable {
    let id: String
    let organizationId: String?
    let eventId: String
    let incidentType: String
    let severity: EmergencySeverity
    let location: String?
    let description: String
    let status: IncidentStatus
    let reportedBy: String?
    let reportedByUserId: String?
    let reportedAt: Date
    let responders: [String]?
    let assignedTo: String?
    let responseStartedAt: Date?
    let estimatedAffected: Int
    let actualAffected: Int?
    let resolutionNotes: String?
    let resolvedBy: String?
    let resolvedAt: Date?
    let evidence: [EmergencyEvidence]?
    let actionLog: [EmergencyAction]?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case organizationId = "organization_id"
        case eventId = "event_id"
        case incidentType = "incident_type"
        case severity, location, description, status
        case reportedBy = "reported_by"
        case reportedByUserId = "reported_by_user_id"
        case reportedAt = "reported_at"
        case responders
        case assignedTo = "assigned_to"
        case responseStartedAt = "response_started_at"
        case estimatedAffected = "estimated_affected"
        case actualAffected = "actual_affected"
        case resolutionNotes = "resolution_notes"
        case resolvedBy = "resolved_by"
        case resolvedAt = "resolved_at"
        case evidence
        case actionLog = "action_log"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum EmergencySeverity: String, Codable, CaseIterable {
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

    var icon: String {
        switch self {
        case .low: return "info.circle.fill"
        case .medium: return "exclamationmark.triangle.fill"
        case .high: return "exclamationmark.octagon.fill"
        case .critical: return "exclamationmark.shield.fill"
        }
    }
}

enum IncidentStatus: String, Codable, CaseIterable {
    case active = "active"
    case investigating = "investigating"
    case resolved = "resolved"
    case closed = "closed"

    var displayName: String {
        rawValue.capitalized
    }

    var color: String {
        switch self {
        case .active: return "red"
        case .investigating: return "orange"
        case .resolved: return "blue"
        case .closed: return "gray"
        }
    }
}

struct EmergencyEvidence: Codable {
    let type: String
    let description: String
    let url: String?
    let timestamp: Date
    let uploadedBy: String?
}

struct EmergencyAction: Codable, Identifiable {
    let id: String
    let organizationId: String?
    let eventId: String?
    let incidentId: String?
    let actionType: EmergencyActionType
    let actionTitle: String
    let actionDescription: String?
    let severity: EmergencySeverity
    let estimatedImpact: String?
    let actualImpact: String?
    let executedBy: String
    let executedAt: Date
    let completedAt: Date?
    let status: ActionStatus
    let resultDetails: [String: String]?
    let affectedGates: [String]?
    let affectedUsers: [String]?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case organizationId = "organization_id"
        case eventId = "event_id"
        case incidentId = "incident_id"
        case actionType = "action_type"
        case actionTitle = "action_title"
        case actionDescription = "action_description"
        case severity
        case estimatedImpact = "estimated_impact"
        case actualImpact = "actual_impact"
        case executedBy = "executed_by"
        case executedAt = "executed_at"
        case completedAt = "completed_at"
        case status
        case resultDetails = "result_details"
        case affectedGates = "affected_gates"
        case affectedUsers = "affected_users"
        case createdAt = "created_at"
    }
}

enum EmergencyActionType: String, Codable {
    case lockdown = "lockdown"
    case evacuation = "evacuation"
    case broadcast = "broadcast"
    case staffAlert = "staff_alert"
    case systemShutdown = "system_shutdown"
    case gateControl = "gate_control"
    case accessRestriction = "access_restriction"

    var displayName: String {
        switch self {
        case .lockdown: return "Lockdown"
        case .evacuation: return "Evacuation"
        case .broadcast: return "Broadcast Alert"
        case .staffAlert: return "Staff Alert"
        case .systemShutdown: return "System Shutdown"
        case .gateControl: return "Gate Control"
        case .accessRestriction: return "Access Restriction"
        }
    }

    var icon: String {
        switch self {
        case .lockdown: return "lock.shield.fill"
        case .evacuation: return "arrow.uturn.backward.circle.fill"
        case .broadcast: return "megaphone.fill"
        case .staffAlert: return "bell.badge.fill"
        case .systemShutdown: return "power"
        case .gateControl: return "door.sliding.left.hand.closed"
        case .accessRestriction: return "hand.raised.fill"
        }
    }
}

enum ActionStatus: String, Codable {
    case pending = "pending"
    case executing = "executing"
    case completed = "completed"
    case failed = "failed"
    case cancelled = "cancelled"

    var displayName: String {
        rawValue.capitalized
    }

    var color: String {
        switch self {
        case .pending: return "orange"
        case .executing: return "blue"
        case .completed: return "green"
        case .failed: return "red"
        case .cancelled: return "gray"
        }
    }
}

/// System-wide emergency status
struct EmergencyStatus: Codable, Identifiable {
    let id: String
    let organizationId: String?
    let alertLevel: AlertLevel
    let isActive: Bool
    let activeIncidents: Int
    let systemsLocked: Bool
    let evacuationStatus: EvacuationStatus
    let lastUpdatedAt: Date
    let alertStartedAt: Date?
    let alertClearedAt: Date?
    let statusDetails: [String: String]?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case organizationId = "organization_id"
        case alertLevel = "alert_level"
        case isActive = "is_active"
        case activeIncidents = "active_incidents"
        case systemsLocked = "systems_locked"
        case evacuationStatus = "evacuation_status"
        case lastUpdatedAt = "last_updated_at"
        case alertStartedAt = "alert_started_at"
        case alertClearedAt = "alert_cleared_at"
        case statusDetails = "status_details"
        case updatedAt = "updated_at"
    }
}

enum AlertLevel: String, Codable {
    case normal = "normal"
    case elevated = "elevated"
    case high = "high"
    case critical = "critical"

    var displayName: String {
        rawValue.capitalized
    }

    var color: String {
        switch self {
        case .normal: return "green"
        case .elevated: return "yellow"
        case .high: return "orange"
        case .critical: return "red"
        }
    }
}

enum EvacuationStatus: String, Codable {
    case none = "none"
    case partial = "partial"
    case full = "full"

    var displayName: String {
        rawValue.capitalized
    }
}
