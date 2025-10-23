import Foundation

// MARK: - Event Series Model
struct EventSeries: Codable, Identifiable {
    let id: String
    let mainEventId: String
    let name: String
    let description: String?
    let startDate: Date
    let endDate: Date
    let checkinWindowStartOffset: TimeInterval?
    let checkinWindowEndOffset: TimeInterval?
    let lifecycleStatus: LifecycleStatus
    let statusChangedAt: Date?
    let statusChangedBy: String?
    let autoTransitionEnabled: Bool
    let sequenceNumber: Int?
    let seriesType: SeriesType
    let location: String?
    let venueId: String?
    let capacity: Int?
    let isRecurring: Bool
    let recurrencePattern: String?  // Store as JSON string
    let parentSeriesId: String?
    let config: String?  // Store as JSON string
    let isPublic: Bool
    let requiresSeparateTicket: Bool
    let createdAt: Date
    let updatedAt: Date
    let createdBy: String?
    let organizationId: String
    
    enum LifecycleStatus: String, Codable {
        case draft = "draft"
        case scheduled = "scheduled"
        case active = "active"
        case completed = "completed"
        case cancelled = "cancelled"
        
        var displayName: String {
            switch self {
            case .draft: return "Draft"
            case .scheduled: return "Scheduled"
            case .active: return "Active"
            case .completed: return "Completed"
            case .cancelled: return "Cancelled"
            }
        }
        
        var color: String {
            switch self {
            case .draft: return "#9CA3AF"
            case .scheduled: return "#F59E0B"
            case .active: return "#10B981"
            case .completed: return "#6B7280"
            case .cancelled: return "#EF4444"
            }
        }
    }
    
    enum SeriesType: String, Codable {
        case standard = "standard"
        case knockout = "knockout"
        case groupStage = "group_stage"
        case roundRobin = "round_robin"
        case custom = "custom"
        
        var displayName: String {
            switch self {
            case .standard: return "Standard"
            case .knockout: return "Knockout"
            case .groupStage: return "Group Stage"
            case .roundRobin: return "Round Robin"
            case .custom: return "Custom"
            }
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case mainEventId = "main_event_id"
        case name, description
        case startDate = "start_date"
        case endDate = "end_date"
        case checkinWindowStartOffset = "checkin_window_start_offset"
        case checkinWindowEndOffset = "checkin_window_end_offset"
        case lifecycleStatus = "lifecycle_status"
        case statusChangedAt = "status_changed_at"
        case statusChangedBy = "status_changed_by"
        case autoTransitionEnabled = "auto_transition_enabled"
        case sequenceNumber = "sequence_number"
        case seriesType = "series_type"
        case location
        case venueId = "venue_id"
        case capacity
        case isRecurring = "is_recurring"
        case recurrencePattern = "recurrence_pattern"
        case parentSeriesId = "parent_series_id"
        case config
        case isPublic = "is_public"
        case requiresSeparateTicket = "requires_separate_ticket"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case createdBy = "created_by"
        case organizationId = "organization_id"
    }
    
    // Computed properties
    var isPast: Bool {
        return endDate < Date()
    }
    
    var isActiveAndCurrent: Bool {
        let notPast = !isPast
        let isActive = lifecycleStatus == .active || lifecycleStatus == .scheduled
        return notPast && isActive
    }
    
    var formattedDateRange: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        
        if Calendar.current.isDate(startDate, inSameDayAs: endDate) {
            return formatter.string(from: startDate)
        } else {
            return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
        }
    }
    
    // Custom decoder to handle JSONB fields
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        mainEventId = try container.decode(String.self, forKey: .mainEventId)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        startDate = try container.decode(Date.self, forKey: .startDate)
        endDate = try container.decode(Date.self, forKey: .endDate)
        
        // Handle interval as seconds - just store as nil for now
        checkinWindowStartOffset = nil
        checkinWindowEndOffset = nil
        
        lifecycleStatus = try container.decode(LifecycleStatus.self, forKey: .lifecycleStatus)
        statusChangedAt = try container.decodeIfPresent(Date.self, forKey: .statusChangedAt)
        statusChangedBy = try container.decodeIfPresent(String.self, forKey: .statusChangedBy)
        autoTransitionEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoTransitionEnabled) ?? true
        sequenceNumber = try container.decodeIfPresent(Int.self, forKey: .sequenceNumber)
        seriesType = try container.decodeIfPresent(SeriesType.self, forKey: .seriesType) ?? .standard
        location = try container.decodeIfPresent(String.self, forKey: .location)
        venueId = try container.decodeIfPresent(String.self, forKey: .venueId)
        capacity = try container.decodeIfPresent(Int.self, forKey: .capacity)
        isRecurring = try container.decodeIfPresent(Bool.self, forKey: .isRecurring) ?? false
        recurrencePattern = try container.decodeIfPresent(String.self, forKey: .recurrencePattern)
        parentSeriesId = try container.decodeIfPresent(String.self, forKey: .parentSeriesId)
        
        // Handle config - can be String or Dictionary from JSONB
        // Try to decode as string, otherwise set to nil (we don't currently use this field)
        config = try? container.decodeIfPresent(String.self, forKey: .config)
        
        isPublic = try container.decodeIfPresent(Bool.self, forKey: .isPublic) ?? false
        requiresSeparateTicket = try container.decodeIfPresent(Bool.self, forKey: .requiresSeparateTicket) ?? false
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        createdBy = try container.decodeIfPresent(String.self, forKey: .createdBy)
        organizationId = try container.decode(String.self, forKey: .organizationId)
    }
    
    // Helper to parse PostgreSQL interval format
    private func parseInterval(_ interval: String) -> TimeInterval? {
        // PostgreSQL interval format: "HH:MM:SS" or "X hours Y minutes"
        // For simplicity, handle "HH:MM:SS" format
        let components = interval.split(separator: ":")
        guard components.count == 3,
              let hours = Double(components[0]),
              let minutes = Double(components[1]),
              let seconds = Double(components[2]) else {
            return nil
        }
        return (hours * 3600) + (minutes * 60) + seconds
    }
}

// MARK: - Series with Event Info
struct SeriesWithEvent: Identifiable {
    let series: EventSeries
    let event: Event
    
    var id: String { series.id }
    var name: String { series.name }
    var startDate: Date { series.startDate }
    var endDate: Date { series.endDate }
    var location: String? { series.location ?? event.location }
    var isActiveAndCurrent: Bool { series.isActiveAndCurrent }
}
