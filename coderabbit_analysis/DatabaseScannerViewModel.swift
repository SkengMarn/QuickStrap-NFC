import SwiftUI
import CoreNFC
import Combine

@MainActor
class DatabaseScannerViewModel: NSObject, ObservableObject {
    @Published var scanState: ScanState = .ready
    @Published var statusMessage = "Ready to scan"
    @Published var detailMessage = ""
    @Published var isScanning = false
    @Published var lastPolicyResult: CheckinPolicyResult?
    @Published var locationConfidence: Double = 0.0
    @Published var currentGate: Gate?
    @Published var recentScans: [DatabaseScanResult] = []
    @Published var isContinuousMode = false
    @Published var todayScans = 0
    @Published var totalScans = 0
    @Published var successRate: Double = 0.0
    @Published var lastScanTime: Date?
    @Published var showingManualCheckin = false
    @Published var manualWristbandId = ""
    @Published var showingBulkCheckin = false
    
    // Ticket Linking Properties
    @Published var showingTicketLinking = false
    @Published var pendingWristbandId: String?
    @Published var currentScanResult: EnhancedScanResult?
    @Published var availableTickets: [Ticket] = []
    @Published var selectedTicket: Ticket?
    @Published var ticketSearchQuery = ""
    @Published var isLinkingTicket = false
    
    private var gateBindingService = GateBindingService.shared
    // private var locationManager = LocationManager.shared
    private var supabaseService: SupabaseService?
    
    // Public getter for supabaseService
    var currentSupabaseService: SupabaseService? {
        return supabaseService
    }
    private var eventData: EventDataManager?
    private var nfcSession: NFCNDEFReaderSession?
    private var cancellables = Set<AnyCancellable>()
    private var ticketService = TicketService.shared
    
    enum ScanState {
        case ready, scanning, success, error, blocked
    }
    
    var backgroundColors: [Color] {
        switch scanState {
        case .ready: return [.black, .blue.opacity(0.3)]
        case .scanning: return [.black, .orange.opacity(0.4)]
        case .success: return [.black, .green.opacity(0.4)]
        case .error, .blocked: return [.black, .red.opacity(0.4)]
        }
    }
    
    var statusIcon: String {
        switch scanState {
        case .ready: return "nfc"
        case .scanning: return "wave.3.right.circle"
        case .success: return "checkmark.circle.fill"
        case .error, .blocked: return "xmark.circle.fill"
        }
    }
    
    var statusColor: Color {
        switch scanState {
        case .ready: return .blue
        case .scanning: return .orange
        case .success: return .green
        case .error, .blocked: return .red
        }
    }
    
    var cardBorderColor: Color {
        switch scanState {
        case .ready: return .gray
        case .scanning: return .orange
        case .success: return .green
        case .error, .blocked: return .red
        }
    }
    
    func setup(nfcReader: NFCReader, supabaseService: SupabaseService, eventData: EventDataManager) {
        self.supabaseService = supabaseService
        self.eventData = eventData
        // locationManager.startUpdating() // LocationManager not available
        
        Task {
            if let eventId = supabaseService.currentEvent?.id {
                try await gateBindingService.detectNearbyGates(eventId: eventId)
                await loadStats()
            }
        }
    }
    
    func cleanup() {
        nfcSession?.invalidate()
    }
    
