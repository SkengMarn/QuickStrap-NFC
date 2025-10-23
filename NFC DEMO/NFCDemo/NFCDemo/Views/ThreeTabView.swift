import SwiftUI

// MARK: - Three Tab View with Navigation Menu
struct ThreeTabView: View {
    let selectedEvent: Event
    @State private var showingMenu = false
    @State private var showingBroadcasts = false
    @State private var activeBanner: BroadcastMessage? = nil
    @EnvironmentObject var supabaseService: SupabaseService
    @EnvironmentObject var eventData: EventDataManager
    @EnvironmentObject var nfcReader: NFCReader
    @EnvironmentObject var broadcastService: BroadcastService
    
    var body: some View {
        ZStack {
            // Main tab content
            TabView {
                DatabaseScanView()
                    .tabItem {
                        Image(systemName: "wave.3.right.circle")
                        Text("Scan")
                    }
                    .environmentObject(eventData)
                    .environmentObject(nfcReader)
                    .environmentObject(supabaseService)
                
                EnhancedGatesView()
                    .tabItem {
                        Image(systemName: "location.circle")
                        Text("Gates")
                    }
                    .environmentObject(supabaseService)
                
                DatabaseStatsView()
                    .tabItem {
                        Image(systemName: "chart.bar.fill")
                        Text("Analytics")
                    }
                    .environmentObject(eventData)
                    .environmentObject(supabaseService)
                
                DatabaseWristbandsView()
                    .tabItem {
                        Image(systemName: "list.bullet")
                        Text("Wristbands")
                    }
                    .environmentObject(eventData)
                    .environmentObject(supabaseService)
            }
            .accentColor(.blue)
            .offset(x: showingMenu ? 250 : 0)
            .scaleEffect(showingMenu ? 0.8 : 1)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: showingMenu)
            .disabled(showingMenu)
            
            // Side menu overlay
            if showingMenu {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation {
                            showingMenu = false
                        }
                    }
                
                SideMenuView(
                    currentEvent: selectedEvent,
                    onSwitchEvent: {
                        withAnimation {
                            showingMenu = false
                        }
                        // Clear current event to return to event list
                        supabaseService.currentEvent = nil
                    },
                    onLogout: {
                        withAnimation {
                            showingMenu = false
                        }
                        Task { @MainActor in
                            supabaseService.signOut()
                        }
                    }
                )
                .transition(.move(edge: .leading))
            }

