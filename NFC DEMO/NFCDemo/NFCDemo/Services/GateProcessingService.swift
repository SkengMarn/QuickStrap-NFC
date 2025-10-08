import Foundation
import Combine

// MARK: - Gate Processing Notifications
enum GateProcessingEvent {
    case scanDetected(gateId: String, gateName: String)
    case duplicateDetected(originalGate: String, duplicateGate: String)
    case duplicateRemoved(gateName: String, mergedInto: String)
    case gatePromoted(gateName: String, from: GateBindingStatus, to: GateBindingStatus)
    case gateCreated(gateName: String, location: String)
    case qualityImproved(gateName: String, newScore: Double)
    case backgroundProcessingStarted
    case backgroundProcessingCompleted
    
    var message: String {
        switch self {
        case .scanDetected(_, let gateName):
            return "📍 New scan at \(gateName)"
        case .duplicateDetected(let original, let duplicate):
            return "🔍 Duplicate detected: \(duplicate) matches \(original)"
        case .duplicateRemoved(let gateName, let mergedInto):
            return "🔄 Merged \(gateName) into \(mergedInto)"
        case .gatePromoted(let gateName, let from, let to):
            return "⬆️ \(gateName) promoted: \(from.rawValue) → \(to.rawValue)"
        case .gateCreated(let gateName, let location):
            return "✨ New gate created: \(gateName) at \(location)"
        case .qualityImproved(let gateName, let newScore):
            return "📈 \(gateName) quality improved to \(Int(newScore))%"
        case .backgroundProcessingStarted:
            return "🔄 Processing gate updates..."
        case .backgroundProcessingCompleted:
            return "✅ Gate processing completed"
        }
    }
    
    var icon: String {
        switch self {
        case .scanDetected: return "location.fill"
        case .duplicateDetected: return "exclamationmark.triangle.fill"
        case .duplicateRemoved: return "arrow.triangle.merge"
        case .gatePromoted: return "arrow.up.circle.fill"
        case .gateCreated: return "plus.circle.fill"
        case .qualityImproved: return "chart.line.uptrend.xyaxis"
        case .backgroundProcessingStarted: return "gear"
        case .backgroundProcessingCompleted: return "checkmark.circle.fill"
        }
    }
    
    var color: String {
        switch self {
        case .scanDetected: return "blue"
        case .duplicateDetected: return "orange"
        case .duplicateRemoved: return "purple"
        case .gatePromoted: return "green"
        case .gateCreated: return "mint"
        case .qualityImproved: return "indigo"
        case .backgroundProcessingStarted: return "gray"
        case .backgroundProcessingCompleted: return "green"
        }
    }
}

// MARK: - Automatic Gate Processing Service
@MainActor
class GateProcessingService: ObservableObject {
    static let shared = GateProcessingService()
    
    @Published var recentEvents: [GateProcessingEvent] = []
    @Published var isProcessing = false
    @Published var processingStatus = "Ready"
    
    private let eventPublisher = PassthroughSubject<GateProcessingEvent, Never>()
    private var cancellables = Set<AnyCancellable>()
    private var processingTimer: Timer?
    
    private let gateBindingService = GateBindingService.shared
    private let deduplicationService = GateDeduplicationService.shared
    private let supabaseService = SupabaseService.shared
    
    private init() {
        setupEventHandling()
        startAutomaticProcessing()
    }
    