    func startScan() {
        guard NFCNDEFReaderSession.readingAvailable else { return }
        
        isScanning = true
        scanState = .scanning
        statusMessage = "Hold iPhone near wristband"
        
        nfcSession = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: !isContinuousMode)
        nfcSession?.begin()
    }
    
    func stopScan() {
        nfcSession?.invalidate()
        isScanning = false
        scanState = .ready
        statusMessage = "Ready to scan"
    }
    
    func stopScanning() {
        stopScan()
    }
    
    func startContinuousScanning() {
        isContinuousMode = true
        startScan()
    }
    
    func performSingleScan() {
        isContinuousMode = false
        startScan()
    }
    
    func toggleContinuousMode() {
        isContinuousMode.toggle()
        if !isContinuousMode && isScanning {
            stopScan()
        }
    }
    
    private func processNFC(_ nfcId: String) async {
        print("🔍 [DEBUG] Step 1: Starting NFC processing for ID: \(nfcId)")
        
        guard let supabaseService = supabaseService else {
            print("❌ [DEBUG] Step 1 FAILED: SupabaseService not available")
            await MainActor.run {
                scanState = .error
                statusMessage = "Service not available"
                isScanning = false
            }
            return
        }
        
        guard let eventId = supabaseService.currentEvent?.id else {
            print("❌ [DEBUG] Step 1 FAILED: No event selected")
            await MainActor.run {
                scanState = .error
                statusMessage = "No event selected"
                isScanning = false
            }
            return
        }
        
        print("✅ [DEBUG] Step 1 SUCCESS: Processing for event: \(eventId)")
        
        await MainActor.run {
            scanState = .scanning
            statusMessage = "Checking wristband..."
        }
        
        do {
            // Step 2: Validate Wristband - Query wristbands table
            print("🔍 [DEBUG] Step 2: Looking up wristband: \(nfcId)")
            
            // Build query with proper URL encoding to prevent injection
            var components = URLComponents()
            components.queryItems = [
                URLQueryItem(name: "nfc_id", value: "eq.\(nfcId)")
            ]
            let queryString = components.percentEncodedQuery ?? ""

            let wristbands: [Wristband] = try await supabaseService.makeRequest(
                endpoint: "rest/v1/wristbands?\(queryString)",
                method: "GET",
                body: nil,
                responseType: [Wristband].self
            )
            
            guard let wristband = wristbands.first else {
                print("❌ [DEBUG] Step 2 FAILED: Wristband not found (possibly counterfeit or unregistered)")
                await MainActor.run {
                    scanState = .error
                    statusMessage = "Wristband not found"
                    currentScanResult = .invalid("Invalid wristband (possibly counterfeit or unregistered)")
                    isScanning = false
                }
                return
            }
            
            // Step 3: Check Event Context - Validate wristband belongs to current event
            print("🔍 [DEBUG] Step 3: Checking event context - Wristband event: \(wristband.eventId), Scanner event: \(eventId)")
            
            guard wristband.eventId == eventId else {
                print("❌ [DEBUG] Step 3 FAILED: Wristband belongs to different event")
                await MainActor.run {
                    scanState = .error
                    statusMessage = "Wrong event"
                    currentScanResult = .invalid("Wristband belongs to a different event")
                    isScanning = false
                }
                return
            }
            
            // Step 4: Determine Wristband Category
            print("✅ [DEBUG] Step 4: Wristband category determined: \(wristband.category.name)")
            
            // Step 5: Gate Enforcement Check
            await processGateEnforcement(nfcId: nfcId, wristband: wristband)
            
        } catch {
            print("❌ [DEBUG] CRITICAL ERROR in processNFC: \(error)")
            print("❌ [DEBUG] Error details: \(String(describing: error))")
            
            // Log the full error for debugging
            if let nsError = error as NSError? {
                print("❌ [DEBUG] NSError domain: \(nsError.domain), code: \(nsError.code)")
                print("❌ [DEBUG] NSError userInfo: \(nsError.userInfo)")
            }
            
            await MainActor.run {
                scanState = .error
                statusMessage = "System error: \(error.localizedDescription)"
                isScanning = false
                
                // Add failed scan to recent scans for debugging
                let scanResult = DatabaseScanResult(
                    wristbandId: nfcId,
                    nfcId: nfcId,
                    category: WristbandCategory(name: "Unknown"),
                    timestamp: Date(),
                    isValid: false,
                    message: "Error: \(error.localizedDescription)"
                )
                recentScans.insert(scanResult, at: 0)
                if recentScans.count > 10 {
                    recentScans.removeLast()
                }
            }
        }
    }
    
    private func processGateEnforcement(nfcId: String, wristband: Wristband) async {
        guard let gateId = gateBindingService.currentGate?.id else {
            await MainActor.run {
                scanState = .error
                statusMessage = "No gate detected"
            }
            return
        }
        
        do {
            // Step 5: Gate Enforcement Check
            print("🚪 [DEBUG] Step 5: Checking gate enforcement for category: \(wristband.category.name)")
            
            let result = try await gateBindingService.evaluateCheckin(
                wristbandId: nfcId,
                categoryName: wristband.category.name,
                gateId: gateId
            )
            
            await MainActor.run {
                lastPolicyResult = result
            }
            
            if result.allowed {
                print("✅ [DEBUG] Step 5 SUCCESS: Gate allows entry")
                
                // Step 6: Check Ticket Linking Requirements
                await processTicketLinking(nfcId: nfcId, wristband: wristband, gateResult: result)
            } else {
                // Step 5 FAILED: Gate denies entry
                print("❌ [DEBUG] Step 5 FAILED: Gate denies entry - \(result.reason.displayMessage)")
                
                await MainActor.run {
                    scanState = .blocked
                    statusMessage = result.reason.displayMessage
                    currentScanResult = .invalid(result.reason.displayMessage)
                    isScanning = false
                }
                
                // Step 7: Log the failed check-in
                await logCheckin(
                    wristbandId: wristband.id,
                    gateId: gateId,
                    status: "denied",
                    ticketId: wristband.linkedTicketId
                )
            }
            
            // Update analytics after processing
            await MainActor.run {
                lastScanTime = Date()
                
                // Add to recent scans for analytics
                let scanResult = DatabaseScanResult(
                    wristbandId: nfcId,
                    nfcId: nfcId,
                    category: wristband.category,
                    timestamp: Date(),
                    isValid: result.allowed,
                    message: result.allowed ? "Entry allowed" : result.reason.displayMessage
                )
                recentScans.insert(scanResult, at: 0)
                if recentScans.count > 10 {
                    recentScans.removeLast()
                }
                
                totalScans += 1
                updateSuccessRate()
            }
        } catch {
            print("❌ [DEBUG] Gate evaluation error: \(error)")
            await MainActor.run {
                scanState = .error
                statusMessage = "Gate check failed"
                isScanning = false
            }
        }
    }
    
    // MARK: - Step 6: Check for Recent Entry (Re-entry Detection)
    private func processTicketLinking(nfcId: String, wristband: Wristband, gateResult: CheckinPolicyResult) async {
        guard let event = supabaseService?.currentEvent else { return }
        let eventId = event.id
        
        print("🎫 [DEBUG] Step 6: Checking recent entries and ticket linking requirements")
        
        // First check for recent entries (re-entry detection)
        await checkForRecentEntry(wristbandId: wristband.id, eventId: eventId, nfcId: nfcId, wristband: wristband, gateResult: gateResult)
    }
    
    private func checkForRecentEntry(wristbandId: String, eventId: String, nfcId: String, wristband: Wristband, gateResult: CheckinPolicyResult) async {
        do {
            // Check for recent check-ins within the last 30 minutes
            let thirtyMinutesAgo = Calendar.current.date(byAdding: .minute, value: -30, to: Date()) ?? Date()
            let isoFormatter = ISO8601DateFormatter()
            
            print("🔍 [DEBUG] Step 6A: Checking for recent entries since \(isoFormatter.string(from: thirtyMinutesAgo))")
            
            guard let supabaseService = supabaseService else {
                print("❌ [DEBUG] Step 6A ERROR: SupabaseService not available")
                await processTicketLinkingRequirements(nfcId: nfcId, wristband: wristband, gateResult: gateResult)
                return
            }
            
            // Build query with proper URL encoding to prevent injection
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
                print("🔄 [DEBUG] Step 6A: Recent entry found at \(lastCheckin.timestamp) - This is RE-ENTRY")
                await handleReEntry(lastCheckin: lastCheckin, nfcId: nfcId, wristband: wristband)
            } else {
                print("✅ [DEBUG] Step 6A: No recent entries found - This is FIRST ENTRY")
                await processTicketLinkingRequirements(nfcId: nfcId, wristband: wristband, gateResult: gateResult)
            }
            
        } catch {
            print("❌ [DEBUG] Step 6A ERROR: Failed to check recent entries: \(error)")
            // If we can't check, proceed as normal entry
            await processTicketLinkingRequirements(nfcId: nfcId, wristband: wristband, gateResult: gateResult)
        }
    }
    
    private func handleReEntry(lastCheckin: CheckinLog, nfcId: String, wristband: Wristband) async {
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        let lastEntryTime = timeFormatter.string(from: lastCheckin.timestamp)
        
        await MainActor.run {
            scanState = .success
            statusMessage = "Re-entry permitted"
            currentScanResult = .valid("Re-entry permitted (Last entry: \(lastEntryTime))", ticket: nil)
            // DO NOT increment todayScans or totalScans for re-entries
            isScanning = false
            lastScanTime = Date()
            
            // Add to recent scans with re-entry indicator (for UI display only)
            let scanResult = DatabaseScanResult(
                wristbandId: nfcId,
                nfcId: nfcId,
                category: wristband.category,
                timestamp: Date(),
                isValid: true,
                message: "Re-entry permitted"
            )
            recentScans.insert(scanResult, at: 0)
            if recentScans.count > 10 {
                recentScans.removeLast()
            }
            
            // DO NOT increment scan counters or update success rate for re-entries
        }
        
        print("✅ [DEBUG] Step 6A SUCCESS: Re-entry permitted - No scan counters incremented")
    }
    
    private func processTicketLinkingRequirements(nfcId: String, wristband: Wristband, gateResult: CheckinPolicyResult) async {
        guard let event = supabaseService?.currentEvent else { return }
        
        print("🎫 [DEBUG] Step 6B: Checking ticket linking requirements")
        
        if event.ticketLinkingMode == .required {
            if wristband.linkedTicketId != nil {
                print("✅ [DEBUG] Step 6B SUCCESS: Wristband already linked to ticket")
                await completeSuccessfulEntry(nfcId: nfcId, wristband: wristband, gateResult: gateResult)
            } else {
                print("⚠️ [DEBUG] Step 6B REQUIRED: Ticket linking required but not linked")
                await MainActor.run {
                    currentScanResult = .requiresLinking(wristbandId: nfcId, reason: "Link ticket to continue")
                    pendingWristbandId = nfcId
                    showingTicketLinking = true
                    scanState = .ready
                    statusMessage = "Link ticket to continue"
                    isScanning = false
                }
            }
        } else {
            print("✅ [DEBUG] Step 6B SKIPPED: Ticket linking not required")
            await completeSuccessfulEntry(nfcId: nfcId, wristband: wristband, gateResult: gateResult)
        }
    }
    
    // MARK: - Step 7: Complete Successful Entry
    private func completeSuccessfulEntry(nfcId: String, wristband: Wristband, gateResult: CheckinPolicyResult) async {
        guard let gateId = gateBindingService.currentGate?.id else { return }
        
        await MainActor.run {
            scanState = .success
            statusMessage = "Entry allowed"
            currentScanResult = .valid("Entry allowed", ticket: nil)
            todayScans += 1
            isScanning = false
        }
        
        // Step 7: Log the successful check-in
        await logCheckin(
            wristbandId: wristband.id,
            gateId: gateId,
            status: "success",
            ticketId: wristband.linkedTicketId
        )
        
        print("✅ [DEBUG] Step 7 SUCCESS: Check-in logged successfully")
    }
    
    // MARK: - Step 7: Log Check-in to Database
    private func logCheckin(wristbandId: String, gateId: String, status: String, ticketId: String?) async {
        guard let supabaseService = supabaseService,
              let eventId = supabaseService.currentEvent?.id,
              let staffId = supabaseService.currentUser?.id else {
            print("❌ [DEBUG] Step 7 FAILED: Missing required data for logging")
            return
        }
        
        do {
            let checkinData: [String: Any] = [
                "event_id": eventId,
                "wristband_id": wristbandId,
                "gate_id": gateId,
                "staff_id": staffId,
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "status": status,
                "ticket_id": ticketId as Any
            ]
            
            let jsonData = try JSONSerialization.data(withJSONObject: checkinData)
            
            let _: EmptyResponse = try await supabaseService.makeRequest(
                endpoint: "rest/v1/checkin_logs",
                method: "POST",
                body: jsonData,
                responseType: EmptyResponse.self
            )
            
            print("✅ [DEBUG] Step 7: Check-in logged with status: \(status)")
            
        } catch {
            print("❌ [DEBUG] Step 7 ERROR: Failed to log check-in: \(error)")
        }
    }
    
    // MARK: - Ticket Linking Methods
    
    func searchTickets(method: TicketCaptureMethod = .search) async {
        guard let eventId = supabaseService?.currentEvent?.id,
              !ticketSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await MainActor.run {
                availableTickets = []
            }
            return
        }
        
        do {
            let tickets = try await ticketService.searchAvailableTickets(
                eventId: eventId,
                query: ticketSearchQuery,
                method: method
            )
            
            await MainActor.run {
                availableTickets = tickets
            }
        } catch {
            print("Failed to search tickets: \(error)")
            await MainActor.run {
                availableTickets = []
            }
        }
    }
    
    func linkSelectedTicket() async {
        guard let wristbandId = pendingWristbandId,
              let ticket = selectedTicket,
              let userId = supabaseService?.currentUser?.id else {
            return
        }
        
        await MainActor.run {
            isLinkingTicket = true
        }
        
        do {
            try await ticketService.linkTicketToWristband(
                ticketId: ticket.id,
                wristbandId: wristbandId,
                performedBy: userId
            )
            
            await MainActor.run {
                showingTicketLinking = false
                pendingWristbandId = nil
                selectedTicket = nil
                ticketSearchQuery = ""
                availableTickets = []
                isLinkingTicket = false
                statusMessage = "Ticket linked successfully"
                
                // Close manual check-in if it was open
                if showingManualCheckin {
                    showingManualCheckin = false
                    manualWristbandId = ""
                }
            }
            
            // Process the scan again now that it's linked
            await processNFC(wristbandId)
            
        } catch {
            await MainActor.run {
                isLinkingTicket = false
                statusMessage = "Failed to link ticket: \(error.localizedDescription)"
            }
        }
    }
    
    func cancelTicketLinking() {
        showingTicketLinking = false
        pendingWristbandId = nil
        selectedTicket = nil
        ticketSearchQuery = ""
        availableTickets = []
        isLinkingTicket = false
        statusMessage = "Ticket linking cancelled"
    }
    
    // MARK: - Manual Check-in
    func performManualCheckin() async {
        guard !manualWristbandId.isEmpty else {
            await MainActor.run {
                statusMessage = "Please enter wristband ID"
            }
            return
        }
        
        await MainActor.run {
            scanState = .scanning
            statusMessage = "Processing manual check-in..."
        }
        
        // Use the same validation process as NFC scans
        await processNFC(manualWristbandId)
        
        // Only close the manual check-in sheet if we don't need ticket linking
        await MainActor.run {
            if !showingTicketLinking {
                showingManualCheckin = false
                manualWristbandId = ""
            }
            // If ticket linking is required, keep the manual check-in sheet open
            // so user can see the wristband ID they entered
        }
    }
    
    // Helper method to close manual check-in after successful ticket linking
    func completeManualCheckin() {
        showingManualCheckin = false
        manualWristbandId = ""
    }
    
    // MARK: - Stats Loading
    private func loadStats() async {
        guard let supabaseService = supabaseService,
              let eventId = supabaseService.currentEvent?.id else { return }
        
        do {
            // Load today's scans
            let today = Calendar.current.startOfDay(for: Date())
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
            
            struct CheckinCount: Codable {
                let count: Int
            }
            
            // Build today query with proper URL encoding
            var todayComponents = URLComponents()
            todayComponents.queryItems = [
                URLQueryItem(name: "event_id", value: "eq.\(eventId)"),
                URLQueryItem(name: "timestamp", value: "gte.\(today.ISO8601Format())"),
                URLQueryItem(name: "timestamp", value: "lt.\(tomorrow.ISO8601Format())"),
                URLQueryItem(name: "select", value: "count")
            ]
            let todayQueryString = todayComponents.percentEncodedQuery ?? ""

            let todayResult: [CheckinCount] = try await supabaseService.makeRequest(
                endpoint: "rest/v1/checkin_logs?\(todayQueryString)",
                method: "GET",
                body: nil,
                responseType: [CheckinCount].self
            )

            // Build total query with proper URL encoding
            var totalComponents = URLComponents()
            totalComponents.queryItems = [
                URLQueryItem(name: "event_id", value: "eq.\(eventId)"),
                URLQueryItem(name: "select", value: "count")
            ]
            let totalQueryString = totalComponents.percentEncodedQuery ?? ""

            let totalResult: [CheckinCount] = try await supabaseService.makeRequest(
                endpoint: "rest/v1/checkin_logs?\(totalQueryString)",
                method: "GET",
                body: nil,
                responseType: [CheckinCount].self
            )
            
            await MainActor.run {
                self.todayScans = todayResult.first?.count ?? 0
                self.totalScans = totalResult.first?.count ?? 0
                self.updateSuccessRate()
            }
        } catch {
            print("Failed to load stats: \(error)")
        }
    }
    
    private func updateSuccessRate() {
        let validScans = recentScans.filter { $0.isValid }.count
        let totalRecentScans = recentScans.count
        successRate = totalRecentScans > 0 ? Double(validScans) / Double(totalRecentScans) * 100 : 100.0
    }
}

