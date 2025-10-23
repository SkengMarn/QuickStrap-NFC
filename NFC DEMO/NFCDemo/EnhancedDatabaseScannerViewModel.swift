import SwiftUI
import CoreNFC
import Combine

/// Enhanced DatabaseScannerViewModel that supports multi-series events
/// while maintaining backwards compatibility with existing single events
extension DatabaseScannerViewModel {
    
    // MARK: - Enhanced NFC Processing with Multi-Series Support
    
    /// Enhanced processNFC method that uses the new verification service
    /// Maintains backwards compatibility while adding series support
    func processNFCEnhanced(_ nfcId: String) async {
        print("🔍 [ENHANCED] Starting enhanced NFC processing for ID: \(nfcId)")
        
        guard let supabaseService = supabaseService else {
            print("❌ [ENHANCED] SupabaseService not available")
            await MainActor.run {
                scanState = .error
                statusMessage = "Service not available"
                isScanning = false
            }
            return
        }
        
        guard let eventId = supabaseService.currentEvent?.id else {
            print("❌ [ENHANCED] No event selected")
            await MainActor.run {
                scanState = .error
                statusMessage = "No event selected"
                isScanning = false
            }
            return
        }
        
        print("✅ [ENHANCED] Processing for event: \(eventId)")
        
        await MainActor.run {
            scanState = .scanning
            statusMessage = "Checking wristband access..."
        }
        
        // Use the enhanced verification service
        let verificationResult = await EnhancedWristbandVerificationService.shared.verifyWristbandAccess(
            nfcId: nfcId,
            eventId: eventId,
            supabaseService: supabaseService
        )
        
        switch verificationResult {
        case .directAccess(let wristband):
            print("✅ [ENHANCED] Direct access granted")
            await processVerifiedWristband(nfcId: nfcId, wristband: wristband, accessType: .direct)
            
        case .seriesAccess(let wristband, let seriesName):
            print("✅ [ENHANCED] Series access granted via: \(seriesName)")
            await processVerifiedWristband(nfcId: nfcId, wristband: wristband, accessType: .series(seriesName))
            
        case .noAccess:
            print("❌ [ENHANCED] No access found")
            await MainActor.run {
                scanState = .error
                statusMessage = "Access denied"
                currentScanResult = .invalid("No access to this event")
                isScanning = false
            }
            
        case .error(let errorMessage):
            print("❌ [ENHANCED] Verification error: \(errorMessage)")
            await MainActor.run {
                scanState = .error
                statusMessage = "Verification failed"
                currentScanResult = .invalid(errorMessage)
                isScanning = false
            }
        }
    }
    
    // MARK: - Process Verified Wristband
    
    private func processVerifiedWristband(
        nfcId: String,
        wristband: Wristband,
        accessType: AccessType
    ) async {
        print("🔍 [ENHANCED] Processing verified wristband with \(accessType) access")
        
        // Continue with existing gate enforcement logic
        await processGateEnforcementEnhanced(nfcId: nfcId, wristband: wristband, accessType: accessType)
    }
    
    // MARK: - Enhanced Gate Enforcement
    
    private func processGateEnforcementEnhanced(
        nfcId: String,
        wristband: Wristband,
        accessType: AccessType
    ) async {
        guard let gateId = gateBindingService.currentGate?.id else {
            await MainActor.run {
                scanState = .error
                statusMessage = "No gate detected"
            }
            return
        }
        
        do {
            print("🚪 [ENHANCED] Checking gate enforcement for category: \(wristband.category.name)")
            
            let result = try await gateBindingService.evaluateCheckin(
                wristbandId: nfcId,
                categoryName: wristband.category.name,
                gateId: gateId
            )
            
            await MainActor.run {
                lastPolicyResult = result
            }
            
            if result.allowed {
                print("✅ [ENHANCED] Gate allows entry")
                await processTicketLinkingEnhanced(
                    nfcId: nfcId,
                    wristband: wristband,
                    gateResult: result,
                    accessType: accessType
                )
            } else {
                print("❌ [ENHANCED] Gate denies entry - \(result.reason.displayMessage)")
                
                await MainActor.run {
                    scanState = .blocked
                    statusMessage = result.reason.displayMessage
                    currentScanResult = .invalid(result.reason.displayMessage)
                    isScanning = false
                }
                
                // Log the failed check-in with access type info
                await logCheckinEnhanced(
                    wristbandId: wristband.id,
                    gateId: gateId,
                    status: "denied",
                    ticketId: wristband.linkedTicketId,
                    accessType: accessType
                )
            }
            
            // Update analytics
            await updateAnalytics(wristband: wristband, result: result, accessType: accessType)
            
        } catch {
            print("❌ [ENHANCED] Gate evaluation error: \(error)")
            await MainActor.run {
                scanState = .error
                statusMessage = "Gate check failed"
                isScanning = false
            }
        }
    }
    
    // MARK: - Enhanced Ticket Linking
    
