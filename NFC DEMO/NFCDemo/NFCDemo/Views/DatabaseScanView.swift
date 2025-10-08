import SwiftUI
import CoreNFC
import Combine

// MARK: - Database-Integrated Scan View
struct DatabaseScanView: View {
    @EnvironmentObject var eventData: EventDataManager
    @EnvironmentObject var nfcReader: NFCReader
    @EnvironmentObject var supabaseService: SupabaseService
    @StateObject private var viewModel = DatabaseScannerViewModel()
    
    var body: some View {
        ZStack {
            // Dynamic Gradient Background
            LinearGradient(
                colors: viewModel.backgroundColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea(.container, edges: .top)
            .animation(.easeInOut(duration: 1.0), value: viewModel.scanState)
            
            // Compact single-screen layout - NO SCROLLING
            VStack(spacing: DesignSystem.Spacing.medium) {
                // Compact Header
                compactHeaderSection
                
                // WiFi Scan Initiator (replaces large circle)
                wifiScanInitiator
                
                // Horizontal Control Buttons
                horizontalControlsSection
                
                // Manual Check-in Button
                manualCheckinButton
                
                // Bulk Check-in Button (only show if ticket linking is enabled)
                if let event = supabaseService.currentEvent, event.ticketLinkingMode != .disabled {
                    bulkCheckinButton
                }
                
                // Status & Recent Scans
                compactStatusSection
                
                Spacer()
            }
            .padding(.horizontal, DesignSystem.Spacing.large)
            .padding(.top, DesignSystem.Spacing.medium)
        }
        .onAppear {
            viewModel.setup(
                nfcReader: nfcReader,
                supabaseService: supabaseService,
                eventData: eventData
            )
        }
        .onDisappear {
            viewModel.cleanup()
        }
        .sheet(isPresented: $viewModel.showingManualCheckin) {
            manualCheckinSheet
        }
        .sheet(isPresented: $viewModel.showingTicketLinking) {
            TicketLinkingView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showingBulkCheckin) {
            BulkCheckinView(viewModel: viewModel)
                .environmentObject(supabaseService)
        }
    }
    
    // MARK: - Compact Header Section
    private var compactHeaderSection: some View {
        HStack(spacing: DesignSystem.Spacing.medium) {
            // Quick Stats with improved styling
            statItem("Today", value: "\(viewModel.todayScans)", icon: "calendar")
            statItem("Total", value: "\(viewModel.totalScans)", icon: "number.circle")
            statItem("Success Rate", value: "\(Int(viewModel.successRate))%", icon: "checkmark.circle")
        }
        .padding(DesignSystem.Spacing.large)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large))
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - WiFi Scan Initiator (replaces large circle)
    private var wifiScanInitiator: some View {
        Button(action: {
            if viewModel.isContinuousMode {
                if viewModel.isScanning {
                    viewModel.stopScanning()
                } else {
                    viewModel.startContinuousScanning()
                }
            } else {
                viewModel.performSingleScan()
            }
        }) {
            VStack(spacing: DesignSystem.Spacing.small) {
                // WiFi Icon pointing up
                Image(systemName: "wifi")
                    .font(.system(size: 40))
                    .foregroundColor(viewModel.isScanning ? DesignSystem.Colors.success : DesignSystem.Colors.primary)
                    .scaleEffect(viewModel.isScanning ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: viewModel.isScanning)
                
                // "Tap to scan" text underneath
                Text(viewModel.isScanning ? "Scanning..." : "Tap to Scan")
                    .font(DesignSystem.Typography.headline)
                    .foregroundColor(DesignSystem.Colors.primaryText)
            }
            .frame(width: 120, height: 120)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(
                Circle()
                    .stroke(viewModel.isScanning ? DesignSystem.Colors.success : DesignSystem.Colors.primary, lineWidth: 2)
            )
        }
        .disabled(viewModel.isContinuousMode && viewModel.isScanning)
    }
    
