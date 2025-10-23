import SwiftUI

struct TicketLinkingSettingsView: View {
    @Binding var event: Event?
    @EnvironmentObject var supabaseService: SupabaseService
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedMode: Event.TicketLinkingMode = .disabled
    @State private var allowUnlinkedEntry = true
    @State private var isLoading = false
    @State private var showingConfirmation = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header Section
                headerSection
                
                // Settings Form
                Form {
                    // Current Event Info
                    if let event = event {
                        eventInfoSection(event)
                    }
                    
                    // Ticket Linking Mode Selection
                    ticketLinkingModeSection
                    
                    // Advanced Options
                    if selectedMode == .required {
                        advancedOptionsSection
                    }
                    
                    // Security Information
                    securityInfoSection
                }
                
                // Action Buttons
                actionButtonsSection
            }
            .navigationTitle("Ticket Linking")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            loadCurrentSettings()
        }
        .alert("Confirm Changes", isPresented: $showingConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Apply Changes", role: .destructive) {
                Task {
                    await saveSettings()
                }
            }
        } message: {
            Text("This will change the ticket linking mode for the entire event. All staff will be affected immediately.")
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 16) {
            // Security Icon
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "shield.checkered")
                    .font(.system(size: 40))
                    .foregroundColor(.blue)
            }
            
            VStack(spacing: 8) {
                Text("Event Security Configuration")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("Configure ticket linking and fraud prevention settings")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 20)
        .background(Color(.systemGroupedBackground))
    }
    
    // MARK: - Event Info Section
    private func eventInfoSection(_ event: Event) -> some View {
        Section("Current Event") {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if let location = event.location {
                        Text(location)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(event.startDate, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Current Status Badge
                VStack(spacing: 4) {
                    Image(systemName: event.ticketLinkingMode.icon)
                        .font(.title2)
                        .foregroundColor(statusColor(for: event.ticketLinkingMode))
                    
                    Text(event.ticketLinkingMode.displayName)
                        .font(.caption)
                        .foregroundColor(statusColor(for: event.ticketLinkingMode))
                }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Ticket Linking Mode Section
    private var ticketLinkingModeSection: some View {
        Section {
            ForEach(Event.TicketLinkingMode.allCases, id: \.self) { mode in
                TicketModeRow(
                    mode: mode,
                    isSelected: selectedMode == mode
                ) {
                    selectedMode = mode
                }
            }
        } header: {
            Text("Ticket Linking Mode")
        } footer: {
            Text(selectedMode.description)
        }
    }
    
    // MARK: - Advanced Options Section
    private var advancedOptionsSection: some View {
        Section {
            Toggle(isOn: $allowUnlinkedEntry) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Allow Emergency Override")
                        .font(.body)
                        .fontWeight(.medium)
                    
                    Text("Permit unlinked wristbands in emergency situations")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .tint(.orange)
        } header: {
            Text("Advanced Options")
        } footer: {
            Text("When enabled, admins can override ticket linking requirements for emergency access.")
        }
    }
    
    // MARK: - Security Info Section
    private var securityInfoSection: some View {
        Section("Security Information") {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.shield.fill")
                    .foregroundColor(.green)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Fraud Prevention")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text("Chip authentication prevents counterfeit wristbands")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            HStack(spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Audit Trail")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text("Complete logging of all ticket linking operations")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            HStack(spacing: 12) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(.purple)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Revenue Protection")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text("Prevents revenue loss from unauthorized entries")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - Action Buttons Section
    private var actionButtonsSection: some View {
        VStack(spacing: 16) {
            // Save Button
            Button(action: {
                if hasChanges {
                    showingConfirmation = true
                } else {
                    dismiss()
                }
            }) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.white)
                    }
                    
                    Text(isLoading ? "Saving..." : (hasChanges ? "Save Changes" : "No Changes"))
                        .font(.headline)
                        .fontWeight(.medium)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(hasChanges ? Color.blue : Color.gray)
                .cornerRadius(12)
            }
            .disabled(!hasChanges || isLoading)
            
            // Error Message
            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(20)
        .background(Color(.systemGroupedBackground))
    }
    
    // MARK: - Helper Methods
    
    private var hasChanges: Bool {
        guard let event = event else { return false }
        return selectedMode != event.ticketLinkingMode || 
               allowUnlinkedEntry != event.allowUnlinkedEntry
    }
    
    private func statusColor(for mode: Event.TicketLinkingMode) -> Color {
        switch mode {
        case .disabled: return .gray
        case .optional: return .orange
        case .required: return .green
        }
    }
    
    private func loadCurrentSettings() {
        guard let event = event else { return }
        selectedMode = event.ticketLinkingMode
        allowUnlinkedEntry = event.allowUnlinkedEntry
    }
    
    @MainActor
    private func saveSettings() async {
        guard let event = event else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            // Update event settings via API
            let updateData: [String: Any] = [
                "ticket_linking_mode": selectedMode.rawValue,
                "allow_unlinked_entry": allowUnlinkedEntry
            ]
            
            let jsonData = try JSONSerialization.data(withJSONObject: updateData)
            
            let _: EmptyResponse = try await supabaseService.makeRequest(
                endpoint: "rest/v1/events?id=eq.\(event.id)",
                method: "PATCH",
                body: jsonData,
                responseType: EmptyResponse.self
            )
            
            // Update local event object
            self.event = Event(
                id: event.id,
                name: event.name,
                description: event.description,
                location: event.location,
                startDate: event.startDate,
                endDate: event.endDate,
                totalCapacity: event.totalCapacity,
                createdBy: event.createdBy,
                createdAt: event.createdAt,
                updatedAt: Date(),
                lifecycleStatus: event.lifecycleStatus,
                organizationId: event.organizationId,
                ticketLinkingMode: selectedMode,
                allowUnlinkedEntry: allowUnlinkedEntry,
                config: event.config
            )
            
            // Update current event in service
            supabaseService.currentEvent = self.event
            
            isLoading = false
            dismiss()
            
        } catch {
            isLoading = false
            errorMessage = "Failed to save settings: \(error.localizedDescription)"
        }
    }
}

// MARK: - Ticket Mode Row
struct TicketModeRow: View {
    let mode: Event.TicketLinkingMode
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Selection Indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: 2)
                        .frame(width: 24, height: 24)
                    
                    if isSelected {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 12, height: 12)
                    }
                }
                
                // Mode Icon
                Image(systemName: mode.icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .blue : .secondary)
                    .frame(width: 30)
                
                // Mode Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.displayName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(mode.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Empty Response Helper
// Using EmptyResponse from NetworkClient

#Preview {
    TicketLinkingSettingsView(event: .constant(nil))
        .environmentObject(SupabaseService.shared)
}
