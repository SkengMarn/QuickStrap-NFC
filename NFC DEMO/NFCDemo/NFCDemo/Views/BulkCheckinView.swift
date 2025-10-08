import SwiftUI

struct BulkCheckinView: View {
    @ObservedObject var viewModel: DatabaseScannerViewModel
    @EnvironmentObject var supabaseService: SupabaseService
    @Environment(\.dismiss) private var dismiss
    
    @State private var wristbandIds: String = ""
    @State private var isProcessing = false
    @State private var results: [BulkCheckinResult] = []
    @State private var showingResults = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header Section
                headerSection
                
                // Input Section
                inputSection
                
                // Process Button
                processButton
                
                // Results Section
                if showingResults {
                    resultsSection
                }
                
                Spacer()
            }
            .padding(20)
            .navigationTitle("Bulk Check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Clear") {
                        clearAll()
                    }
                    .disabled(wristbandIds.isEmpty && results.isEmpty)
                }
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.2))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "list.clipboard")
                    .font(.system(size: 40))
                    .foregroundColor(.purple)
            }
            
            VStack(spacing: 8) {
                Text("Bulk Check-in")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Process multiple wristband IDs at once")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Ticket linking status
            if let event = supabaseService.currentEvent, event.ticketLinkingMode != .disabled {
                HStack(spacing: 8) {
                    Image(systemName: "shield.checkered")
                        .foregroundColor(.blue)
                    
                    Text("Ticket linking \(event.ticketLinkingMode == .required ? "required" : "optional")")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }
    
    // MARK: - Input Section
    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Wristband IDs")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("Enter one wristband ID per line")
                .font(.caption)
                .foregroundColor(.secondary)
            
            TextEditor(text: $wristbandIds)
                .font(.system(.body, design: .monospaced))
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .frame(minHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
            
            HStack {
                Text("\(wristbandIdList.count) wristbands")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if !wristbandIds.isEmpty {
                    Button("Paste from Clipboard") {
                        if let clipboardString = UIPasteboard.general.string {
                            wristbandIds = clipboardString
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }
        }
    }
    
    // MARK: - Process Button
    private var processButton: some View {
        Button(action: {
            Task {
                await processBulkCheckin()
            }
        }) {
            HStack {
                if isProcessing {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.white)
                }
                
                Text(isProcessing ? "Processing..." : "Process Check-ins")
                    .font(.headline)
                    .fontWeight(.medium)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(wristbandIdList.isEmpty ? Color.gray : Color.purple)
            .cornerRadius(12)
        }
        .disabled(wristbandIdList.isEmpty || isProcessing)
    }
    
    // MARK: - Results Section
    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Results")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("\(results.count) processed")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(results, id: \.wristbandId) { result in
                        BulkResultRow(result: result)
                    }
                }
            }
            .frame(maxHeight: 200)
            
            // Summary
            summarySection
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    // MARK: - Summary Section
    private var summarySection: some View {
        let successful = results.filter { $0.success }.count
        let failed = results.count - successful
        let needsLinking = results.filter { $0.needsTicketLinking }.count
        
        return VStack(spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Summary")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    HStack(spacing: 16) {
                        Label("\(successful)", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        
                        Label("\(failed)", systemImage: "xmark.circle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                        
                        if needsLinking > 0 {
                            Label("\(needsLinking)", systemImage: "link.circle")
                                .foregroundColor(.orange)
                                .font(.caption)
                        }
                    }
                }
                
                Spacer()
            }
            
            if needsLinking > 0 {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.orange)
                    
                    Text("\(needsLinking) wristbands need ticket linking")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
    }
    
    // MARK: - Helper Properties
    
    private var wristbandIdList: [String] {
        wristbandIds
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    
    // MARK: - Helper Methods
    
    private func clearAll() {
        wristbandIds = ""
        results = []
        showingResults = false
    }
    
    @MainActor
    private func processBulkCheckin() async {
        guard !wristbandIdList.isEmpty else { return }
        
        isProcessing = true
        results = []
        showingResults = true
        
        for wristbandId in wristbandIdList {
            let result = await processWristband(wristbandId)
            results.append(result)
        }
        
        isProcessing = false
    }
    
    private func processWristband(_ wristbandId: String) async -> BulkCheckinResult {
        guard let eventId = supabaseService.currentEvent?.id else {
            return BulkCheckinResult(
                wristbandId: wristbandId,
                success: false,
                message: "No event selected",
                needsTicketLinking: false
            )
        }
        
        do {
            let validation = try await TicketService.shared.validateWristbandEntry(
                wristbandId: wristbandId,
                eventId: eventId
            )
            
            if validation.canEnter {
                // TODO: Record the check-in in the database
                return BulkCheckinResult(
                    wristbandId: wristbandId,
                    success: true,
                    message: validation.reason,
                    needsTicketLinking: false,
                    ticket: validation.ticket
                )
            } else if validation.requiresLinking {
                return BulkCheckinResult(
                    wristbandId: wristbandId,
                    success: false,
                    message: validation.reason,
                    needsTicketLinking: true
                )
            } else {
                return BulkCheckinResult(
                    wristbandId: wristbandId,
                    success: false,
                    message: validation.reason,
                    needsTicketLinking: false
                )
            }
        } catch {
            return BulkCheckinResult(
                wristbandId: wristbandId,
                success: false,
                message: "Validation failed: \(error.localizedDescription)",
                needsTicketLinking: false
            )
        }
    }
}

// MARK: - Bulk Checkin Result Model
struct BulkCheckinResult {
    let wristbandId: String
    let success: Bool
    let message: String
    let needsTicketLinking: Bool
    let ticket: Ticket?
    
    init(wristbandId: String, success: Bool, message: String, needsTicketLinking: Bool, ticket: Ticket? = nil) {
        self.wristbandId = wristbandId
        self.success = success
        self.message = message
        self.needsTicketLinking = needsTicketLinking
        self.ticket = ticket
    }
}

// MARK: - Bulk Result Row
struct BulkResultRow: View {
    let result: BulkCheckinResult
    
    var body: some View {
        HStack(spacing: 12) {
            // Status Icon
            Image(systemName: statusIcon)
                .foregroundColor(statusColor)
                .frame(width: 20)
            
            // Wristband ID
            Text(result.wristbandId)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.primary)
            
            Spacer()
            
            // Message or Ticket Info
            VStack(alignment: .trailing, spacing: 2) {
                if let ticket = result.ticket {
                    Text(ticket.holderName ?? "Ticket #\(ticket.ticketNumber)")
                        .font(.caption)
                        .foregroundColor(.primary)
                    
                    Text(ticket.ticketCategory)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text(result.message)
                        .font(.caption)
                        .foregroundColor(statusColor)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private var statusIcon: String {
        if result.success {
            return "checkmark.circle.fill"
        } else if result.needsTicketLinking {
            return "link.circle"
        } else {
            return "xmark.circle.fill"
        }
    }
    
    private var statusColor: Color {
        if result.success {
            return .green
        } else if result.needsTicketLinking {
            return .orange
        } else {
            return .red
        }
    }
}

#Preview {
    BulkCheckinView(viewModel: DatabaseScannerViewModel())
        .environmentObject(SupabaseService.shared)
}
