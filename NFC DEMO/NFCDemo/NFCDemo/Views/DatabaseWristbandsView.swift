import SwiftUI

struct DatabaseWristbandsView: View {
    @EnvironmentObject var eventData: EventDataManager
    @EnvironmentObject var supabaseService: SupabaseService
    @StateObject private var viewModel = WristbandsViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search and Filters
                searchAndFiltersSection
                
                // Wristbands List
                wristbandsListSection
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Wristbands")
            .navigationBarTitleDisplayMode(.large)
            .preferredColorScheme(.dark)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if viewModel.isSelectionMode {
                        Button("Cancel") {
                            viewModel.exitSelectionMode()
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        if viewModel.isSelectionMode {
                            Button("Actions") {
                                viewModel.showingBulkActions = true
                            }
                            .disabled(viewModel.selectedWristbands.isEmpty)
                        } else {
                            Menu {
                                Button("Select Multiple") {
                                    viewModel.enterSelectionMode()
                                }
                                
                                Divider()
                                
                                Button("Refresh Data") {
                                    Task { @MainActor in
                                        await viewModel.refreshData()
                                    }
                                }
                                
                                Button("Export List") {
                                    // TODO: Implement export functionality
                                }
                                
                                if supabaseService.currentUser?.role == .admin {
                                    Button("Add Wristband") {
                                        viewModel.showingAddWristband = true
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .foregroundColor(.white)
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $viewModel.showingAddWristband) {
                AddWristbandView()
                    .environmentObject(supabaseService)
                    .environmentObject(viewModel)
            }
            .sheet(isPresented: $viewModel.showingBulkActions) {
                BulkActionsView()
                    .environmentObject(supabaseService)
                    .environmentObject(viewModel)
            }
        }
        .onAppear {
            viewModel.setup(supabaseService: supabaseService)
        }
        .refreshable {
            await viewModel.refreshData()
        }
    }
    
    // MARK: - Search and Filters Section
    private var searchAndFiltersSection: some View {
        VStack(spacing: 16) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.white.opacity(0.6))
                
                TextField("Search wristbands...", text: $viewModel.searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .foregroundColor(.white)
                    .onChange(of: viewModel.searchText) {
                        Task { @MainActor in
                            viewModel.applyFilters()
                        }
                    }
                
                if !viewModel.searchText.isEmpty {
                    Button(action: {
                        viewModel.searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
            
            // Filter Buttons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // Category Filter (only show categories with wristbands)
                    Menu {
                        Button("All Categories") {
                            Task { @MainActor in
                                viewModel.selectedCategory = nil
                                viewModel.applyFilters()
                            }
                        }
                        ForEach(viewModel.availableCategories, id: \.self) { category in
                            Button(action: {
                                Task { @MainActor in
                                    viewModel.selectedCategory = category
                                    viewModel.applyFilters()
                                }
                            }) {
                                HStack {
                                    Text(category.displayName)
                                    Spacer()
                                    Text("(\(viewModel.categoryCounts[category] ?? 0))")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    } label: {
                        HStack {
                            if let category = viewModel.selectedCategory {
                                Circle()
                                    .fill(Color(hex: category.color) ?? .blue)
                                    .frame(width: 12, height: 12)
                            }
                            Text(viewModel.selectedCategory?.displayName ?? "Category")
                            Image(systemName: "chevron.down")
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                    
                    // Status Filter
                    Menu {
                        ForEach(WristbandStatusFilter.allCases, id: \.self) { status in
                            Button(status.displayName) {
                                Task { @MainActor in
                                    viewModel.statusFilter = status
                                    viewModel.applyFilters()
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text(viewModel.statusFilter.displayName)
                            Image(systemName: "chevron.down")
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
            }
            
            // Results Summary
            HStack {
                if viewModel.isSelectionMode {
                    Text("\(viewModel.selectedWristbands.count) selected of \(viewModel.filteredWristbands.count) wristbands")
                        .font(.caption)
                        .foregroundColor(.blue)
                } else {
                    Text("\(viewModel.filteredWristbands.count) of \(viewModel.allWristbands.count) wristbands")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                }
                
                Spacer()
                
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.white)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 16)
        .background(Color.black.opacity(0.5))
    }
    
    // MARK: - Wristbands List Section
    private var wristbandsListSection: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if viewModel.isLoading {
                    // Loading state
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                            .tint(.white)
                        
                        Text("Loading wristbands...")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.vertical, 60)
                } else if viewModel.filteredWristbands.isEmpty {
                    emptyStateView
                } else {
                    ForEach(viewModel.filteredWristbands) { wristband in
                        wristbandRow(wristband)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
        .refreshable {
            await viewModel.refreshData()
        }
    }
    
    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.4))
            
            Text("No wristbands found")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            
            Text("Try adjusting your search or filters")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
            
            Button("Clear Filters") {
                Task { @MainActor in
                    viewModel.clearFilters()
                }
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(.vertical, 60)
    }
    
    // MARK: - Wristband Row
    private func wristbandRow(_ wristband: Wristband) -> some View {
        HStack(spacing: 16) {
            // Selection checkbox (when in selection mode)
            if viewModel.isSelectionMode {
                Button(action: {
                    viewModel.toggleSelection(for: wristband.id)
                }) {
                    Image(systemName: viewModel.selectedWristbands.contains(wristband.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundColor(viewModel.selectedWristbands.contains(wristband.id) ? .blue : .white.opacity(0.3))
                }
            }
            
            // Category and Status Indicators
            VStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: wristband.category.color) ?? .blue)
                    .frame(width: 16, height: 16)
                
                Image(systemName: viewModel.getCheckInStatus(for: wristband) ? "checkmark.circle.fill" : "circle")
                    .font(.caption)
                    .foregroundColor(viewModel.getCheckInStatus(for: wristband) ? .green : .white.opacity(0.3))
            }
            
            // Wristband Info
            VStack(alignment: .leading, spacing: 6) {
                // NFC ID
                Text(wristband.nfcId)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                
                // Category Badge
                HStack {
                    Text(wristband.category.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background((Color(hex: wristband.category.color) ?? .blue).opacity(0.3))
                        .foregroundColor(Color(hex: wristband.category.color) ?? .blue)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    
                    if !wristband.isActive {
                        Text("INACTIVE")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.red.opacity(0.3))
                            .foregroundColor(.red)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                    
                    Spacer()
                }
                
                // Check-in info
                if let checkInTime = viewModel.getCheckInTime(for: wristband) {
                    HStack {
                        Image(systemName: "clock")
                            .font(.caption2)
                            .foregroundColor(.green)
                        
                        Text("Checked in: \(checkInTime, style: .time)")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.6))
                    }
                } else {
                    Text("Not checked in")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.4))
                }
                
                // Created date
                Text("Created: \(wristband.createdAt, style: .date)")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.4))
            }
            
            Spacer()
            
            // Actions
            if !viewModel.isSelectionMode {
                VStack(spacing: 8) {
                    if !viewModel.getCheckInStatus(for: wristband) && wristband.isActive {
                        Button(action: {
                            Task {
                                await viewModel.manualCheckIn(wristband: wristband)
                            }
                        }) {
                            Text("Check In")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(.blue, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .disabled(viewModel.isLoading)
                    }
                    
                    // Only show View History action
                    Button(action: {
                        viewModel.selectedWristband = wristband
                        viewModel.showingWristbandHistory = true
                    }) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.6))
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke((Color(hex: wristband.category.color) ?? .blue).opacity(0.3), lineWidth: 1)
        )
        .sheet(isPresented: $viewModel.showingEditWristband) {
            if let wristband = viewModel.selectedWristband {
                EditWristbandView(wristband: wristband)
                    .environmentObject(supabaseService)
                    .environmentObject(viewModel)
            }
        }
        .sheet(isPresented: $viewModel.showingWristbandHistory) {
            if let wristband = viewModel.selectedWristband {
                WristbandHistoryView(wristband: wristband)
                    .environmentObject(supabaseService)
            }
        }
    }
}

// MARK: - Wristbands View Model
@MainActor
class WristbandsViewModel: ObservableObject {
    @Published var allWristbands: [Wristband] = []
    @Published var filteredWristbands: [Wristband] = []
    @Published var checkinLogs: [CheckinLog] = []
    @Published var searchText = ""
    @Published var selectedCategory: WristbandCategory?
    @Published var statusFilter: WristbandStatusFilter = .all
    @Published var isLoading = false
    @Published var showingAddWristband = false
    @Published var showingEditWristband = false
    @Published var showingWristbandHistory = false
    @Published var selectedWristband: Wristband?
    
    // Bulk Actions
    @Published var isSelectionMode = false
    @Published var selectedWristbands: Set<String> = []
    @Published var showingBulkActions = false
    
    // MARK: - Dynamic Categories (only categories with actual wristbands)
    var availableCategories: [WristbandCategory] {
        let categoriesWithWristbands = Set(allWristbands.map { $0.category })
        return Array(categoriesWithWristbands).sorted { $0.displayName < $1.displayName }
    }
    
    // MARK: - Category Counts (only non-zero counts)
    var categoryCounts: [WristbandCategory: Int] {
        var counts: [WristbandCategory: Int] = [:]
        for wristband in allWristbands {
            counts[wristband.category, default: 0] += 1
        }
        // Only return categories with count > 0
        return counts.filter { $0.value > 0 }
    }
    
    private var supabaseService: SupabaseService?
    private var loadTask: Task<Void, Never>?
    
    deinit {
        print("🧹 WristbandsViewModel: Cleaning up...")
        loadTask?.cancel()
    }
    
    func setup(supabaseService: SupabaseService) {
        self.supabaseService = supabaseService
        loadTask = Task { @MainActor in
            await loadData()
        }
    }
    
    @MainActor
    func refreshData() async {
        await loadData()
    }
    
    @MainActor
    private func loadData() async {
        guard let supabaseService = supabaseService,
              let currentEvent = supabaseService.currentEvent else { 
            print("⚠️ WristbandsViewModel: No supabase service or event")
            return 
        }
        
        let eventId = currentEvent.id
        let seriesId = currentEvent.seriesId
        
        if let seriesId = seriesId {
            print("🔍 WristbandsViewModel: Loading data for SERIES \(seriesId)")
        } else {
            print("🔍 WristbandsViewModel: Loading data for PARENT EVENT \(eventId)")
        }
        
        isLoading = true
        
        do {
            print("📡 WristbandsViewModel: Fetching wristbands and logs...")
            
            // Fetch wristbands based on whether this is a series or parent event
            let fetchedWristbands: [Wristband]
            let fetchedLogs: [CheckinLog]
            
            if let seriesId = seriesId {
                // This is a series event - fetch wristbands and logs by series_id
                fetchedWristbands = try await supabaseService.fetchWristbandsForSeries(seriesId)
                fetchedLogs = try await supabaseService.fetchCheckinLogsForSeries(seriesId)
                print("✅ Fetched \(fetchedWristbands.count) wristbands and \(fetchedLogs.count) logs for series \(seriesId)")
            } else {
                // This is a parent event - fetch wristbands and logs by event_id
                fetchedWristbands = try await supabaseService.fetchWristbands(for: eventId)
                fetchedLogs = try await supabaseService.fetchCheckinLogs(for: eventId)
                print("✅ Fetched \(fetchedWristbands.count) wristbands and \(fetchedLogs.count) logs for parent event \(eventId)")
            }
            
            print("✅ WristbandsViewModel: Data loaded - \(fetchedWristbands.count) wristbands, \(fetchedLogs.count) logs")
            self.allWristbands = fetchedWristbands
            self.checkinLogs = fetchedLogs
            self.applyFilters()
            self.isLoading = false
        } catch {
            print("❌ WristbandsViewModel: Load data failed - \(error)")
            self.isLoading = false
            // Show empty state or error message
            self.allWristbands = []
            self.checkinLogs = []
            self.applyFilters()
        }
    }
    
    @MainActor
    func applyFilters() {
        filteredWristbands = allWristbands.filter { wristband in
            // Search text filter
            let matchesSearch = searchText.isEmpty ||
                wristband.nfcId.localizedCaseInsensitiveContains(searchText) ||
                wristband.category.displayName.localizedCaseInsensitiveContains(searchText)
            
            // Category filter
            let matchesCategory = selectedCategory == nil || wristband.category == selectedCategory
            
            // Status filter
            let isCheckedIn = getCheckInStatus(for: wristband)
            let matchesStatus = statusFilter == .all ||
                (statusFilter == .checkedIn && isCheckedIn) ||
                (statusFilter == .pending && !isCheckedIn)
            
            return matchesSearch && matchesCategory && matchesStatus
        }
    }
    
    @MainActor
    func clearFilters() {
        searchText = ""
        selectedCategory = nil
        statusFilter = .all
        applyFilters()
    }
    
    func getCheckInStatus(for wristband: Wristband) -> Bool {
        return checkinLogs.contains { $0.wristbandId == wristband.id }
    }
    
    func getCheckInTime(for wristband: Wristband) -> Date? {
        return checkinLogs.first { $0.wristbandId == wristband.id }?.timestamp
    }
    
    func manualCheckIn(wristband: Wristband) async {
        guard let supabaseService = supabaseService,
              let currentEvent = supabaseService.currentEvent else { 
            print("❌ No supabase service or event available")
            return 
        }
        
        // Determine the correct event_id and series_id
        // For series events: event_id should be the parent event ID (from wristband.eventId)
        // and series_id should be the series ID (from currentEvent.seriesId)
        let eventId: String
        let seriesId: String?
        
        if let currentSeriesId = currentEvent.seriesId {
            // This is a series event - use wristband's event_id (parent) and current series_id
            eventId = wristband.eventId
            seriesId = currentSeriesId
            print("🔄 Starting manual check-in for SERIES wristband: \(wristband.nfcId)")
            print("   Parent Event ID: \(eventId), Series ID: \(currentSeriesId)")
        } else {
            // This is a parent event - use current event ID, no series_id
            eventId = currentEvent.id
            seriesId = nil
            print("🔄 Starting manual check-in for PARENT EVENT wristband: \(wristband.nfcId)")
            print("   Event ID: \(eventId)")
        }
        
        do {
            // Record the check-in using the existing method
            let _ = try await supabaseService.recordCheckIn(
                wristbandId: wristband.id,
                eventId: eventId,
                location: "Manual Check-in - \(wristband.category.name) Area",
                notes: "Manual check-in from wristbands view",
                gateId: nil, // No specific gate for manual check-in
                seriesId: seriesId
            )
            
            print("✅ Manual check-in successful for \(wristband.category.name) wristband: \(wristband.nfcId)")
            
            // Refresh data to show the updated status
            await refreshData()
            
        } catch {
            print("❌ Failed to check in wristband: \(error)")
            // You might want to show an alert to the user here
        }
    }
    
    func deactivateWristband(_ wristband: Wristband) async {
        // TODO: Implement deactivation
        print("Deactivating wristband: \(wristband.nfcId)")
    }
    
    func activateWristband(_ wristband: Wristband) async {
        // TODO: Implement activation
        print("Activating wristband: \(wristband.nfcId)")
    }
    
    // MARK: - Selection Mode Methods
    func enterSelectionMode() {
        isSelectionMode = true
        selectedWristbands.removeAll()
    }
    
    func exitSelectionMode() {
        isSelectionMode = false
        selectedWristbands.removeAll()
    }
    
    func toggleSelection(for wristbandId: String) {
        if selectedWristbands.contains(wristbandId) {
            selectedWristbands.remove(wristbandId)
        } else {
            selectedWristbands.insert(wristbandId)
        }
    }
    
    func selectAll() {
        selectedWristbands = Set(filteredWristbands.map { $0.id })
    }
    
    func deselectAll() {
        selectedWristbands.removeAll()
    }
    
    // MARK: - Bulk Actions
    func bulkCheckIn() async {
        guard let supabaseService = supabaseService,
              let eventId = supabaseService.currentEvent?.id else { return }
        
        let wristbandsToCheckIn = filteredWristbands.filter { 
            selectedWristbands.contains($0.id) && 
            !getCheckInStatus(for: $0) && 
            $0.isActive 
        }
        
        for wristband in wristbandsToCheckIn {
            await manualCheckIn(wristband: wristband)
        }
        
        exitSelectionMode()
    }
    
    func bulkExport() {
        let selectedWristbandsList = filteredWristbands.filter { selectedWristbands.contains($0.id) }
        // TODO: Implement export functionality
        print("Exporting \(selectedWristbandsList.count) wristbands")
        exitSelectionMode()
    }
}

// MARK: - Add Wristband View
struct AddWristbandView: View {
    @EnvironmentObject var supabaseService: SupabaseService
    @EnvironmentObject var viewModel: WristbandsViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var nfcId = ""
    @State private var selectedCategory: WristbandCategory = WristbandCategory(name: "General")
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Wristband Details")) {
                    TextField("NFC ID", text: $nfcId)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(viewModel.availableCategories, id: \.self) { category in
                            Text(category.displayName).tag(category)
                        }
                    }
                }
                
                if let errorMessage = errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Add Wristband")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        Task {
                            await addWristband()
                        }
                    }
                    .disabled(nfcId.isEmpty || isLoading)
                }
            }
        }
    }
    
    @MainActor
    private func addWristband() async {
        guard let eventId = supabaseService.currentEvent?.id else { return }
        
        isLoading = true
        errorMessage = nil
        
        let wristband = Wristband(
            id: UUID().uuidString,
            eventId: eventId,
            nfcId: nfcId,
            category: selectedCategory,
            isActive: true,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        do {
            let _ = try await supabaseService.createWristband(wristband)
            await viewModel.refreshData()
            dismiss()
        } catch {
            self.errorMessage = error.localizedDescription
            self.isLoading = false
        }
    }
}

