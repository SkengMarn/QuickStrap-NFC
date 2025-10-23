import Foundation

// MARK: - User Profile Model
struct UserProfile: Codable, Identifiable {
    let id: String
    let email: String
    let fullName: String?
    let phone: String?
    let role: UserRole
    let createdAt: Date
    let updatedAt: Date
    let lastSignIn: Date?
    
    enum CodingKeys: String, CodingKey {
        case id, email, role, phone
        case fullName = "full_name"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lastSignIn = "last_sign_in"
    }
}

enum UserRole: String, Codable, CaseIterable {
    case admin = "admin"
    case owner = "owner"
    case scanner = "scanner"
    
    var displayName: String {
        switch self {
        case .admin: return "Admin"
        case .owner: return "Owner"
        case .scanner: return "Scanner"
        }
    }
}

// MARK: - Event Model
struct Event: Codable, Identifiable {
    let id: String
    let name: String
    let description: String?
    let location: String?
    let startDate: Date
    let endDate: Date?  // End date can be optional for single-day events
    let totalCapacity: Int?  // Make optional to handle missing capacity
    let createdBy: String?
    let createdAt: Date?  // Make optional to handle missing timestamps
    let updatedAt: Date?  // Make optional to handle missing timestamps
    
    // Lifecycle status from database
    let lifecycleStatus: String?  // draft, scheduled, active, completed, cancelled
    let organizationId: String

    // Series tracking - if this Event represents a series event, this will be the series ID
    let seriesId: String?

    // Ticket Linking Configuration
    let ticketLinkingMode: TicketLinkingMode
    let allowUnlinkedEntry: Bool

    // Event Configuration (JSONB)
    let config: EventConfig?

    // Computed property for backward compatibility and display
    var date: Date {
        return startDate
    }

    // Computed property for capacity settings
    var capacitySettings: CapacitySettings? {
        return config?.capacitySettings
    }
    
    // Check if event is in the past
    var isPast: Bool {
        guard let endDate = endDate else {
            return startDate < Date()
        }
        return endDate < Date()
    }
    
    // Check if event is active and not in the past
    var isActiveAndCurrent: Bool {
        let notPast = !isPast
        let isActive = lifecycleStatus == "active" || lifecycleStatus == "scheduled" || lifecycleStatus == nil
        return notPast && isActive
    }
    
    enum TicketLinkingMode: String, Codable, CaseIterable {
        case disabled = "disabled"    // No ticket system at all
        case optional = "optional"    // Tickets exist but linking not enforced
        case required = "required"    // Every wristband must link to ticket
        
        var displayName: String {
            switch self {
            case .disabled: return "No Tickets"
            case .optional: return "Optional Linking"
            case .required: return "Required Linking"
            }
        }
        
        var description: String {
            switch self {
            case .disabled: return "Event has no ticketing system"
            case .optional: return "Tickets exist but linking is not enforced"
            case .required: return "All wristbands must be linked to tickets"
            }
        }
        
        var icon: String {
            switch self {
            case .disabled: return "xmark.circle"
            case .optional: return "questionmark.circle"
            case .required: return "checkmark.circle"
            }
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, description, location
        case startDate = "start_date"
        case endDate = "end_date"
        case totalCapacity = "total_capacity"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lifecycleStatus = "lifecycle_status"
        case organizationId = "organization_id"
        case seriesId = "series_id"
        case ticketLinkingMode = "ticket_linking_mode"
        case allowUnlinkedEntry = "allow_unlinked_entry"
        case config
    }
    
    // Regular initializer for creating Event instances
    init(
        id: String,
        name: String,
        description: String? = nil,
        location: String? = nil,
        startDate: Date,
        endDate: Date? = nil,
        totalCapacity: Int? = nil,
        createdBy: String? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        lifecycleStatus: String? = nil,
        organizationId: String,
        seriesId: String? = nil,
        ticketLinkingMode: TicketLinkingMode = .disabled,
        allowUnlinkedEntry: Bool = true,
        config: EventConfig? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.location = location
        self.startDate = startDate
        self.endDate = endDate
        self.totalCapacity = totalCapacity
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lifecycleStatus = lifecycleStatus
        self.organizationId = organizationId
        self.seriesId = seriesId
        self.ticketLinkingMode = ticketLinkingMode
        self.allowUnlinkedEntry = allowUnlinkedEntry
        self.config = config
    }
    