            // Broadcast notification banner overlay
            if let banner = activeBanner {
                BroadcastNotificationBanner(
                    message: banner,
                    onDismiss: {
                        activeBanner = nil
                    },
                    onTap: {
                        activeBanner = nil
                        showingBroadcasts = true
                    }
                )
                .zIndex(999)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showingBroadcasts) {
            BroadcastMessagesView()
                .environmentObject(broadcastService)
        }
        .onAppear {
            // Subscribe to broadcasts when view appears
            Task {
                if let userId = supabaseService.currentUser?.id {
                    await broadcastService.subscribeToBroadcasts(
                        eventId: selectedEvent.id,
                        userId: userId
                    )
                }
            }
        }
        .onDisappear {
            // Unsubscribe when view disappears
            Task {
                await broadcastService.unsubscribeAll()
            }
        }
        .onReceive(broadcastService.$messages) { messages in
            // Show banner for new messages
            if let latestMessage = messages.first,
               let userId = supabaseService.currentUser?.id,
               !latestMessage.isReadBy(userId: userId),
               activeBanner?.id != latestMessage.id {
                activeBanner = latestMessage
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        showingMenu.toggle()
                    }
                }) {
                    Image(systemName: "line.3.horizontal")
                        .font(.title2)
                        .foregroundColor(.primary)
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    // Notification bell
                    NotificationBellIcon(
                        unreadCount: broadcastService.unreadCount,
                        action: {
                            showingBroadcasts = true
                        }
                    )

                    // Event info
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(selectedEvent.name)
                            .font(.headline)
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        if let location = selectedEvent.location {
                            Text(location)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Side Menu View
struct SideMenuView: View {
    let currentEvent: Event
    let onSwitchEvent: () -> Void
    let onLogout: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                // Unified Header Section
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                    // Header Title
                    HStack {
                        Image(systemName: "calendar.badge.checkmark")
                            .font(.title2)
                            .foregroundColor(DesignSystem.Colors.primary)
                        
                        Text("Current Event")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                            .textCase(.uppercase)
                            .tracking(1)
                    }
                    
                    // Event Details
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                        Text(currentEvent.name)
                            .font(DesignSystem.Typography.title)
                            .foregroundColor(DesignSystem.Colors.primaryText)
                            .lineLimit(2)
                        
                        if let location = currentEvent.location {
                            HStack(spacing: DesignSystem.Spacing.xs) {
                                Image(systemName: "location")
                                    .font(DesignSystem.Typography.caption)
                                    .foregroundColor(DesignSystem.Colors.secondaryText)
                                
                                Text(location)
                                    .font(DesignSystem.Typography.body)
                                    .foregroundColor(DesignSystem.Colors.secondaryText)
                                    .lineLimit(1)
                            }
                        }
                        
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            Image(systemName: "clock")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.secondaryText)
                                
                            Text(currentEvent.date, style: .date)
                                .font(DesignSystem.Typography.body)
                                .foregroundColor(DesignSystem.Colors.secondaryText)
                        }
                    }
                }
                .padding(DesignSystem.Spacing.large)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DesignSystem.Colors.sectionBackground)
                
                // Menu Options Section
                VStack(spacing: 0) {
                    MenuButton(
                        icon: "arrow.left.arrow.right",
                        title: "Switch Event",
                        subtitle: "Choose a different event",
                        action: onSwitchEvent
                    )
                    
                    Rectangle()
                        .fill(DesignSystem.Colors.sectionBackground)
                        .frame(height: 1)
                        .padding(.leading, DesignSystem.Spacing.xl + DesignSystem.Spacing.large)
                    
                    MenuButton(
                        icon: "rectangle.portrait.and.arrow.right",
                        title: "Log Out",
                        subtitle: "Sign out of your account",
                        action: onLogout,
                        isDestructive: true
                    )
                }
                .background(DesignSystem.Colors.menuBackground)
                
                Spacer()
                
                // Unified Footer
                VStack(spacing: DesignSystem.Spacing.small) {
                    Rectangle()
                        .fill(DesignSystem.Colors.sectionBackground)
                        .frame(height: 1)
                    
                    HStack(spacing: DesignSystem.Spacing.small) {
                        Image(systemName: "wave.3.right.circle.fill")
                            .foregroundColor(DesignSystem.Colors.primary)
                        
                        Text("NFC Event Manager")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                        
                        Spacer()
                    }
                    .padding(DesignSystem.Spacing.large)
                }
                .background(DesignSystem.Colors.menuBackground)
            }
            .frame(width: 300)
            .background(DesignSystem.Colors.menuBackground)
            .shadow(
                color: DesignSystem.Shadow.menu.color,
                radius: DesignSystem.Shadow.menu.radius,
                x: DesignSystem.Shadow.menu.x,
                y: DesignSystem.Shadow.menu.y
            )
            
            Spacer()
        }
    }
}

// MARK: - Menu Button Component
struct MenuButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void
    let isDestructive: Bool
    
    init(icon: String, title: String, subtitle: String, action: @escaping () -> Void, isDestructive: Bool = false) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.action = action
        self.isDestructive = isDestructive
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Spacing.medium) {
                // Icon Container
                Image(systemName: icon)
                    .font(.title3)
                    .frame(width: 24, height: 24)
                    .foregroundColor(isDestructive ? DesignSystem.Colors.danger : DesignSystem.Colors.primary)
                
                // Text Content
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text(title)
                        .font(DesignSystem.Typography.headline)
                        .foregroundColor(isDestructive ? DesignSystem.Colors.danger : DesignSystem.Colors.primaryText)
                    
                    Text(subtitle)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.secondaryText)
                }
                
                Spacer()
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
            }
            .padding(.horizontal, DesignSystem.Spacing.large)
            .padding(.vertical, DesignSystem.Spacing.medium)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    NavigationView {
        ThreeTabView(selectedEvent: Event(
            id: "1",
            name: "Sample Event",
            description: "A sample event for preview",
            location: "Sample Location",
            startDate: Date(),
            endDate: Calendar.current.date(byAdding: .day, value: 1, to: Date()),
            totalCapacity: 100,
            createdBy: "admin",
            createdAt: Date(),
            updatedAt: Date(),
            organizationId: "org-1"
        ))
    }
}