    private func processTicketLinkingEnhanced(
        nfcId: String,
        wristband: Wristband,
        gateResult: CheckinPolicyResult,
        accessType: AccessType
    ) async {
        guard let event = supabaseService?.currentEvent else { return }
        let eventId = event.id
        
        print("🎫 [ENHANCED] Checking recent entries and ticket linking requirements")
        
        // Check for recent entries (re-entry detection)
        await checkForRecentEntryEnhanced(
            wristbandId: wristband.id,
            eventId: eventId,
            nfcId: nfcId,
            wristband: wristband,
            gateResult: gateResult,
            accessType: accessType
        )
    }
    
    private func checkForRecentEntryEnhanced(
        wristbandId: String,
        eventId: String,
        nfcId: String,
        wristband: Wristband,
        gateResult: CheckinPolicyResult,
        accessType: AccessType
    ) async {
        do {
            // Check for recent check-ins within the last 30 minutes
            let thirtyMinutesAgo = Calendar.current.date(byAdding: .minute, value: -30, to: Date()) ?? Date()
            let isoFormatter = ISO8601DateFormatter()
            
            print("🔍 [ENHANCED] Checking for recent entries since \(isoFormatter.string(from: thirtyMinutesAgo))")
            
            guard let supabaseService = supabaseService else {
                await processTicketLinkingRequirementsEnhanced(
                    nfcId: nfcId,
                    wristband: wristband,
                    gateResult: gateResult,
                    accessType: accessType
                )
                return
            }
            
            // Build query for recent check-ins
            let timestampValue = isoFormatter.string(from: thirtyMinutesAgo)
            var components = URLComponents()
            components.queryItems = [
                URLQueryItem(name: "wristband_id", value: "eq.\(wristbandId)"),
                URLQueryItem(name: "event_id", value: "eq.\(eventId)"),
                URLQueryItem(name: "timestamp", value: "gte.\(timestampValue)"),
                URLQueryItem(name: "status", value: "eq.success"),
                URLQueryItem(name: "order", value: "timestamp.desc"),
                URLQueryItem(name: "limit", value: "1")
            ]
            let queryString = components.percentEncodedQuery ?? ""

            let recentCheckins: [CheckinLog] = try await supabaseService.makeRequest(
                endpoint: "rest/v1/checkin_logs?\(queryString)",
                method: "GET",
                body: nil,
                responseType: [CheckinLog].self
            )
            
            if let lastCheckin = recentCheckins.first {
                print("🔄 [ENHANCED] Recent entry found - This is RE-ENTRY")
                await handleReEntryEnhanced(
                    lastCheckin: lastCheckin,
                    nfcId: nfcId,
                    wristband: wristband,
                    accessType: accessType
                )
            } else {
                print("✅ [ENHANCED] No recent entries found - This is FIRST ENTRY")
                await processTicketLinkingRequirementsEnhanced(
                    nfcId: nfcId,
                    wristband: wristband,
                    gateResult: gateResult,
                    accessType: accessType
                )
            }
            
        } catch {
            print("❌ [ENHANCED] Failed to check recent entries: \(error)")
            await processTicketLinkingRequirementsEnhanced(
                nfcId: nfcId,
                wristband: wristband,
                gateResult: gateResult,
                accessType: accessType
            )
        }
    }
    
    private func handleReEntryEnhanced(
        lastCheckin: CheckinLog,
        nfcId: String,
        wristband: Wristband,
        accessType: AccessType
    ) async {
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        let lastEntryTime = timeFormatter.string(from: lastCheckin.timestamp)
        
        let accessMessage = accessType.reentryMessage
        
        await MainActor.run {
            scanState = .success
            statusMessage = "Re-entry permitted"
            currentScanResult = .valid("Re-entry permitted \(accessMessage) (Last entry: \(lastEntryTime))", ticket: nil)
            isScanning = false
            lastScanTime = Date()
            
            // Add to recent scans with access type info
            let scanResult = DatabaseScanResult(
                wristbandId: nfcId,
                nfcId: nfcId,
                category: wristband.category,
                timestamp: Date(),
                isValid: true,
                message: "Re-entry permitted \(accessMessage)"
            )
            recentScans.insert(scanResult, at: 0)
            if recentScans.count > 10 {
                recentScans.removeLast()
            }
        }
        
        print("✅ [ENHANCED] Re-entry permitted with \(accessType) access")
    }
    