extension DatabaseScannerViewModel: NFCNDEFReaderSessionDelegate {
    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        print("🔍 [DEBUG] NFC: Detected \(messages.count) NDEF messages")
        
        guard let message = messages.first else {
            print("❌ [DEBUG] NFC: No NDEF message found")
            return
        }
        
        guard let record = message.records.first else {
            print("❌ [DEBUG] NFC: No NDEF record found in message")
            return
        }
        
        print("🔍 [DEBUG] NFC: Processing NDEF record with \(record.payload.count) bytes")
        
        // Parse NDEF text record properly to extract clean NFC ID
        guard let nfcId = parseNFCTextRecord(record.payload), !nfcId.isEmpty else {
            print("❌ [DEBUG] NFC: Failed to parse NFC ID from payload")
            Task { @MainActor in
                // Show error to user
                await MainActor.run {
                    scanState = .error
                    statusMessage = "Invalid NFC tag format"
                    isScanning = false
                }
            }
            return
        }
        
        print("✅ [DEBUG] NFC: Successfully parsed ID: \(nfcId)")
        
        Task { @MainActor in
            do {
                await processNFC(nfcId)
            } catch {
                print("❌ [DEBUG] NFC: Error processing NFC: \(error)")
                await MainActor.run {
                    scanState = .error
                    statusMessage = "Processing error: \(error.localizedDescription)"
                    isScanning = false
                }
            }
        }
    }
    
    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        print("❌ [DEBUG] NFC: Session invalidated with error: \(error)")
        Task { @MainActor in
            isScanning = false
            if let nfcError = error as? NFCReaderError {
                switch nfcError.code {
                case .readerSessionInvalidationErrorUserCanceled:
                    print("🔍 [DEBUG] NFC: User cancelled scan")
                case .readerSessionInvalidationErrorSessionTimeout:
                    statusMessage = "Scan timeout - try again"
                case .readerSessionInvalidationErrorSessionTerminatedUnexpectedly:
                    statusMessage = "Scan interrupted - try again"
                default:
                    statusMessage = "NFC error - try again"
                }
            }
        }
    }
    
    nonisolated func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {
        print("✅ [DEBUG] NFC: Session became active")
        // Session started - no action needed
    }
    
    // Helper function to properly parse NDEF text records
    nonisolated private func parseNFCTextRecord(_ payload: Data) -> String? {
        guard payload.count > 1 else { return nil }
        
        // NDEF Text Record format:
        // Byte 0: Status byte (bit 7 = encoding, bits 5-0 = language code length)
        // Bytes 1 to N: Language code (typically "en")
        // Bytes N+1 to end: Actual text data
        
        let statusByte = payload[0]
        let isUTF16 = (statusByte & 0x80) != 0
        let languageCodeLength = Int(statusByte & 0x3F)
        
        // Calculate start of actual text data
        let textStartIndex = 1 + languageCodeLength
        
        guard payload.count > textStartIndex else { return nil }
        
        // Extract just the text portion, skipping status byte and language code
        let textData = payload.subdata(in: textStartIndex..<payload.count)
        
        // Convert to string using appropriate encoding
        let encoding: String.Encoding = isUTF16 ? .utf16 : .utf8
        let rawText = String(data: textData, encoding: encoding)
        
        // Clean up the text - remove any remaining control characters and whitespace
        return rawText?.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
    }
}
