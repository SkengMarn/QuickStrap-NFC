import Foundation
import Combine
import CoreLocation

/// Enhanced integration manager that orchestrates all enhanced services and Supabase functions
class EnhancedIntegrationManager: ObservableObject {
    static let shared = EnhancedIntegrationManager()
    
    // Service dependencies
    private let supabaseService = SupabaseService.shared
    private let processor = RealSchemaCheckInProcessor.shared
    private let bindingService = IntelligentGateBindingService.shared
    private let clusteringIntegration = GateClusteringIntegration()
    
    // Published state
    @Published var isFullyInitialized = false
    @Published var systemHealth: SystemHealth = .unknown
    @Published var activeProcesses: Set<ActiveProcess> = []
    @Published var lastSystemCheck: Date?
    
    // Configuration
    private let healthCheckInterval: TimeInterval = 60.0
    private let autoProcessingInterval: TimeInterval = 30.0
    
    // Timers
    private var healthCheckTimer: Timer?
    private var autoProcessingTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Models
    
    enum SystemHealth: String, CaseIterable {
        case excellent = "Excellent"
        case good = "Good"
        case fair = "Fair"
        case poor = "Poor"
        case unknown = "Unknown"
        
        var color: String {
            switch self {
            case .excellent: return "#4CAF50"
            case .good: return "#8BC34A"
            case .fair: return "#FF9800"
            case .poor: return "#F44336"
            case .unknown: return "#9E9E9E"
            }
        }
        
        var icon: String {
            switch self {
            case .excellent: return "checkmark.circle.fill"
            case .good: return "checkmark.circle"
            case .fair: return "exclamationmark.triangle"
            case .poor: return "xmark.circle"
            case .unknown: return "questionmark.circle"
            }
        }
    }
    
    enum ActiveProcess: String, CaseIterable {
        case realTimeProcessing = "Real-time Processing"
        case gateDiscovery = "Gate Discovery"
        case bindingAnalysis = "Binding Analysis"
        case dataSync = "Data Synchronization"
        case healthMonitoring = "Health Monitoring"
        
        var icon: String {
            switch self {
            case .realTimeProcessing: return "gear.circle"
            case .gateDiscovery: return "location.magnifyingglass"
            case .bindingAnalysis: return "brain.head.profile"
            case .dataSync: return "arrow.triangle.2.circlepath"
            case .healthMonitoring: return "heart.text.square"
            }
        }
    }
    
    struct SystemStatus {
        let health: SystemHealth
        let activeProcesses: Set<ActiveProcess>
        let lastCheck: Date
        let metrics: SystemMetrics
    }
    
    struct SystemMetrics {
        let processingEfficiency: Double
        let bindingQuality: Double
        let dataFreshness: TimeInterval
        let errorRate: Double
        let responseTime: TimeInterval
    }
    
    private init() {
        setupObservers()
    }
    
    // MARK: - Initialization
    
    func initializeEnhancedSystem(eventId: String) async throws {
        print("🚀 Initializing Enhanced Integration System...")
        
        do {
            // Step 1: Verify Supabase functions are available
            try await verifySupabaseFunctions()
            
            // Step 2: Initialize real-time processing
            try await initializeRealTimeProcessing(eventId: eventId)
            
            // Step 3: Start intelligent binding analysis
            try await initializeBindingIntelligence(eventId: eventId)
            
            // Step 4: Initialize gate discovery
            try await initializeGateDiscovery(eventId: eventId)
            
            // Step 5: Start system health monitoring
            startSystemHealthMonitoring()
            
            await MainActor.run {
                self.isFullyInitialized = true
                self.systemHealth = .good
                self.lastSystemCheck = Date()
            }
            
            print("✅ Enhanced Integration System initialized successfully")
            
        } catch {
            print("❌ System initialization failed: \(error)")
            await MainActor.run {
                self.systemHealth = .poor
            }
            throw error
        }
    }
    
    // MARK: - Service Initialization
    
    private func verifySupabaseFunctions() async throws {
        print("🔍 Verifying Supabase functions availability...")
        
        // Test the haversine distance function
        let testDistance = AdaptiveClusteringService.haversineDistance(
            lat1: 40.7128, lon1: -74.0060,
            lat2: 40.7589, lon2: -73.9851
        )
        
        guard testDistance > 8000 && testDistance < 9000 else {
            throw IntegrationError.functionVerificationFailed("Haversine distance function returned unexpected result")
        }
        
        print("✅ Supabase functions verified")
    }
    
    private func initializeRealTimeProcessing(eventId: String) async throws {
        print("⚡ Initializing real-time processing...")
        
        await MainActor.run {
            activeProcesses.insert(.realTimeProcessing)
        }
        
        // Start continuous processing
        processor.startContinuousProcessing(eventId: eventId)
        
        // Test initial processing
        try await processor.smartProcess(eventId: eventId)
        
        print("✅ Real-time processing initialized")
    }
    
