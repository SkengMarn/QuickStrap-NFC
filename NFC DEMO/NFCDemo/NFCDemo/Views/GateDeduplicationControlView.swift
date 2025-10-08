import SwiftUI
import CoreLocation

/// Interactive UI for managing duplicate gates
struct GateDeduplicationControlView: View {
    @ObservedObject var viewModel: GatesViewModel
    @StateObject private var deduplicationService = GateDeduplicationService.shared
    @State private var duplicateClusters: [GateCluster] = []
    @State private var isAnalyzing = false
    @State private var showingMergeConfirmation = false
    @State private var selectedCluster: GateCluster?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header section
                headerSection

                // Analysis controls
                analysisControlsSection

                // Duplicate clusters
                if !duplicateClusters.isEmpty {
                    duplicateClustersSection
                } else if !isAnalyzing {
                    emptyStateSection
                }
            }
            .padding()
        }
        .navigationTitle("Gate Deduplication")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingMergeConfirmation) {
            if let cluster = selectedCluster {
                MergeConfirmationSheet(cluster: cluster, onConfirm: {
                    Task {
                        await mergeCluster(cluster)
                    }
                })
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.triangle.merge")
                    .font(.title2)
                    .foregroundColor(.blue)

                VStack(alignment: .leading) {
                    Text("Duplicate Detection")
                        .font(.headline)

                    Text("Find and merge gates at similar locations")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            if !duplicateClusters.isEmpty {
                HStack(spacing: 16) {
                    InfoPill(
                        icon: "exclamationmark.triangle.fill",
                        text: "\(duplicateClusters.count) duplicate groups",
                        color: .orange
                    )

                    InfoPill(
                        icon: "location.fill",
                        text: "\(totalDuplicateGates) gates affected",
                        color: .red
                    )
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Analysis Controls

    private var analysisControlsSection: some View {
        VStack(spacing: 12) {
            Button(action: analyzeForDuplicates) {
                HStack {
                    if isAnalyzing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    } else {
                        Image(systemName: "magnifyingglass.circle.fill")
                    }

                    Text(isAnalyzing ? "Analyzing..." : "Analyze for Duplicates")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(isAnalyzing)

            // Distance threshold info
            HStack {
                Image(systemName: "ruler")
                    .foregroundColor(.secondary)

                Text("Detection threshold: 25 meters")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Duplicate Clusters Section

    private var duplicateClustersSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Duplicate Groups")
                .font(.headline)

            ForEach(Array(duplicateClusters.enumerated()), id: \.offset) { index, cluster in
                DuplicateClusterCard(
                    cluster: cluster,
                    index: index + 1,
                    onMerge: {
                        selectedCluster = cluster
                        showingMergeConfirmation = true
                    }
                )
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)

            Text("No Duplicates Found")
                .font(.headline)

            Text("All gates appear to be unique based on location and name")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helper Properties

    private var totalDuplicateGates: Int {
        duplicateClusters.reduce(0) { $0 + $1.duplicateGates.count + 1 }
    }

    // MARK: - Actions

    private func analyzeForDuplicates() {
        Task {
            isAnalyzing = true

            do {
                let clusters = try await deduplicationService.findAndMergeDuplicateGates(
                    gates: viewModel.activeGates,
                    bindings: viewModel.gateBindings
                )

                await MainActor.run {
                    duplicateClusters = clusters
                    isAnalyzing = false
                }

                HapticManager.shared.success()
            } catch {
                await MainActor.run {
                    isAnalyzing = false
                }
                HapticManager.shared.error()
                AppLogger.shared.error("Deduplication analysis failed: \(error)", category: "Gates")
            }
        }
    }

    private func mergeCluster(_ cluster: GateCluster) async {
        // TODO: Implement merge logic
        AppLogger.shared.info("Merging cluster with primary gate: \(cluster.primaryGate.name)", category: "Gates")
        showingMergeConfirmation = false

        // Refresh after merge
        await viewModel.refreshData()
        duplicateClusters.removeAll { $0.primaryGate.id == cluster.primaryGate.id }
    }
}

// MARK: - Duplicate Cluster Card

struct DuplicateClusterCard: View {
    let cluster: GateCluster
    let index: Int
    let onMerge: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Group \(index)")
                    .font(.headline)
                    .foregroundColor(.orange)

                Spacer()

                Text("\(cluster.duplicateGates.count + 1) gates")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Primary gate
            VStack(alignment: .leading, spacing: 8) {
                Text("Primary Gate")
                    .font(.caption)
                    .foregroundColor(.secondary)

                GateMiniCard(
                    gate: cluster.primaryGate,
                    confidence: cluster.highestConfidence,
                    isPrimary: true
                )
            }

            // Duplicate gates
            if !cluster.duplicateGates.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Duplicates (\(cluster.duplicateGates.count))")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ForEach(cluster.duplicateGates, id: \.id) { gate in
                        GateMiniCard(
                            gate: gate,
                            confidence: cluster.highestConfidence,
                            isPrimary: false
                        )
                    }
                }
            }

            // Merge button
            Button(action: onMerge) {
                HStack {
                    Image(systemName: "arrow.triangle.merge")
                    Text("Merge into Primary")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .buttonHaptic()
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .orange.opacity(0.2), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Gate Mini Card

struct GateMiniCard: View {
    let gate: Gate
    let confidence: Double
    let isPrimary: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(gate.name)
                    .font(.subheadline)
                    .fontWeight(isPrimary ? .semibold : .regular)

                HStack(spacing: 8) {
                    if let lat = gate.latitude, let lon = gate.longitude {
                        Label(
                            String(format: "%.4f, %.4f", lat, lon),
                            systemImage: "location.fill"
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            if isPrimary {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
                    .font(.caption)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(isPrimary ? Color.blue.opacity(0.1) : Color(.systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - Info Pill

struct InfoPill: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)

            Text(text)
                .font(.caption)
        }
        .foregroundColor(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - Merge Confirmation Sheet

struct MergeConfirmationSheet: View {
    let cluster: GateCluster
    let onConfirm: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Warning icon
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.orange)
                    .padding(.top, 20)

                VStack(spacing: 12) {
                    Text("Merge Gates?")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("This will merge \(cluster.duplicateGates.count) duplicate gate(s) into the primary gate. This action cannot be undone.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // Primary gate info
                VStack(alignment: .leading, spacing: 8) {
                    Text("Primary Gate")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack {
                        VStack(alignment: .leading) {
                            Text(cluster.primaryGate.name)
                                .font(.headline)

                            Text("\(cluster.totalSampleCount) total scans")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Image(systemName: "star.fill")
                            .foregroundColor(.yellow)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
                .padding(.horizontal)

                Spacer()

                // Action buttons
                VStack(spacing: 12) {
                    Button(action: {
                        onConfirm()
                        dismiss()
                    }) {
                        Text("Merge Gates")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }

                    Button("Cancel") {
                        dismiss()
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    NavigationView {
        GateDeduplicationControlView(viewModel: GatesViewModel())
    }
}
