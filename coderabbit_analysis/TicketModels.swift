import Foundation

// MARK: - Ticket Linking Models

struct Ticket: Codable, Identifiable {
    let id: String
    let eventId: String
    let ticketNumber: String
    let ticketCategory: String
    let holderName: String?
    let holderEmail: String?
    let holderPhone: String?
    let status: TicketStatus
    let linkedWristbandId: String?
    let linkedAt: Date?
    let linkedBy: String?
    let uploadedAt: Date
    let createdAt: Date
    let updatedAt: Date
    
    enum TicketStatus: String, Codable, CaseIterable {
        case unused = "unused"
        case linked = "linked"
        case cancelled = "cancelled"
        
        var displayName: String {
            switch self {
            case .unused: return "Available"
            case .linked: return "Linked"
            case .cancelled: return "Cancelled"
            }
        }
        
        var color: String {
            switch self {
            case .unused: return "blue"
            case .linked: return "green"
            case .cancelled: return "red"
            }
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case eventId = "event_id"
        case ticketNumber = "ticket_number"
        case ticketCategory = "ticket_category"
        case holderName = "holder_name"
        case holderEmail = "holder_email"
        case holderPhone = "holder_phone"
        case status
        case linkedWristbandId = "linked_wristband_id"
        case linkedAt = "linked_at"
        case linkedBy = "linked_by"
        case uploadedAt = "uploaded_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Ticket Capture Methods

enum TicketCaptureMethod: String, CaseIterable, Codable {
    case search = "search"
    case barcode = "barcode"
    case qrCode = "qr_code"
    case phoneNumber = "phone_number"
    case email = "email"
    case ticketNumber = "ticket_number"
    
    var displayName: String {
        switch self {
        case .search: return "Search All Fields"
        case .barcode: return "Scan Barcode"
        case .qrCode: return "Scan QR Code"
        case .phoneNumber: return "Phone Number"
        case .email: return "Email Address"
        case .ticketNumber: return "Ticket Number"
        }
    }
    
    var icon: String {
        switch self {
        case .search: return "magnifyingglass"
        case .barcode: return "barcode"
        case .qrCode: return "qrcode"
        case .phoneNumber: return "phone"
        case .email: return "envelope"
        case .ticketNumber: return "number"
        }
    }
    
    var requiresCamera: Bool {
        switch self {
        case .barcode, .qrCode: return true
        default: return false
        }
    }
}

// MARK: - Ticket Linking Preferences

struct TicketLinkingPreferences: Codable {
    var primaryCaptureMethod: TicketCaptureMethod
    var enabledMethods: [TicketCaptureMethod]
    var autoSwitchOnFailure: Bool
    var showMethodSelector: Bool
    
    static let `default` = TicketLinkingPreferences(
        primaryCaptureMethod: .search,
        enabledMethods: [.search, .ticketNumber, .phoneNumber, .email, .barcode, .qrCode],
        autoSwitchOnFailure: true,
        showMethodSelector: false
    )
}

// MARK: - Enhanced Event Model
// Note: TicketLinkingMode is defined in DatabaseModels.swift to avoid duplication

// MARK: - Wristband Validation Result

struct WristbandValidationResult {
    let canEnter: Bool
    let reason: String
    let ticketId: String?
    let requiresLinking: Bool
    let ticket: Ticket?
    
    static func allowed(_ reason: String, ticket: Ticket? = nil) -> WristbandValidationResult {
        WristbandValidationResult(
            canEnter: true,
            reason: reason,
            ticketId: ticket?.id,
            requiresLinking: false,
            ticket: ticket
        )
    }
    
    static func denied(_ reason: String) -> WristbandValidationResult {
        WristbandValidationResult(
            canEnter: false,
            reason: reason,
            ticketId: nil,
            requiresLinking: false,
            ticket: nil
        )
    }
    
    static func needsLinking(_ reason: String) -> WristbandValidationResult {
        WristbandValidationResult(
            canEnter: false,
            reason: reason,
            ticketId: nil,
            requiresLinking: true,
            ticket: nil
        )
    }
}

// MARK: - Ticket Link Audit

struct TicketLinkAudit: Codable, Identifiable {
    let id: String
    let eventId: String
    let ticketId: String?
    let wristbandId: String
    let action: AuditAction
    let performedBy: String
    let reason: String?
    let timestamp: Date
    let metadata: [String: String]?
    
    enum AuditAction: String, Codable {
        case link = "link"
        case unlink = "unlink"
        case linkAttemptFailed = "link_attempt_failed"
        case entryAllowedNoTicket = "entry_allowed_no_ticket"
        case entryDeniedNoTicket = "entry_denied_no_ticket"
        
        var displayName: String {
            switch self {
            case .link: return "Linked"
            case .unlink: return "Unlinked"
            case .linkAttemptFailed: return "Link Failed"
            case .entryAllowedNoTicket: return "Entry Allowed (No Ticket)"
            case .entryDeniedNoTicket: return "Entry Denied (No Ticket)"
            }
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case eventId = "event_id"
        case ticketId = "ticket_id"
        case wristbandId = "wristband_id"
        case action
        case performedBy = "performed_by"
        case reason
        case timestamp
        case metadata
    }
}

// MARK: - Ticket Upload Tracking

struct TicketUpload: Codable, Identifiable {
    let id: String
    let eventId: String
    let uploadedBy: String
    let filename: String
    let totalTickets: Int
    let successfulImports: Int
    let failedImports: Int
    let uploadTimestamp: Date
    let metadata: [String: String]?
    
    enum CodingKeys: String, CodingKey {
        case id
        case eventId = "event_id"
        case uploadedBy = "uploaded_by"
        case filename
        case totalTickets = "total_tickets"
        case successfulImports = "successful_imports"
        case failedImports = "failed_imports"
        case uploadTimestamp = "upload_timestamp"
        case metadata
    }
}

// MARK: - Enhanced Scan Result

enum EnhancedScanResult {
    case valid(String, ticket: Ticket? = nil)
    case invalid(String)
    case requiresLinking(wristbandId: String, reason: String)
    case alreadyUsed(ticket: Ticket, lastEntry: Date)
    case expired(ticket: Ticket)
    case counterfeit(String)
    
    var isSuccess: Bool {
        switch self {
        case .valid: return true
        default: return false
        }
    }
    
    var displayMessage: String {
        switch self {
        case .valid(let message, _): return message
        case .invalid(let message): return message
        case .requiresLinking(_, let reason): return reason
        case .alreadyUsed(let ticket, _): return "Ticket \(ticket.ticketNumber) already used"
        case .expired(let ticket): return "Ticket \(ticket.ticketNumber) has expired"
        case .counterfeit(let message): return message
        }
    }
    
    var statusColor: String {
        switch self {
        case .valid: return "green"
        case .requiresLinking: return "orange"
        case .invalid, .alreadyUsed, .expired, .counterfeit: return "red"
        }
    }
    
    var statusIcon: String {
        switch self {
        case .valid: return "checkmark.circle.fill"
        case .requiresLinking: return "link.circle"
        case .invalid, .counterfeit: return "xmark.circle.fill"
        case .alreadyUsed: return "exclamationmark.triangle.fill"
        case .expired: return "clock.fill"
        }
    }
}

// MARK: - Ticket Analytics

struct TicketAnalytics {
    let ticketsUploaded: Int
    let ticketsLinked: Int
    let ticketsScanned: Int
    let unlinkedWristbands: Int
    let noShowTickets: Int
    let fraudAttempts: Int
    let averageTicketPrice: Double
    
    var linkingRate: Double {
        guard ticketsUploaded > 0 else { return 0 }
        return Double(ticketsLinked) / Double(ticketsUploaded)
    }
    
    var attendanceRate: Double {
        guard ticketsLinked > 0 else { return 0 }
        return Double(ticketsScanned) / Double(ticketsLinked)
    }
    
    var revenueProtection: Double {
        Double(fraudAttempts) * averageTicketPrice
    }
    
    var utilizationRate: Double {
        guard ticketsUploaded > 0 else { return 0 }
        return Double(ticketsScanned) / Double(ticketsUploaded)
    }
}