    // Initialize with default ticket linking values for backward compatibility
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        startDate = try container.decode(Date.self, forKey: .startDate)
        endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
        totalCapacity = try container.decodeIfPresent(Int.self, forKey: .totalCapacity)
        createdBy = try container.decodeIfPresent(String.self, forKey: .createdBy)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        
        // Lifecycle status and organization
        lifecycleStatus = try container.decodeIfPresent(String.self, forKey: .lifecycleStatus)
        organizationId = try container.decode(String.self, forKey: .organizationId)
        
        // Series ID (if this event represents a series event)
        seriesId = try container.decodeIfPresent(String.self, forKey: .seriesId)

        // Default to disabled mode for backward compatibility
        ticketLinkingMode = try container.decodeIfPresent(TicketLinkingMode.self, forKey: .ticketLinkingMode) ?? .disabled
        allowUnlinkedEntry = try container.decodeIfPresent(Bool.self, forKey: .allowUnlinkedEntry) ?? true

        // Optional config field
        config = try container.decodeIfPresent(EventConfig.self, forKey: .config)
    }
}

// MARK: - Event Configuration Models

struct EventConfig: Codable {
    let capacitySettings: CapacitySettings?
    let checkinWindow: CheckinWindow?

    enum CodingKeys: String, CodingKey {
        case capacitySettings = "capacity_settings"
        case checkinWindow = "checkin_window"
    }
}

struct CapacitySettings: Codable {
    let alertsEnabled: Bool
    let alertThreshold: Int  // Percentage (e.g., 90)
    let maxCapacity: Int?

    enum CodingKeys: String, CodingKey {
        case alertsEnabled = "alerts_enabled"
        case alertThreshold = "alert_threshold"
        case maxCapacity = "max_capacity"
    }

    // Computed property to check if threshold is reached
    func hasReachedThreshold(currentCount: Int) -> Bool {
        guard alertsEnabled, let max = maxCapacity else { return false }
        let currentPercentage = (Double(currentCount) / Double(max)) * 100
        return currentPercentage >= Double(alertThreshold)
    }

    // Computed property to get current capacity percentage
    func capacityPercentage(currentCount: Int) -> Double {
        guard let max = maxCapacity, max > 0 else { return 0 }
        return (Double(currentCount) / Double(max)) * 100
    }
}

struct CheckinWindow: Codable {
    let enabled: Bool
    let startTime: String?  // Format: "HH:mm" (e.g., "14:00")
    let endTime: String?    // Format: "HH:mm" (e.g., "22:00")

    enum CodingKeys: String, CodingKey {
        case enabled
        case startTime = "start_time"
        case endTime = "end_time"
    }

    // Check if current time is within the check-in window
    func isWithinWindow(at date: Date = Date()) -> CheckinWindowStatus {
        // If not enabled, always allow
        guard enabled else {
            return .allowed
        }

        // If enabled but no times set, deny (invalid configuration)
        guard let startTimeStr = startTime,
              let endTimeStr = endTime else {
            return .invalidConfiguration
        }

        // Parse times
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        timeFormatter.timeZone = TimeZone.current

        guard let startTime = timeFormatter.date(from: startTimeStr),
              let endTime = timeFormatter.date(from: endTimeStr) else {
            return .invalidConfiguration
        }

        // Get current time components
        let calendar = Calendar.current
        let currentComponents = calendar.dateComponents([.hour, .minute], from: date)
        let startComponents = calendar.dateComponents([.hour, .minute], from: startTime)
        let endComponents = calendar.dateComponents([.hour, .minute], from: endTime)

        guard let currentHour = currentComponents.hour,
              let currentMinute = currentComponents.minute,
              let startHour = startComponents.hour,
              let startMinute = startComponents.minute,
              let endHour = endComponents.hour,
              let endMinute = endComponents.minute else {
            return .invalidConfiguration
        }

        // Convert to minutes since midnight for easier comparison
        let currentMinutes = currentHour * 60 + currentMinute
        let startMinutes = startHour * 60 + startMinute
        let endMinutes = endHour * 60 + endMinute

        // Handle overnight windows (e.g., 22:00 - 02:00)
        if endMinutes < startMinutes {
            // Window crosses midnight
            if currentMinutes >= startMinutes || currentMinutes <= endMinutes {
                return .allowed
            } else {
                return .outsideWindow(startTime: startTimeStr, endTime: endTimeStr)
            }
        } else {
            // Normal window (same day)
            if currentMinutes >= startMinutes && currentMinutes <= endMinutes {
                return .allowed
            } else {
                return .outsideWindow(startTime: startTimeStr, endTime: endTimeStr)
            }
        }
    }

