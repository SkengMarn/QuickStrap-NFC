import SwiftUI
import Combine

/// Enhanced Gates View Model for Real Schema Processing
class EnhancedGatesViewModel: ObservableObject {
    @Published var isProcessingCheckIns = false
    @Published var processingEfficiency: ProcessingEfficiency = .poor
    @Published var discoveredGates: [GateClusteringIntegration.DiscoveredGate] = []
    @Published var showGateDiscoveryResults = false
    
    private var cancellables = Set<AnyCancellable>()
    
    func observeProcessorState(_ processor: RealSchemaCheckInProcessor) {
        // Observe processing state changes
        processor.$isProcessing
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isProcessing in
                self?.isProcessingCheckIns = isProcessing
            }
            .store(in: &cancellables)
        
        // Observe processing results
        processor.$linkedCount
            .receive(on: DispatchQueue.main)
            .sink { _ in
                // Trigger data reload in parent view
                NotificationCenter.default.post(name: .enhancedGatesDataReload, object: nil)
            }
            .store(in: &cancellables)
        
        // Observe efficiency changes
        processor.$processingEfficiency
            .receive(on: DispatchQueue.main)
            .sink { [weak self] efficiency in
                self?.processingEfficiency = efficiency
            }
            .store(in: &cancellables)
    }
}

extension Notification.Name {
    static let enhancedGatesDataReload = Notification.Name("enhancedGatesDataReload")
}

/// Enhanced Gates View Extension with Real Schema Processing
extension EnhancedGatesView {
    
    // MARK: - Real Schema Processing Integration
    
    func startRealSchemaProcessing() {
        let processor = RealSchemaCheckInProcessor.shared
        
        // Start continuous processing with current event
        if let eventId = SupabaseService.shared.currentEvent?.id {
            processor.startContinuousProcessing(eventId: eventId)
        }
    }
    
    func stopRealSchemaProcessing() {
        RealSchemaCheckInProcessor.shared.stopContinuousProcessing()
    }
    
    func createEnhancedGatesViewModel() -> EnhancedGatesViewModel {
        let viewModel = EnhancedGatesViewModel()
        let processor = RealSchemaCheckInProcessor.shared
        viewModel.observeProcessorState(processor)
        return viewModel
    }
    
    // MARK: - Enhanced Processing Controls
    
