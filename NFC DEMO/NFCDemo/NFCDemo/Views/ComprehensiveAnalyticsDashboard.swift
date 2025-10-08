import SwiftUI
import Charts
import Combine

/// Comprehensive analytics dashboard using enhanced Supabase functions and real schema processing
struct ComprehensiveAnalyticsDashboard: View {
    @StateObject private var supabaseService = SupabaseService.shared
    @StateObject private var processor = RealSchemaCheckInProcessor.shared
    @StateObject private var bindingService = IntelligentGateBindingService.shared
    @StateObject private var clusteringIntegration = GateClusteringIntegration()
    
    @State private var eventStats: ComprehensiveEventStats?
    @State private var categories: [EventCategory] = []
    @State private var gateCounts: [String: Int] = [:]
    @State private var processingReport: ProcessingReport?
    @State private var bindingRecommendations: [IntelligentGateBindingService.BindingRecommendation] = []
    
    @State private var isLoading = false
    @State private var selectedTimeRange: AnalyticsTimeRange = .today
    @State private var showingDetailedReport = false
    @State private var refreshTimer: Timer?
    
    enum AnalyticsTimeRange: String, CaseIterable {
        case today = "Today"
        case week = "This Week"
        case month = "This Month"
        case all = "All Time"
        
        var icon: String {
            switch self {
            case .today: return "calendar"
            case .week: return "calendar.badge.clock"
            case .month: return "calendar.badge.plus"
            case .all: return "calendar.badge.exclamationmark"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 20) {
                    // Header with refresh controls
                    headerSection
                    
                    // Key Performance Indicators
                    if let stats = eventStats {
                        kpiSection(stats)
                    }
                    
                    // Real-time Processing Status
                    processingStatusSection
                    
                    // Category Analytics
                    if !categories.isEmpty {
                        categoryAnalyticsSection
                    }
                    
                    // Gate Performance
                    if !gateCounts.isEmpty {
                        gatePerformanceSection
                    }
                    
                    // Binding Intelligence
                    bindingIntelligenceSection
                    
                    // Clustering Insights
                    clusteringInsightsSection
                    
                    // Recommendations
                    if !bindingRecommendations.isEmpty {
                        recommendationsSection
                    }
                }
                .padding()
            }
            .navigationTitle("Analytics Dashboard")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Detailed Report") {
                        showingDetailedReport = true
                    }
                }
            }
            .refreshable {
                await loadAllData()
            }
            .onAppear {
                startRealTimeUpdates()
            }
            .onDisappear {
                stopRealTimeUpdates()
            }
            .sheet(isPresented: $showingDetailedReport) {
                if let report = processingReport {
                    ProcessingReportView(report: report)
                }
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Event Analytics")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    if let eventName = supabaseService.currentEvent?.name {
                        Text(eventName)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            
            // Time Range Selector
            Picker("Time Range", selection: $selectedTimeRange) {
                ForEach(AnalyticsTimeRange.allCases, id: \.self) { range in
                    HStack {
                        Image(systemName: range.icon)
                        Text(range.rawValue)
                    }
                    .tag(range)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .onChange(of: selectedTimeRange) { _ in
                Task { await loadAllData() }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - KPI Section
    
    private func kpiSection(_ stats: ComprehensiveEventStats) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Key Performance Indicators")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                KPICard(
                    title: "Check-in Rate",
                    value: "\(Int(stats.checkInRate * 100))%",
                    subtitle: "\(stats.uniqueCheckins)/\(stats.totalWristbands)",
                    color: stats.checkInRate > 0.8 ? .green : stats.checkInRate > 0.5 ? .orange : .red,
                    icon: "person.badge.checkmark"
                )
                
                KPICard(
                    title: "Gate Linking",
                    value: "\(Int(stats.linkingRate * 100))%",
                    subtitle: stats.linkingQuality.rawValue,
                    color: Color(stats.linkingQuality.color),
                    icon: "point.3.connected.trianglepath.dotted"
                )
                
                KPICard(
                    title: "Gate Utilization",
                    value: "\(Int(stats.gateUtilization * 100))%",
                    subtitle: "\(stats.activeGates)/\(stats.totalGates) active",
                    color: stats.gateUtilization > 0.7 ? .green : stats.gateUtilization > 0.4 ? .orange : .red,
                    icon: "door.left.hand.open"
                )
                
                KPICard(
                    title: "Avg Scans/Gate",
                    value: String(format: "%.1f", stats.avgCheckinsPerGate),
                    subtitle: "per active gate",
                    color: .blue,
                    icon: "chart.bar.fill"
                )
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Processing Status Section
    
    private var processingStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Real-time Processing")
                    .font(.headline)
                Spacer()
                
                if processor.isProcessing {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Processing...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("Processed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(processor.processedCount)")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                
                VStack(alignment: .leading) {
                    Text("Linked")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(processor.linkedCount)")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                }
                
                VStack(alignment: .leading) {
                    Text("Efficiency")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack {
                        Image(systemName: processor.processingEfficiency.icon)
                            .foregroundColor(Color(processor.processingEfficiency.color))
                        Text(processor.processingEfficiency.rawValue)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
                
                Spacer()
            }
            
            if let lastProcessed = processor.lastProcessedTime {
                Text("Last processed: \(lastProcessed, style: .relative) ago")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Category Analytics Section
    
    private var categoryAnalyticsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Category Distribution")
                .font(.headline)
            
            Chart(categories, id: \.name) { category in
                BarMark(
                    x: .value("Count", category.wristbandCount),
                    y: .value("Category", category.displayName)
                )
                .foregroundStyle(Color(category.color))
            }
            .frame(height: max(200, CGFloat(categories.count * 30)))
            
            // Category processing stats
            if !processor.categoryStats.isEmpty {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 8) {
                    ForEach(Array(processor.categoryStats.values), id: \.categoryName) { stats in
                        categoryProcessingCard(stats)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private func categoryProcessingCard(_ stats: RealSchemaCheckInProcessor.CategoryProcessingStats) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(stats.categoryName)
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                Image(systemName: stats.efficiency.icon)
                    .foregroundColor(Color(stats.efficiency.color))
                    .font(.caption)
            }
            
            HStack {
                Text("\(stats.totalLinked)/\(stats.totalProcessed)")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(Int(stats.linkingRate * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(6)
    }
    
    // MARK: - Gate Performance Section
    
    private var gatePerformanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Gate Performance")
                .font(.headline)
            
            let sortedGates = gateCounts.sorted { $0.value > $1.value }
            
            Chart(sortedGates.prefix(10), id: \.key) { gate in
                BarMark(
                    x: .value("Scans", gate.value),
                    y: .value("Gate", "Gate \(gate.key.prefix(8))")
                )
                .foregroundStyle(.blue)
            }
            .frame(height: max(200, CGFloat(min(sortedGates.count, 10) * 25)))
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Binding Intelligence Section
    
    private var bindingIntelligenceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Binding Intelligence")
                    .font(.headline)
                Spacer()
                
                HStack {
                    Image(systemName: bindingService.bindingQuality.color.contains("4CAF50") ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(Color(bindingService.bindingQuality.color))
                    Text(bindingService.bindingQuality.rawValue)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
            
            Text(bindingService.bindingQuality.description)
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack {
                Button(action: {
                    Task {
                        guard let eventId = supabaseService.currentEvent?.id else { return }
                        try? await bindingService.analyzeEventBindings(eventId: eventId)
                    }
                }) {
                    HStack {
                        Image(systemName: "brain.head.profile")
                        Text("Analyze Bindings")
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .cornerRadius(8)
                }
                .disabled(bindingService.isAnalyzing)
                
                if bindingService.isAnalyzing {
                    ProgressView()
                        .scaleEffect(0.8)
                }
                
                Spacer()
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Clustering Insights Section
    
    private var clusteringInsightsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Gate Discovery")
                    .font(.headline)
                Spacer()
                
                if clusteringIntegration.isProcessing {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            
            HStack {
                VStack(alignment: .leading) {
                    Text("Discovered Gates")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(clusteringIntegration.discoveredGates.count)")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                
                Spacer()
                
                Button(action: {
                    Task {
                        guard let eventId = supabaseService.currentEvent?.id else { return }
                        try? await clusteringIntegration.analyzeEventForGates(eventId: eventId)
                    }
                }) {
                    HStack {
                        Image(systemName: "location.magnifyingglass")
                        Text("Discover Gates")
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(6)
                }
                .disabled(clusteringIntegration.isProcessing)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Recommendations Section
    
    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Intelligent Recommendations")
                .font(.headline)
            
            ForEach(bindingRecommendations.prefix(3)) { recommendation in
                recommendationCard(recommendation)
            }
            
            if bindingRecommendations.count > 3 {
                Button("View All \(bindingRecommendations.count) Recommendations") {
                    // Show all recommendations
                }
                .foregroundColor(.blue)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private func recommendationCard(_ recommendation: IntelligentGateBindingService.BindingRecommendation) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: recommendation.recommendedAction.icon)
                        .foregroundColor(Color(recommendation.recommendedAction.color))
                    Text(recommendation.recommendedAction.displayName)
                        .fontWeight(.medium)
                }
                
                Text(recommendation.reasoning)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            Button("Apply") {
                Task {
                    guard let eventId = supabaseService.currentEvent?.id else { return }
                    try? await bindingService.implementRecommendation(recommendation, eventId: eventId)
                    await loadAllData()
                }
            }
            .foregroundColor(.blue)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(6)
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(8)
    }
    
    // MARK: - Data Loading
    
    private func loadAllData() async {
        guard let eventId = supabaseService.currentEvent?.id else { return }
        
        await MainActor.run {
            isLoading = true
        }
        
        async let statsTask = supabaseService.fetchComprehensiveEventStats(eventId: eventId)
        async let categoriesTask = supabaseService.fetchEventCategories(eventId: eventId)
        async let gateCountsTask = supabaseService.fetchGateScanCounts(eventId: eventId)
        async let reportTask = processor.generateProcessingReport(eventId: eventId)
        
        do {
            let (stats, cats, gates, report) = try await (statsTask, categoriesTask, gateCountsTask, reportTask)
            
            await MainActor.run {
                self.eventStats = stats
                self.categories = cats
                self.gateCounts = gates
                self.processingReport = report
                self.isLoading = false
            }
            
            // Load binding recommendations
            self.bindingRecommendations = bindingService.bindingRecommendations
            
        } catch {
            print("❌ Failed to load analytics data: \(error)")
            await MainActor.run {
                isLoading = false
            }
        }
    }
    
    // MARK: - Real-time Updates
    
    private func startRealTimeUpdates() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
            Task {
                await loadAllData()
            }
        }
        
        Task {
            await loadAllData()
        }
    }
    
    private func stopRealTimeUpdates() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}

// MARK: - KPI Card Component

struct KPICard: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.tertiarySystemBackground))
        .cornerRadius(8)
    }
}
