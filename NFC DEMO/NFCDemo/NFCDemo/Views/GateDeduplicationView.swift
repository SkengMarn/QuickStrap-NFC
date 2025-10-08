import SwiftUI
import CoreLocation

struct GateDeduplicationView: View {
    @StateObject private var deduplicationService = GateDeduplicationService.shared
    @StateObject private var gateBindingService = GateBindingService.shared
    @StateObject private var supabaseService = SupabaseService.shared
    
    @State private var gates: [Gate] = []
    @State private var bindings: [GateBinding] = []
    @State private var clusters: [GateCluster] = []
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var selectedCluster: GateCluster?
    @State private var showingExecutionConfirmation = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header with summary
                headerSection
                
                if deduplicationService.isProcessing {
                    loadingSection
                } else if clusters.isEmpty {
                    emptyStateSection
                } else {
                    // Clusters list
                    clustersList
                }
                
                Spacer()
                
                // Action buttons
                actionButtons
            }
            .navigationTitle("Gate Deduplication")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                loadData()
            }
            .alert("Deduplication Status", isPresented: $showingAlert) {
                Button("OK") { }
            } message: {
                Text(alertMessage)
            }
            .confirmationDialog(
                "Execute Deduplication",
                isPresented: $showingExecutionConfirmation,
                presenting: selectedCluster
            ) { cluster in
                Button("Merge \(cluster.duplicateGates.count) Duplicate Gates", role: .destructive) {
                    executeDeduplication(for: cluster)
                }
                Button("Cancel", role: .cancel) { }
            } message: { cluster in
                Text("This will permanently merge \(cluster.duplicateGates.count) duplicate gates into the primary gate. This action cannot be undone.")
            }
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Duplicate Gate Analysis")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if !clusters.isEmpty {
                        Text("\(clusters.count) clusters found • \(totalDuplicates) duplicates")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if !clusters.isEmpty {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Potential Savings")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("\(totalDuplicates) gates")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.green)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            
            Divider()
        }
        .background(Color(.systemGroupedBackground))
    }
    
    private var loadingSection: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Analyzing gate locations and bindings...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateSection: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            
            VStack(spacing: 8) {
                Text("No Duplicates Found")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("All gates appear to be unique based on location and naming analysis.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var clustersList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(clusters.indices, id: \.self) { index in
                    ClusterCard(
                        cluster: clusters[index],
                        onExecute: { cluster in
                            selectedCluster = cluster
                            showingExecutionConfirmation = true
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                Button(action: loadData) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh Analysis")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray6))
                    .foregroundColor(.primary)
                    .cornerRadius(10)
                }
                
                if !clusters.isEmpty {
                    Button(action: executeAllDuplications) {
                        HStack {
                            Image(systemName: "arrow.merge")
                            Text("Merge All")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(Color(.systemBackground))
    }
    
    private var totalDuplicates: Int {
        clusters.reduce(0) { $0 + $1.duplicateGates.count }
    }
    
    private func loadData() {
        Task {
            do {
                // Load gates and bindings
                async let gatesTask = gateBindingService.fetchGates()
                async let bindingsTask = gateBindingService.fetchAllGateBindings()
                
                let (fetchedGates, fetchedBindings) = try await (gatesTask, bindingsTask)
                
                await MainActor.run {
                    self.gates = fetchedGates
                    self.bindings = fetchedBindings
                }
                
                // Analyze for duplicates
                let foundClusters = try await deduplicationService.findAndMergeDuplicateGates(
                    gates: fetchedGates,
                    bindings: fetchedBindings
                )
                
                await MainActor.run {
                    self.clusters = foundClusters
                }
                
            } catch {
                await MainActor.run {
                    alertMessage = "Failed to load data: \(error.localizedDescription)"
                    showingAlert = true
                }
            }
        }
    }
    
    private func executeDeduplication(for cluster: GateCluster) {
        Task {
            do {
                try await deduplicationService.executeDuplication(cluster: cluster)
                
                await MainActor.run {
                    alertMessage = "Successfully merged \(cluster.duplicateGates.count) duplicate gates!"
                    showingAlert = true
                    
                    // Remove the processed cluster from the list
                    clusters.removeAll { $0.primaryGate.id == cluster.primaryGate.id }
                }
                
                // Refresh data
                loadData()
                
            } catch {
                await MainActor.run {
                    alertMessage = "Failed to execute deduplication: \(error.localizedDescription)"
                    showingAlert = true
                }
            }
        }
    }
    
    private func executeAllDuplications() {
        Task {
            for cluster in clusters {
                do {
                    try await deduplicationService.executeDuplication(cluster: cluster)
                } catch {
                    await MainActor.run {
                        alertMessage = "Failed to merge cluster for gate \(cluster.primaryGate.name): \(error.localizedDescription)"
                        showingAlert = true
                    }
                    return
                }
            }
            
            await MainActor.run {
                alertMessage = "Successfully merged all duplicate gates!"
                showingAlert = true
                clusters.removeAll()
            }
            
            // Refresh data
            loadData()
        }
    }
}

struct ClusterCard: View {
    let cluster: GateCluster
    let onExecute: (GateCluster) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(cluster.primaryGate.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("Primary Gate")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(cluster.duplicateGates.count)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                    
                    Text("duplicates")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            // Location info
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "location")
                        .foregroundColor(.green)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Average Location")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(String(format: "%.6f, %.6f", cluster.averageLocation.latitude, cluster.averageLocation.longitude))
                            .font(.caption)
                            .monospaced()
                    }
                    
                    Spacer()
                }
                
                // Statistics
                HStack(spacing: 20) {
                    StatItem(
                        icon: "chart.bar.fill",
                        title: "Total Samples",
                        value: "\(cluster.totalSampleCount)",
                        color: .blue
                    )
                    
                    StatItem(
                        icon: "target",
                        title: "Best Confidence",
                        value: String(format: "%.1f%%", cluster.highestConfidence * 100),
                        color: cluster.highestConfidence > 0.7 ? .green : .orange
                    )
                }
            }
            
            // Duplicate gates list
            VStack(alignment: .leading, spacing: 6) {
                Text("Duplicate Gates:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ForEach(cluster.duplicateGates.prefix(3), id: \.id) { gate in
                    HStack {
                        Circle()
                            .fill(Color.red.opacity(0.3))
                            .frame(width: 6, height: 6)
                        
                        Text(gate.id.prefix(8) + "...")
                            .font(.caption)
                            .monospaced()
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(String(format: "%.6f, %.6f", gate.latitude ?? 0.0, gate.longitude ?? 0.0))
                            .font(.caption2)
                            .monospaced()
                            .foregroundColor(.secondary)
                    }
                }
                
                if cluster.duplicateGates.count > 3 {
                    Text("... and \(cluster.duplicateGates.count - 3) more")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
            
            // Action button
            Button(action: { onExecute(cluster) }) {
                HStack {
                    Image(systemName: "arrow.merge")
                    Text("Merge Duplicates")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}

private struct StatItem: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.caption)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Text(value)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(color)
            }
        }
    }
}

#Preview {
    GateDeduplicationView()
}
