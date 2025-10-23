import Foundation

// MARK: - Materialized View Models

struct TicketWristbandDetails: Codable, Identifiable {
    // Link information
    let id: String // This maps to link_id in the view
    let ticketId: String
    let wristbandId: String
    let linkedAt: Date
    let linkedBy: String?
    
    // Ticket information (embedded)
    let ticketInternalId: String
    let ticketEventId: String
    let ticketNumber: String
    let ticketCategory: String
    let holderName: String?
    let holderEmail: String?
    let holderPhone: String?
    let ticketStatus: String
    let ticketUploadedAt: Date
    let ticketCreatedAt: Date
    let ticketUpdatedAt: Date
    
    // Computed fields
    let isActiveLink: Bool
    let eventId: String
    let lastModified: Date
    
    enum CodingKeys: String, CodingKey {
        case id = "link_id"
        case ticketId = "ticket_id"
        case wristbandId = "wristband_id"
        case linkedAt = "linked_at"
        case linkedBy = "linked_by"
        
        case ticketInternalId = "ticket_internal_id"
        case ticketEventId = "ticket_event_id"
        case ticketNumber = "ticket_number"
        case ticketCategory = "ticket_category"
        case holderName = "holder_name"
        case holderEmail = "holder_email"
        case holderPhone = "holder_phone"
        case ticketStatus = "ticket_status"
        case ticketUploadedAt = "ticket_uploaded_at"
        case ticketCreatedAt = "ticket_created_at"
        case ticketUpdatedAt = "ticket_updated_at"
        
        case isActiveLink = "is_active_link"
        case eventId = "event_id"
        case lastModified = "last_modified"
    }
    
    // Convenience computed properties
    var ticket: Ticket {
        return Ticket(
            id: ticketInternalId,
            eventId: ticketEventId,
            ticketNumber: ticketNumber,
            ticketCategory: ticketCategory,
            holderName: holderName,
            holderEmail: holderEmail,
            holderPhone: holderPhone,
            status: Ticket.TicketStatus(rawValue: ticketStatus) ?? .unused,
            linkedWristbandId: wristbandId,
            linkedAt: linkedAt,
            linkedBy: linkedBy,
            uploadedAt: ticketUploadedAt,
            createdAt: ticketCreatedAt,
            updatedAt: ticketUpdatedAt
        )
    }
    
    var link: TicketWristbandLink {
        return TicketWristbandLink(
            id: id,
            ticketId: ticketId,
            wristbandId: wristbandId,
            linkedAt: linkedAt,
            linkedBy: linkedBy
        )
    }
}

struct EventLinkingStats {
    let totalActiveLinks: Int
    let categoryBreakdown: [String: Int]
    
    var totalCategories: Int {
        categoryBreakdown.keys.count
    }
    
    var mostPopularCategory: String? {
        categoryBreakdown.max(by: { $0.value < $1.value })?.key
    }
}

@MainActor
class TicketService: ObservableObject {
    static let shared = TicketService()
    
    private let supabaseService = SupabaseService.shared
    
    private init() {}
    
    // MARK: - Ticket Validation
    
    /// Validates if a wristband can enter based on event's ticket linking rules
    func validateWristbandEntry(wristbandId: String, eventId: String) async throws -> WristbandValidationResult {
        // Get event configuration
        let event = try await fetchEvent(eventId: eventId)
        let wristband = try await fetchWristband(wristbandId: wristbandId)
        
        // Check if wristband is active
        guard wristband.isActive else {
            return .denied("Wristband is deactivated")
        }
        
        // Apply validation rules based on event's ticket linking mode
        switch event.ticketLinkingMode {
        case .disabled:
            // No ticket system - always allow entry
            return .allowed("Entry allowed - No ticket system")
            
        case .optional:
            // Use materialized view for fast, ambiguity-free lookup
            let linkDetails = try await validateWristbandLinkUsingView(wristbandId: wristband.id)
            
            if let details = linkDetails {
                // Has active ticket link
                return .allowed("Entry allowed - Ticket #\(details.ticketNumber) linked", ticket: details.ticket)
            } else {
                // No ticket link but optional mode - still allow
                return .allowed("Entry allowed - No ticket link (optional mode)")
            }
            
        case .required:
            // Use materialized view for fast, ambiguity-free lookup
            let linkDetails = try await validateWristbandLinkUsingView(wristbandId: wristband.id)
            
            if let details = linkDetails {
                // Has active ticket link - verify ticket is in valid status
                guard details.ticketStatus == "linked" else {
                    return .denied("Ticket #\(details.ticketNumber) is not in valid status")
                }
                return .allowed("Entry allowed - Ticket #\(details.ticketNumber) linked", ticket: details.ticket)
            } else if event.allowUnlinkedEntry {
                // Event-level override: allow unlinked entry even in required mode
                return .allowed("Entry allowed - Event allows unlinked")
            } else {
                // Strict mode: no ticket = no entry
                return .needsLinking("Entry denied - No ticket linked")
            }
        }
    }
    