    // Get human-readable window description
    func windowDescription() -> String? {
        guard enabled, let start = startTime, let end = endTime else {
            return nil
        }
        return "\(formatTime(start)) - \(formatTime(end))"
    }

    // Format time for display (e.g., "14:00" -> "2:00 PM")
    private func formatTime(_ timeString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone.current

        guard let date = formatter.date(from: timeString) else {
            return timeString
        }

        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - Check-in Window Status

enum CheckinWindowStatus {
    case allowed
    case outsideWindow(startTime: String, endTime: String)
    case invalidConfiguration

    var isAllowed: Bool {
        if case .allowed = self {
            return true
        }
        return false
    }

    var errorMessage: String {
        switch self {
        case .allowed:
            return ""
        case .outsideWindow(let start, let end):
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"

            // Format times for display
            let startFormatted: String
            let endFormatted: String

            if let startDate = formatter.date(from: start) {
                formatter.dateFormat = "h:mm a"
                startFormatted = formatter.string(from: startDate)
            } else {
                startFormatted = start
            }

            if let endDate = formatter.date(from: end) {
                formatter.dateFormat = "h:mm a"
                endFormatted = formatter.string(from: endDate)
            } else {
                endFormatted = end
            }

            return "Check-in not allowed at this time\nAllowed: \(startFormatted) - \(endFormatted)"
        case .invalidConfiguration:
            return "Check-in window not configured properly"
        }
    }
}

// MARK: - Wristband Status
enum WristbandStatus: String, Codable, CaseIterable {
    case active = "active"
    case activated = "activated"  // Added to handle database inconsistency
    case inactive = "inactive"
    case lost = "lost"
    case stolen = "stolen"
    
    var displayName: String {
        switch self {
        case .active, .activated: return "Active"
        case .inactive: return "Inactive"
        case .lost: return "Lost"
        case .stolen: return "Stolen"
        }
    }
    
    var color: String {
        switch self {
        case .active, .activated: return "green"
        case .inactive: return "gray"
        case .lost: return "orange"
        case .stolen: return "red"
        }
    }
}

// MARK: - Wristband Model
struct Wristband: Codable, Identifiable {
    let id: String
    let eventId: String
    let nfcId: String
    let category: WristbandCategory
    let isActive: Bool
    let status: WristbandStatus
    let createdAt: Date
    let updatedAt: Date
    
    // Series tracking - if this wristband belongs to a series event
    let seriesId: String?
    
    // Ticket Linking Properties (legacy - for backward compatibility)
    let linkedTicketId: String?
    let linkedAt: Date?
    let ticketLinkRequired: Bool
    
    // Computed properties for UI
    var isCheckedIn: Bool {
        // This will be determined by checking if there's a recent checkin log
        false // Default value, will be updated when loading from database
    }
    
    var checkInTime: Date? {
        // This will be populated from the most recent checkin log
        nil // Default value, will be updated when loading from database
    }
    
    var hasTicketLink: Bool {
        linkedTicketId != nil
    }
    
    var linkingStatus: String {
        if hasTicketLink {
            return "Linked"
        } else if ticketLinkRequired {
            return "Link Required"
        } else {
            return "No Link Needed"
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case eventId = "event_id"
        case nfcId = "nfc_id"
        case category
        case isActive = "is_active"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case seriesId = "series_id"
        case linkedTicketId = "linked_ticket_id"
        case linkedAt = "linked_at"
        case ticketLinkRequired = "ticket_link_required"
    }
    
    // Regular initializer for creating Wristband instances
    init(
        id: String,
        eventId: String,
        nfcId: String,
        category: WristbandCategory,
        isActive: Bool,
        status: WristbandStatus = .active,
        createdAt: Date,
        updatedAt: Date,
        seriesId: String? = nil,
        linkedTicketId: String? = nil,
        linkedAt: Date? = nil,
        ticketLinkRequired: Bool = false
    ) {
        self.id = id
        self.eventId = eventId
        self.nfcId = nfcId
        self.category = category
        self.isActive = isActive
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.seriesId = seriesId
        self.linkedTicketId = linkedTicketId
        self.linkedAt = linkedAt
        self.ticketLinkRequired = ticketLinkRequired
    }
    
    // Initialize with default ticket linking values for backward compatibility
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(String.self, forKey: .id)
        eventId = try container.decode(String.self, forKey: .eventId)
        nfcId = try container.decode(String.self, forKey: .nfcId)
        category = try container.decode(WristbandCategory.self, forKey: .category)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        status = try container.decodeIfPresent(WristbandStatus.self, forKey: .status) ?? .active
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        
        // Series ID (if wristband belongs to a series event)
        seriesId = try container.decodeIfPresent(String.self, forKey: .seriesId)
        
        // Default ticket linking values for backward compatibility
        linkedTicketId = try container.decodeIfPresent(String.self, forKey: .linkedTicketId)
        linkedAt = try container.decodeIfPresent(Date.self, forKey: .linkedAt)
        ticketLinkRequired = try container.decodeIfPresent(Bool.self, forKey: .ticketLinkRequired) ?? false
    }
}

// MARK: - Wristband Category
struct WristbandCategory: Codable, Hashable, Identifiable {
    var id: String { name } // Use name as ID to avoid decoding issues
    let name: String
    
    init(name: String) {
        // Only default to "General" if the category is truly null/empty
        self.name = name.isEmpty ? "General" : name
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String?.self) ?? ""
        
        // Only default to "General" if null/empty, preserve all other values
        self.name = rawValue.isEmpty ? "General" : rawValue
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(name)
    }
    
    var displayName: String {
        return name
    }
    
    var color: String {
        // Provide colors based on common category patterns
        switch name.lowercased() {
        case let n where n.contains("vip"):
            return "#FFD700" // Gold
        case let n where n.contains("general"):
            return "#0056D2" // Blue
        case let n where n.contains("staff"):
            return "#00C853" // Green
        case let n where n.contains("press") || n.contains("media"):
            return "#757575" // Gray
        case let n where n.contains("artist") || n.contains("performer"):
            return "#E91E63" // Pink
        case let n where n.contains("crew") || n.contains("vendor"):
            return "#FF9800" // Orange
        case let n where n.contains("early"):
            return "#8BC34A" // Light Green
        default:
            return "#9E9E9E" // Default Grey
        }
    }
    
    // Equatable conformance
    static func == (lhs: WristbandCategory, rhs: WristbandCategory) -> Bool {
        return lhs.name == rhs.name
    }
    
    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

// MARK: - Check-in Log Model
struct CheckinLog: Codable, Identifiable {
    let id: String
    let eventId: String
    let wristbandId: String
    let staffId: String?
    let timestamp: Date
    let location: String?
    let notes: String?
    let gateId: String?
    let scannerId: String?
    let appLat: Double?
    let appLon: Double?
    let appAccuracy: Double?
    let bleSeen: [String]?
    let wifiSSIDs: [String]?
    let probationTagged: Bool?
    let seriesId: String?  // Series ID if check-in is for a series event
    
    enum CodingKeys: String, CodingKey {
        case id
        case eventId = "event_id"
        case wristbandId = "wristband_id"
        case staffId = "staff_id"
        case timestamp, location, notes
        case gateId = "gate_id"
        case scannerId = "scanner_id"
        case appLat = "app_lat"
        case appLon = "app_lon"
        case appAccuracy = "app_accuracy"
        case bleSeen = "ble_seen"
        case wifiSSIDs = "wifi_ssids"
        case probationTagged = "probation_tagged"
        case seriesId = "series_id"
    }
    
    // MARK: - Scan Type Detection
    
    /// Determines the type of scan based on available data
    var scanType: ScanType {
        // Manual check-in by staff
        if staffId != nil {
            return .manual
        }
        
        // All other scans are mobile app scans (NFC via phone)
        if appLat != nil && appLon != nil {
            return .mobile
        }
        
        // Check location string for clues
        if let location = location?.lowercased() {
            if location.contains("manual") {
                return .manual
            } else if location.contains("mobile") || location.contains("app") || location.contains("nfc") {
                return .mobile
            }
        }
        
        // Default to unknown
        return .unknown
    }
    
    /// Icon for the scan type
    var scanTypeIcon: String {
        switch scanType {
        case .manual: return "person.fill"
        case .mobile: return "iphone.radiowaves.left.and.right"
        case .unknown: return "questionmark.circle"
        }
    }
    
    /// Color for the scan type
    var scanTypeColor: String {
        switch scanType {
        case .manual: return "blue"
        case .mobile: return "green"
        case .unknown: return "gray"
        }
    }
}

// MARK: - Scan Type Enum
enum ScanType: String, CaseIterable {
    case manual = "Manual"
    case mobile = "Mobile"
    case unknown = "Unknown"
}

// MARK: - Event Access Model
struct EventAccess: Codable, Identifiable {
    let id: String
    let userId: String
    let eventId: String
    let accessLevel: AccessLevel
    let grantedBy: String?
    let createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case eventId = "event_id"
        case accessLevel = "access_level"
        case grantedBy = "granted_by"
        case createdAt = "created_at"
    }
}

enum AccessLevel: String, Codable, CaseIterable {
    case admin = "admin"
    case staff = "staff"
    case viewer = "viewer"
    
