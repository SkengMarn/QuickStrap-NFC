import SwiftUI

struct EventSelectionView: View {
    @EnvironmentObject var supabaseService: SupabaseService
    @State private var events: [Event] = []
    @State private var seriesEvents: [SeriesWithEvent] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingDrawer = false
    @State private var wristbandCounts: [String: Int] = [:]
    @State private var searchText: String = ""
    @State private var sortOption: EventSortOption = .startDate
    @State private var statusFilter: EventStatusFilter = .all
    @State private var selectedEvent: Event? = nil
    @State private var showingSeriesSelection = false
    @State private var eventSeriesMap: [String: [EventSeries]] = [:]  // Cache series for events

    // Filtered and sorted series events
    private var filteredSeriesEvents: [SeriesWithEvent] {
        var filtered = seriesEvents

        // Apply search filter
        if !searchText.isEmpty {
            filtered = filtered.filter { seriesEvent in
                seriesEvent.series.name.localizedCaseInsensitiveContains(searchText) ||
                seriesEvent.series.description?.localizedCaseInsensitiveContains(searchText) == true ||
                seriesEvent.series.location?.localizedCaseInsensitiveContains(searchText) == true ||
                seriesEvent.event.name.localizedCaseInsensitiveContains(searchText) ||
                seriesEvent.event.location?.localizedCaseInsensitiveContains(searchText) == true
            }
        }

        // Apply status filter
        filtered = filtered.filter { seriesEvent in
            switch statusFilter {
            case .all:
                return true
            case .active:
                let now = Date()
                return now >= seriesEvent.startDate && now <= seriesEvent.endDate
            case .upcoming:
                return seriesEvent.startDate > Date()
            case .past:
                return seriesEvent.endDate < Date()
            }
        }

        // Apply sorting
        switch sortOption {
        case .startDate:
            filtered.sort { $0.startDate < $1.startDate }
        case .name:
            filtered.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .status:
            filtered.sort { seriesStatusPriority(for: $0.series) < seriesStatusPriority(for: $1.series) }
        case .wristbandCount:
            filtered.sort { (wristbandCounts[$0.id] ?? 0) > (wristbandCounts[$1.id] ?? 0) }
        }

        return filtered
    }

    // Filtered and sorted standalone events (events without series)
    private var filteredEvents: [Event] {
        var filtered = events

        // Apply search filter
        if !searchText.isEmpty {
            filtered = filtered.filter { event in
                event.name.localizedCaseInsensitiveContains(searchText) ||
                event.description?.localizedCaseInsensitiveContains(searchText) == true ||
                event.location?.localizedCaseInsensitiveContains(searchText) == true
            }
        }

        // Apply status filter
        filtered = filtered.filter { event in
            switch statusFilter {
            case .all:
                return true
            case .active:
                let now = Date()
                return now >= event.startDate && (event.endDate == nil || now <= event.endDate!)
            case .upcoming:
                return event.startDate > Date()
            case .past:
                guard let endDate = event.endDate else {
                    return event.startDate < Date()
                }
                return endDate < Date()
            }
        }

        // Apply sorting
        switch sortOption {
        case .startDate:
            filtered.sort { $0.startDate < $1.startDate }
        case .name:
            filtered.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .status:
            filtered.sort { statusPriority(for: $0) < statusPriority(for: $1) }
        case .wristbandCount:
            filtered.sort { (wristbandCounts[$0.id] ?? 0) > (wristbandCounts[$1.id] ?? 0) }
        }

        return filtered
    }

    private func statusPriority(for event: Event) -> Int {
        let now = Date()
        if now >= event.startDate && (event.endDate == nil || now <= event.endDate!) {
            return 0 // Active events first
        } else if now < event.startDate {
            return 1 // Upcoming events second
        } else {
            return 2 // Past events last
        }
    }