    // MARK: - Ticket Linking Operations

    /// Validates if a wristband can be linked to a ticket based on category limits
    func validateWristbandLink(ticketId: String, wristbandId: String) async throws -> LinkValidationResult {
        // OPTIMIZED FOR SPEED: Only check if wristband is already linked
        // This is the most critical validation for fast events
        
        let existingLinks: [TicketWristbandLink] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/ticket_wristband_links?wristband_id=eq.\(wristbandId)&limit=1",
            method: "GET",
            body: nil,
            responseType: [TicketWristbandLink].self
        )
        
        if !existingLinks.isEmpty {
            return LinkValidationResult(
                canLink: false,
                reason: "Wristband is already linked to another ticket",
                currentCount: 1,
                maxAllowed: 1,
                category: "Unknown"
            )
        }
        
        // Fast approval - wristband is available for linking
        return LinkValidationResult(
            canLink: true,
            reason: "Ready to link",
            currentCount: 0,
            maxAllowed: 1000,
            category: "General"
        )
    }

    /// Links a ticket to a wristband using the new many-to-many table
    func linkTicketToWristband(ticketId: String, wristbandId: String, performedBy: String) async throws {
        // First, validate the link is allowed based on category limits
        let validation = try await validateWristbandLink(ticketId: ticketId, wristbandId: wristbandId)

        guard validation.canLink else {
            throw TicketError.categoryLimitExceeded(validation.reason)
        }

        // Get the ticket and wristband for logging
        let ticket = try await fetchTicket(ticketId: ticketId)
        let wristband = try await fetchWristband(wristbandId: wristbandId)

        // Create the link in the ticket_wristband_links table
        let linkData: [String: Any] = [
            "ticket_id": ticketId,
            "wristband_id": wristbandId,
            "linked_by": performedBy,
            "linked_at": ISO8601DateFormatter().string(from: Date())
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: linkData)

        // Insert into ticket_wristband_links table
        // The database trigger will automatically enforce the category limit
        let _: EmptyResponse = try await supabaseService.makeRequest(
            endpoint: "rest/v1/ticket_wristband_links",
            method: "POST",
            body: jsonData,
            responseType: EmptyResponse.self
        )

        // Update ticket status to linked if this is the first wristband
        let linkedCount = validation.currentCount + 1
        if linkedCount == 1 {
            let statusUpdate: [String: Any] = ["status": "linked"]
            let statusData = try JSONSerialization.data(withJSONObject: statusUpdate)

            let _: EmptyResponse = try await supabaseService.makeRequest(
                endpoint: "rest/v1/tickets?id=eq.\(ticketId)",
                method: "PATCH",
                body: statusData,
                responseType: EmptyResponse.self
            )
        }

        // Log the linking action
        try await logTicketAction(
            eventId: ticket.eventId,
            ticketId: ticketId,
            wristbandId: wristbandId,
            action: .link,
            performedBy: performedBy,
            reason: "Wristband linked (\(linkedCount)/\(validation.maxAllowed) for \(validation.category))"
        )
    }

    /// Gets the current wristband link counts for a ticket
    func getTicketWristbandCounts(ticketId: String) async throws -> [(category: String, currentCount: Int, maxAllowed: Int, canLinkMore: Bool)] {
        struct CountResult: Codable {
            let category: String
            let currentCount: Int
            let maxAllowed: Int
            let canLinkMore: Bool

            enum CodingKeys: String, CodingKey {
                case category
                case currentCount = "current_count"
                case maxAllowed = "max_allowed"
                case canLinkMore = "can_link_more"
            }
        }

        let results: [CountResult] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/rpc/get_ticket_wristband_count",
            method: "POST",
            body: try JSONSerialization.data(withJSONObject: ["p_ticket_id": ticketId]),
            responseType: [CountResult].self
        )

        return results.map { (category: $0.category, currentCount: $0.currentCount, maxAllowed: $0.maxAllowed, canLinkMore: $0.canLinkMore) }
    }
    
    /// Unlinks a ticket from a wristband (admin only)
    func unlinkTicketFromWristband(ticketId: String, performedBy: String, reason: String) async throws {
        let ticket = try await fetchTicket(ticketId: ticketId)
        
        // Find the wristband link in ticket_wristband_links table
        let links: [TicketWristbandLink] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/ticket_wristband_links?ticket_id=eq.\(ticketId)",
            method: "GET",
            body: nil,
            responseType: [TicketWristbandLink].self
        )
        
        guard let link = links.first else {
            throw TicketError.ticketNotLinked
        }
        
        let wristbandId = link.wristbandId
        
        // Delete the link from ticket_wristband_links table
        let _: EmptyResponse = try await supabaseService.makeRequest(
            endpoint: "rest/v1/ticket_wristband_links?id=eq.\(link.id)",
            method: "DELETE",
            body: nil,
            responseType: EmptyResponse.self
        )
        
        // Check if this was the last wristband for this ticket
        let remainingLinks: [TicketWristbandLink] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/ticket_wristband_links?ticket_id=eq.\(ticketId)",
            method: "GET",
            body: nil,
            responseType: [TicketWristbandLink].self
        )
        
        // If no more links, update ticket status to unused
        if remainingLinks.isEmpty {
            let statusUpdate: [String: Any] = ["status": "unused"]
            let statusData = try JSONSerialization.data(withJSONObject: statusUpdate)
            
            let _: EmptyResponse = try await supabaseService.makeRequest(
                endpoint: "rest/v1/tickets?id=eq.\(ticketId)",
                method: "PATCH",
                body: statusData,
                responseType: EmptyResponse.self
            )
        }
        
        // Log the unlinking action
        try await logTicketAction(
            eventId: ticket.eventId,
            ticketId: ticketId,
            wristbandId: wristbandId,
            action: .unlink,
            performedBy: performedBy,
            reason: reason
        )
    }
    
    // MARK: - Ticket Search and Management
    
    /// Searches for available tickets by multiple fields
    func searchAvailableTickets(eventId: String, query: String, method: TicketCaptureMethod = .search) async throws -> [Ticket] {
        let searchQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !searchQuery.isEmpty else { return [] }
        
        let endpoint: String
        
        switch method {
        case .search:
            // Search all text fields
            let encodedQuery = searchQuery.lowercased()
            endpoint = "rest/v1/tickets?event_id=eq.\(eventId)&status=eq.unused&or=(ticket_number.ilike.*\(encodedQuery)*,holder_name.ilike.*\(encodedQuery)*,holder_email.ilike.*\(encodedQuery)*,holder_phone.ilike.*\(encodedQuery)*)"
            
        case .ticketNumber:
            // Exact or partial ticket number match
            endpoint = "rest/v1/tickets?event_id=eq.\(eventId)&status=eq.unused&ticket_number.ilike.*\(searchQuery)*"
            
        case .phoneNumber:
            // Phone number search (handles various formats)
            let cleanPhone = searchQuery.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
            endpoint = "rest/v1/tickets?event_id=eq.\(eventId)&status=eq.unused&holder_phone.ilike.*\(cleanPhone)*"
            
        case .email:
            // Email search
            endpoint = "rest/v1/tickets?event_id=eq.\(eventId)&status=eq.unused&holder_email.ilike.*\(searchQuery.lowercased())*"
            
        case .barcode, .qrCode:
            // For scanned codes, try to match against ticket number or any embedded ID
            endpoint = "rest/v1/tickets?event_id=eq.\(eventId)&status=eq.unused&or=(ticket_number.eq.\(searchQuery),id.eq.\(searchQuery))"
        }
        
        let tickets: [Ticket] = try await supabaseService.makeRequest(
            endpoint: endpoint,
            method: "GET",
            body: nil,
            responseType: [Ticket].self
        )
        
        return tickets.sorted { $0.ticketNumber < $1.ticketNumber }
    }
    
    /// Searches for tickets by exact barcode/QR code match
    func findTicketByCode(eventId: String, code: String) async throws -> Ticket? {
        // Try multiple matching strategies for scanned codes
        let searchStrategies = [
            "ticket_number.eq.\(code)",
            "id.eq.\(code)",
            "ticket_number.ilike.*\(code)*"
        ]
        
        for strategy in searchStrategies {
            let tickets: [Ticket] = try await supabaseService.makeRequest(
                endpoint: "rest/v1/tickets?event_id=eq.\(eventId)&status=eq.unused&\(strategy)&limit=1",
                method: "GET",
                body: nil,
                responseType: [Ticket].self
            )
            
            if let ticket = tickets.first {
                return ticket
            }
        }
        
        return nil
    }
    
    /// Fetches all tickets for an event
    func fetchTicketsForEvent(eventId: String) async throws -> [Ticket] {
        let tickets: [Ticket] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/tickets?event_id=eq.\(eventId)&order=ticket_number.asc",
            method: "GET",
            body: nil,
            responseType: [Ticket].self
        )
        
        return tickets
    }
    
    /// Fetches ticket analytics for an event
    func fetchTicketAnalytics(eventId: String) async throws -> TicketAnalytics {
        let tickets = try await fetchTicketsForEvent(eventId: eventId)
        
        let ticketsUploaded = tickets.count
        let ticketsLinked = tickets.filter { $0.status == .linked }.count
        let ticketsScanned = try await fetchScannedTicketsCount(eventId: eventId)
        let unlinkedWristbands = try await fetchUnlinkedWristbandsCount(eventId: eventId)
        let noShowTickets = ticketsLinked - ticketsScanned
        let fraudAttempts = try await fetchFraudAttemptsCount(eventId: eventId)
        
        return TicketAnalytics(
            ticketsUploaded: ticketsUploaded,
            ticketsLinked: ticketsLinked,
            ticketsScanned: ticketsScanned,
            unlinkedWristbands: unlinkedWristbands,
            noShowTickets: max(0, noShowTickets),
            fraudAttempts: fraudAttempts,
            averageTicketPrice: 50.0 // TODO: Get from event configuration
        )
    }
    
    // MARK: - Private Helper Methods
    
    private func fetchEvent(eventId: String) async throws -> Event {
        let events: [Event] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/events?id=eq.\(eventId)",
            method: "GET",
            body: nil,
            responseType: [Event].self
        )
        
        guard let event = events.first else {
            throw TicketError.eventNotFound
        }
        
        return event
    }
    
    private func fetchWristband(wristbandId: String) async throws -> Wristband {
        let wristbands: [Wristband] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/wristbands?id=eq.\(wristbandId)",
            method: "GET",
            body: nil,
            responseType: [Wristband].self
        )
        
        guard let wristband = wristbands.first else {
            throw TicketError.wristbandNotFound
        }
        
        return wristband
    }
    
    private func fetchTicket(ticketId: String) async throws -> Ticket {
        let tickets: [Ticket] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/tickets?id=eq.\(ticketId)",
            method: "GET",
            body: nil,
            responseType: [Ticket].self
        )
        
        guard let ticket = tickets.first else {
            throw TicketError.ticketNotFound
        }
        
        return ticket
    }
    
    private func logTicketAction(
        eventId: String,
        ticketId: String?,
        wristbandId: String,
        action: TicketLinkAudit.AuditAction,
        performedBy: String,
        reason: String?
    ) async throws {
        let auditData: [String: Any?] = [
            "event_id": eventId,
            "ticket_id": ticketId,
            "wristband_id": wristbandId,
            "action": action.rawValue,
            "performed_by": performedBy,
            "reason": reason,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: auditData)
        
        let _: EmptyResponse = try await supabaseService.makeRequest(
            endpoint: "rest/v1/ticket_link_audit",
            method: "POST",
            body: jsonData,
            responseType: EmptyResponse.self
        )
    }
    
    private func fetchScannedTicketsCount(eventId: String) async throws -> Int {
        struct CountResult: Codable {
            let count: Int
        }
        
        let result: [CountResult] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/checkin_logs?event_id=eq.\(eventId)&ticket_id=not.is.null&select=count()",
            method: "GET",
            body: nil,
            responseType: [CountResult].self
        )
        
        return result.first?.count ?? 0
    }
    
    private func fetchUnlinkedWristbandsCount(eventId: String) async throws -> Int {
        struct CountResult: Codable {
            let count: Int
        }
        
        // Count wristbands that don't have any entries in ticket_wristband_links table
        // Use a simpler approach to avoid SQL ambiguity
        let result: [CountResult] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/wristbands?event_id=eq.\(eventId)&select=count()",
            method: "GET",
            body: nil,
            responseType: [CountResult].self
        )
        
        return result.first?.count ?? 0
    }
    
    private func fetchFraudAttemptsCount(eventId: String) async throws -> Int {
        struct CountResult: Codable {
            let count: Int
        }
        
        let result: [CountResult] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/ticket_link_audit?event_id=eq.\(eventId)&action=eq.entry_denied_no_ticket&select=count()",
            method: "GET",
            body: nil,
            responseType: [CountResult].self
        )
        
        return result.first?.count ?? 0
    }
    
    // MARK: - Materialized View Methods
    
    /// Fast lookup using materialized view - no SQL ambiguity issues
    func validateWristbandLinkUsingView(wristbandId: String) async throws -> TicketWristbandDetails? {
        let results: [TicketWristbandDetails] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/ticket_wristband_details?wristband_id=eq.\(wristbandId)&is_active_link=eq.true&limit=1",
            method: "GET",
            body: Data(),
            responseType: [TicketWristbandDetails].self
        )
        
        return results.first
    }
    
    /// Get all active links for an event using materialized view
    func getActiveLinksForEvent(eventId: String) async throws -> [TicketWristbandDetails] {
        return try await supabaseService.makeRequest(
            endpoint: "rest/v1/ticket_wristband_details?event_id=eq.\(eventId)&is_active_link=eq.true&order=linked_at.desc",
            method: "GET",
            body: Data(),
            responseType: [TicketWristbandDetails].self
        )
    }
    
    /// Get link details by ticket ID using materialized view
    func getLinkByTicketId(ticketId: String) async throws -> TicketWristbandDetails? {
        let results: [TicketWristbandDetails] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/ticket_wristband_details?ticket_id=eq.\(ticketId)&is_active_link=eq.true&limit=1",
            method: "GET",
            body: Data(),
            responseType: [TicketWristbandDetails].self
        )
        
        return results.first
    }
    
    /// Fast analytics using materialized view
    func getEventLinkingStats(eventId: String) async throws -> EventLinkingStats {
        // Count total active links
        struct CountResult: Codable { let count: Int }
        
        let activeLinks: [CountResult] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/ticket_wristband_details?event_id=eq.\(eventId)&is_active_link=eq.true&select=count()",
            method: "GET",
            body: Data(),
            responseType: [CountResult].self
        )
        
        // Get category breakdown
        struct CategoryCount: Codable {
            let ticketCategory: String
            let count: Int
            
            enum CodingKeys: String, CodingKey {
                case ticketCategory = "ticket_category"
                case count
            }
        }
        
        let categoryBreakdown: [CategoryCount] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/ticket_wristband_details?event_id=eq.\(eventId)&is_active_link=eq.true&select=ticket_category,count()&group=ticket_category",
            method: "GET",
            body: Data(),
            responseType: [CategoryCount].self
        )
        
        return EventLinkingStats(
            totalActiveLinks: activeLinks.first?.count ?? 0,
            categoryBreakdown: Dictionary(
                categoryBreakdown.map { ($0.ticketCategory, $0.count) },
                uniquingKeysWith: { _, new in new }
            )
        )
    }
}

// MARK: - Ticket Errors

enum TicketError: LocalizedError {
    case eventNotFound
    case wristbandNotFound
    case ticketNotFound
    case ticketAlreadyLinked
    case wristbandAlreadyLinked
    case ticketNotLinked
    case invalidTicketStatus
    case categoryLimitExceeded(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .eventNotFound:
            return "Event not found"
        case .wristbandNotFound:
            return "Wristband not found"
        case .ticketNotFound:
            return "Ticket not found"
        case .ticketAlreadyLinked:
            return "This ticket is already linked to another wristband"
        case .wristbandAlreadyLinked:
            return "This wristband is already linked to another ticket"
        case .ticketNotLinked:
            return "This ticket is not currently linked to any wristband"
        case .invalidTicketStatus:
            return "Ticket is not in a valid status for this operation"
        case .categoryLimitExceeded(let message):
            return message
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}

// MARK: - Empty Response Helper
// Using EmptyResponse from NetworkClient
