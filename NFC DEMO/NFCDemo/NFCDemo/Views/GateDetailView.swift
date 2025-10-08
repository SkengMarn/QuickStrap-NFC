import SwiftUI
import Charts

struct GateDetailView: View {
    let gate: Gate
    let binding: GateBinding?
    
    @StateObject private var supabaseService = SupabaseService.shared
    @State private var scanHistory: [CheckinLog] = []
    @State private var isLoading = true
    @State private var scanStats: ScanStats?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Gate Header
                gateHeaderSection
                
                // Stats Cards
                statsSection
                
                // Scan History Chart
                if !scanHistory.isEmpty {
                    chartSection
                }
                
                // Wristband Breakdown
                wristbandBreakdownSection
                
                // Recent Scans List
                recentScansSection
            }
            .padding()
        }
        .navigationTitle(gate.name)
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            loadGateData()
        }
    }
    
    // MARK: - Header Section
    private var gateHeaderSection: some View {
        VStack(spacing: 12) {
            // Status Badge
            HStack {
                statusBadge
                Spacer()
                confidenceBadge
            }
            
            // Location Info
            if let lat = gate.latitude, let lon = gate.longitude {
                HStack {
                    Image(systemName: "location.fill")
                        .foregroundColor(.blue)
                    Text("\(lat, specifier: "%.6f"), \(lon, specifier: "%.6f")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(statusColor.opacity(0.1))
        .cornerRadius(16)
    }
    
    private var confidenceBadge: some View {
        Text("\(Int((binding?.confidence ?? 0) * 100))% confidence")
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(.blue)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(16)
    }
    
    // MARK: - Stats Section
    private var statsSection: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
            StatCard(
                title: "Total Scans",
                value: "\(scanHistory.count)",
                icon: "qrcode.viewfinder",
                color: .blue
            )
            
            StatCard(
                title: "Sample Count",
                value: "\(binding?.sampleCount ?? 0)",
                icon: "chart.bar.fill",
                color: .green
            )
            
            if let stats = scanStats {
                StatCard(
                    title: "Peak Hour",
                    value: stats.peakHour,
                    icon: "clock.fill",
                    color: .orange
                )
                
                StatCard(
                    title: "Unique Wristbands",
                    value: "\(stats.uniqueWristbands)",
                    icon: "person.fill",
                    color: .purple
                )
            }
        }
    }
    
    // MARK: - Chart Section
    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Unique Wristbands Activity")
                .font(.headline)
                .fontWeight(.semibold)
            
            Chart(hourlyData) { data in
                BarMark(
                    x: .value("Hour", data.hour),
                    y: .value("Unique Wristbands", data.count)
                )
                .foregroundStyle(.blue.gradient)
                .cornerRadius(4)
            }
            .frame(height: 200)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 2)) { value in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .abbreviated)))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Wristband Breakdown Section
    private var wristbandBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Wristband Breakdown")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(uniqueWristbands.count) unique")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if isLoading {
                ProgressView("Loading wristband data...")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else if uniqueWristbands.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.slash")
                        .font(.system(size: 32))
                        .foregroundColor(.orange)
                    Text("No Wristbands Found")
                        .font(.headline)
                    Text("No wristbands have been scanned at this gate")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(Array(uniqueWristbands.prefix(10)), id: \.key) { wristbandId, scanCount in
                        WristbandBreakdownRow(
                            wristbandId: wristbandId,
                            scanCount: scanCount,
                            lastScan: lastScanForWristband(wristbandId)
                        )
                    }
                    
                    if uniqueWristbands.count > 10 {
                        Text("+ \(uniqueWristbands.count - 10) more wristbands")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Recent Scans Section
    private var recentScansSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Scans")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(scanHistory.count) total")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if isLoading {
                ProgressView("Loading scan history...")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else if scanHistory.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundColor(.orange)
                    Text("No Scans Found")
                        .font(.headline)
                    Text("This gate has no recorded scan activity")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(scanHistory.prefix(20), id: \.id) { scan in
                        ScanHistoryRow(scan: scan)
                    }
                    
                    if scanHistory.count > 20 {
                        Text("+ \(scanHistory.count - 20) more scans")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 8)
                    }
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    private var statusColor: Color {
        switch binding?.status {
        case .enforced: return .green
        case .probation: return .orange
        case .unbound: return .gray
        case .none: return .gray
        }
    }
    
    private var statusText: String {
        switch binding?.status {
        case .enforced: return "Confirmed"
        case .probation: return "Probation"
        case .unbound: return "Unbound"
        case .none: return "No Binding"
        }
    }
    
    private var uniqueWristbands: [(key: String, value: Int)] {
        let wristbandCounts = Dictionary(grouping: scanHistory) { $0.wristbandId }
            .mapValues { $0.count }
        return wristbandCounts.sorted { $0.value > $1.value }
    }
    
    private func lastScanForWristband(_ wristbandId: String) -> Date? {
        return scanHistory
            .filter { $0.wristbandId == wristbandId }
            .max { $0.timestamp < $1.timestamp }?
            .timestamp
    }
    
    private var hourlyData: [HourlyData] {
        let calendar = Calendar.current
        let now = Date()
        
        // Determine aggregation based on data span
        let oldestScan = scanHistory.min { $0.timestamp < $1.timestamp }?.timestamp ?? now
        let timeSpan = now.timeIntervalSince(oldestScan)
        
        if timeSpan <= 86400 { // 24 hours - show hourly
            return generateHourlyData(calendar: calendar, now: now)
        } else if timeSpan <= 604800 { // 7 days - show daily
            return generateDailyData(calendar: calendar, now: now)
        } else if timeSpan <= 2592000 { // 30 days - show weekly
            return generateWeeklyData(calendar: calendar, now: now)
        } else { // More than 30 days - show monthly
            return generateMonthlyData(calendar: calendar, now: now)
        }
    }
    
    private func generateHourlyData(calendar: Calendar, now: Date) -> [HourlyData] {
        var hourlyScans: [Date: Int] = [:]
        
        // Initialize 24 hours with 0
        for i in 0..<24 {
            let hour = calendar.date(byAdding: .hour, value: -i, to: now)!
            let hourStart = calendar.date(bySetting: .minute, value: 0, of: hour)!
            hourlyScans[hourStart] = 0
        }
        
        // Count unique wristbands by hour
        var hourlyUniqueWristbands: [Date: Set<String>] = [:]
        
        for scan in scanHistory {
            let hourStart = calendar.date(bySetting: .minute, value: 0, of: scan.timestamp)!
            if hourlyUniqueWristbands[hourStart] == nil {
                hourlyUniqueWristbands[hourStart] = Set<String>()
            }
            hourlyUniqueWristbands[hourStart]?.insert(scan.wristbandId)
        }
        
        // Convert to counts
        for (hour, wristbands) in hourlyUniqueWristbands {
            hourlyScans[hour] = wristbands.count
        }
        
        return hourlyScans.map { HourlyData(hour: $0.key, count: $0.value) }
            .sorted { $0.hour < $1.hour }
    }
    
    private func generateDailyData(calendar: Calendar, now: Date) -> [HourlyData] {
        var dailyScans: [Date: Int] = [:]
        
        // Initialize 7 days with 0
        for i in 0..<7 {
            let day = calendar.date(byAdding: .day, value: -i, to: now)!
            let dayStart = calendar.startOfDay(for: day)
            dailyScans[dayStart] = 0
        }
        
        // Count unique wristbands by day
        var dailyUniqueWristbands: [Date: Set<String>] = [:]
        
        for scan in scanHistory {
            let dayStart = calendar.startOfDay(for: scan.timestamp)
            if dailyUniqueWristbands[dayStart] == nil {
                dailyUniqueWristbands[dayStart] = Set<String>()
            }
            dailyUniqueWristbands[dayStart]?.insert(scan.wristbandId)
        }
        
        // Convert to counts
        for (day, wristbands) in dailyUniqueWristbands {
            dailyScans[day] = wristbands.count
        }
        
        return dailyScans.map { HourlyData(hour: $0.key, count: $0.value) }
            .sorted { $0.hour < $1.hour }
    }
    
    private func generateWeeklyData(calendar: Calendar, now: Date) -> [HourlyData] {
        var weeklyScans: [Date: Int] = [:]
        
        // Initialize 4 weeks with 0
        for i in 0..<4 {
            let week = calendar.date(byAdding: .weekOfYear, value: -i, to: now)!
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: week)?.start ?? week
            weeklyScans[weekStart] = 0
        }
        
        // Count unique wristbands by week
        var weeklyUniqueWristbands: [Date: Set<String>] = [:]
        
        for scan in scanHistory {
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: scan.timestamp)?.start ?? scan.timestamp
            if weeklyUniqueWristbands[weekStart] == nil {
                weeklyUniqueWristbands[weekStart] = Set<String>()
            }
            weeklyUniqueWristbands[weekStart]?.insert(scan.wristbandId)
        }
        
        // Convert to counts
        for (week, wristbands) in weeklyUniqueWristbands {
            weeklyScans[week] = wristbands.count
        }
        
        return weeklyScans.map { HourlyData(hour: $0.key, count: $0.value) }
            .sorted { $0.hour < $1.hour }
    }
    
    private func generateMonthlyData(calendar: Calendar, now: Date) -> [HourlyData] {
        var monthlyScans: [Date: Int] = [:]
        
        // Initialize 12 months with 0
        for i in 0..<12 {
            let month = calendar.date(byAdding: .month, value: -i, to: now)!
            let monthStart = calendar.dateInterval(of: .month, for: month)?.start ?? month
            monthlyScans[monthStart] = 0
        }
        
        // Count unique wristbands by month
        var monthlyUniqueWristbands: [Date: Set<String>] = [:]
        
        for scan in scanHistory {
            let monthStart = calendar.dateInterval(of: .month, for: scan.timestamp)?.start ?? scan.timestamp
            if monthlyUniqueWristbands[monthStart] == nil {
                monthlyUniqueWristbands[monthStart] = Set<String>()
            }
            monthlyUniqueWristbands[monthStart]?.insert(scan.wristbandId)
        }
        
        // Convert to counts
        for (month, wristbands) in monthlyUniqueWristbands {
            monthlyScans[month] = wristbands.count
        }
        
        return monthlyScans.map { HourlyData(hour: $0.key, count: $0.value) }
            .sorted { $0.hour < $1.hour }
    }
    
    // MARK: - Data Loading
    private func loadGateData() {
        guard let eventId = supabaseService.currentEvent?.id else { return }
        
        Task {
            do {
                // Load scan history
                let logs: [CheckinLog] = try await supabaseService.makeRequest(
                    endpoint: "rest/v1/checkin_logs?gate_id=eq.\(gate.id)&event_id=eq.\(eventId)&select=*&order=timestamp.desc",
                    method: "GET",
                    body: nil,
                    responseType: [CheckinLog].self
                )
                
                // Calculate stats
                let stats = calculateScanStats(from: logs)
                
                await MainActor.run {
                    self.scanHistory = logs
                    self.scanStats = stats
                    self.isLoading = false
                }
            } catch {
                print("Failed to load gate data: \(error)")
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
    
    private func calculateScanStats(from logs: [CheckinLog]) -> ScanStats {
        let calendar = Calendar.current
        let hourCounts = Dictionary(grouping: logs) { log in
            calendar.component(.hour, from: log.timestamp)
        }.mapValues { $0.count }
        
        let peakHour = hourCounts.max(by: { $0.value < $1.value })?.key ?? 0
        let uniqueCategories = Set(logs.compactMap { $0.wristbandId }).count
        
        return ScanStats(
            peakHour: "\(peakHour):00",
            uniqueWristbands: uniqueCategories
        )
    }
}

// MARK: - Supporting Views
struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct ScanHistoryRow: View {
    let scan: CheckinLog
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Wristband: \(scan.wristbandId)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(scan.timestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text(scan.timestamp, style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let location = scan.location {
                    Text(location)
                        .font(.caption2)
                        .foregroundColor(.blue)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

struct WristbandBreakdownRow: View {
    let wristbandId: String
    let scanCount: Int
    let lastScan: Date?
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Wristband: \(wristbandId)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                if let lastScan = lastScan {
                    Text("Last scan: \(lastScan, style: .relative)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(scanCount)")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
                
                Text(scanCount == 1 ? "scan" : "scans")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - Data Models
struct ScanStats {
    let peakHour: String
    let uniqueWristbands: Int
}

struct HourlyData: Identifiable {
    let id = UUID()
    let hour: Date
    let count: Int
}

#Preview {
    NavigationView {
        GateDetailView(
            gate: Gate(
                id: "1",
                eventId: "event1",
                name: "Main Entrance Gate",
                latitude: 40.7128,
                longitude: -74.0060
            ),
            binding: GateBinding(
                gateId: "1",
                categoryName: "VIP",
                status: .enforced,
                confidence: 0.95,
                sampleCount: 150,
                eventId: "event1"
            )
        )
    }
}
