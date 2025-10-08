import SwiftUI
import MapKit

/// Interactive map view showing gates with real-time status
struct InteractiveGateMapView: View {
    @ObservedObject var viewModel: GatesViewModel
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 0.354, longitude: 32.599),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    @State private var selectedGate: Gate?
    @State private var showingGateDetail = false

    var body: some View {
        ZStack(alignment: .top) {
            // Map with gate annotations
            Map(coordinateRegion: $region, annotationItems: viewModel.activeGates) { gate in
                MapAnnotation(coordinate: coordinate(for: gate)) {
                    GateMapPin(
                        gate: gate,
                        stats: viewModel.getGateStats(for: gate),
                        isSelected: selectedGate?.id == gate.id
                    )
                    .onTapGesture {
                        withAnimation {
                            selectedGate = gate
                            showingGateDetail = true
                        }
                    }
                }
            }
            .ignoresSafeArea()

            // Map controls overlay
            VStack {
                HStack {
                    Spacer()

                    VStack(spacing: 12) {
                        // Center on all gates
                        MapControlButton(icon: "location", color: .blue) {
                            centerOnAllGates()
                        }

                        // Refresh gates
                        MapControlButton(icon: "arrow.clockwise", color: .green) {
                            Task {
                                await viewModel.refreshData()
                            }
                        }

                        // Toggle clustering
                        MapControlButton(icon: "circle.grid.3x3.fill", color: .purple) {
                            // Future: Toggle clustering view
                        }
                    }
                    .padding()
                }

                Spacer()

                // Bottom legend
                MapLegend(
                    enforcedCount: viewModel.enforcedGatesCount,
                    probationCount: viewModel.probationGatesCount,
                    unboundCount: viewModel.unlinkedCount
                )
                .padding()
            }
        }
        .sheet(isPresented: $showingGateDetail) {
            if let gate = selectedGate {
                GateDetailView(
                    gate: gate,
                    binding: viewModel.gateBindings.first { $0.gateId == gate.id }
                )
            }
        }
        .onAppear {
            centerOnAllGates()
        }
    }

    private func coordinate(for gate: Gate) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: gate.latitude ?? 0.354,
            longitude: gate.longitude ?? 32.599
        )
    }

    private func centerOnAllGates() {
        guard !viewModel.activeGates.isEmpty else { return }

        let coordinates = viewModel.activeGates.compactMap { gate -> CLLocationCoordinate2D? in
            guard let lat = gate.latitude, let lon = gate.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }

        guard !coordinates.isEmpty else { return }

        // Calculate center and span
        let minLat = coordinates.map { $0.latitude }.min() ?? 0
        let maxLat = coordinates.map { $0.latitude }.max() ?? 0
        let minLon = coordinates.map { $0.longitude }.min() ?? 0
        let maxLon = coordinates.map { $0.longitude }.max() ?? 0

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        let span = MKCoordinateSpan(
            latitudeDelta: max(0.01, (maxLat - minLat) * 1.5),
            longitudeDelta: max(0.01, (maxLon - minLon) * 1.5)
        )

        withAnimation {
            region = MKCoordinateRegion(center: center, span: span)
        }
    }
}

// MARK: - Gate Map Pin

struct GateMapPin: View {
    let gate: Gate
    let stats: GateStats
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            // Pin icon with status color
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.3))
                    .frame(width: isSelected ? 60 : 44, height: isSelected ? 60 : 44)

                Circle()
                    .fill(statusColor)
                    .frame(width: isSelected ? 48 : 32, height: isSelected ? 48 : 32)

                Image(systemName: "location.fill")
                    .font(.system(size: isSelected ? 24 : 16))
                    .foregroundColor(.white)
            }
            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)

            // Gate info badge
            if isSelected {
                VStack(spacing: 2) {
                    Text(gate.name)
                        .font(.caption)
                        .fontWeight(.bold)
                        .lineLimit(1)

                    Text("\(stats.totalScans) scans")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.systemBackground))
                .cornerRadius(8)
                .shadow(radius: 2)
            }
        }
        .animation(.spring(), value: isSelected)
    }

    private var statusColor: Color {
        switch stats.status {
        case .enforced: return .green
        case .probation: return .orange
        case .unbound: return .red
        }
    }
}

// MARK: - Map Control Button

struct MapControlButton: View {
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(color)
                .clipShape(Circle())
                .shadow(radius: 4)
        }
    }
}

// MARK: - Map Legend

struct MapLegend: View {
    let enforcedCount: Int
    let probationCount: Int
    let unboundCount: Int

    var body: some View {
        HStack(spacing: 20) {
            LegendItem(color: .green, label: "Enforced", count: enforcedCount)
            LegendItem(color: .orange, label: "Probation", count: probationCount)
            LegendItem(color: .red, label: "Unbound", count: unboundCount)
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
    }
}

struct LegendItem: View {
    let color: Color
    let label: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)

            Text(label)
                .font(.caption)
                .foregroundColor(.primary)

            Text("(\(count))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    InteractiveGateMapView(viewModel: GatesViewModel())
}