    private func processTicketLinkingRequirementsEnhanced(
        nfcId: String,
        wristband: Wristband,
        gateResult: CheckinPolicyResult,
        accessType: AccessType
    ) async {
        guard let event = supabaseService?.currentEvent else { return }
        
        print("🎫 [ENHANCED] Checking ticket linking requirements")
        
        if event.ticketLinkingMode == .required {
            if wristband.linkedTicketId != nil {
                print("✅ [ENHANCED] Wristband already linked to ticket")
                await completeSuccessfulEntryEnhanced(
                    nfcId: nfcId,
                    wristband: wristband,
                    gateResult: gateResult,
                    accessType: accessType
                )
            } else {
                print("⚠️ [ENHANCED] Ticket linking required but not linked")
                await MainActor.run {
                    let linkingResult: EnhancedScanResult
                    switch accessType {
                    case .direct:
                        linkingResult = .requiresLinking(wristbandId: nfcId, reason: "Link ticket to continue")
                    case .series(let seriesName):
                        linkingResult = .requiresSeriesLinking(wristbandId: nfcId, seriesName: seriesName, reason: "Link ticket to continue")
                    }
                    
                    currentScanResult = linkingResult
                    pendingWristbandId = nfcId
                    showingTicketLinking = true
                    scanState = .ready
                    statusMessage = "Link ticket to continue"
                    isScanning = false
                }
            }
        } else {
            print("✅ [ENHANCED] Ticket linking not required")
            await completeSuccessfulEntryEnhanced(
                nfcId: nfcId,
                wristband: wristband,
                gateResult: gateResult,
                accessType: accessType
            )
        }
    }
    
    // MARK: - Complete Successful Entry
    
    private func completeSuccessfulEntryEnhanced(
        nfcId: String,
        wristband: Wristband,
        gateResult: CheckinPolicyResult,
        accessType: AccessType
    ) async {
        guard let gateId = gateBindingService.currentGate?.id else { return }
        
        let accessMessage = accessType.successMessage
        
        await MainActor.run {
            scanState = .success
            statusMessage = "Entry allowed"
            
            switch accessType {
            case .direct:
                currentScanResult = .valid("Entry allowed", ticket: nil)
            case .series(let seriesName):
                currentScanResult = .validSeries("Entry allowed", seriesName: seriesName, ticket: nil)
            }
            
            todayScans += 1
            isScanning = false
        }
        
        // Log the successful check-in with access type
        await logCheckinEnhanced(
            wristbandId: wristband.id,
            gateId: gateId,
            status: "success",
            ticketId: wristband.linkedTicketId,
            accessType: accessType
        )
        
        print("✅ [ENHANCED] Check-in logged successfully with \(accessType) access")
    }
    
    // MARK: - Enhanced Logging
    
    private func logCheckinEnhanced(
        wristbandId: String,
        gateId: String,
        status: String,
        ticketId: String?,
        accessType: AccessType
    ) async {
        guard let supabaseService = supabaseService,
              let eventId = supabaseService.currentEvent?.id,
              let staffId = supabaseService.currentUser?.id else {
            print("❌ [ENHANCED] Missing required data for logging")
            return
        }
        
        do {
            var checkinData: [String: Any] = [
                "event_id": eventId,
                "wristband_id": wristbandId,
                "gate_id": gateId,
                "staff_id": staffId,
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "status": status,
                "ticket_id": ticketId as Any,
                "access_type": accessType.logValue
            ]
            
            // Add series information if applicable
            if case .series(let seriesName) = accessType {
                checkinData["series_name"] = seriesName
            }
            
            let jsonData = try JSONSerialization.data(withJSONObject: checkinData)
            
            let _: EmptyResponse = try await supabaseService.makeRequest(
                endpoint: "rest/v1/checkin_logs",
                method: "POST",
                body: jsonData,
                responseType: EmptyResponse.self
            )
            
            print("✅ [ENHANCED] Check-in logged with status: \(status), access: \(accessType)")
            
        } catch {
            print("❌ [ENHANCED] Failed to log check-in: \(error)")
        }
    }
    
    // MARK: - Analytics Update
    
    private func updateAnalytics(
        wristband: Wristband,
        result: CheckinPolicyResult,
        accessType: AccessType
    ) async {
        await MainActor.run {
            lastScanTime = Date()
            
            let accessMessage = accessType.displayMessage
            
            // Add to recent scans with access type info
            let scanResult = DatabaseScanResult(
                wristbandId: wristband.nfcId,
                nfcId: wristband.nfcId,
                category: wristband.category,
                timestamp: Date(),
                isValid: result.allowed,
                message: result.allowed ? "Entry allowed \(accessMessage)" : result.reason.displayMessage
            )
            recentScans.insert(scanResult, at: 0)
            if recentScans.count > 10 {
                recentScans.removeLast()
            }
            
            totalScans += 1
            updateSuccessRate()
        }
    }
}

// MARK: - Access Type Enum

enum AccessType {
    case direct
    case series(String)
    
    var displayMessage: String {
        switch self {
        case .direct:
            return ""
        case .series(let seriesName):
            return "(via \(seriesName))"
        }
    }
    
    var successMessage: String {
        switch self {
        case .direct:
            return "Entry allowed"
        case .series(let seriesName):
            return "Entry allowed via \(seriesName)"
        }
    }
    
    var reentryMessage: String {
        switch self {
        case .direct:
            return ""
        case .series(let seriesName):
            return "(via \(seriesName))"
        }
    }
    
    var logValue: String {
        switch self {
        case .direct:
            return "direct"
        case .series:
            return "series"
        }
    }
}
