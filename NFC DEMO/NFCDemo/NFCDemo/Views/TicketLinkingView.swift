import SwiftUI

struct TicketLinkingView: View {
    @ObservedObject var viewModel: DatabaseScannerViewModel
    @Environment(\.dismiss) private var dismiss
    
    @StateObject private var scannerService = TicketScannerService.shared
    @State private var currentCaptureMethod: TicketCaptureMethod = .search
    @State private var showingScanner = false
    @State private var ticketLinkingPreferences = TicketLinkingPreferences.default
    
    var body: some View {
        ZStack {
            NavigationView {
                VStack(spacing: 20) {
                    // Header Section
                    headerSection
                    
                    // Capture Method Selector (if enabled)
                    if ticketLinkingPreferences.showMethodSelector {
                        captureMethodSelector
                    }
                    
                    // Input Section based on selected method
                    inputSection
                    
                    // Available Tickets List
                    if viewModel.availableTickets.isEmpty && !viewModel.ticketSearchQuery.isEmpty {
                        emptyStateSection
                    } else if !viewModel.availableTickets.isEmpty {
                        ticketListSection
                    }
                    
                    Spacer()
                    
                    // Action Buttons
                    actionButtonsSection
                }
                .padding(20)
                .navigationTitle("Link Ticket")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            viewModel.cancelTicketLinking()
                        }
                    }
                    
                    if ticketLinkingPreferences.enabledMethods.count > 1 {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(action: {
                                withAnimation {
                                    ticketLinkingPreferences.showMethodSelector.toggle()
                                }
                            }) {
                                Image(systemName: ticketLinkingPreferences.showMethodSelector ? "list.bullet" : "ellipsis")
                            }
                        }
                    }
                }
            }
            
            // Scanner Overlay
            if showingScanner {
                ZStack {
                    TicketScannerView(scannerService: scannerService)
                    
                    ScannerOverlayView(
                        scannerType: currentCaptureMethod,
                        onCancel: {
                            showingScanner = false
                            scannerService.stopScanning()
                        }
                    )
                }
                .ignoresSafeArea()
            }
        }
        .onAppear {
            setupInitialCaptureMethod()
        }
        .onChange(of: scannerService.scannedCode) { code in
            if let code = code {
                handleScannedCode(code)
            }
        }
    }
    
    // MARK: - Header Section
    private var headerSection: some View {
        VStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.2))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.orange)
            }
            
            VStack(spacing: 8) {
                Text("Ticket Required")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("This wristband needs to be linked to a ticket before entry")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
        }
    }
    
    // MARK: - Capture Method Selector
    private var captureMethodSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(ticketLinkingPreferences.enabledMethods, id: \.self) { method in
                    Button(action: {
                        withAnimation {
                            currentCaptureMethod = method
                            viewModel.ticketSearchQuery = ""
                            viewModel.availableTickets = []
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: method.icon)
                                .font(.system(size: 14))
                            
                            Text(method.displayName)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            currentCaptureMethod == method ? 
                            Color.orange : Color(.systemGray5)
                        )
                        .foregroundColor(
                            currentCaptureMethod == method ? 
                            .white : .primary
                        )
                        .cornerRadius(20)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Input Section
    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(inputSectionTitle)
                .font(.headline)
                .foregroundColor(.primary)
            
            if currentCaptureMethod.requiresCamera {
                // Camera-based input
                Button(action: {
                    startScanning()
                }) {
                    HStack {
                        Image(systemName: currentCaptureMethod.icon)
                            .foregroundColor(.orange)
                        
                        Text("Tap to scan \(currentCaptureMethod.displayName.lowercased())")
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Image(systemName: "camera")
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                }
            } else {
                // Text-based input
                HStack {
                    Image(systemName: currentCaptureMethod.icon)
                        .foregroundColor(.secondary)
                    
                    TextField(inputPlaceholder, text: $viewModel.ticketSearchQuery)
                        .textFieldStyle(PlainTextFieldStyle())
                        .keyboardType(keyboardType)
                        .onSubmit {
                            Task {
                                await searchWithCurrentMethod()
                            }
                        }
                        .onChange(of: viewModel.ticketSearchQuery) { _ in
                            Task {
                                await searchWithCurrentMethod()
                            }
                        }
                    
                    if !viewModel.ticketSearchQuery.isEmpty {
                        Button(action: {
                            viewModel.ticketSearchQuery = ""
                            viewModel.availableTickets = []
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemGray6))
                .cornerRadius(10)
            }
        }
    }
    
    // MARK: - Computed Properties
    private var inputSectionTitle: String {
        switch currentCaptureMethod {
        case .search: return "Search Tickets"
        case .barcode: return "Scan Barcode"
        case .qrCode: return "Scan QR Code"
        case .phoneNumber: return "Enter Phone Number"
        case .email: return "Enter Email Address"
        case .ticketNumber: return "Enter Ticket Number"
        }
    }
    
    private var inputPlaceholder: String {
        switch currentCaptureMethod {
        case .search: return "Search by any field..."
        case .ticketNumber: return "Enter ticket number"
        case .phoneNumber: return "Enter phone number"
        case .email: return "Enter email address"
        case .barcode, .qrCode: return ""
        }
    }
    
    private var keyboardType: UIKeyboardType {
        switch currentCaptureMethod {
        case .phoneNumber: return .phonePad
        case .email: return .emailAddress
        case .ticketNumber: return .numbersAndPunctuation
        default: return .default
        }
    }
    
    // MARK: - Empty State
    private var emptyStateSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "ticket")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No tickets found")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Try searching with a different ticket number or holder name")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
    }
    
    // MARK: - Ticket List Section
    private var ticketListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Available Tickets")
                .font(.headline)
                .foregroundColor(.primary)
            
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.availableTickets) { ticket in
                        TicketRowView(
                            ticket: ticket,
                            isSelected: viewModel.selectedTicket?.id == ticket.id
                        ) {
                            viewModel.selectedTicket = ticket
                        }
                    }
                }
            }
            .frame(maxHeight: 300)
        }
    }
    
    // MARK: - Action Buttons
    private var actionButtonsSection: some View {
        VStack(spacing: 16) {
            // Link Button
            Button(action: {
                Task {
                    await viewModel.linkSelectedTicket()
                }
            }) {
                HStack {
                    if viewModel.isLinkingTicket {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.white)
                    }
                    
                    Text(viewModel.isLinkingTicket ? "Linking..." : "Link Selected Ticket")
                        .font(.headline)
                        .fontWeight(.medium)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(viewModel.selectedTicket != nil ? Color.orange : Color.gray)
                .cornerRadius(12)
            }
            .disabled(viewModel.selectedTicket == nil || viewModel.isLinkingTicket)
            
            // Cancel Button
            Button("Cancel") {
                viewModel.cancelTicketLinking()
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
    }
}

// MARK: - Ticket Row View
struct TicketRowView: View {
    let ticket: Ticket
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Selection Indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? Color.orange : Color.gray.opacity(0.3), lineWidth: 2)
                        .frame(width: 24, height: 24)
                    
                    if isSelected {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 12, height: 12)
                    }
                }
                
                // Ticket Info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Ticket #\(ticket.ticketNumber)")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Text(ticket.ticketCategory)
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(6)
                    }
                    
                    if let holderName = ticket.holderName {
                        Text(holderName)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    if let holderEmail = ticket.holderEmail {
                        Text(holderEmail)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Status Badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    
                    Text("Available")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.orange.opacity(0.1) : Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.orange : Color.gray.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - TicketLinkingView Helper Methods
extension TicketLinkingView {
    
    private func setupInitialCaptureMethod() {
        currentCaptureMethod = ticketLinkingPreferences.primaryCaptureMethod
        
        // Load user preferences if available
        if let savedPreferences = UserDefaults.standard.data(forKey: "TicketLinkingPreferences"),
           let preferences = try? JSONDecoder().decode(TicketLinkingPreferences.self, from: savedPreferences) {
            ticketLinkingPreferences = preferences
            currentCaptureMethod = preferences.primaryCaptureMethod
        }
    }
    
    private func startScanning() {
        guard currentCaptureMethod.requiresCamera else { return }
        
        scannerService.checkCameraPermission()
        
        if scannerService.hasPermission {
            showingScanner = true
            scannerService.startScanning { code in
                handleScannedCode(code)
            }
        } else {
            // Handle permission denied
            viewModel.statusMessage = "Camera permission required for scanning"
        }
    }
    
    private func handleScannedCode(_ code: String) {
        showingScanner = false
        
        Task {
            await searchByScannedCode(code)
        }
    }
    
    private func searchByScannedCode(_ code: String) async {
        guard let eventId = viewModel.currentSupabaseService?.currentEvent?.id else { return }
        
        do {
            // Try to find exact ticket match first
            if let ticket = try await TicketService.shared.findTicketByCode(eventId: eventId, code: code) {
                await MainActor.run {
                    viewModel.availableTickets = [ticket]
                    viewModel.selectedTicket = ticket
                    viewModel.ticketSearchQuery = code
                }
            } else {
                // Fallback to general search
                viewModel.ticketSearchQuery = code
                await searchWithCurrentMethod()
                
                if viewModel.availableTickets.isEmpty && ticketLinkingPreferences.autoSwitchOnFailure {
                    // Try other methods automatically
                    await tryAlternativeSearchMethods(code)
                }
            }
        } catch {
            await MainActor.run {
                viewModel.statusMessage = "Search failed: \(error.localizedDescription)"
            }
        }
    }
    
    private func searchWithCurrentMethod() async {
        guard let eventId = viewModel.currentSupabaseService?.currentEvent?.id,
              !viewModel.ticketSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await MainActor.run {
                viewModel.availableTickets = []
            }
            return
        }
        
        do {
            let tickets = try await TicketService.shared.searchAvailableTickets(
                eventId: eventId,
                query: viewModel.ticketSearchQuery,
                method: currentCaptureMethod
            )
            
            await MainActor.run {
                viewModel.availableTickets = tickets
            }
        } catch {
            await MainActor.run {
                viewModel.availableTickets = []
                print("Search error: \(error)")
            }
        }
    }
    
    private func tryAlternativeSearchMethods(_ query: String) async {
        guard let eventId = viewModel.currentSupabaseService?.currentEvent?.id else { return }
        
        let alternativeMethods: [TicketCaptureMethod] = [.ticketNumber, .search, .phoneNumber, .email]
        
        for method in alternativeMethods {
            guard method != currentCaptureMethod,
                  ticketLinkingPreferences.enabledMethods.contains(method) else { continue }
            
            do {
                let tickets = try await TicketService.shared.searchAvailableTickets(
                    eventId: eventId,
                    query: query,
                    method: method
                )
                
                if !tickets.isEmpty {
                    await MainActor.run {
                        viewModel.availableTickets = tickets
                        currentCaptureMethod = method
                        viewModel.statusMessage = "Found using \(method.displayName)"
                    }
                    break
                }
            } catch {
                continue
            }
        }
    }
}

#Preview {
    TicketLinkingView(viewModel: DatabaseScannerViewModel())
}
