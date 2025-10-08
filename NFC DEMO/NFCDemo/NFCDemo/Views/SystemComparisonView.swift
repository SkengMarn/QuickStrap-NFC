import SwiftUI

/// Visual comparison of legacy vs advanced gate learning systems
struct SystemComparisonView: View {
    @ObservedObject var viewModel: GatesViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                headerSection

                // System toggle
                systemToggleSection

                // Quick actions
                if viewModel.systemComparison == nil {
                    quickActionsSection
                }

                // Comparison results
                if let comparison = viewModel.systemComparison {
                    comparisonResultsSection(comparison)
                }

                // Historical metrics
                historicalMetricsSection

                Spacer()
            }
            .padding()
        }
        .navigationTitle("System Validation")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: viewModel.useAdvancedSystem ? "brain.head.profile" : "gearshape.2")
                .font(.system(size: 60))
                .foregroundStyle(viewModel.useAdvancedSystem ? .green : .blue)

            Text(viewModel.useAdvancedSystem ? "Advanced Learning System" : "Legacy System")
                .font(.title2)
                .fontWeight(.bold)

            Text(viewModel.useAdvancedSystem
                ? "Self-learning with Bayesian inference & DBSCAN clustering"
                : "Distance-based with hardcoded thresholds")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        )
    }

    // MARK: - System Toggle

    private var systemToggleSection: some View {
        VStack(spacing: 16) {
            Text("Active System")
                .font(.headline)

            HStack(spacing: 20) {
                // Legacy button
                Button(action: {
                    if viewModel.useAdvancedSystem {
                        viewModel.toggleSystemMode()
                    }
                }) {
                    VStack(spacing: 8) {
                        Image(systemName: "gearshape.2")
                            .font(.system(size: 32))
                        Text("Legacy")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(viewModel.useAdvancedSystem ? Color(.secondarySystemBackground) : Color.blue)
                    )
                    .foregroundColor(viewModel.useAdvancedSystem ? .secondary : .white)
                }
                .buttonStyle(.plain)

                // Advanced button
                Button(action: {
                    if !viewModel.useAdvancedSystem {
                        viewModel.toggleSystemMode()
                    }
                }) {
                    VStack(spacing: 8) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 32))
                        Text("Advanced")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(!viewModel.useAdvancedSystem ? Color(.secondarySystemBackground) : Color.green)
                    )
                    .foregroundColor(!viewModel.useAdvancedSystem ? .secondary : .white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        )
    }

    // MARK: - Quick Actions

    private var quickActionsSection: some View {
        VStack(spacing: 16) {
            Text("Validation")
                .font(.headline)

            Button(action: {
                Task {
                    await viewModel.runSystemComparison()
                }
            }) {
                HStack {
                    Image(systemName: "play.circle.fill")
                        .font(.title3)

                    Text("Run System Comparison")
                        .fontWeight(.semibold)

                    Spacer()

                    if viewModel.isProcessing {
                        ProgressView()
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.blue)
                )
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isProcessing)

            Text("Compare both systems side-by-side to see improvements")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        )
    }

    // MARK: - Comparison Results

    private func comparisonResultsSection(_ comparison: GateDiscoveryComparison) -> some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Latest Comparison")
                    .font(.headline)

                Spacer()

                Text(comparison.timestamp, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Side-by-side comparison
            HStack(spacing: 16) {
                // Legacy results
                VStack(spacing: 12) {
                    Text("🔴 Legacy")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    VStack(alignment: .leading, spacing: 8) {
                        statRow("Gates", "\(comparison.legacyResult.gateCount)")
                        statRow("Avg Scans", String(format: "%.1f", comparison.legacyResult.averageScansPerGate))
                        statRow("Time", String(format: "%.2fs", comparison.legacyResult.executionTime))
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.red.opacity(0.1))
                )

                // Advanced results
                VStack(spacing: 12) {
                    Text("🟢 Advanced")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    VStack(alignment: .leading, spacing: 8) {
                        statRow("Gates", "\(comparison.advancedResult.gateCount)")
                        statRow("Avg Scans", String(format: "%.1f", comparison.advancedResult.averageScansPerGate))
                        statRow("Time", String(format: "%.2fs", comparison.advancedResult.executionTime))
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.green.opacity(0.1))
                )
            }

            Divider()

            // Improvements
            VStack(spacing: 12) {
                Text("📈 Improvements")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                improvementRow(
                    icon: "minus.circle.fill",
                    label: "Fewer Gates",
                    value: "\(comparison.gateCountReduction)",
                    percent: comparison.gateCountReductionPercent,
                    isPositive: comparison.gateCountReduction > 0
                )

                improvementRow(
                    icon: "trash.slash.fill",
                    label: "Fewer Duplicates",
                    value: "\(comparison.duplicateReduction)",
                    percent: comparison.duplicateReductionPercent,
                    isPositive: comparison.duplicateReduction > 0
                )

                improvementRow(
                    icon: "arrow.up.circle.fill",
                    label: "More Scans/Gate",
                    value: String(format: "+%.1f", comparison.scansPerGateImprovement),
                    percent: comparison.scansPerGateImprovementPercent,
                    isPositive: comparison.scansPerGateImprovement > 0
                )
            }

            Divider()

            // Advanced system details
            VStack(spacing: 12) {
                Text("🧠 Advanced System Details")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                VStack(alignment: .leading, spacing: 8) {
                    detailRow("Learned Epsilon", "\(Int(comparison.learnedEpsilon))m")
                    detailRow("Clusters Found", "\(comparison.advancedResult.clusters.count)")
                    detailRow("GMM Components", "\(comparison.advancedResult.gmmComponents.count)")
                    detailRow("Avg Density", String(format: "%.4f scans/m²", comparison.averageClusterDensity))
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.secondarySystemBackground))
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        )
    }

    // MARK: - Historical Metrics

    private var historicalMetricsSection: some View {
        VStack(spacing: 16) {
            Text("Historical Averages")
                .font(.headline)

            let improvements = viewModel.getAverageImprovements()

            VStack(spacing: 12) {
                averageMetricRow(
                    icon: "chart.line.downtrend.xyaxis",
                    label: "Avg Gate Reduction",
                    value: String(format: "%.1f gates", improvements.gateReduction),
                    color: .green
                )

                averageMetricRow(
                    icon: "checkmark.shield.fill",
                    label: "Avg Duplicate Reduction",
                    value: String(format: "%.1f duplicates", improvements.duplicateReduction),
                    color: .blue
                )

                averageMetricRow(
                    icon: "arrow.up.right.circle.fill",
                    label: "Avg Scans/Gate Increase",
                    value: String(format: "+%.1f scans", improvements.scansPerGateIncrease),
                    color: .orange
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        )
    }

    // MARK: - Helper Views

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
        }
    }

    private func improvementRow(
        icon: String,
        label: String,
        value: String,
        percent: Double,
        isPositive: Bool
    ) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(isPositive ? .green : .red)

            Text(label)
                .font(.subheadline)

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.bold)

                Text(String(format: "%.1f%%", abs(percent)))
                    .font(.caption)
                    .foregroundColor(isPositive ? .green : .red)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
        }
    }

    private func averageMetricRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)

            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.secondarySystemBackground))
        )
    }
}
