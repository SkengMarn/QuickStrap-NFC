import Foundation

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
            if let ticketId = wristband.linkedTicketId {
                // Has ticket link - verify ticket is valid
                let ticket = try await fetchTicket(ticketId: ticketId)
                return .allowed("Entry allowed - Ticket linked", ticket: ticket)
            } else {
                // No ticket link but optional mode - still allow
                return .allowed("Entry allowed - No ticket link (optional mode)")
            }
            
        case .required:
            if let ticketId = wristband.linkedTicketId {
                // Has ticket link - verify ticket is valid
                let ticket = try await fetchTicket(ticketId: ticketId)
                guard ticket.status == .linked else {
                    return .denied("Ticket is not in valid status")
                }
                return .allowed("Entry allowed - Ticket verified", ticket: ticket)
            } else if wristband.ticketLinkRequired {
                // Wristband specifically requires link but doesn't have one
                return .needsLinking("Entry denied - Ticket link required")
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
    
    /// Links a ticket to a wristband
    func linkTicketToWristband(ticketId: String, wristbandId: String, performedBy: String) async throws {
        // Verify ticket is available for linking
        let ticket = try await fetchTicket(ticketId: ticketId)
        guard ticket.status == .unused else {
            throw TicketError.ticketAlreadyLinked
        }
        
        // Verify wristband is not already linked
        let wristband = try await fetchWristband(wristbandId: wristbandId)
        guard wristband.linkedTicketId == nil else {
            throw TicketError.wristbandAlreadyLinked
        }
        
        // Perform the linking
        let linkingData: [String: Any] = [
            "linked_wristband_id": wristbandId,
            "linked_at": ISO8601DateFormatter().string(from: Date()),
            "linked_by": performedBy,
            "status": "linked"
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: linkingData)
        
        let _: EmptyResponse = try await supabaseService.makeRequest(
            endpoint: "rest/v1/tickets?id=eq.\(ticketId)",
            method: "PATCH",
            body: jsonData,
            responseType: EmptyResponse.self
        )
        
        // Log the linking action
        try await logTicketAction(
            eventId: ticket.eventId,
            ticketId: ticketId,
            wristbandId: wristbandId,
            action: .link,
            performedBy: performedBy,
            reason: "Manual ticket linking"
        )
    }
    
    /// Unlinks a ticket from a wristband (admin only)
    func unlinkTicketFromWristband(ticketId: String, performedBy: String, reason: String) async throws {
        let ticket = try await fetchTicket(ticketId: ticketId)
        guard let wristbandId = ticket.linkedWristbandId else {
            throw TicketError.ticketNotLinked
        }
        
        // Perform the unlinking
        let unlinkingData: [String: Any?] = [
            "linked_wristband_id": nil,
            "linked_at": nil,
            "linked_by": nil,
            "status": "unused"
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: unlinkingData)
        
        let _: EmptyResponse = try await supabaseService.makeRequest(
            endpoint: "rest/v1/tickets?id=eq.\(ticketId)",
            method: "PATCH",
            body: jsonData,
            responseType: EmptyResponse.self
        )
        
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
        
        let result: [CountResult] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/wristbands?event_id=eq.\(eventId)&linked_ticket_id=is.null&select=count()",
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
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}

// MARK: - Empty Response Helper
// Using EmptyResponse from NetworkClient
