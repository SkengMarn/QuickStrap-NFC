import SwiftUI
import Charts

struct EnhancedStatsView: View {
    @StateObject private var supabaseService = SupabaseService.shared
    @StateObject private var gateBindingService = GateBindingService.shared
    @StateObject private var deduplicationService = GateDeduplicationService.shared
    
    @State private var selectedTab = 0
    @State private var gates: [Gate] = []
    @State private var bindings: [GateBinding] = []
    @State private var duplicateClusters: [GateCluster] = []
    @State private var isLoading = true
    
    private let tabs = ["Overview", "Gates", "Quality"]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Tab selector
                Picker("Tab", selection: $selectedTab) {
                    ForEach(0..<tabs.count, id: \.self) { index in
                        Text(tabs[index]).tag(index)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
                // Content
                TabView(selection: $selectedTab) {
                    overviewTab.tag(0)
                    gatesTab.tag(1)
                    qualityTab.tag(2)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            }
            .navigationTitle("Analytics")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: GateDeduplicationView()) {
                        HStack {
                            Image(systemName: "point.3.connected.trianglepath.dotted")
                            Text("Fix Duplicates")
                        }
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(duplicateClusters.isEmpty ? Color.green : Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                    }
                }
            }
            .onAppear(perform: loadData)
        }
    }
    
    private var overviewTab: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                MetricCard(
                    title: "Total Gates",
                    value: "\(gates.count)",
                    subtitle: duplicateClusters.isEmpty ? "All unique" : "\(duplicateClusters.count) clusters",
                    color: duplicateClusters.isEmpty ? .green : .red
                )
                
                MetricCard(
                    title: "Active Bindings",
                    value: "\(bindings.filter { $0.status != .unbound }.count)",
                    subtitle: "of \(bindings.count) total",
                    color: .blue
                )
                
                MetricCard(
                    title: "Confirmed Gates",
                    value: "\(bindings.filter { $0.status == .enforced }.count)",
                    subtitle: "High confidence",
                    color: .green
                )
                
                MetricCard(
                    title: "Data Quality",
                    value: String(format: "%.0f%%", dataQualityScore),
                    subtitle: qualityStatus,
                    color: dataQualityScore > 80 ? .green : .orange
                )
            }
            .padding()
        }
    }
    
    private var gatesTab: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Status overview
                HStack(spacing: 12) {
                    StatusCard(title: "Confirmed", count: confirmedGates.count, color: .green)
                    StatusCard(title: "Probation", count: probationGates.count, color: .orange)
                    StatusCard(title: "Duplicates", count: totalDuplicates, color: .red)
                }
                .padding(.horizontal)
                
                // Gates list
                LazyVStack(spacing: 8) {
                    ForEach(gates, id: \.id) { gate in
                        GateRow(gate: gate, binding: bindings.first { $0.gateId == gate.id })
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    private var qualityTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Quality score
                QualityScoreView(score: dataQualityScore, status: qualityStatus)
                
                // Issues
                if !duplicateClusters.isEmpty {
                    QualityIssueCard(
                        title: "Duplicate Gates Found",
                        description: "\(duplicateClusters.count) clusters with \(totalDuplicates) duplicates",
                        severity: .high,
                        action: "Fix Now"
                    )
                }
                
                let lowConfidenceCount = bindings.filter { $0.confidence < 0.5 }.count
                if lowConfidenceCount > 0 {
                    QualityIssueCard(
                        title: "Low Confidence Bindings",
                        description: "\(lowConfidenceCount) gates need review",
                        severity: .medium,
                        action: "Review"
                    )
                }
            }
            .padding()
        }
    }
    
    // MARK: - Computed Properties
    private var confirmedGates: [GateBinding] {
        bindings.filter { $0.status == .enforced }
    }
    
    private var probationGates: [GateBinding] {
        bindings.filter { $0.status == .probation }
    }
    
    private var totalDuplicates: Int {
        duplicateClusters.reduce(0) { $0 + $1.duplicateGates.count }
    }
    
    private var dataQualityScore: Double {
        var score = 100.0
        score -= Double(totalDuplicates) * 5.0
        score -= Double(bindings.filter { $0.confidence < 0.5 }.count) * 3.0
        return max(0, score)
    }
    
    private var qualityStatus: String {
        dataQualityScore > 80 ? "Good" : dataQualityScore > 60 ? "Fair" : "Poor"
    }
    
    private func loadData() {
        Task {
            do {
                let (fetchedGates, fetchedBindings) = try await (
                    gateBindingService.fetchGates(),
                    gateBindingService.fetchAllGateBindings()
                )
                
                let clusters = try await deduplicationService.findAndMergeDuplicateGates(
                    gates: fetchedGates,
                    bindings: fetchedBindings
                )
                
                await MainActor.run {
                    self.gates = fetchedGates
                    self.bindings = fetchedBindings
                    self.duplicateClusters = clusters
                    self.isLoading = false
                }
            } catch {
                print("Failed to load data: \(error)")
            }
        }
    }
}

