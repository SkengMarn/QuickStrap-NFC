import SwiftUI
import Charts

struct DatabaseStatsView: View {
    @EnvironmentObject var eventData: EventDataManager
    @EnvironmentObject var supabaseService: SupabaseService
    @StateObject private var viewModel = StatsViewModel()
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 20) {
                    // Header with event info
                    headerSection
                    
                    // Time range selector
                    timeRangeSelector
                    
                    // Overview cards
                    overviewCards
                    
                    // Category breakdown
                    categoryBreakdownSection
                    
                    // Activity chart
                    activityChartSection
                    
                    // Recent activity
                    recentActivitySection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Statistics")
            .navigationBarTitleDisplayMode(.large)
            .preferredColorScheme(.dark)
            .refreshable {
                await viewModel.refreshData()
            }
        }
        .onAppear {
            viewModel.setup(supabaseService: supabaseService)
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(supabaseService.currentEvent?.name ?? "Event Statistics")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    if let location = supabaseService.currentEvent?.location {
                        Text(location)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                
                Spacer()
                
                // Refresh button
                Button(action: {
                    Task {
                        await viewModel.refreshData()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.title3)
                        .foregroundColor(.white)
                }
                .disabled(viewModel.isLoading)
            }
            
            // Last updated
            if let lastUpdated = viewModel.lastUpdated {
                Text("Last updated: \(lastUpdated, style: .time)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    
    // MARK: - Time Range Selector
    private var timeRangeSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(StatsTimeRange.allCases, id: \.self) { range in
                    Button(action: {
                        viewModel.selectedTimeRange = range
                    }) {
                        Text(range.displayName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(viewModel.selectedTimeRange == range ? .black : .white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                viewModel.selectedTimeRange == range ? .white : .clear,
                                in: RoundedRectangle(cornerRadius: 20)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(.white.opacity(0.3), lineWidth: 1)
                            )
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Overview Cards
    private var overviewCards: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 16) {
            overviewCard(
                title: "Total Check-ins",
                value: "\(viewModel.stats?.totalCheckedIn ?? 0)",
                subtitle: "of \(viewModel.stats?.totalWristbands ?? 0) wristbands",
                color: .blue,
                icon: "checkmark.circle.fill"
            )
            
            overviewCard(
                title: "Completion Rate",
                value: "\(Int(viewModel.stats?.checkInRate ?? 0))%",
                subtitle: "check-in progress",
                color: .green,
                icon: "chart.line.uptrend.xyaxis"
            )
            
            overviewCard(
                title: "Today's Scans",
                value: "\(viewModel.stats?.totalScansToday ?? 0)",
                subtitle: "scans today",
                color: .orange,
                icon: "wave.3.right.circle.fill"
            )
            
            overviewCard(
                title: "Active Categories",
                value: "\(viewModel.activeCategoriesCount)",
                subtitle: "categories in use",
                color: .purple,
                icon: "tag.fill"
            )
        }
        .padding(.horizontal, 20)
    }
    
    private func overviewCard(title: String, value: String, subtitle: String, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - Category Breakdown Section
    private var categoryBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Category Breakdown")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 20)
            
            if let categoryStats = viewModel.stats?.categoryBreakdown {
                LazyVStack(spacing: 12) {
                    ForEach(Array(categoryStats.keys.sorted(by: { $0.name < $1.name })), id: \.self) { category in
                        if let stats = categoryStats[category] {
                            categoryRow(category: category, stats: stats)
                        }
                    }
                }
                .padding(.horizontal, 20)
            } else {
                Text("No category data available")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 20)
            }
        }
    }
    
    private func categoryRow(category: WristbandCategory, stats: CategoryStats) -> some View {
        VStack(spacing: 12) {
            HStack {
                // Category indicator
                Circle()
                    .fill(Color(hex: category.color) ?? .blue)
                    .frame(width: 12, height: 12)
                
                Text(category.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                
                Spacer()
                
                Text("\(stats.checkedIn)/\(stats.total)")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Text("(\(Int(stats.percentage))%)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
            
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(.white.opacity(0.2))
                        .frame(height: 6)
                        .cornerRadius(3)
                    
                    Rectangle()
                        .fill(Color(hex: category.color) ?? .blue)
                        .frame(width: geometry.size.width * stats.completionRate, height: 6)
                        .cornerRadius(3)
                        .animation(.easeInOut(duration: 0.5), value: stats.completionRate)
                }
            }
            .frame(height: 6)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Activity Chart Section
    private var activityChartSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Check-in Activity")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 20)
            
            if !viewModel.chartData.isEmpty {
                Chart(viewModel.chartData) { dataPoint in
                    LineMark(
                        x: .value("Time", dataPoint.time),
                        y: .value("Check-ins", dataPoint.count)
                    )
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    
                    AreaMark(
                        x: .value("Time", dataPoint.time),
                        y: .value("Check-ins", dataPoint.count)
                    )
                    .foregroundStyle(.blue.opacity(0.3))
                }
                .frame(height: 200)
                .chartXAxis {
                    AxisMarks(values: .automatic) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(.white.opacity(0.2))
                        AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(.white.opacity(0.5))
                        AxisValueLabel()
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(.white.opacity(0.2))
                        AxisTick(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(.white.opacity(0.5))
                        AxisValueLabel()
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding(20)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 20)
            } else {
                Text("No activity data available")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 20)
            }
        }
    }
    
    // MARK: - Recent Activity Section
    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent Activity")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 20)
            
            if let recentActivity = viewModel.stats?.recentActivity, !recentActivity.isEmpty {
                LazyVStack(spacing: 8) {
                    ForEach(recentActivity.prefix(10)) { log in
                        recentActivityRow(log)
                    }
                }
                .padding(.horizontal, 20)
            } else {
                Text("No recent activity")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
                    .padding(.horizontal, 20)
            }
        }
    }
    
    private func recentActivityRow(_ log: CheckinLog) -> some View {
        HStack(spacing: 12) {
            // Time indicator
            VStack(spacing: 2) {
                Text(log.timestamp, style: .time)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                
                Text(log.timestamp, style: .date)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
            }
            .frame(width: 60)
            
            // Activity info
            VStack(alignment: .leading, spacing: 2) {
                Text("Wristband Check-in")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                
                Text("ID: \(log.wristbandId.suffix(8))")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                
                if let location = log.location {
                    Text("📍 \(location)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            
            Spacer()
            
            // Success indicator
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundColor(.green)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Stats View Model
@MainActor
class StatsViewModel: ObservableObject {
    @Published var stats: EventStats?
    @Published var selectedTimeRange: StatsTimeRange = .today {
        didSet {
            Task { @MainActor in
                await loadStats()
            }
        }
    }
    @Published var isLoading = false
    @Published var lastUpdated: Date?
    @Published var chartData: [ChartDataPoint] = []
    
    private var supabaseService: SupabaseService?
    
    var activeCategoriesCount: Int {
        stats?.categoryBreakdown.values.filter { $0.total > 0 }.count ?? 0
    }
    
    func setup(supabaseService: SupabaseService) {
        self.supabaseService = supabaseService
        Task { @MainActor in
            await loadStats()
        }
    }
    
    @MainActor
    func refreshData() async {
        await loadStats()
    }
    
    @MainActor
    private func loadStats() async {
        guard let supabaseService = supabaseService,
              let currentEvent = supabaseService.currentEvent else { return }
        
        let eventId = currentEvent.id
        let seriesId = currentEvent.seriesId
        
        isLoading = true
        
        do {
            // Pass seriesId if this is a series event
            let eventStats = try await supabaseService.fetchEventStats(
                for: eventId,
                seriesId: seriesId,
                timeRange: selectedTimeRange
            )
            let chartData = generateChartData(from: eventStats.recentActivity)
            
            self.stats = eventStats
            self.chartData = chartData
            self.lastUpdated = Date()
            self.isLoading = false
        } catch {
            self.isLoading = false
            // Handle error appropriately
            print("Failed to load stats: \(error)")
        }
    }
    
    private func generateChartData(from logs: [CheckinLog]) -> [ChartDataPoint] {
        let calendar = Calendar.current
        let _ = Date() // Current time reference
        
        // Group logs by hour for today, or by day for longer periods
        let groupingComponent: Calendar.Component = selectedTimeRange == .today ? .hour : .day
        
        var groupedData: [Date: Int] = [:]
        
        for log in logs {
            let key = calendar.dateInterval(of: groupingComponent, for: log.timestamp)?.start ?? log.timestamp
            groupedData[key, default: 0] += 1
        }
        
        // Create data points for the chart
        let sortedKeys = groupedData.keys.sorted()
        return sortedKeys.map { date in
            ChartDataPoint(time: date, count: groupedData[date] ?? 0)
        }
    }
}

// MARK: - Chart Data Model
struct ChartDataPoint: Identifiable {
    let id = UUID()
    let time: Date
    let count: Int
}

// MARK: - Color Extension
extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#Preview {
    DatabaseStatsView()
        .environmentObject(EventDataManager())
        .environmentObject(SupabaseService.shared)
}
