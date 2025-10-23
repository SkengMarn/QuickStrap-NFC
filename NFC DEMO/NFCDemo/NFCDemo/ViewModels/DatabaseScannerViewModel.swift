import SwiftUI
#if canImport(CoreNFC)
import CoreNFC
#endif
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
    @Published var pendingWristbandUUID: String?  // The actual wristband.id (UUID) for API calls
    @Published var pendingWristbandNFC: String?   // The NFC tag ID string for UI/rescan
    @Published var currentScanResult: EnhancedScanResult?
    @Published var availableTickets: [Ticket] = []
    @Published var selectedTicket: Ticket?
    @Published var ticketSearchQuery = ""
    @Published var isLinkingTicket = false
    @Published var linkValidation: LinkValidationResult?
    @Published var isValidatingLink = false
    
    private var gateBindingService = GateBindingService.shared
    private var capacityMonitoringService = CapacityMonitoringService.shared
    // private var locationManager = LocationManager.shared
    private var supabaseService: SupabaseService?

    // Public getter for supabaseService
    var currentSupabaseService: SupabaseService? {
        return supabaseService
    }
    // EventDataManager removed - not needed
    #if canImport(CoreNFC)
    private var nfcSession: NFCNDEFReaderSession?
    #endif
    private var cancellables = Set<AnyCancellable>()
    private var ticketService = TicketService.shared
    private var errorDismissalTimer: Timer?
    
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
    
    func setup(supabaseService: SupabaseService) {
        self.supabaseService = supabaseService
        // locationManager.startUpdating() // LocationManager not available

        Task {
            if let event = supabaseService.currentEvent {
                try await gateBindingService.detectNearbyGates(eventId: event.id)
                await loadStats()

                // Configure capacity monitoring for this event
                capacityMonitoringService.configure(for: event, supabaseService: supabaseService)
            }
        }
    }
    
    func cleanup() {
        nfcSession?.invalidate()
        errorDismissalTimer?.invalidate()
        errorDismissalTimer = nil
        capacityMonitoringService.reset()
    }
    
    // MARK: - Error Management
    
    private func setErrorState(message: String, detail: String = "", autoDismissAfter seconds: TimeInterval = 5.0) {
        // Cancel any existing timer
        errorDismissalTimer?.invalidate()
        
        // Set error state
        scanState = .error
        statusMessage = message
        detailMessage = detail
        isScanning = false
        
        // Auto-dismiss after specified seconds
        errorDismissalTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.clearErrorState()
            }
        }
    }
    
    private func clearErrorState() {
        errorDismissalTimer?.invalidate()
        errorDismissalTimer = nil
        
        if scanState == .error || scanState == .blocked {
            scanState = .ready
            statusMessage = "Ready to scan"
            detailMessage = ""
        }
    }
    
    func startNFCScanning() {
        #if canImport(CoreNFC)
        nfcSession?.invalidate()

        guard NFCNDEFReaderSession.readingAvailable else {
            // Already on MainActor, no need for await
            setErrorState(message: "NFC not available on this device")
            return
        }

        nfcSession = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: true)
        nfcSession?.alertMessage = "Hold your iPhone near the wristband"
        nfcSession?.begin()

        // Already on MainActor, no need for await
        isScanning = true
        scanState = .scanning
        statusMessage = "Scanning for wristband..."
        #else
        // Already on MainActor, no need for await
        setErrorState(message: "NFC not available on this platform")
        #endif
    }
    
    func stopScanning() {
        #if canImport(CoreNFC)
        nfcSession?.invalidate()
        #endif
        isScanning = false
    }

    func startContinuousScanning() {
        isContinuousMode = true
        startNFCScanning()
    }

    func performSingleScan() {
        isContinuousMode = false
        startNFCScanning()
    }

    func toggleContinuousMode() {
        isContinuousMode.toggle()
        if !isContinuousMode && isScanning {
            stopScanning()
        }
    }
    
    private func processNFC(_ nfcId: String) async {
        print("🔍 [DEBUG] Step 1: Starting NFC processing for ID: \(nfcId)")
        
        guard let supabaseService = supabaseService else {
            print("❌ [DEBUG] Step 1 FAILED: SupabaseService not available")
            await MainActor.run {
                setErrorState(message: "Service not available")
            }
            return
        }
        
        guard let eventId = supabaseService.currentEvent?.id else {
            print("❌ [DEBUG] Step 1 FAILED: No event selected")
            await MainActor.run {
                setErrorState(message: "No event selected")
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
            
            let wristbands: [Wristband] = try await supabaseService.makeRequest(
                endpoint: "rest/v1/wristbands?nfc_id=eq.\(nfcId)",
                method: "GET",
                body: nil,
                responseType: [Wristband].self
            )
            
            guard let wristband = wristbands.first else {
                print("❌ [DEBUG] Step 2 FAILED: Wristband not found (possibly counterfeit or unregistered)")
                await MainActor.run {
                    setErrorState(message: "Wristband not found", detail: "Invalid wristband (possibly counterfeit or unregistered)")
                    currentScanResult = EnhancedScanResult.invalid("Invalid wristband (possibly counterfeit or unregistered)")
                }
                return
            }

            // Step 3: Check Event Context - Validate wristband belongs to current event/series
            let currentEvent = supabaseService.currentEvent
            let isSeriesEvent = currentEvent?.seriesId != nil
            
            if isSeriesEvent {
                // For series events, check if wristband belongs to this series
                let currentSeriesId = currentEvent?.seriesId
                print("🔍 [DEBUG] Step 3: Checking SERIES context - Wristband series: \(wristband.seriesId ?? "nil"), Scanner series: \(currentSeriesId ?? "nil")")
                
                guard wristband.seriesId == currentSeriesId else {
                    print("❌ [DEBUG] Step 3 FAILED: Wristband belongs to different series or parent event")
                    await MainActor.run {
                        setErrorState(message: "Wrong event", detail: "Wristband belongs to a different event or series")
                        currentScanResult = EnhancedScanResult.invalid("Wristband belongs to a different event or series")
                    }
                    return
                }
            } else {
                // For parent events, check if wristband belongs to this parent event (and not a series)
                print("🔍 [DEBUG] Step 3: Checking PARENT EVENT context - Wristband event: \(wristband.eventId), Scanner event: \(eventId)")
                
                guard wristband.eventId == eventId && wristband.seriesId == nil else {
                    print("❌ [DEBUG] Step 3 FAILED: Wristband belongs to different event or a series")
                    await MainActor.run {
                        setErrorState(message: "Wrong event", detail: "Wristband belongs to a different event or series")
                        currentScanResult = EnhancedScanResult.invalid("Wristband belongs to a different event or series")
                    }
                    return
                }
            }

            // Step 4: Check Check-in Time Window
            print("🔍 [DEBUG] Step 4: Checking check-in time window")
            let windowStatus = supabaseService.currentEvent?.config?.checkinWindow?.isWithinWindow() ?? .allowed

            guard windowStatus.isAllowed else {
                print("❌ [DEBUG] Step 4 FAILED: Check-in outside allowed time window")
                await MainActor.run {
                    setErrorState(message: "Outside check-in hours", detail: windowStatus.errorMessage, autoDismissAfter: 8.0)
                    currentScanResult = EnhancedScanResult.invalid(windowStatus.errorMessage)
                }
                return
            }

            print("✅ [DEBUG] Step 4 SUCCESS: Within check-in time window")

            // Step 5: Determine Wristband Category
            print("✅ [DEBUG] Step 5: Wristband category determined: \(wristband.category.name)")

            // Step 6: Gate Enforcement Check
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
                setErrorState(message: "System error", detail: error.localizedDescription, autoDismissAfter: 8.0)
                
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
                setErrorState(message: "No gate detected", autoDismissAfter: 3.0)
            }
            return
        }

        do {
            // Step 6: Gate Enforcement Check
            print("🚪 [DEBUG] Step 6: Checking gate enforcement for category: \(wristband.category.name)")

            let result = try await gateBindingService.evaluateCheckin(
                wristbandId: nfcId,
                categoryName: wristband.category.name,
                gateId: gateId
            )

            await MainActor.run {
                lastPolicyResult = result
            }

            if result.allowed {
                print("✅ [DEBUG] Step 6 SUCCESS: Gate allows entry")

                // Step 7: Check Ticket Linking Requirements
                await processTicketLinking(nfcId: nfcId, wristband: wristband, gateResult: result)
            } else {
                // Step 6 FAILED: Gate denies entry
                print("❌ [DEBUG] Step 6 FAILED: Gate denies entry - \(result.reason.displayMessage)")

                await MainActor.run {
                    scanState = .blocked
                    statusMessage = result.reason.displayMessage
                    currentScanResult = .invalid(result.reason.displayMessage)
                    isScanning = false
                }

                // Step 8: Log the failed check-in
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
                setErrorState(message: "Gate check failed", detail: error.localizedDescription)
            }
        }
    }
    
    // MARK: - Step 7: Check for Recent Entry (Re-entry Detection)
    private func processTicketLinking(nfcId: String, wristband: Wristband, gateResult: CheckinPolicyResult) async {
        guard let event = supabaseService?.currentEvent else { return }
        let eventId = event.id

        print("🎫 [DEBUG] Step 7: Checking recent entries and ticket linking requirements")

        // First check for recent entries (re-entry detection)
        await checkForRecentEntry(wristbandId: wristband.id, eventId: eventId, nfcId: nfcId, wristband: wristband, gateResult: gateResult)
    }
    
    private func checkForRecentEntry(wristbandId: String, eventId: String, nfcId: String, wristband: Wristband, gateResult: CheckinPolicyResult) async {
        do {
            // Check for recent check-ins within the last 30 minutes
            let thirtyMinutesAgo = Calendar.current.date(byAdding: .minute, value: -30, to: Date()) ?? Date()
            let isoFormatter = ISO8601DateFormatter()

            print("🔍 [DEBUG] Step 7A: Checking for recent entries since \(isoFormatter.string(from: thirtyMinutesAgo))")

            guard let supabaseService = supabaseService else {
                print("❌ [DEBUG] Step 7A ERROR: SupabaseService not available")
                await processTicketLinkingRequirements(nfcId: nfcId, wristband: wristband, gateResult: gateResult)
                return
            }

            let recentCheckins: [CheckinLog] = try await supabaseService.makeRequest(
                endpoint: "rest/v1/checkin_logs?wristband_id=eq.\(wristbandId)&event_id=eq.\(eventId)&timestamp=gte.\(isoFormatter.string(from: thirtyMinutesAgo))&status=eq.success&order=timestamp.desc&limit=1",
                method: "GET",
                body: nil,
                responseType: [CheckinLog].self
            )

            if let lastCheckin = recentCheckins.first {
                print("🔄 [DEBUG] Step 7A: Recent entry found at \(lastCheckin.timestamp) - This is RE-ENTRY")
                await handleReEntry(lastCheckin: lastCheckin, nfcId: nfcId, wristband: wristband)
            } else {
                print("✅ [DEBUG] Step 7A: No recent entries found - This is FIRST ENTRY")
                await processTicketLinkingRequirements(nfcId: nfcId, wristband: wristband, gateResult: gateResult)
            }

        } catch {
            print("❌ [DEBUG] Step 7A ERROR: Failed to check recent entries: \(error)")
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
            currentScanResult = EnhancedScanResult.valid("Re-entry permitted (Last entry: \(lastEntryTime))", ticket: nil as Ticket?)
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

        print("✅ [DEBUG] Step 7A SUCCESS: Re-entry permitted - No scan counters incremented")
    }

    private func processTicketLinkingRequirements(nfcId: String, wristband: Wristband, gateResult: CheckinPolicyResult) async {
        guard let supabaseService = supabaseService,
              let event = supabaseService.currentEvent else { return }

        print("🎫 [DEBUG] Step 7B: Checking ticket linking requirements")

        if event.ticketLinkingMode == .required {
            // Check if wristband has ticket link in ticket_wristband_links table
            do {
                let links: [TicketWristbandLink] = try await supabaseService.makeRequest(
                    endpoint: "rest/v1/ticket_wristband_links?wristband_id=eq.\(wristband.id)",
                    method: "GET",
                    body: nil,
                    responseType: [TicketWristbandLink].self
                )

                if !links.isEmpty {
                    print("✅ [DEBUG] Step 7B SUCCESS: Wristband already linked to ticket")
                    await completeSuccessfulEntry(nfcId: nfcId, wristband: wristband, gateResult: gateResult)
                } else {
                    print("⚠️ [DEBUG] Step 7B REQUIRED: Ticket linking required but not linked")
                    await MainActor.run {
                        currentScanResult = EnhancedScanResult.requiresLinking(wristbandId: nfcId, reason: "Link ticket to continue")
                        pendingWristbandUUID = wristband.id  // Store the UUID for API calls
                        pendingWristbandNFC = nfcId          // Store the NFC ID for UI/rescan
                        showingTicketLinking = true
                        scanState = .ready
                        statusMessage = "Link ticket to continue"
                        isScanning = false
                    }
                }
            } catch {
                print("❌ [DEBUG] Step 7B ERROR: Failed to check ticket link: \(error)")
                await MainActor.run {
                    currentScanResult = EnhancedScanResult.requiresLinking(wristbandId: nfcId, reason: "Link ticket to continue")
                    pendingWristbandUUID = wristband.id
                    pendingWristbandNFC = nfcId
                    showingTicketLinking = true
                    scanState = .ready
                    statusMessage = "Link ticket to continue"
                    isScanning = false
                }
            }
        } else {
            print("✅ [DEBUG] Step 7B SKIPPED: Ticket linking not required")
            await completeSuccessfulEntry(nfcId: nfcId, wristband: wristband, gateResult: gateResult)
        }
    }

    // MARK: - Step 8: Complete Successful Entry
    private func completeSuccessfulEntry(nfcId: String, wristband: Wristband, gateResult: CheckinPolicyResult) async {
        guard let gateId = gateBindingService.currentGate?.id else { return }

        await MainActor.run {
            scanState = .success
            statusMessage = "Entry allowed"
            currentScanResult = EnhancedScanResult.valid("Entry allowed", ticket: nil as Ticket?)
            todayScans += 1
            isScanning = false
        }

        // Step 8: Log the successful check-in
        // Get ticket ID from ticket_wristband_links if available
        let ticketId = await getLinkedTicketId(for: wristband.id)
        await logCheckin(
            wristbandId: wristband.id,
            gateId: gateId,
            status: "success",
            ticketId: ticketId
        )

        // Update capacity monitoring (this will trigger alert if threshold reached)
        await capacityMonitoringService.incrementCapacity()

        print("✅ [DEBUG] Step 8 SUCCESS: Check-in logged successfully")
    }

    // MARK: - Step 8: Log Check-in to Database
    private func logCheckin(wristbandId: String, gateId: String, status: String, ticketId: String?) async {
        guard let supabaseService = supabaseService,
              let currentEvent = supabaseService.currentEvent,
              let staffId = supabaseService.currentUser?.id else {
            print("❌ [DEBUG] Step 8 FAILED: Missing required data for logging")
            return
        }

        do {
            // Determine correct event_id and series_id based on context
            let eventId: String
            let seriesId: String?
            
            if let currentSeriesId = currentEvent.seriesId {
                // This is a series event - use parent event ID and series ID
                // Get parent event ID from wristband
                let wristbands: [Wristband] = try await supabaseService.makeRequest(
                    endpoint: "rest/v1/wristbands?id=eq.\(wristbandId)&select=event_id,series_id",
                    method: "GET",
                    body: nil,
                    responseType: [Wristband].self
                )
                eventId = wristbands.first?.eventId ?? currentEvent.id
                seriesId = currentSeriesId
                print("📝 [DEBUG] Step 8: Logging SERIES check-in - Parent Event: \(eventId), Series: \(currentSeriesId)")
            } else {
                // This is a parent event - use current event ID, no series
                eventId = currentEvent.id
                seriesId = nil
                print("📝 [DEBUG] Step 8: Logging PARENT EVENT check-in - Event: \(eventId)")
            }
            
            var checkinData: [String: Any] = [
                "event_id": eventId,
                "wristband_id": wristbandId,
                "gate_id": gateId,
                "staff_id": staffId,
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "status": status,
                "ticket_id": ticketId as Any
            ]
            
            // Add series_id if this is a series event
            if let seriesId = seriesId {
                checkinData["series_id"] = seriesId
            }

            let jsonData = try JSONSerialization.data(withJSONObject: checkinData)

            let _: EmptyResponse = try await supabaseService.makeRequest(
                endpoint: "rest/v1/checkin_logs",
                method: "POST",
                body: jsonData,
                responseType: EmptyResponse.self
            )

            print("✅ [DEBUG] Step 8: Check-in logged with status: \(status)")

        } catch {
            print("❌ [DEBUG] Step 8 ERROR: Failed to log check-in: \(error)")
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
    
    /// Validates if the selected ticket can be linked to the pending wristband
    func validateSelectedTicketLink() async {
        guard let wristbandUUID = pendingWristbandUUID,
              let ticket = selectedTicket else {
            await MainActor.run {
                linkValidation = nil
            }
            return
        }

        await MainActor.run {
            isValidatingLink = true
        }

        do {
            let validation = try await ticketService.validateWristbandLink(
                ticketId: ticket.id,
                wristbandId: wristbandUUID  // Use UUID for API call
            )

            await MainActor.run {
                linkValidation = validation
                isValidatingLink = false
            }
        } catch {
            await MainActor.run {
                linkValidation = nil
                isValidatingLink = false
            }
        }
    }

    func linkSelectedTicket() async {
        guard let wristbandUUID = pendingWristbandUUID,
              let wristbandNFC = pendingWristbandNFC,
              let ticket = selectedTicket,
              let userId = supabaseService?.currentUser?.id else {
            return
        }

        await MainActor.run {
            isLinkingTicket = true
            scanState = .scanning
            statusMessage = "🔍 Validating Ticket Link..."
            detailMessage = "Checking if wristband can be linked"
        }

        do {
            // First validate the link against category limits (use UUID)
            let validation = try await ticketService.validateWristbandLink(
                ticketId: ticket.id,
                wristbandId: wristbandUUID  // Use UUID for API call
            )

            // Check if we can proceed
            guard validation.canLink else {
                await MainActor.run {
                    isLinkingTicket = false
                    
                    // Show clear validation failure message
                    scanState = .error
                    statusMessage = "❌ Cannot Link Wristband"
                    detailMessage = validation.reason
                    
                    // Auto-clear error after 5 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                        self?.scanState = .ready
                        self?.statusMessage = "Ready to scan"
                        self?.detailMessage = ""
                    }
                }
                return
            }

            // Proceed with linking (use UUID)
            await MainActor.run {
                statusMessage = "🔗 Linking Ticket to Wristband..."
                detailMessage = "Ticket #\(ticket.ticketNumber) → Wristband"
            }

            try await ticketService.linkTicketToWristband(
                ticketId: ticket.id,
                wristbandId: wristbandUUID,  // Use UUID for API call
                performedBy: userId
            )

            await MainActor.run {
                showingTicketLinking = false
                pendingWristbandUUID = nil
                pendingWristbandNFC = nil
                selectedTicket = nil
                ticketSearchQuery = ""
                availableTickets = []
                isLinkingTicket = false
                linkValidation = nil
                
                // Show clear success message
                scanState = .success
                statusMessage = "✅ Ticket Linked Successfully!"
                detailMessage = "Ticket #\(ticket.ticketNumber) linked to wristband"

                // Close manual check-in if it was open
                if showingManualCheckin {
                    showingManualCheckin = false
                    manualWristbandId = ""
                }
            }
            
            // Auto-clear success message after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                self?.scanState = .ready
                self?.statusMessage = "Ready to scan"
                self?.detailMessage = ""
            }

            // Instead of re-processing the entire NFC flow, directly complete the successful entry
            // since we know the ticket is now linked and validation should pass
            if let wristband = await getWristbandByNFC(wristbandNFC) {
                await completeSuccessfulEntryAfterLinking(nfcId: wristbandNFC, wristband: wristband)
            }

        } catch {
            let errorMessage = error.localizedDescription

            await MainActor.run {
                isLinkingTicket = false
                
                // Show clear failure message with specific reason
                scanState = .error
                statusMessage = "❌ Ticket Linking Failed"
                detailMessage = "Reason: \(errorMessage)"
                
                // Auto-clear error after 5 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                    self?.scanState = .ready
                    self?.statusMessage = "Ready to scan"
                    self?.detailMessage = ""
                }
            }
        }
    }
    
    func cancelTicketLinking() {
        showingTicketLinking = false
        pendingWristbandUUID = nil
        pendingWristbandNFC = nil
        selectedTicket = nil
        ticketSearchQuery = ""
        availableTickets = []
        isLinkingTicket = false
        linkValidation = nil
        isValidatingLink = false
        
        // Show clear cancellation message
        scanState = .ready
        statusMessage = "🚫 Ticket Linking Cancelled"
        detailMessage = "Wristband remains unlinked"
        
        // Auto-clear message after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.statusMessage = "Ready to scan"
            self?.detailMessage = ""
        }
    }
    
    // MARK: - Helper Methods
    
    private func getWristbandByNFC(_ nfcId: String) async -> Wristband? {
        guard let supabaseService = supabaseService else { return nil }
        
        do {
            let wristbands: [Wristband] = try await supabaseService.makeRequest(
                endpoint: "rest/v1/wristbands?nfc_id=eq.\(nfcId)",
                method: "GET",
                body: nil,
                responseType: [Wristband].self
            )
            return wristbands.first
        } catch {
            print("❌ [DEBUG] Failed to get wristband by NFC: \(error)")
            return nil
        }
    }
    
    private func completeSuccessfulEntryAfterLinking(nfcId: String, wristband: Wristband) async {
        guard let gateId = gateBindingService.currentGate?.id else { return }

        await MainActor.run {
            scanState = .success
            statusMessage = "Entry allowed - Ticket linked successfully"
            currentScanResult = EnhancedScanResult.valid("Entry allowed", ticket: nil as Ticket?)
            todayScans += 1
            isScanning = false
        }

        // Log the successful check-in with the newly linked ticket
        let ticketId = await getLinkedTicketId(for: wristband.id)
        await logCheckin(
            wristbandId: wristband.id,
            gateId: gateId,
            status: "success",
            ticketId: ticketId
        )

        // Update capacity monitoring (this will trigger alert if threshold reached)
        await capacityMonitoringService.incrementCapacity()

        print("✅ [DEBUG] Entry completed successfully after ticket linking")
    }
    
    private func getLinkedTicketId(for wristbandId: String) async -> String? {
        guard let supabaseService = supabaseService else { return nil }
        
        do {
            let links: [TicketWristbandLink] = try await supabaseService.makeRequest(
                endpoint: "rest/v1/ticket_wristband_links?wristband_id=eq.\(wristbandId)&limit=1",
                method: "GET",
                body: nil,
                responseType: [TicketWristbandLink].self
            )
            
            return links.first?.ticketId
        } catch {
            print("❌ [DEBUG] Failed to get linked ticket ID: \(error)")
            return nil
        }
    }
    
    // MARK: - Manual Check-in
    func performManualCheckin() async {
        guard !manualWristbandId.isEmpty else {
            await MainActor.run {
                setErrorState(message: "Please enter wristband ID", autoDismissAfter: 3.0)
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
            
            let todayResult: [CheckinCount] = try await supabaseService.makeRequest(
                endpoint: "rest/v1/checkin_logs?event_id=eq.\(eventId)&timestamp=gte.\(today.ISO8601Format())&timestamp=lt.\(tomorrow.ISO8601Format())&select=count",
                method: "GET",
                body: nil,
                responseType: [CheckinCount].self
            )
            
            let totalResult: [CheckinCount] = try await supabaseService.makeRequest(
                endpoint: "rest/v1/checkin_logs?event_id=eq.\(eventId)&select=count",
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
                    setErrorState(message: "Invalid NFC tag format")
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
                    setErrorState(message: "Processing error", detail: error.localizedDescription)
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
                    // Don't show error message for user-initiated cancellation
                    return
                case .readerSessionInvalidationErrorSessionTimeout:
                    statusMessage = "Scan timeout - try again"
                    scanState = .error
                case .readerSessionInvalidationErrorSessionTerminatedUnexpectedly:
                    statusMessage = "Scan interrupted - try again"
                    scanState = .error
                default:
                    statusMessage = "NFC error - try again"
                    scanState = .error
                }

                // Auto-clear error message after 5 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                    guard let self = self else { return }
                    if self.scanState == .error {
                        self.scanState = .ready
                        self.statusMessage = "Ready to scan"
                    }
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
