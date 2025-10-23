import Foundation

// MARK: - Offline Sync Queue Models

/// Mobile sync queue for offline operations
struct MobileSyncQueue: Codable, Identifiable {
    let id: String
    let userId: String
    let actionType: SyncActionType
    let tableName: String
    let recordData: [String: String] // JSONB stored as dictionary
    let syncStatus: SyncStatus
    let retryCount: Int
    let lastError: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case actionType = "action_type"
        case tableName = "table_name"
        case recordData = "record_data"
        case syncStatus = "sync_status"
        case retryCount = "retry_count"
        case lastError = "last_error"
        case createdAt = "created_at"
    }
}

enum SyncActionType: String, Codable {
    case create = "create"
    case update = "update"
    case delete = "delete"
    case checkin = "checkin"
    case linkTicket = "link_ticket"

    var displayName: String {
        switch self {
        case .create: return "Create"
        case .update: return "Update"
        case .delete: return "Delete"
        case .checkin: return "Check-in"
        case .linkTicket: return "Link Ticket"
        }
    }

    var icon: String {
        switch self {
        case .create: return "plus.circle.fill"
        case .update: return "pencil.circle.fill"
        case .delete: return "trash.circle.fill"
        case .checkin: return "checkmark.circle.fill"
        case .linkTicket: return "link.circle.fill"
        }
    }
}

enum SyncStatus: String, Codable {
    case pending = "pending"
    case syncing = "syncing"
    case completed = "completed"
    case failed = "failed"
    case conflicted = "conflicted"

    var displayName: String {
        rawValue.capitalized
    }

    var color: String {
        switch self {
        case .pending: return "orange"
        case .syncing: return "blue"
        case .completed: return "green"
        case .failed: return "red"
        case .conflicted: return "purple"
        }
    }

    var icon: String {
        switch self {
        case .pending: return "clock.fill"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .conflicted: return "exclamationmark.triangle.fill"
        }
    }
}

/// Sync conflict resolution
struct SyncConflict: Identifiable {
    let id: String
    let queueItem: MobileSyncQueue
    let localData: [String: Any]
    let serverData: [String: Any]
    let conflictType: ConflictType
    let detectedAt: Date

    enum ConflictType {
        case dataModified
        case recordDeleted
        case permissionDenied
        case validationFailed

        var displayName: String {
            switch self {
            case .dataModified: return "Data Modified"
            case .recordDeleted: return "Record Deleted"
            case .permissionDenied: return "Permission Denied"
            case .validationFailed: return "Validation Failed"
            }
        }
    }
}

/// Sync statistics
struct SyncStatistics {
    let totalPending: Int
    let totalFailed: Int
    let totalCompleted: Int
    let lastSyncAt: Date?
    let averageSyncTimeMs: Double
    let conflictCount: Int
    let retryCount: Int

    var syncHealth: SyncHealth {
        let failureRate = totalFailed > 0 ? Double(totalFailed) / Double(totalCompleted + totalFailed) : 0
        if failureRate > 0.1 { return .poor }
        if conflictCount > 5 { return .fair }
        if totalPending > 50 { return .fair }
        return .good
    }

    enum SyncHealth {
        case good
        case fair
        case poor

        var displayName: String {
            switch self {
            case .good: return "Good"
            case .fair: return "Fair"
            case .poor: return "Poor"
            }
        }

        var color: String {
            switch self {
            case .good: return "green"
            case .fair: return "orange"
            case .poor: return "red"
            }
        }

        var icon: String {
            switch self {
            case .good: return "checkmark.shield.fill"
            case .fair: return "exclamationmark.shield.fill"
            case .poor: return "xmark.shield.fill"
            }
        }
    }
}
