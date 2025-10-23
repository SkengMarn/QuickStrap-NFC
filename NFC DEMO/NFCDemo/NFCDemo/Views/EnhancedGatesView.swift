import SwiftUI
import MapKit

struct EnhancedGatesView: View {
    @StateObject private var viewModel = GatesViewModel()
    @State private var selectedTimeRange: GatesViewModel.TimeRange = .all
    @State private var showingSystemComparison = false
    @State private var showingGateDeduplication = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 16) {
                    // Header with time range selector
                    headerSection
                    
                    // Quick stats
                    quickStatsSection
                    
                    // Gates list
                    gatesListSection
                }
                .padding()
            }
            .navigationTitle("Gates")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("System Comparison") {
                            showingSystemComparison = true
                        }
                        Button("Gate Deduplication") {
                            showingGateDeduplication = true
                        }
                        Button("Refresh Data") {
                            Task {
                                await viewModel.refreshData()
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .onAppear {
            viewModel.startMonitoring()
        }
        .onDisappear {
            viewModel.stopMonitoring()
        }
        .sheet(isPresented: $showingSystemComparison) {
            SystemComparisonView(viewModel: viewModel)
        }
        .sheet(isPresented: $showingGateDeduplication) {
            GateDeduplicationControlView(viewModel: viewModel)
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Gate Management")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                // Time range picker
                Picker("Time Range", selection: $selectedTimeRange) {
                    ForEach(GatesViewModel.TimeRange.allCases, id: \.self) { range in
                        Label(range.rawValue, systemImage: range.icon)
                            .tag(range)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .onChange(of: selectedTimeRange) { newRange in
                    viewModel.updateTimeRange(newRange)
                }
            }
            
            // Processing banner
            if viewModel.isProcessing {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Processing gate data...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .cornerRadius(8)
            }
        }
    }
    
    // MARK: - Quick Stats Section
    
    private var quickStatsSection: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
            EnhancedStatCard(
                title: "Active Gates",
                value: "\(viewModel.activeGates.count)",
                icon: "location.circle.fill",
                color: .blue
            )
            
            EnhancedStatCard(
                title: "Data Quality",
                value: viewModel.dataQualityDescription,
                icon: "checkmark.seal.fill",
                color: viewModel.dataQualityStatus.color
            )
            
            EnhancedStatCard(
                title: "Total Check-ins",
                value: "\(viewModel.totalCheckins)",
                icon: "person.badge.plus.fill",
                color: .green
            )
            
            EnhancedStatCard(
                title: "Linking Rate",
                value: String(format: "%.1f%%", viewModel.linkingPercentage),
                icon: "link.circle.fill",
                color: .purple
            )
        }
    }
    
    // MARK: - Gates List Section
    
    private var gatesListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Gates (\(viewModel.filteredGates.count))")
                    .font(.headline)
                
                Spacer()
                
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            
            if viewModel.filteredGates.isEmpty {
                EmptyGatesView()
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.filteredGates, id: \.id) { gate in
                        GateCard(
                            gate: gate,
                            stats: viewModel.getGateStats(for: gate)
                        )
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Views

private struct EnhancedStatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title3)
                
                Spacer()
            }
            
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }
}

struct GateCard: View {
    let gate: Gate
    let stats: GateStats

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with health and status
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(gate.name)
                            .font(.headline)