// MARK: - Supporting Views
private struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
            
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
}

struct StatusCard: View {
    let title: String
    let count: Int
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
}

struct GateRow: View {
    let gate: Gate
    let binding: GateBinding?
    @State private var scanCount: Int = 0
    @State private var scanTypes: [ScanType: Int] = [:]
    @State private var showingDetail = false
    
    private let supabaseService = SupabaseService.shared
    
    var body: some View {
        Button(action: {
            showingDetail = true
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(gate.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text("\(gate.latitude ?? 0.0, specifier: "%.4f"), \(gate.longitude ?? 0.0, specifier: "%.4f")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // Scan count information
                    HStack(spacing: 4) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.caption2)
                            .foregroundColor(.blue)
                        
                        Text("\(scanCount) scans")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if let binding = binding {
                            Text("• \(binding.sampleCount) samples")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Scan type breakdown
                    if !scanTypes.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(ScanType.allCases.filter { scanTypes[$0, default: 0] > 0 }, id: \.self) { scanType in
                                HStack(spacing: 2) {
                                    Image(systemName: scanTypeIcon(for: scanType))
                                        .font(.caption2)
                                        .foregroundColor(scanTypeColor(for: scanType))
                                    
                                    Text("\(scanTypes[scanType, default: 0])")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    if let binding = binding {
                        HStack(spacing: 4) {
                            Text(binding.status.rawValue.capitalized)
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(binding.status == .enforced ? Color.green : Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(4)
                        }
                        
                        Text("\(Int(binding.confidence * 100))% confidence")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(8)
            .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
        }
        .buttonStyle(PlainButtonStyle())
        .onAppear {
            loadScanCount()
        }
        .sheet(isPresented: $showingDetail) {
            GateDetailsView(gate: gate)
                .environmentObject(supabaseService)
        }
    }
    
    private func loadScanCount() {
        Task {
            do {
                // Get full scan data to analyze scan types
                let logs: [CheckinLog] = try await supabaseService.makeRequest(
                    endpoint: "rest/v1/checkin_logs?gate_id=eq.\(gate.id)&select=*",
                    method: "GET",
                    body: nil,
                    responseType: [CheckinLog].self
                )
                
                // If no direct gate_id matches, try location-based matching for virtual gates
                var allLogs = logs
                if logs.isEmpty && gate.name.contains("Virtual Gate") {
                    // Get all check-ins near this gate's location
                    let nearbyLogs: [CheckinLog] = try await supabaseService.makeRequest(
                        endpoint: "rest/v1/checkin_logs?select=*",
                        method: "GET",
                        body: nil,
                        responseType: [CheckinLog].self
                    )
                    
                    // Filter by location proximity (within ~100m)
                    allLogs = nearbyLogs.filter { log in
                        guard let logLat = log.appLat, let logLon = log.appLon,
                              let gateLat = gate.latitude, let gateLon = gate.longitude else {
                            return false
                        }
                        
                        let distance = sqrt(pow(logLat - gateLat, 2) + pow(logLon - gateLon, 2))
                        return distance < 0.001 // ~100m
                    }
                }
                
                // Count scan types
                var typeCount: [ScanType: Int] = [:]
                for log in allLogs {
                    let scanType = log.scanType
                    typeCount[scanType, default: 0] += 1
                }
                
                await MainActor.run {
                    self.scanCount = allLogs.count
                    self.scanTypes = typeCount
                }
            } catch {
                // Silently handle errors
            }
        }
    }
    
    // MARK: - Helper Functions
    
    private func scanTypeIcon(for scanType: ScanType) -> String {
        switch scanType {
        case .manual: return "person.fill"
        case .mobile: return "iphone.radiowaves.left.and.right"
        case .unknown: return "questionmark.circle"
        }
    }
    
    private func scanTypeColor(for scanType: ScanType) -> Color {
        switch scanType {
        case .manual: return .blue
        case .mobile: return .green
        case .unknown: return .gray
        }
    }
}

struct QualityScoreView: View {
    let score: Double
    let status: String
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Data Quality Score")
                .font(.headline)
            
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 8)
                
                Circle()
                    .trim(from: 0, to: score / 100)
                    .stroke(score > 80 ? Color.green : Color.orange, lineWidth: 8)
                    .rotationEffect(.degrees(-90))
                
                VStack {
                    Text("\(score, specifier: "%.0f")%")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text(status)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 120, height: 120)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
}

struct QualityIssueCard: View {
    let title: String
    let description: String
    let severity: IssueSeverity
    let action: String
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action) {
                // Action handled by parent
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(severity.color)
            .foregroundColor(.white)
            .cornerRadius(8)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
}

enum IssueSeverity {
    case high, medium, low
    
    var color: Color {
        switch self {
        case .high: return .red
        case .medium: return .orange
        case .low: return .yellow
        }
    }
}

#Preview {
    EnhancedStatsView()
}