// MARK: - Edit Wristband View
struct EditWristbandView: View {
    let wristband: Wristband
    @EnvironmentObject var supabaseService: SupabaseService
    @EnvironmentObject var viewModel: WristbandsViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var nfcId: String
    @State private var selectedCategory: WristbandCategory
    @State private var isActive: Bool
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    init(wristband: Wristband) {
        self.wristband = wristband
        self._nfcId = State(initialValue: wristband.nfcId)
        self._selectedCategory = State(initialValue: wristband.category)
        self._isActive = State(initialValue: wristband.isActive)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Wristband Details")) {
                    TextField("NFC ID", text: $nfcId)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(viewModel.availableCategories, id: \.self) { category in
                            Text(category.displayName).tag(category)
                        }
                    }
                    
                    Toggle("Active", isOn: $isActive)
                }
                
                Section("Information") {
                    HStack {
                        Text("Created")
                        Spacer()
                        Text(wristband.createdAt, style: .date)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Last Updated")
                        Spacer()
                        Text(wristband.updatedAt, style: .date)
                            .foregroundColor(.secondary)
                    }
                }
                
                if let errorMessage = errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Edit Wristband")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task {
                            await saveChanges()
                        }
                    }
                    .disabled(nfcId.isEmpty || isLoading)
                }
            }
        }
    }
    
    @MainActor
    private func saveChanges() async {
        // TODO: Implement save functionality
        dismiss()
    }
}