    var displayName: String {
        return rawValue.capitalized
    }
}

// MARK: - Scan Result Model (Enhanced)
struct DatabaseScanResult: Codable, Identifiable {
    let id: String
    let wristbandId: String
    let nfcId: String
    let category: WristbandCategory
    let timestamp: Date
    let isValid: Bool
    let message: String
    let location: String?
    let notes: String?
    let staffId: String?
    
    // For compatibility with existing UI
    var wristband: Wristband? = nil
    
    init(wristbandId: String, nfcId: String, category: WristbandCategory, timestamp: Date, isValid: Bool, message: String, location: String? = nil, notes: String? = nil, staffId: String? = nil) {
        self.id = UUID().uuidString
        self.wristbandId = wristbandId
        self.nfcId = nfcId
        self.category = category
        self.timestamp = timestamp
        self.isValid = isValid
        self.message = message
        self.location = location
        self.notes = notes
        self.staffId = staffId
    }
}

// MARK: - Statistics Models
struct EventStats {
    let totalWristbands: Int
    let totalCheckedIn: Int
    let totalScansToday: Int
    let categoryBreakdown: [WristbandCategory: CategoryStats]
    let recentActivity: [CheckinLog]
    
    var completionPercentage: Double {
        totalWristbands > 0 ? Double(totalCheckedIn) / Double(totalWristbands) : 0
    }
    
