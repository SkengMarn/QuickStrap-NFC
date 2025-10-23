import Foundation

// MARK: - Broadcast Message Types

/// Message type for broadcasts
enum BroadcastMessageType: String, Codable {
    case broadcast = "broadcast"
    case alert = "alert"
    case emergency = "emergency"

    var displayTitle: String {
        switch self {
        case .broadcast:
            return "Broadcast Message"
        case .alert:
            return "Important Alert"
        case .emergency:
            return "Emergency Alert"
        }
    }

    var icon: String {
        switch self {
        case .broadcast:
            return "speaker.wave.2.fill"
        case .alert:
            return "exclamationmark.triangle.fill"
        case .emergency:
            return "exclamationmark.octagon.fill"
        }
    }
}

/// Priority level for broadcasts
enum BroadcastPriority: String, Codable {
    case low = "low"
    case normal = "normal"
    case high = "high"
    case urgent = "urgent"

    var displayName: String {
        return rawValue.capitalized
    }

    var color: String {
        switch self {
        case .low:
            return "gray"
        case .normal:
            return "blue"
        case .high:
            return "orange"
        case .urgent:
            return "red"
        }
    }
}

// MARK: - Broadcast Message Model

/// Broadcast message sent to all users in an event
struct BroadcastMessage: Codable, Identifiable {
    let id: String
    let eventId: String
    let senderId: String
    let message: String
    let messageType: BroadcastMessageType
    let priority: BroadcastPriority
    let sentAt: Date
    let expiresAt: Date?
    let readBy: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case eventId = "event_id"
        case senderId = "sender_id"
        case message
        case messageType = "message_type"
        case priority
        case sentAt = "sent_at"
        case expiresAt = "expires_at"
        case readBy = "read_by"
    }

    /// Check if message has expired
    var isExpired: Bool {
        guard let expiresAt = expiresAt else { return false }
        return Date() > expiresAt
    }

    /// Check if user has read the message
    func isReadBy(userId: String) -> Bool {
        return readBy?.contains(userId) ?? false
    }
}

// MARK: - Notification Model

/// Notification sent to individual users
struct AppNotification: Codable, Identifiable {
    let id: String
    let userId: String
    let type: String
    let title: String
    let message: String
    let data: NotificationData?
    let read: Bool
    let readAt: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case type
        case title
        case message
        case data
        case read
        case readAt = "read_at"
        case createdAt = "created_at"
    }
}

/// Additional data attached to notifications
struct NotificationData: Codable {
    let broadcastId: String?
    let eventId: String?
    let priority: String?
    let senderId: String?

    enum CodingKeys: String, CodingKey {
        case broadcastId = "broadcast_id"
        case eventId = "event_id"
        case priority
        case senderId = "sender_id"
    }
}

// MARK: - Broadcast Statistics

/// Statistics about broadcast delivery
struct BroadcastStats {
    let totalRecipients: Int
    let deliveredCount: Int
    let readCount: Int

    var deliveryRate: Double {
        guard totalRecipients > 0 else { return 0 }
        return Double(deliveredCount) / Double(totalRecipients)
    }

    var readRate: Double {
        guard deliveredCount > 0 else { return 0 }
        return Double(readCount) / Double(deliveredCount)
    }
}