    // MARK: - Horizontal Controls Section
    private var horizontalControlsSection: some View {
        HStack(spacing: DesignSystem.Spacing.medium) {
            // Scan Mode Toggle
            Button(action: {
                viewModel.isContinuousMode.toggle()
                if viewModel.isScanning {
                    viewModel.stopScanning()
                }
            }) {
                HStack(spacing: DesignSystem.Spacing.small) {
                    Image(systemName: viewModel.isContinuousMode ? "repeat.circle.fill" : "1.circle.fill")
                        .font(.title3)
                    
                    Text(viewModel.isContinuousMode ? "Continuous" : "Single")
                        .font(DesignSystem.Typography.caption)
                }
                .foregroundColor(DesignSystem.Colors.inverseText)
                .padding(.horizontal, DesignSystem.Spacing.medium)
                .padding(.vertical, DesignSystem.Spacing.small)
                .background(DesignSystem.Colors.secondary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
            }
            
            // Stop Button (when scanning)
            if viewModel.isScanning {
                Button(action: {
                    viewModel.stopScanning()
                }) {
                    HStack(spacing: DesignSystem.Spacing.small) {
                        Image(systemName: "stop.circle.fill")
                            .font(.title3)
                        
                        Text("Stop")
                            .font(DesignSystem.Typography.caption)
                    }
                    .foregroundColor(DesignSystem.Colors.inverseText)
                    .padding(.horizontal, DesignSystem.Spacing.medium)
                    .padding(.vertical, DesignSystem.Spacing.small)
                    .background(DesignSystem.Colors.danger, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                }
            }
        }
    }
    
    // MARK: - Compact Status Section
    private var compactStatusSection: some View {
        VStack(spacing: DesignSystem.Spacing.small) {
            // Current Status
            HStack {
                Image(systemName: viewModel.statusIcon)
                    .foregroundColor(viewModel.statusColor)
                
                Text(viewModel.statusMessage)
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.primaryText)
                
                Spacer()
            }
            .cardStyle()
            
            // Recent Scans (compact)
            if !viewModel.recentScans.isEmpty {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text("Recent Scans")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                    
                    ForEach(viewModel.recentScans.prefix(3)) { scan in
                        HStack {
                            Text(scan.nfcId)
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.primaryText)
                            
                            Spacer()
                            
                            Text(scan.timestamp, style: .time)
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.secondaryText)
                        }
                    }
                }
                .cardStyle()
            }
        }
    }
    
    private func statItem(_ title: String, value: String, icon: String = "") -> some View {
        VStack(spacing: 6) {
            if !icon.isEmpty {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.9))
            }
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
    
    
    // MARK: - Status Card
    private var statusCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: viewModel.statusIcon)
                    .font(.title2)
                    .foregroundColor(viewModel.statusColor)
                
                Text(viewModel.statusMessage)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                Spacer()
            }
            
            if !viewModel.detailMessage.isEmpty {
                Text(viewModel.detailMessage)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // Mode indicator
            Divider()
                .background(.white.opacity(0.2))
            
            HStack {
                Image(systemName: viewModel.isContinuousMode ? "repeat.circle.fill" : "circle")
                    .foregroundColor(viewModel.isContinuousMode ? .green : .blue)
                
                Text(viewModel.isContinuousMode ? "Continuous Mode" : "Single Scan Mode")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                
                Spacer()
                
                if viewModel.isContinuousMode && viewModel.isScanning {
                    Text("Listening...")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            
            // Last scan time
            if let lastScanTime = viewModel.lastScanTime {
                Divider()
                    .background(.white.opacity(0.2))
                
                HStack {
                    Text("Last Scan:")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                    
                    Spacer()
                    
                    Text(lastScanTime, style: .time)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white.opacity(0.8))
                }
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(viewModel.cardBorderColor, lineWidth: 1)
        )
    }
    
    // MARK: - Recent Scans View
    private var recentScansView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Scans")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            ForEach(viewModel.recentScans.prefix(3)) { scan in
                recentScanRow(scan)
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
    
    private func recentScanRow(_ scan: DatabaseScanResult) -> some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(scan.isValid ? .green : .red)
                .frame(width: 8, height: 8)
            
            // Scan info
            VStack(alignment: .leading, spacing: 2) {
                Text(scan.nfcId)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                
                Text(scan.category.displayName)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
            
            Spacer()
            
            // Time
            Text(scan.timestamp, style: .time)
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Scan Control Section
    private var scanControlSection: some View {
        VStack(spacing: DesignSystem.Spacing.medium) {
            // Scan Mode Toggle Card
            VStack(spacing: DesignSystem.Spacing.small) {
                HStack {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                        Text("Scan Mode")
                            .font(DesignSystem.Typography.headline)
                            .foregroundColor(DesignSystem.Colors.primaryText)
                        
                        Text(viewModel.isContinuousMode ? "Continuous scanning enabled" : "Single scan mode")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: $viewModel.isContinuousMode)
                        .toggleStyle(SwitchToggleStyle(tint: DesignSystem.Colors.primary))
                }
            }
            .cardStyle()
            
            // Primary Scan Button
            if viewModel.isContinuousMode {
                Button(action: {
                    if viewModel.isScanning {
                        viewModel.stopScanning()
                    } else {
                        viewModel.startContinuousScanning()
                    }
                }) {
                    HStack(spacing: DesignSystem.Spacing.small) {
                        Image(systemName: viewModel.isScanning ? "stop.circle.fill" : "play.circle.fill")
                            .font(.title2)
                        
                        Text(viewModel.isScanning ? "Stop Listening" : "Start Listening")
                            .font(DesignSystem.Typography.button)
                    }
                    .foregroundColor(DesignSystem.Colors.inverseText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignSystem.Spacing.large)
                    .background(
                        viewModel.isScanning ? DesignSystem.Colors.danger : DesignSystem.Colors.success,
                        in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                    )
                }
                .shadow(
                    color: DesignSystem.Shadow.card.color,
                    radius: DesignSystem.Shadow.card.radius,
                    x: DesignSystem.Shadow.card.x,
                    y: DesignSystem.Shadow.card.y
                )
            } else {
                Button(action: {
                    viewModel.performSingleScan()
                }) {
                    HStack(spacing: DesignSystem.Spacing.small) {
                        Image(systemName: "wave.3.right.circle.fill")
                            .font(.title2)
                        
                        Text(viewModel.isScanning ? "Scanning..." : "Tap to Scan")
                            .font(DesignSystem.Typography.button)
                    }
                    .foregroundColor(DesignSystem.Colors.inverseText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignSystem.Spacing.large)
                    .background(
                        viewModel.isScanning ? DesignSystem.Colors.warning : DesignSystem.Colors.primary,
                        in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                    )
                }
                .disabled(viewModel.isScanning)
                .shadow(
                    color: DesignSystem.Shadow.card.color,
                    radius: DesignSystem.Shadow.card.radius,
                    x: DesignSystem.Shadow.card.x,
                    y: DesignSystem.Shadow.card.y
                )
            }
        }
    }
    
    // MARK: - Manual Check-in Button
    private var manualCheckinButton: some View {
        Button(action: {
            viewModel.showingManualCheckin = true
        }) {
            HStack(spacing: DesignSystem.Spacing.small) {
                Image(systemName: "keyboard")
                    .font(.title3)
                
                Text("Manual Check-in")
                    .font(DesignSystem.Typography.caption)
            }
            .foregroundColor(DesignSystem.Colors.inverseText)
            .padding(.horizontal, DesignSystem.Spacing.medium)
            .padding(.vertical, DesignSystem.Spacing.small)
            .background(DesignSystem.Colors.primary, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        }
    }
    
    // MARK: - Bulk Check-in Button
    private var bulkCheckinButton: some View {
        Button(action: {
            viewModel.showingBulkCheckin = true
        }) {
            HStack(spacing: DesignSystem.Spacing.small) {
                Image(systemName: "list.clipboard")
                    .font(.title3)
                
                Text("Bulk Check-in")
                    .font(DesignSystem.Typography.caption)
            }
            .foregroundColor(.white)
            .padding(.horizontal, DesignSystem.Spacing.medium)
            .padding(.vertical, DesignSystem.Spacing.small)
            .background(Color.purple, in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
        }
    }
    
    // MARK: - Manual Check-in Sheet
    private var manualCheckinSheet: some View {
        NavigationView {
            VStack(spacing: DesignSystem.Spacing.large) {
                Text("Manual Check-in")
                    .font(DesignSystem.Typography.title)
                    .fontWeight(.bold)
                
                VStack(spacing: 8) {
                    Text("Enter the wristband ID to manually check in a participant")
                        .font(DesignSystem.Typography.body)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                        .multilineTextAlignment(.center)
                    
                    // Show ticket linking status if enabled
                    if let event = supabaseService.currentEvent, event.ticketLinkingMode != .disabled {
                        HStack(spacing: 8) {
                            Image(systemName: "link.circle")
                                .foregroundColor(.blue)
                            
                            Text("Ticket linking is \(event.ticketLinkingMode == .required ? "required" : "optional") for this event")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                
                TextField("Wristband ID", text: $viewModel.manualWristbandId)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(DesignSystem.Typography.body)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                
                Button(action: {
                    Task {
                        await viewModel.performManualCheckin()
                    }
                }) {
                    HStack {
                        if viewModel.scanState == .scanning {
                            ProgressView()
                                .scaleEffect(0.8)
                                .foregroundColor(.white)
                        }
                        
                        Text(viewModel.scanState == .scanning ? "Processing..." : "Check In")
                            .font(DesignSystem.Typography.button)
                    }
                    .foregroundColor(DesignSystem.Colors.inverseText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignSystem.Spacing.medium)
                    .background(
                        viewModel.manualWristbandId.isEmpty ? DesignSystem.Colors.secondary : DesignSystem.Colors.primary,
                        in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                    )
                }
                .disabled(viewModel.manualWristbandId.isEmpty || viewModel.scanState == .scanning)
                
                Spacer()
            }
            .padding(DesignSystem.Spacing.large)
            .navigationTitle("Manual Check-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        viewModel.showingManualCheckin = false
                        viewModel.manualWristbandId = ""
                    }
                }
            }
        }
    }
}

#Preview {
    DatabaseScanView()
        .environmentObject(EventDataManager())
        .environmentObject(NFCReader())
        .environmentObject(SupabaseService.shared)
}