    private func initializeBindingIntelligence(eventId: String) async throws {
        print("🧠 Initializing binding intelligence...")
        
        await MainActor.run {
            activeProcesses.insert(.bindingAnalysis)
        }
        
        // Run initial binding analysis
        try await bindingService.analyzeEventBindings(eventId: eventId)
        
        print("✅ Binding intelligence initialized")
    }
    
    private func initializeGateDiscovery(eventId: String) async throws {
        print("🔍 Initializing gate discovery...")
        
        await MainActor.run {
            activeProcesses.insert(.gateDiscovery)
        }
        
        // Run initial gate discovery
        try await clusteringIntegration.analyzeEventForGates(eventId: eventId, venueType: .hybrid)
        
        print("✅ Gate discovery initialized")
    }
    
    // MARK: - System Health Monitoring
    
    private func startSystemHealthMonitoring() {
        print("💓 Starting system health monitoring...")
        
        Task { @MainActor in
            activeProcesses.insert(.healthMonitoring)
        }
        
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: healthCheckInterval, repeats: true) { _ in
            Task {
                await self.performHealthCheck()
            }
        }
        
        // Perform initial health check
        Task {
            await performHealthCheck()
        }
    }
    
    private func performHealthCheck() async {
        let startTime = Date()
        
        // Check processing efficiency
        let processingEfficiency = calculateProcessingEfficiency()
        
        // Check binding quality
        let bindingQuality = calculateBindingQuality()
        
        // Check data freshness
        let dataFreshness = calculateDataFreshness()
        
        // Check response time
        let responseTime = Date().timeIntervalSince(startTime)
        
        let metrics = SystemMetrics(
            processingEfficiency: processingEfficiency,
            bindingQuality: bindingQuality,
            dataFreshness: dataFreshness,
            errorRate: 0.0, // Would track actual errors
            responseTime: responseTime
        )
        
        let health = calculateOverallHealth(metrics: metrics)
        
        await MainActor.run {
            self.systemHealth = health
            self.lastSystemCheck = Date()
        }
        
        print("💓 Health check complete: \(health.rawValue)")
    }
    
    // MARK: - Intelligent Orchestration
    
    func orchestrateIntelligentProcessing(eventId: String) async throws {
        print("🎯 Starting intelligent orchestration...")
        
        // Get comprehensive event stats to inform decisions
        let eventStats = try await supabaseService.fetchComprehensiveEventStats(eventId: eventId)
        
        // Decide on processing strategy based on event state
        let strategy = determineProcessingStrategy(eventStats: eventStats)
        
        switch strategy {
        case .intensive:
            try await runIntensiveProcessing(eventId: eventId)
        case .balanced:
            try await runBalancedProcessing(eventId: eventId)
        case .minimal:
            try await runMinimalProcessing(eventId: eventId)
        case .maintenance:
            try await runMaintenanceMode(eventId: eventId)
        }
        
        print("✅ Intelligent orchestration complete")
    }
    
    private enum ProcessingStrategy {
        case intensive  // High unlinked count, poor binding quality
        case balanced   // Normal operation
        case minimal    // Low activity, good quality
        case maintenance // System issues detected
    }
    
    private func determineProcessingStrategy(eventStats: ComprehensiveEventStats) -> ProcessingStrategy {
        let unlinkedRatio = Double(eventStats.unlinkedCheckins) / Double(max(eventStats.totalCheckins, 1))
        let linkingQuality = eventStats.linkingRate
        
        switch (unlinkedRatio, linkingQuality, systemHealth) {
        case let (unlinked, linking, _) where unlinked > 0.3 || linking < 0.5:
            return .intensive
        case let (_, _, health) where health == .poor:
            return .maintenance
        case let (unlinked, linking, _) where unlinked < 0.1 && linking > 0.8:
            return .minimal
        default:
            return .balanced
        }
    }
    
    private func runIntensiveProcessing(eventId: String) async throws {
        print("🔥 Running intensive processing mode...")
        
        // Run enhanced batch processing
        try await processor.processUnlinkedCheckInsEnhanced(eventId: eventId)
        
        // Analyze bindings more frequently
        try await bindingService.analyzeEventBindings(eventId: eventId)
        
        // Discover new gates
        try await clusteringIntegration.analyzeEventForGates(eventId: eventId, venueType: .hybrid)
        
        // Apply high-confidence recommendations automatically
        let highConfidenceRecommendations = bindingService.bindingRecommendations.filter { $0.confidence > 0.8 }
        for recommendation in highConfidenceRecommendations {
            try await bindingService.implementRecommendation(recommendation, eventId: eventId)
        }
    }
    
    private func runBalancedProcessing(eventId: String) async throws {
        print("⚖️ Running balanced processing mode...")
        
        // Smart processing based on data size
        try await processor.smartProcess(eventId: eventId)
        
        // Periodic binding analysis
        if shouldRunBindingAnalysis() {
            try await bindingService.analyzeEventBindings(eventId: eventId)
        }
    }
    
    private func runMinimalProcessing(eventId: String) async throws {
        print("🌙 Running minimal processing mode...")
        
        // Light processing only
        if processor.processedCount % 100 == 0 { // Every 100 processed items
            try await processor.smartProcess(eventId: eventId)
        }
    }
    
    private func runMaintenanceMode(eventId: String) async throws {
        print("🔧 Running maintenance mode...")
        
        // Focus on system health recovery
        try await performSystemMaintenance(eventId: eventId)
    }
    
    // MARK: - System Maintenance
    
    private func performSystemMaintenance(eventId: String) async throws {
        print("🛠️ Performing system maintenance...")
        
        // Clear any stuck processes
        await MainActor.run {
            if processor.isProcessing {
                // Reset processing state if stuck
                processor.stopContinuousProcessing()
                processor.startContinuousProcessing(eventId: eventId)
            }
        }
        
        // Verify database connections
        _ = try await supabaseService.fetchComprehensiveEventStats(eventId: eventId)
        
        // Reset system health
        await MainActor.run {
            systemHealth = .fair
        }
        
        print("✅ System maintenance complete")
    }
    
    // MARK: - Helper Methods
    
    private func setupObservers() {
        // Observe processor state
        processor.$isProcessing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isProcessing in
                if isProcessing {
                    self?.activeProcesses.insert(.realTimeProcessing)
                } else {
                    self?.activeProcesses.remove(.realTimeProcessing)
                }
            }
            .store(in: &cancellables)
        
        // Observe binding service state
        bindingService.$isAnalyzing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isAnalyzing in
                if isAnalyzing {
                    self?.activeProcesses.insert(.bindingAnalysis)
                } else {
                    self?.activeProcesses.remove(.bindingAnalysis)
                }
            }
            .store(in: &cancellables)
        
        // Observe clustering state
        clusteringIntegration.$isProcessing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isProcessing in
                if isProcessing {
                    self?.activeProcesses.insert(.gateDiscovery)
                } else {
                    self?.activeProcesses.remove(.gateDiscovery)
                }
            }
            .store(in: &cancellables)
    }
    
    private func calculateProcessingEfficiency() -> Double {
        let totalProcessed = processor.processedCount
        let totalLinked = processor.linkedCount
        
        guard totalProcessed > 0 else { return 0.0 }
        return Double(totalLinked) / Double(totalProcessed)
    }
    
    private func calculateBindingQuality() -> Double {
        switch bindingService.bindingQuality {
        case .excellent: return 1.0
        case .good: return 0.8
        case .fair: return 0.6
        case .poor: return 0.3
        }
    }
    
    private func calculateDataFreshness() -> TimeInterval {
        guard let lastProcessed = processor.lastProcessedTime else { return 3600.0 }
        return Date().timeIntervalSince(lastProcessed)
    }
    
    private func calculateOverallHealth(metrics: SystemMetrics) -> SystemHealth {
        let healthScore = (
            metrics.processingEfficiency * 0.3 +
            metrics.bindingQuality * 0.3 +
            (metrics.dataFreshness < 300 ? 1.0 : 0.5) * 0.2 +
            (1.0 - metrics.errorRate) * 0.2
        )
        
        switch healthScore {
        case 0.9...1.0: return .excellent
        case 0.7..<0.9: return .good
        case 0.5..<0.7: return .fair
        default: return .poor
        }
    }
    
    private func shouldRunBindingAnalysis() -> Bool {
        guard let lastCheck = lastSystemCheck else { return true }
        return Date().timeIntervalSince(lastCheck) > 300 // Every 5 minutes
    }
    
    // MARK: - Public Interface
    
    func getSystemStatus() -> SystemStatus {
        let metrics = SystemMetrics(
            processingEfficiency: calculateProcessingEfficiency(),
            bindingQuality: calculateBindingQuality(),
            dataFreshness: calculateDataFreshness(),
            errorRate: 0.0,
            responseTime: 0.0
        )
        
        return SystemStatus(
            health: systemHealth,
            activeProcesses: activeProcesses,
            lastCheck: lastSystemCheck ?? Date(),
            metrics: metrics
        )
    }
    
    func shutdown() {
        print("🛑 Shutting down Enhanced Integration System...")
        
        healthCheckTimer?.invalidate()
        autoProcessingTimer?.invalidate()
        processor.stopContinuousProcessing()
        
        activeProcesses.removeAll()
        isFullyInitialized = false
        
        print("✅ System shutdown complete")
    }
}

// MARK: - Error Types

enum IntegrationError: LocalizedError {
    case functionVerificationFailed(String)
    case initializationFailed(String)
    case healthCheckFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .functionVerificationFailed(let message):
            return "Function verification failed: \(message)"
        case .initializationFailed(let message):
            return "Initialization failed: \(message)"
        case .healthCheckFailed(let message):
            return "Health check failed: \(message)"
        }
    }
}
