import SwiftUI

struct EventSelectionView: View {
    @EnvironmentObject var supabaseService: SupabaseService
    @State private var events: [Event] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingDrawer = false
    @State private var wristbandCounts: [String: Int] = [:]
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background matching Flutter design
                Color(hex: "#F5F5F5")
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Custom App Bar
                    customAppBar
                    
                    // Content
                    if isLoading {
                        loadingSection
                    } else if events.isEmpty {
                        emptyStateSection
                    } else {
                        eventsListSection
                    }
                }
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            loadEvents()
        }
        .sheet(isPresented: $showingDrawer) {
            DrawerView()
                .environmentObject(supabaseService)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }
    
    // MARK: - Custom App Bar
    private var customAppBar: some View {
        HStack {
            Button(action: {
                showingDrawer = true
            }) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.black)
            }
            
            Spacer()
            
            Text("Events")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.black)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false) // Fix: Prevent title from expanding
            
            Spacer()
            
            // Placeholder for balance
            Color.clear
                .frame(width: 18)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8) // Fix: Reduce vertical padding
        .frame(height: 44) // Fix: Set fixed height for app bar
        .background(Color.white)
        .shadow(color: .black.opacity(0.05), radius: 1, x: 0, y: 1)
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
        .background(Color(hex: "#F5F5F5"))
    }
    
    // MARK: - Empty State Section
    private var emptyStateSection: some View {
        VStack(spacing: 24) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 64))
                .foregroundColor(.gray.opacity(0.6))
            
            VStack(spacing: 8) {
                Text("No Events Available")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text("Contact your administrator to get access to events")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button("Refresh") {
                loadEvents()
            }
            .buttonStyle(RefreshButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "#F5F5F5"))
    }
    
    // MARK: - Events List Section
    private var eventsListSection: some View {
        VStack(spacing: 0) {
            // Production-ready events list
            List(events) { event in
                EventCard(
                    event: event,
                    wristbandCount: wristbandCounts[event.id] ?? 0,
                    onTap: { selectEvent(event) }
                )
            }
            .listStyle(PlainListStyle())
            .refreshable {
                await refreshEvents()
            }
        }
    }
    
    // MARK: - Event Card
    private func eventCard(_ event: Event) -> some View {
        Button(action: {
            selectEvent(event)
        }) {
            VStack(alignment: .leading, spacing: 16) {
                // Header with event name and date
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.name)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.black)
                            .multilineTextAlignment(.leading)
                        
                        if let description = event.description {
                            Text(description)
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                                .lineLimit(2)
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(event.startDate, style: .date)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.gray)
                        
                        Text(event.startDate, style: .time)
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                            
                        if let endDate = event.endDate, !Calendar.current.isDate(event.startDate, inSameDayAs: endDate) {
                            Text("→ \(endDate, style: .date)")
                                .font(.system(size: 10))
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                // Location if available
                if let location = event.location {
                    HStack(spacing: 6) {
                        Image(systemName: "location")
                            .font(.system(size: 12))
                            .foregroundColor(.gray)
                        
                        Text(location)
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                    }
                }
                
                // Footer with wristband count
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "person.2")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "#635BFF") ?? .blue)
                        
                        Text("\(wristbandCounts[event.id] ?? 0) wristbands")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color(hex: "#635BFF") ?? .blue)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }
            }
            .padding(16)
            .background(Color.white)
            .cornerRadius(8)
            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(hex: "#E9ECEF") ?? .gray.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Actions
    private func loadEvents() {
        guard supabaseService.isAuthenticated else { 
            print("❌ EventSelectionView: Not authenticated, cannot load events")
            return 
        }
        
        print("🔄 EventSelectionView: Starting to load events...")
        
        Task { @MainActor in
            isLoading = true
            errorMessage = nil
            print("⏳ EventSelectionView: Set loading = true")
            
            do {
                print("📡 EventSelectionView: Calling fetchEvents...")
                let fetchedEvents = try await supabaseService.fetchEvents()
                print("✅ EventSelectionView: Received \(fetchedEvents.count) events from API")
                
                // Print each event for debugging
                for (index, event) in fetchedEvents.enumerated() {
                    print("   Event \(index + 1): \(event.name)")
                    print("      Location: \(event.location ?? "No location")")
                    print("      Start Date: \(event.startDate.description)")
                    print("      End Date: \(event.endDate?.description ?? "No end date")")
                    print("      ID: \(event.id)")
                }
                
                // Load wristband counts for each event (skip for now to isolate issue)
                print("📊 EventSelectionView: Loading wristband counts...")
                var counts: [String: Int] = [:]
                for event in fetchedEvents {
                    do {
                        let wristbands = try await supabaseService.fetchWristbands(for: event.id)
                        counts[event.id] = wristbands.count
                        print("   Event \(event.name): \(wristbands.count) wristbands")
                    } catch {
                        print("⚠️ Failed to load wristbands for \(event.name): \(error)")
                        counts[event.id] = 0
                    }
                }
                
                print("🎯 EventSelectionView: About to update UI with \(fetchedEvents.count) events")
                self.events = fetchedEvents
                self.wristbandCounts = counts
                self.isLoading = false
                print("✅ EventSelectionView: UI updated - events.count = \(self.events.count), isLoading = \(self.isLoading)")
                
            } catch {
                print("❌ EventSelectionView: Load events failed - \(error)")
                self.errorMessage = error.localizedDescription
                self.isLoading = false
                self.events = [] // Clear events on error - no sample data
                
                // Handle authentication errors
                if let authError = error as? AuthError {
                    print("🔒 Authentication error: \(authError.localizedDescription)")
                    // SupabaseService will handle logout automatically
                }
            }
        }
    }
    
    private func refreshEvents() async {
        await MainActor.run {
            loadEvents()
        }
    }
    
    private func selectEvent(_ event: Event) {
        Task { @MainActor in
            supabaseService.selectEvent(event)
        }
    }
}