// MARK: - Wristband History View
struct WristbandHistoryView: View {
    let wristband: Wristband
    @EnvironmentObject var supabaseService: SupabaseService
    @Environment(\.dismiss) private var dismiss
    
    @State private var checkinLogs: [CheckinLog] = []
    @State private var isLoading = false
    
    var body: some View {
        NavigationView {
            List {
                Section("Wristband Info") {
                    HStack {
                        Text("NFC ID")
                        Spacer()
                        Text(wristband.nfcId)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Category")
                        Spacer()
                        Text(wristband.category.displayName)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(wristband.isActive ? "Active" : "Inactive")
                            .foregroundColor(wristband.isActive ? .green : .red)
                    }
                }
                
                Section("Check-in History") {
                    if checkinLogs.isEmpty {
                        Text("No check-in history")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(checkinLogs) { log in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(log.timestamp, style: .date)
                                        .font(.headline)
                                    Spacer()
                                    Text(log.timestamp, style: .time)
                                        .foregroundColor(.secondary)
                                }
                                
                                if let location = log.location {
                                    Text("📍 \(location)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                if let notes = log.notes {
                                    Text(notes)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .navigationTitle("Wristband History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            loadHistory()
        }
    }
    
    private func loadHistory() {
        // TODO: Load actual check-in history for this wristband
        // For now, use mock data
        checkinLogs = []
    }
}

// MARK: - Bulk Actions View
struct BulkActionsView: View {
    @EnvironmentObject var supabaseService: SupabaseService
    @EnvironmentObject var viewModel: WristbandsViewModel
    @Environment(\.dismiss) private var dismiss
    
    var selectedWristbands: [Wristband] {
        viewModel.filteredWristbands.filter { viewModel.selectedWristbands.contains($0.id) }
    }
    
    var uncheckedInCount: Int {
        selectedWristbands.filter { !viewModel.getCheckInStatus(for: $0) && $0.isActive }.count
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Selection Summary
                VStack(spacing: 12) {
                    Text("Bulk Actions")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("\(selectedWristbands.count) wristbands selected")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if uncheckedInCount > 0 {
                        Text("\(uncheckedInCount) can be checked in")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                
                // Actions
                VStack(spacing: 16) {
                    // Bulk Check-in
                    if uncheckedInCount > 0 {
                        Button(action: {
                            Task {
                                await viewModel.bulkCheckIn()
                                dismiss()
                            }
                        }) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title3)
                                
                                VStack(alignment: .leading) {
                                    Text("Check In All")
                                        .font(.headline)
                                    Text("Check in \(uncheckedInCount) wristbands")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                            }
                            .foregroundColor(.white)
                            .padding()
                            .background(.blue, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    
                    // Bulk Export
                    Button(action: {
                        viewModel.bulkExport()
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                                .font(.title3)
                            
                            VStack(alignment: .leading) {
                                Text("Export Selected")
                                    .font(.headline)
                                Text("Export \(selectedWristbands.count) wristbands")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                        .foregroundColor(.primary)
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                    
                    // Select/Deselect All
                    HStack(spacing: 12) {
                        Button("Select All") {
                            viewModel.selectAll()
                        }
                        .buttonStyle(.bordered)
                        
                        Button("Deselect All") {
                            viewModel.deselectAll()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Bulk Actions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    DatabaseWristbandsView()
        .environmentObject(EventDataManager())
        .environmentObject(SupabaseService.shared)
}