    // MARK: - Event Handling
    private func setupEventHandling() {
        eventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleEvent(event)
            }
            .store(in: &cancellables)
    }
    
    private func handleEvent(_ event: GateProcessingEvent) {
        // Add to recent events (keep last 10)
        recentEvents.insert(event, at: 0)
        if recentEvents.count > 10 {
            recentEvents.removeLast()
        }
        
        // Update processing status
        switch event {
        case .backgroundProcessingStarted:
            isProcessing = true
            processingStatus = "Processing gates..."
        case .backgroundProcessingCompleted:
            isProcessing = false
            processingStatus = "Ready"
        case .duplicateDetected:
            processingStatus = "Analyzing duplicates..."
        case .gatePromoted:
            processingStatus = "Updating gate status..."
        default:
            break
        }
        
        print("🔔 Gate Event: \(event.message)")
    }
    
    // MARK: - Automatic Processing
    private func startAutomaticProcessing() {
        // Run automatic processing every 30 seconds
        processingTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task {
                await self?.runAutomaticProcessing()
            }
        }
    }
    
    func runAutomaticProcessing() async {
        guard let eventId = supabaseService.currentEvent?.id else { return }
        
        eventPublisher.send(.backgroundProcessingStarted)
        
        do {
            // 1. Check for new scans and update gate bindings
            await processNewScans(eventId: eventId)
            
            // 2. Automatically detect and merge duplicates
            await processAutomaticDuplicates(eventId: eventId)
            
            // 3. Promote gates based on confidence thresholds
            await processGatePromotions(eventId: eventId)
            
            // 4. Update quality scores
            await updateQualityScores(eventId: eventId)
            
            eventPublisher.send(.backgroundProcessingCompleted)
            
        } catch {
            print("❌ Automatic processing failed: \(error)")
            eventPublisher.send(.backgroundProcessingCompleted)
        }
    }
    
    // MARK: - Processing Steps
    
    private func processNewScans(eventId: String) async {
        do {
            let gates = try await gateBindingService.fetchActiveGatesWithScans(for: eventId)
            
            for gate in gates {
                // Check if gate has new scans since last processing
                let recentScans = try await getRecentScans(for: gate.id, eventId: eventId)
                
                if !recentScans.isEmpty {
                    eventPublisher.send(.scanDetected(gateId: gate.id, gateName: gate.name))
                    
                    // Update gate binding confidence based on new scans
                    await updateGateBinding(for: gate, with: recentScans)
                }
            }
        } catch {
            print("❌ Failed to process new scans: \(error)")
        }
    }
    
    private func processAutomaticDuplicates(eventId: String) async {
        do {
            let gates = try await gateBindingService.fetchActiveGatesWithScans(for: eventId)
            let bindings = try await gateBindingService.fetchAllGateBindings()
            
            // Find duplicate clusters
            let duplicateClusters = try await deduplicationService.findAndMergeDuplicateGates(
                gates: gates,
                bindings: bindings
            )
            
            // Process each cluster
            for cluster in duplicateClusters {
                if !cluster.duplicateGates.isEmpty {
                    let primaryGate = cluster.primaryGate
                    let duplicateGates = cluster.duplicateGates
                    
                    for duplicate in duplicateGates {
                        eventPublisher.send(.duplicateDetected(
                            originalGate: primaryGate.name,
                            duplicateGate: duplicate.name
                        ))
                        
                        // Automatically merge if confidence is high enough
                        if cluster.highestConfidence > 0.8 {
                            await mergeDuplicateGate(duplicate: duplicate, into: primaryGate)
                            eventPublisher.send(.duplicateRemoved(
                                gateName: duplicate.name,
                                mergedInto: primaryGate.name
                            ))
                        }
                    }
                }
            }
        } catch {
            print("❌ Failed to process duplicates: \(error)")
        }
    }
    
    private func processGatePromotions(eventId: String) async {
        do {
            let bindings = try await gateBindingService.fetchAllGateBindings()
            
            for binding in bindings {
                let newStatus = determineGateStatus(binding: binding)
                
                if newStatus != binding.status {
                    // Get gate name for notification
                    let gates = try await gateBindingService.fetchActiveGatesWithScans(for: eventId)
                    let gate = gates.first { $0.id == binding.gateId }
                    let gateName = gate?.name ?? "Unknown Gate"
                    
                    eventPublisher.send(.gatePromoted(
                        gateName: gateName,
                        from: binding.status,
                        to: newStatus
                    ))
                    
                    // Update the binding status
                    await updateBindingStatus(binding: binding, newStatus: newStatus)
                }
            }
        } catch {
            print("❌ Failed to process gate promotions: \(error)")
        }
    }
    
    private func updateQualityScores(eventId: String) async {
        do {
            let gates = try await gateBindingService.fetchActiveGatesWithScans(for: eventId)
            
            for gate in gates {
                let oldScore = await getGateQualityScore(gate.id)
                let newScore = await calculateGateQuality(gate: gate, eventId: eventId)
                
                if newScore > oldScore + 10 { // Significant improvement
                    eventPublisher.send(.qualityImproved(
                        gateName: gate.name,
                        newScore: newScore
                    ))
                }
            }
        } catch {
            print("❌ Failed to update quality scores: \(error)")
        }
    }
    
    // MARK: - Helper Methods
    
    private func getRecentScans(for gateId: String, eventId: String) async throws -> [CheckinLog] {
        let fiveMinutesAgo = Date().addingTimeInterval(-300) // 5 minutes ago
        
        let logs: [CheckinLog] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/checkin_logs?gate_id=eq.\(gateId)&event_id=eq.\(eventId)&timestamp=gte.\(fiveMinutesAgo.ISO8601Format())&select=*",
            method: "GET",
            body: nil,
            responseType: [CheckinLog].self
        )
        
        return logs
    }
    
    private func updateGateBinding(for gate: Gate, with scans: [CheckinLog]) async {
        // Update binding confidence based on scan patterns
        // This is a simplified version - you can make it more sophisticated
        print("📊 Updating binding for \(gate.name) with \(scans.count) new scans")
    }
    
    private func mergeDuplicateGate(duplicate: Gate, into primary: Gate) async {
        // Merge duplicate gate into primary gate
        print("🔄 Merging \(duplicate.name) into \(primary.name)")
        
        // In a real implementation, you would:
        // 1. Transfer all scans from duplicate to primary
        // 2. Update gate bindings
        // 3. Delete the duplicate gate
        // 4. Update related records
    }
    
    private func determineGateStatus(binding: GateBinding) -> GateBindingStatus {
        // Automatic promotion logic
        if binding.confidence >= 0.8 && binding.sampleCount >= 15 {
            return .enforced
        } else if binding.confidence >= 0.6 && binding.sampleCount >= 5 {
            return .probation
        } else {
            return .unbound
        }
    }
    
    private func updateBindingStatus(binding: GateBinding, newStatus: GateBindingStatus) async {
        print("⬆️ Promoting gate binding to \(newStatus.rawValue)")
        // Update the binding in the database
    }
    
    private func getGateQualityScore(_ gateId: String) async -> Double {
        // Get current quality score for gate
        return 0.0 // Placeholder
    }
    
    private func calculateGateQuality(gate: Gate, eventId: String) async -> Double {
        // Calculate quality score based on various factors
        return 75.0 // Placeholder
    }
    
    // MARK: - Public Interface
    
    func triggerManualProcessing() async {
        await runAutomaticProcessing()
    }
    
    func clearRecentEvents() {
        recentEvents.removeAll()
    }
    
    deinit {
        processingTimer?.invalidate()
    }
}