    var checkInRate: Double {
        totalWristbands > 0 ? Double(totalCheckedIn) / Double(totalWristbands) * 100 : 0
    }
}

struct CategoryStats {
    let category: WristbandCategory
    let total: Int
    let checkedIn: Int
    
    var percentage: Double {
        total > 0 ? Double(checkedIn) / Double(total) * 100 : 0
    }
    
    var completionRate: Double {
        total > 0 ? Double(checkedIn) / Double(total) : 0
    }
}

// MARK: - API Response Models
struct SupabaseResponse<T: Codable>: Codable {
    let data: T?
    let error: SupabaseError?
}

struct SupabaseError: Codable {
    let message: String
    let details: String?
    let hint: String?
    let code: String?
}

// MARK: - Filter Models
struct WristbandFilter {
    var searchText: String = ""
    var selectedCategory: WristbandCategory? = nil
    var statusFilter: WristbandStatusFilter = .all
    var eventId: String? = nil
}

enum WristbandStatusFilter: String, CaseIterable {
    case all = "All"
    case checkedIn = "Checked In"
    case pending = "Pending"
    
    var displayName: String {
        return rawValue
    }
}

// MARK: - Time Range for Statistics
enum StatsTimeRange: String, CaseIterable {
    case today = "Today"
    case week = "This Week"
    case month = "This Month"
    case all = "All Time"
    
    var displayName: String {
        return rawValue
    }
    
    var dateRange: (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()
        
        switch self {
        case .today:
            let startOfDay = calendar.startOfDay(for: now)
            return (startOfDay, now)
        case .week:
            let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            return (startOfWeek, now)
        case .month:
            let startOfMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
            return (startOfMonth, now)
        case .all:
            return (Date.distantPast, now)
        }
    }
}
