import SwiftUI

struct SeriesSelectionView: View {
    let parentEvent: Event
    let series: [EventSeries]
    @EnvironmentObject var supabaseService: SupabaseService
    @Environment(\.dismiss) var dismiss
    
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(hex: "#F5F5F5")
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    headerSection
                    
                    // Content
                    if series.isEmpty {
                        emptyStateSection
                    } else {
                        eventsList
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .foregroundColor(Color(hex: "#635BFF") ?? .blue)
                    }
                }
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 12) {
            Text(parentEvent.name)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
            
            Text("Select an event to scan")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if let location = parentEvent.location {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.caption)
                    Text(location)
                        .font(.subheadline)
                }
                .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .shadow(color: Color.black.opacity(0.05), radius: 2, y: 2)
    }
    
    // MARK: - Events List
    private var eventsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(series) { seriesEvent in
                    SeriesItemCard(series: seriesEvent) {
                        selectSeries(seriesEvent)
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Loading Section
    private var loadingSection: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(Color(hex: "#635BFF") ?? .blue)
            
            Text("Loading events...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Error Section
    private func errorSection(_ error: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 64))
                .foregroundColor(.orange)

            VStack(spacing: 8) {
                Text("Error Loading Events")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text(error)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Close") {
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.horizontal, 40)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Empty State Section
    private var emptyStateSection: some View {
        VStack(spacing: 24) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 64))
                .foregroundColor(.gray.opacity(0.6))
            
            VStack(spacing: 8) {
                Text("No Active Events")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text("There are no active events in this series at the moment")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // No refresh needed - series passed in
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Actions
    private func selectSeries(_ series: EventSeries) {
        // For now, select the parent event
        // TODO: Update scanner to handle series-specific scanning
        Task { @MainActor in
            supabaseService.selectEvent(parentEvent)
            dismiss()
        }
    }
}

// MARK: - Series Item Card
struct SeriesItemCard: View {
    let series: EventSeries
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Date Badge
                VStack(spacing: 4) {
                    Text(series.startDate.formatted(.dateTime.month(.abbreviated)))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    
                    Text(series.startDate.formatted(.dateTime.day()))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }
                .frame(width: 60)
                .padding(.vertical, 8)
                .background(Color(hex: "#F5F5F5"))
                .cornerRadius(8)
                
                // Event Info
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(series.name)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                        
                        // Status badge
                        Text(series.lifecycleStatus.displayName)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(hex: series.lifecycleStatus.color)?.opacity(0.1) ?? Color.gray.opacity(0.1))
                            .foregroundColor(Color(hex: series.lifecycleStatus.color) ?? .gray)
                            .cornerRadius(4)
                    }
                    
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption)
                        Text(series.startDate.formatted(.dateTime.hour().minute()))
                            .font(.subheadline)
                    }
                    .foregroundColor(.secondary)
                    
                    if let location = series.location {
                        HStack(spacing: 4) {
                            Image(systemName: "location")
                                .font(.caption)
                            Text(location)
                                .font(.subheadline)
                        }
                        .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.white)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.05), radius: 4, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    SeriesSelectionView(
        parentEvent: Event(
            id: "1",
            name: "KCCA 2025/26 Football Season",
            description: "Full season of matches",
            location: "MTN Phillip Omondo Stadium",
            startDate: Date(),
            endDate: Date().addingTimeInterval(86400 * 365),
            organizationId: "org-1"
        ),
        series: []
    )
    .environmentObject(SupabaseService.shared)
}