    private func seriesStatusPriority(for series: EventSeries) -> Int {
        let now = Date()
        if now >= series.startDate && now <= series.endDate {
            return 0 // Active events first
        } else if now < series.startDate {
            return 1 // Upcoming events second
        } else {
            return 2 // Past events last
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                // Background matching Flutter design
                Color(hex: "#F5F5F5")
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Custom App Bar
                    customAppBar

                    // Search and Filter Bar (only show when not loading and have events)
                    if !isLoading && (!events.isEmpty || !seriesEvents.isEmpty) {
                        searchAndFilterBar
                    }

                    // Content
                    if isLoading {
                        loadingSection
                    } else if events.isEmpty && seriesEvents.isEmpty {
                        emptyStateSection
                    } else if filteredEvents.isEmpty && filteredSeriesEvents.isEmpty {
                        noResultsSection
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
        .sheet(isPresented: $showingSeriesSelection) {
            if let event = selectedEvent, let series = eventSeriesMap[event.id] {
                SeriesSelectionView(parentEvent: event, series: series)
                    .environmentObject(supabaseService)
            }
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

    // MARK: - Search and Filter Bar
    private var searchAndFilterBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                // Search field
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)

                    TextField("Search events...", text: $searchText)
                        .font(.system(size: 14))
                        .autocapitalization(.none)
                        .disableAutocorrection(true)

                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )

                // Sort menu
                Menu {
                    Button(action: { sortOption = .startDate }) {
                        Label("Start Date", systemImage: sortOption == .startDate ? "checkmark" : "")
                    }
                    Button(action: { sortOption = .name }) {
                        Label("Name", systemImage: sortOption == .name ? "checkmark" : "")
                    }
                    Button(action: { sortOption = .status }) {
                        Label("Status", systemImage: sortOption == .status ? "checkmark" : "")
                    }
                    Button(action: { sortOption = .wristbandCount }) {
                        Label("Attendees", systemImage: sortOption == .wristbandCount ? "checkmark" : "")
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down.circle")
                        .font(.system(size: 18))
                        .foregroundColor(Color(hex: "#635BFF") ?? .blue)
                        .padding(8)
                        .background(Color.white)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // Status filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(EventStatusFilter.allCases, id: \.self) { filter in
                        Button(action: {
                            statusFilter = filter
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: filter.icon)
                                    .font(.system(size: 12))
                                Text(filter.displayName)
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundColor(statusFilter == filter ? .white : Color(hex: "#635BFF") ?? .blue)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(statusFilter == filter ? Color(hex: "#635BFF") ?? .blue : Color.white)
                            .cornerRadius(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Color(hex: "#635BFF") ?? .blue, lineWidth: 1)
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            // Results count
            if !searchText.isEmpty || sortOption != .startDate || statusFilter != .all {
                HStack {
                    let totalCount = events.count + seriesEvents.count
                    let filteredCount = filteredEvents.count + filteredSeriesEvents.count
                    Text("\(filteredCount) of \(totalCount) events")
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                    Spacer()
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 8)
        .background(Color(hex: "#F5F5F5"))
    }

    // MARK: - No Results Section
    private var noResultsSection: some View {
        VStack(spacing: 24) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 64))
                .foregroundColor(.gray.opacity(0.6))

            VStack(spacing: 8) {
                Text("No Events Found")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text("Try adjusting your search or filters")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Clear Search") {
                searchText = ""
            }
            .buttonStyle(RefreshButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: "#F5F5F5"))
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
        ScrollView {
            LazyVStack(spacing: 12) {
                // Show series events first
                ForEach(filteredSeriesEvents) { seriesEvent in
                    SeriesEventCard(
                        seriesEvent: seriesEvent,
                        wristbandCount: wristbandCounts[seriesEvent.id] ?? 0,
                        onTap: { selectSeriesEvent(seriesEvent) }
                    )
                    .padding(.horizontal, 16)
                }

                // Then show standalone events
                ForEach(filteredEvents) { event in
                    EventCard(
                        event: event,
                        wristbandCount: wristbandCounts[event.id] ?? 0,
                        onTap: { selectEvent(event) }
                    )
                    .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 12)
        }
        .refreshable {
            await refreshEvents()
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

        print("🔄 EventSelectionView: Starting to load events and series...")

        Task { @MainActor in
            isLoading = true
            errorMessage = nil
            print("⏳ EventSelectionView: Set loading = true")

            do {
                // Load both series events and standalone events
                print("📡 EventSelectionView: Calling fetchAllActiveSeries...")
                let fetchedSeriesEvents = try await supabaseService.fetchAllActiveSeries()
                print("✅ EventSelectionView: Received \(fetchedSeriesEvents.count) series events from API")

                print("📡 EventSelectionView: Calling fetchEvents...")
                let fetchedEvents = try await supabaseService.fetchEvents()
                print("✅ EventSelectionView: Received \(fetchedEvents.count) regular events from API")

                // Get the main event IDs that have series
                let mainEventIdsWithSeries = Set(fetchedSeriesEvents.map { $0.series.mainEventId })
                print("📊 EventSelectionView: Found \(mainEventIdsWithSeries.count) main events with series")
                print("📊 EventSelectionView: Main event IDs with series: \(mainEventIdsWithSeries)")

                // Debug: Print all fetched events
                print("📋 All fetched events:")
                for event in fetchedEvents {
                    print("   - \(event.name) (ID: \(event.id))")
                }

                // Filter: Keep events that DON'T have series (standalone events)
                // Don't show the main/parent events that have series - show their series instead
                let standaloneEvents = fetchedEvents.filter { event in
                    let hasNoSeries = !mainEventIdsWithSeries.contains(event.id)
                    if !hasNoSeries {
                        print("   ❌ Filtering out '\(event.name)' - it has series")
                    }
                    return hasNoSeries
                }
                print("📊 EventSelectionView: \(standaloneEvents.count) standalone events (without series)")
                print("📊 EventSelectionView: Filtered out \(fetchedEvents.count - standaloneEvents.count) main events (they have series)")

                // Load wristband counts for series events
                print("📊 EventSelectionView: Loading wristband counts for series...")
                var counts: [String: Int] = [:]
                for seriesEvent in fetchedSeriesEvents {
                    do {
                        let wristbands = try await supabaseService.fetchWristbandsForSeries(seriesEvent.id)
                        counts[seriesEvent.id] = wristbands.count
                        print("   Series \(seriesEvent.name): \(wristbands.count) wristbands")
                    } catch {
                        print("⚠️ Failed to load wristbands for series \(seriesEvent.name): \(error)")
                        counts[seriesEvent.id] = 0
                    }
                }

                // Load wristband counts for standalone events
                print("📊 EventSelectionView: Loading wristband counts for standalone events...")
                for event in standaloneEvents {
                    do {
                        let wristbands = try await supabaseService.fetchWristbands(for: event.id)
                        counts[event.id] = wristbands.count
                        print("   Event \(event.name): \(wristbands.count) wristbands")
                    } catch {
                        print("⚠️ Failed to load wristbands for \(event.name): \(error)")
                        counts[event.id] = 0
                    }
                }

                print("🎯 EventSelectionView: About to update UI")
                self.seriesEvents = fetchedSeriesEvents
                self.events = standaloneEvents
                self.wristbandCounts = counts
                self.isLoading = false
                print("✅ EventSelectionView: UI updated - series: \(self.seriesEvents.count), standalone events: \(self.events.count), isLoading = \(self.isLoading)")

            } catch {
                print("❌ EventSelectionView: Load events failed - \(error)")
                self.errorMessage = error.localizedDescription
                self.isLoading = false
                self.events = []
                self.seriesEvents = []

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
        // Standalone event - go straight to scanner
        supabaseService.selectEvent(event)
    }

    private func selectSeriesEvent(_ seriesEvent: SeriesWithEvent) {
        // For series events, we need to create a temporary Event object
        // that represents this specific series instance
        // IMPORTANT: Set seriesId so wristband queries know to filter by series_id
        let event = Event(
            id: seriesEvent.series.id,
            name: seriesEvent.series.name,
            description: seriesEvent.series.description,
            location: seriesEvent.location,
            startDate: seriesEvent.series.startDate,
            endDate: seriesEvent.series.endDate,
            totalCapacity: seriesEvent.series.capacity,
            lifecycleStatus: seriesEvent.series.lifecycleStatus.rawValue,
            organizationId: seriesEvent.series.organizationId,
            seriesId: seriesEvent.series.id  // Mark this as a series event
        )
        supabaseService.selectEvent(event)
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

// MARK: - SeriesEventCard Component
struct SeriesEventCard: View {
    let seriesEvent: SeriesWithEvent
    let wristbandCount: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        // Series name
                        Text(seriesEvent.series.name)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.leading)

                        // Parent event name (smaller, secondary)
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(seriesEvent.event.name)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if let location = seriesEvent.location {
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
                            .fill(seriesStatusColor)
                            .frame(width: 12, height: 12)
                        Text(seriesStatusText)
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
                        Text(seriesEvent.startDate, style: .date)
                            .font(.caption)
                            .foregroundColor(.primary)
                    }

                    if !Calendar.current.isDate(seriesEvent.startDate, inSameDayAs: seriesEvent.endDate) {
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(seriesEvent.endDate, style: .date)
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
                    .stroke(Color.purple.opacity(0.3), lineWidth: 1.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var seriesStatusColor: Color {
        let now = Date()
        if now < seriesEvent.startDate {
            return .orange // Upcoming
        } else if now > seriesEvent.endDate {
            return .gray // Past
        } else {
            return .green // Active
        }
    }

    private var seriesStatusText: String {
        let now = Date()
        if now < seriesEvent.startDate {
            return "Upcoming"
        } else if now > seriesEvent.endDate {
            return "Ended"
        } else {
            return "Active"
        }
    }
}

// MARK: - Sort Options
enum EventSortOption {
    case startDate
    case name
    case status
    case wristbandCount
}

// MARK: - Status Filter
enum EventStatusFilter: String, CaseIterable {
    case all = "All"
    case active = "Active"
    case upcoming = "Upcoming"
    case past = "Past"

    var displayName: String {
        return rawValue
    }

    var icon: String {
        switch self {
        case .all: return "circle.grid.2x2"
        case .active: return "circle.fill"
        case .upcoming: return "clock"
        case .past: return "checkmark.circle"
        }
    }
}

#Preview {
    EventSelectionView()
        .environmentObject(SupabaseService.shared)
}