    func enhancedProcessingControls(viewModel: EnhancedGatesViewModel) -> some View {
        VStack(spacing: 16) {
            // Processing Status Card
            processingStatusCard(viewModel: viewModel)
            
            // Processing Controls
            processingControlsView(viewModel: viewModel)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
    
    private func processingStatusCard(viewModel: EnhancedGatesViewModel) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "gear.circle.fill")
                    .foregroundColor(.blue)
                Text("Real Schema Processing")
                    .font(.headline)
                Spacer()
                
                if viewModel.isProcessingCheckIns {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            
            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("Processed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(RealSchemaCheckInProcessor.shared.processedCount)")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                
                VStack(alignment: .leading) {
                    Text("Linked")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(RealSchemaCheckInProcessor.shared.linkedCount)")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                }
                
                VStack(alignment: .leading) {
                    Text("Efficiency")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack {
                        Image(systemName: viewModel.processingEfficiency.icon)
                            .foregroundColor(Color(viewModel.processingEfficiency.color))
                        Text(viewModel.processingEfficiency.rawValue)
                            .font(.title3)
                            .fontWeight(.medium)
                    }
                }
                
                Spacer()
            }
            
            if let lastProcessed = RealSchemaCheckInProcessor.shared.lastProcessedTime {
                Text("Last processed: \(lastProcessed, style: .relative) ago")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
    
    private func processingControlsView(viewModel: EnhancedGatesViewModel) -> some View {
        HStack(spacing: 12) {
            Button(action: {
                Task {
                    if let eventId = SupabaseService.shared.currentEvent?.id {
                        try? await RealSchemaCheckInProcessor.shared.smartProcess(eventId: eventId)
                    }
                }
            }) {
                HStack {
                    Image(systemName: "play.circle.fill")
                    Text("Process Now")
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.blue)
                .cornerRadius(8)
            }
            .disabled(viewModel.isProcessingCheckIns)
            
            Button(action: {
                Task {
                    if let eventId = SupabaseService.shared.currentEvent?.id {
                        let _ = try? await RealSchemaCheckInProcessor.shared.generateProcessingReport(eventId: eventId)
                        // Handle report display
                    }
                }
            }) {
                HStack {
                    Image(systemName: "chart.bar.doc.horizontal")
                    Text("Report")
                }
                .foregroundColor(.blue)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Enhanced Gate Discovery
    
    func startEnhancedGateDiscovery() {
        Task {
            do {
                if let eventId = SupabaseService.shared.currentEvent?.id {
                    // Use the adaptive clustering integration
                    let integration = GateClusteringIntegration()
                    
                    // Analyze event for potential gates
                    try await integration.analyzeEventForGates(
                        eventId: eventId,
                        venueType: .hybrid
                    )
                    
                    // Get discovered gates
                    let discoveredGates = await integration.discoveredGates
                    
                    // Handle discovered gates
                    print("🎯 Discovered \(discoveredGates.count) potential gates")
                }
            } catch {
                print("❌ Gate discovery failed: \(error)")
            }
        }
    }
}

// MARK: - Processing Report View

struct ProcessingReportView: View {
    let report: ProcessingReport
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Overall Stats
                    overallStatsSection
                    
                    // Category Breakdown
                    categoryBreakdownSection
                    
                    // Event Statistics
                    eventStatsSection
                }
                .padding()
            }
            .navigationTitle("Processing Report")
            .navigationBarTitleDisplayMode(.large)
        }
    }
    
    private var overallStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overall Performance")
                .font(.headline)
            
            HStack(spacing: 20) {
                StatCard(
                    title: "Processed",
                    value: "\(report.totalProcessed)",
                    icon: "tray.full",
                    color: .blue
                )
                
                StatCard(
                    title: "Linked",
                    value: "\(report.totalLinked)",
                    icon: "link",
                    color: .green
                )
                
                StatCard(
                    title: "Success Rate",
                    value: "\(Int(report.linkingRate * 100))%",
                    icon: "percent",
                    color: .orange
                )
            }
            
            HStack {
                Image(systemName: report.overallEfficiency.icon)
                    .foregroundColor(Color(report.overallEfficiency.color))
                Text("Efficiency: \(report.overallEfficiency.rawValue)")
                    .fontWeight(.medium)
                Spacer()
                Text("Last: \(report.formattedLastProcessed)")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private var categoryBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Category Breakdown")
                .font(.headline)
            
            ForEach(report.categoryStats, id: \.categoryName) { stats in
                HStack {
                    VStack(alignment: .leading) {
                        Text(stats.categoryName)
                            .fontWeight(.medium)
                        Text("\(stats.totalLinked)/\(stats.totalProcessed) linked")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        Text("\(Int(stats.linkingRate * 100))%")
                            .fontWeight(.semibold)
                        HStack {
                            Image(systemName: stats.efficiency.icon)
                                .foregroundColor(Color(stats.efficiency.color))
                            Text(stats.efficiency.rawValue)
                                .font(.caption)
                        }
                    }
                }
                .padding()
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private var eventStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Event Statistics")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                StatCard(
                    title: "Total Wristbands",
                    value: "\(report.eventStats.totalWristbands)",
                    icon: "person.3",
                    color: .purple
                )
                
                StatCard(
                    title: "Check-in Rate",
                    value: "\(Int(report.eventStats.checkInRate * 100))%",
                    icon: "checkmark.circle",
                    color: .blue
                )
                
                StatCard(
                    title: "Gate Utilization",
                    value: "\(Int(report.eventStats.gateUtilization * 100))%",
                    icon: "door.left.hand.open",
                    color: .green
                )
                
                StatCard(
                    title: "Categories",
                    value: "\(report.eventStats.categoriesCount)",
                    icon: "tag.fill",
                    color: .orange
                )
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// StatCard is already defined in ComprehensiveAnalyticsDashboard.swift
