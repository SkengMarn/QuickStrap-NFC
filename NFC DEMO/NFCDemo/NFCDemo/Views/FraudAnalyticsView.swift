import SwiftUI

struct FraudAnalyticsView: View {
    @EnvironmentObject var supabaseService: SupabaseService
    @Environment(\.dismiss) private var dismiss
    
    @State private var analytics: TicketAnalytics?
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                headerSection
                
                // Content
                if isLoading {
                    loadingSection
                } else if let analytics = analytics {
                    analyticsContent(analytics)
                } else {
                    errorSection
                }
            }
            .navigationTitle("Fraud Prevention")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Refresh") {
                        Task {
                            await loadAnalytics()
                        }
                    }
                    .disabled(isLoading)
                }
            }
        }
        .onAppear {
            Task {
                await loadAnalytics()
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.2))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                    .font(.system(size: 40))
                    .foregroundColor(.red)
            }
            
            VStack(spacing: 8) {
                Text("Security Analytics")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Monitor fraud prevention and revenue protection")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 20)
        .background(Color(.systemGroupedBackground))
    }
    
    // MARK: - Loading Section
    private var loadingSection: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Loading security analytics...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Error Section
    private var errorSection: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("Unable to Load Analytics")
                .font(.headline)
                .foregroundColor(.primary)
            
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button("Try Again") {
                Task {
                    await loadAnalytics()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Analytics Content
    private func analyticsContent(_ analytics: TicketAnalytics) -> some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // Key Metrics
                keyMetricsSection(analytics)
                
                // Revenue Protection
                revenueProtectionSection(analytics)
                
                // Ticket Status
                ticketStatusSection(analytics)
                
                // Security Insights
                securityInsightsSection(analytics)
            }
            .padding(20)
        }
    }
    
    // MARK: - Key Metrics Section
    private func keyMetricsSection(_ analytics: TicketAnalytics) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Key Metrics")
                .font(.headline)
                .foregroundColor(.primary)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                SecurityMetricCard(
                    title: "Fraud Attempts",
                    value: "\(analytics.fraudAttempts)",
                    icon: "exclamationmark.shield",
                    color: .red
                )
                
                SecurityMetricCard(
                    title: "Revenue Protected",
                    value: "$\(Int(analytics.revenueProtection))",
                    icon: "dollarsign.circle",
                    color: .green
                )
                
                SecurityMetricCard(
                    title: "Linking Rate",
                    value: "\(Int(analytics.linkingRate * 100))%",
                    icon: "link.circle",
                    color: .blue
                )
                
                SecurityMetricCard(
                    title: "Attendance Rate",
                    value: "\(Int(analytics.attendanceRate * 100))%",
                    icon: "person.2.circle",
                    color: .purple
                )
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    // MARK: - Revenue Protection Section
    private func revenueProtectionSection(_ analytics: TicketAnalytics) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Revenue Protection")
                .font(.headline)
                .foregroundColor(.primary)
            
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Prevented Losses")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("$\(Int(analytics.revenueProtection))")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 8) {
                    Text("Fraud Attempts")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("\(analytics.fraudAttempts)")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                }
            }
            
            Divider()
            
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                
                Text("Ticket linking system is actively protecting revenue")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    // MARK: - Ticket Status Section
    private func ticketStatusSection(_ analytics: TicketAnalytics) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ticket Status")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(spacing: 12) {
                StatusRow(
                    title: "Tickets Uploaded",
                    value: analytics.ticketsUploaded,
                    color: .blue
                )
                
                StatusRow(
                    title: "Tickets Linked",
                    value: analytics.ticketsLinked,
                    color: .green
                )
                
                StatusRow(
                    title: "Tickets Scanned",
                    value: analytics.ticketsScanned,
                    color: .purple
                )
                
                StatusRow(
                    title: "No-Show Tickets",
                    value: analytics.noShowTickets,
                    color: .orange
                )
                
                StatusRow(
                    title: "Unlinked Wristbands",
                    value: analytics.unlinkedWristbands,
                    color: .red
                )
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    // MARK: - Security Insights Section
    private func securityInsightsSection(_ analytics: TicketAnalytics) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Security Insights")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(spacing: 12) {
                InsightRow(
                    icon: "shield.checkered",
                    title: "Fraud Prevention",
                    description: "Chip authentication prevents \(analytics.fraudAttempts) unauthorized entries",
                    color: .green
                )
                
                InsightRow(
                    icon: "link.circle",
                    title: "Ticket Accountability",
                    description: "\(Int(analytics.linkingRate * 100))% of wristbands properly linked to tickets",
                    color: .blue
                )
                
                InsightRow(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Revenue Impact",
                    description: "Protected $\(Int(analytics.revenueProtection)) in potential losses",
                    color: .purple
                )
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    // MARK: - Helper Methods
    
    @MainActor
    private func loadAnalytics() async {
        guard let eventId = supabaseService.currentEvent?.id else {
            errorMessage = "No event selected"
            isLoading = false
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            analytics = try await TicketService.shared.fetchTicketAnalytics(eventId: eventId)
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}

// MARK: - Supporting Views

struct SecurityMetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

struct StatusRow: View {
    let title: String
    let value: Int
    let color: Color
    
    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            Spacer()
            
            Text("\(value)")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(color)
        }
    }
}

struct InsightRow: View {
    let icon: String
    let title: String
    let description: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

#Preview {
    FraudAnalyticsView()
        .environmentObject(SupabaseService.shared)
}
