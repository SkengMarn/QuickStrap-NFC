import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var supabaseService: SupabaseService
    @Environment(\.dismiss) private var dismiss
    
    // Settings with UserDefaults persistence
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("soundEnabled") private var soundEnabled = true
    @AppStorage("hapticFeedback") private var hapticFeedback = true
    @AppStorage("autoSync") private var autoSync = true
    
    @State private var isLoading = false
    @State private var lastSyncTime = "Never"
    @State private var showingClearCacheAlert = false
    
    // Admin Settings
    @State private var showingTicketLinkingSettings = false
    @State private var showingFraudAnalytics = false
    @State private var currentEvent: Event?
    
    var body: some View {
        NavigationView {
            List {
                // App Settings
                Section("App Settings") {
                    SettingsToggle(
                        icon: "bell",
                        title: "Notifications",
                        subtitle: "Receive scan alerts and updates",
                        isOn: $notificationsEnabled
                    )
                    
                    SettingsToggle(
                        icon: "speaker.wave.2",
                        title: "Sound Effects",
                        subtitle: "Play sounds for scan feedback",
                        isOn: $soundEnabled
                    )
                    
                    SettingsToggle(
                        icon: "iphone.radiowaves.left.and.right",
                        title: "Haptic Feedback",
                        subtitle: "Vibrate on successful scans",
                        isOn: $hapticFeedback
                    )
                }
                
                // Data & Sync
                Section("Data & Sync") {
                    SettingsToggle(
                        icon: "arrow.triangle.2.circlepath",
                        title: "Auto Sync",
                        subtitle: "Automatically sync data when connected",
                        isOn: $autoSync
                    )
                    
                    SettingsRow(
                        icon: "icloud.and.arrow.up",
                        title: "Sync Now",
                        subtitle: "Last synced: \(lastSyncTime)"
                    ) {
                        Task {
                            await performManualSync()
                        }
                    }
                    
                    SettingsRow(
                        icon: "trash",
                        title: "Clear Cache",
                        subtitle: "Free up storage space",
                        isDestructive: true
                    ) {
                        showingClearCacheAlert = true
                    }
                }
                
                // Admin Settings (only show for admin users)
                if isAdminUser {
                    Section("Event Security (Admin Only)") {
                        SettingsRow(
                            icon: "shield.checkered",
                            title: "Ticket Linking Configuration",
                            subtitle: currentTicketLinkingStatus
                        ) {
                            showingTicketLinkingSettings = true
                        }
                        
                        SettingsRow(
                            icon: "chart.bar.doc.horizontal",
                            title: "Fraud Prevention Analytics",
                            subtitle: "View security metrics and reports"
                        ) {
                            showingFraudAnalytics = true
                        }
                    }
                }
                
                // Performance
                Section("Performance") {
                    SettingsRow(
                        icon: "speedometer",
                        title: "Performance Mode",
                        subtitle: "Optimize for battery or performance"
                    ) {
                        // TODO: Implement performance mode selection
                    }
                    
                    SettingsRow(
                        icon: "wifi",
                        title: "Network Settings",
                        subtitle: "Configure connection preferences"
                    ) {
                        // TODO: Implement network settings
                    }
                }
                
                // About
                Section("About") {
                    SettingsRow(
                        icon: "info.circle",
                        title: "Version",
                        subtitle: appVersionText
                    ) {
                        // No action needed
                    }
                    
                    SettingsRow(
                        icon: "doc.text",
                        title: "Privacy Policy",
                        subtitle: "View our privacy policy"
                    ) {
                        openPrivacyPolicy()
                    }
                    
                    SettingsRow(
                        icon: "questionmark.circle",
                        title: "Support",
                        subtitle: "Get help and contact us"
                    ) {
                        openSupport()
                    }
                    
                    SettingsRow(
                        icon: "star.fill",
                        title: "Rate App",
                        subtitle: "Rate us on the App Store"
                    ) {
                        requestAppReview()
                    }
                }
                
                // Account
                Section("Account") {
                    SettingsRow(
                        icon: "rectangle.portrait.and.arrow.right",
                        title: "Sign Out",
                        subtitle: "Sign out of your account",
                        isDestructive: true
                    ) {
                        supabaseService.signOut()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Clear Cache", isPresented: $showingClearCacheAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Clear", role: .destructive) {
                    clearCache()
                }
            } message: {
                Text("This will clear all cached data and free up storage space. This action cannot be undone.")
            }
            .onAppear {
                loadLastSyncTime()
                loadCurrentEvent()
            }
            .sheet(isPresented: $showingTicketLinkingSettings) {
                TicketLinkingSettingsView(event: $currentEvent)
                    .environmentObject(supabaseService)
            }
            .sheet(isPresented: $showingFraudAnalytics) {
                FraudAnalyticsView()
                    .environmentObject(supabaseService)
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var isAdminUser: Bool {
        // Check if current user has admin or owner role
        guard let user = supabaseService.currentUser else { return false }
        return user.role == .admin || user.role == .owner
    }
    
    private var currentTicketLinkingStatus: String {
        guard let event = currentEvent else { return "No event selected" }
        
        switch event.ticketLinkingMode {
        case .disabled:
            return "Disabled - No ticket system"
        case .optional:
            return "Optional - Tickets not required"
        case .required:
            return "Required - All wristbands must link"
        }
    }
    
    // MARK: - Private Methods
    
    @MainActor
    private func performManualSync() async {
        isLoading = true
        
        // Use the offline manager for sync
        await OfflineDataManager.shared.performManualSync()
        
        // Update last sync time from offline manager
        if let lastSync = OfflineDataManager.shared.lastSyncDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            lastSyncTime = formatter.string(from: lastSync)
        }
        
        // Provide haptic feedback if enabled
        if hapticFeedback {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
        }
        
        isLoading = false
    }
    
    private func clearCache() {
        // Use offline manager to clear cache
        OfflineDataManager.shared.clearCache()
        
        // Also clear URLCache
        URLCache.shared.removeAllCachedResponses()
        
        // Reset last sync time
        lastSyncTime = "Never"
        
        // Provide haptic feedback if enabled
        if hapticFeedback {
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
        }
        
        print("Cache cleared successfully")
    }
    
    private func loadLastSyncTime() {
        if let lastSync = UserDefaults.standard.object(forKey: "lastSyncTime") as? Date {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            lastSyncTime = formatter.string(from: lastSync)
        } else {
            lastSyncTime = "Never"
        }
    }
    
    private func openPrivacyPolicy() {
        // In a real app, this would open a web view or Safari
        if let url = URL(string: "https://example.com/privacy") {
            UIApplication.shared.open(url)
        }
    }
    
    private func openSupport() {
        // In a real app, this would open email composer or support system
        if let url = URL(string: "mailto:support@quickstrap.com?subject=NFC%20Event%20Manager%20Support") {
            UIApplication.shared.open(url)
        }
    }
    
    private func requestAppReview() {
        // In a real app, this would use StoreKit to request review
        if let url = URL(string: "https://apps.apple.com/app/id123456789?action=write-review") {
            UIApplication.shared.open(url)
        }
    }
    
    private var appVersionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (Build \(build))"
    }
    
    private func loadCurrentEvent() {
        currentEvent = supabaseService.currentEvent
    }
}

struct SettingsToggle: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(Color(hex: "#635BFF") ?? .blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var isDestructive: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(isDestructive ? .red : Color(hex: "#635BFF") ?? .blue)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(isDestructive ? .red : .primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if !isDestructive {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    SettingsView()
        .environmentObject(SupabaseService.shared)
}