                        if let healthScore = gate.healthScore {
                            HStack(spacing: 2) {
                                Image(systemName: healthIcon(for: healthScore))
                                    .font(.caption2)
                                Text("\(healthScore)%")
                                    .font(.caption2)
                            }
                            .foregroundColor(healthColor(for: healthScore))
                        }
                    }

                    HStack(spacing: 6) {
                        // Discovery method badge
                        if let description = gate.locationDescription {
                            HStack(spacing: 4) {
                                Image(systemName: discoveryIcon(for: description))
                                    .font(.caption2)
                                Text(description)
                                    .font(.caption2)
                            }
                            .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    GateStatusBadge(status: gate.status)
                    StatusBadge(status: stats.status)
                }
            }

            // Performance metrics
            HStack(spacing: 12) {
                EnhancedStatItem(
                    label: "Scans",
                    value: "\(stats.totalScans)",
                    icon: "person.crop.circle.badge.checkmark"
                )

                EnhancedStatItem(
                    label: "Success",
                    value: String(format: "%.0f%%", successRate(stats.totalScans)),
                    icon: "checkmark.circle.fill"
                )

                EnhancedStatItem(
                    label: "Confidence",
                    value: String(format: "%.0f%%", stats.confidence * 100),
                    icon: "gauge.medium"
                )

                EnhancedStatItem(
                    label: "Categories",
                    value: "\(stats.categories.count)",
                    icon: "tag.fill"
                )
            }

            // Categories with enforcement status
            if !stats.categories.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Learned Categories")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)

                        Spacer()

                        // Enforcement indicator
                        if stats.status == .enforced {
                            HStack(spacing: 2) {
                                Image(systemName: "shield.checkered")
                                    .font(.caption2)
                                Text("Enforcing")
                                    .font(.caption2)
                            }
                            .foregroundColor(.green)
                        }
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(stats.categories, id: \.self) { category in
                                CategoryBadge(category: category, status: stats.status)
                            }
                        }
                        .padding(.horizontal, 1)
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
    }

    private func healthIcon(for score: Int) -> String {
        if score >= 80 { return "checkmark.circle.fill" }
        if score >= 60 { return "exclamationmark.circle.fill" }
        return "xmark.circle.fill"
    }

    private func healthColor(for score: Int) -> Color {
        if score >= 80 { return .green }
        if score >= 60 { return .orange }
        return .red
    }

    private func discoveryIcon(for method: String) -> String {
        if method.contains("v2") { return "sparkles" }
        if method.contains("manual") { return "hand.raised.fill" }
        return "location.fill"
    }

    private func successRate(_ totalScans: Int) -> Double {
        // This would come from metrics in real implementation
        guard totalScans > 0 else { return 0 }
        return 95.0 // Placeholder - would calculate from successful_scans / total_scans
    }
}

struct CategoryBadge: View {
    let category: String
    let status: GateBindingStatus

    var body: some View {
        HStack(spacing: 4) {
            Text(category)
                .font(.caption)
            if status == .enforced {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption2)
                    .foregroundColor(.green)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(backgroundColor)
        .cornerRadius(6)
    }

    private var backgroundColor: Color {
        switch status {
        case .enforced: return Color.green.opacity(0.1)
        case .probation: return Color.orange.opacity(0.1)
        case .unbound: return Color.gray.opacity(0.1)
        }
    }
}

private struct EnhancedStatItem: View {
    let label: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
            
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct StatusBadge: View {
    let status: GateBindingStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.color.opacity(0.2))
            .foregroundColor(status.color)
            .cornerRadius(6)
    }
}

struct GateStatusBadge: View {
    let status: Gate.GateStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconForStatus)
                .font(.caption2)

            Text(status.displayName)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(hex: status.color)?.opacity(0.2) ?? Color.gray.opacity(0.2))
        .foregroundColor(Color(hex: status.color) ?? .gray)
        .cornerRadius(6)
    }

    private var iconForStatus: String {
        switch status {
        case .learning: return "brain.head.profile"
        case .active: return "checkmark.circle.fill"
        case .optimizing: return "arrow.triangle.2.circlepath"
        case .maintenance: return "wrench.and.screwdriver.fill"
        case .paused: return "pause.circle.fill"
        }
    }
}

struct EmptyGatesView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "location.slash")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text("No Active Gates")
                    .font(.headline)

                Text("Gates are automatically created by GPS clustering when check-ins occur. Start scanning to see gates appear here.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 32)
    }
}

// MARK: - Extensions

extension GateBindingStatus {
    var color: Color {
        switch self {
        case .unbound: return .gray
        case .probation: return .orange
        case .enforced: return .green
        }
    }
}

extension HealthStatus {
    var color: Color {
        switch self {
        case .good: return .green
        case .warning: return .orange
        case .attention: return .red
        }
    }
}

// MARK: - Preview

#Preview {
    EnhancedGatesView()
}