// MARK: - Drawer View
struct DrawerView: View {
    @EnvironmentObject var supabaseService: SupabaseService
    @Environment(\.dismiss) private var dismiss
    @State private var showingProfile = false
    @State private var showingSettings = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("QuickStrap NFC")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
                
                if let user = supabaseService.currentUser {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.email)
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.9))
                        
                        Text(user.role.displayName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(.white.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
            }
            .padding(20)
            .background(
                LinearGradient(
                    colors: [Color(hex: "#635BFF") ?? .blue, Color(hex: "#7C3AED") ?? .purple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            
            // Menu Items
            VStack(spacing: 0) {
                DrawerMenuItem(
                    icon: "calendar",
                    title: "Events",
                    isSelected: true
                ) {
                    dismiss()
                }
                
                DrawerMenuItem(
                    icon: "person.circle",
                    title: "Profile",
                    isSelected: false
                ) {
                    showingProfile = true
                }
                
                DrawerMenuItem(
                    icon: "gearshape",
                    title: "Settings",
                    isSelected: false
                ) {
                    showingSettings = true
                }
            }
            
            Spacer()
            
            // Logout
            Button(action: {
                supabaseService.signOut()
                dismiss()
            }) {
                HStack(spacing: 12) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 16))
                        .foregroundColor(.red)
                    
                    Text("Logout")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.red)
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Color.white)
        }
        .background(Color.white)
        .sheet(isPresented: $showingProfile) {
            ProfileView()
                .environmentObject(supabaseService)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(supabaseService)
        }
    }
}

struct DrawerMenuItem: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? Color(hex: "#635BFF") ?? .blue : Color(hex: "#6B7280") ?? .gray)
                    .frame(width: 24)
                
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isSelected ? Color(hex: "#635BFF") ?? .blue : Color(hex: "#374151") ?? .primary)
                
                Spacer()
                
                if isSelected {
                    Circle()
                        .fill(Color(hex: "#635BFF") ?? .blue)
                        .frame(width: 6, height: 6)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: "#9CA3AF") ?? .gray)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(
                isSelected ? 
                Color(hex: "#635BFF")?.opacity(0.08) ?? .blue.opacity(0.08) : 
                Color.clear
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Button Styles
struct RefreshButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .medium))
            .foregroundColor(Color(hex: "#635BFF") ?? .blue)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(hex: "#635BFF") ?? .blue, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Login View (Simplified for drawer context)
struct LoginView: View {
    @EnvironmentObject var supabaseService: SupabaseService
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 16) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.white)
                        
                        Text("Sign In")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                    }
                    .padding(.top, 40)
                    
                    // Form
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Email")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                            
                            TextField("Enter your email", text: $email)
                                .textFieldStyle(CustomTextFieldStyle())
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Password")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                            
                            SecureField("Enter your password", text: $password)
                                .textFieldStyle(CustomTextFieldStyle())
                        }
                        
                        if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.horizontal, 4)
                        }
                    }
                    .padding(.horizontal, 24)
                    
                    // Sign In Button
                    Button(action: signIn) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.white)
                            }
                            Text(isLoading ? "Signing In..." : "Sign In")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isLoading || email.isEmpty || password.isEmpty)
                    .padding(.horizontal, 24)
                    
                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
        }
    }
    
    private func signIn() {
        Task { @MainActor in
            isLoading = true
            errorMessage = nil
            
            do {
                try await supabaseService.signIn(email: email, password: password)
                self.isLoading = false
                dismiss()
            } catch {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}

// MARK: - Custom Button Styles
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(.blue, in: RoundedRectangle(cornerRadius: 12))
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct CustomTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .foregroundColor(.white)
    }
}

// MARK: - EventCard Component
struct EventCard: View {
    let event: Event
    let wristbandCount: Int
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.name)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)
                        
                        if let location = event.location {
                            HStack(spacing: 4) {
                                Image(systemName: "location")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(location)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Status indicator
                    VStack(spacing: 4) {
                        Circle()
                            .fill(eventStatusColor)
                            .frame(width: 12, height: 12)
                        Text(eventStatusText)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Date range
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.caption)
                            .foregroundColor(.blue)
                        Text(event.startDate, style: .date)
                            .font(.caption)
                            .foregroundColor(.primary)
                    }
                    
                    if let endDate = event.endDate, !Calendar.current.isDate(event.startDate, inSameDayAs: endDate) {
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(endDate, style: .date)
                            .font(.caption)
                            .foregroundColor(.primary)
                    }
                    
                    Spacer()
                    
                    // Wristband count
                    if wristbandCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "person.2.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                            Text("\(wristbandCount)")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.green)
                        }
                    }
                }
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.blue.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var eventStatusColor: Color {
        let now = Date()
        if now < event.startDate {
            return .orange // Upcoming
        } else if let endDate = event.endDate, now > endDate {
            return .gray // Past
        } else {
            return .green // Active
        }
    }
    
    private var eventStatusText: String {
        let now = Date()
        if now < event.startDate {
            return "Upcoming"
        } else if let endDate = event.endDate, now > endDate {
            return "Ended"
        } else {
            return "Active"
        }
    }
}

#Preview {
    EventSelectionView()
        .environmentObject(SupabaseService.shared)
}
