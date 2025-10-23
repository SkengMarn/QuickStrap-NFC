import Foundation
import Network
import Combine

// MARK: - Offline Data Manager
@MainActor
class OfflineDataManager: ObservableObject {
    static let shared = OfflineDataManager()
    
    @Published var isOnline = false {
        didSet {
            UserDefaults.standard.set(isOnline, forKey: "isOnline")
        }
    }
    
    nonisolated var isOnlineSync: Bool {
        return UserDefaults.standard.bool(forKey: "isOnline")
    }
    @Published var isSyncing = false
    @Published var pendingSyncCount = 0
    @Published var lastSyncDate: Date?
    
    private let networkMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "NetworkMonitor")
    private var cancellables = Set<AnyCancellable>()
    
    // Local storage keys
    private let pendingScansKey = "pendingScans"
    private let cachedEventsKey = "cachedEvents"
    private let cachedWristbandsKey = "cachedWristbands"
    private let lastSyncKey = "lastSyncDate"
    
    private init() {
        startNetworkMonitoring()
        loadPendingSyncCount()
        loadLastSyncDate()
    }
    
    // MARK: - Network Monitoring
    
    private func startNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                let wasOnline = self?.isOnline ?? false
                self?.isOnline = path.status == .satisfied
                
                // Auto-sync when coming back online
                if !wasOnline && self?.isOnline == true {
                    await self?.performAutoSync()
                }
            }
        }
        networkMonitor.start(queue: monitorQueue)
    }
    
    // MARK: - Local Storage Management
    
    func cacheEvents(_ events: [Event]) async {
        do {
            let data = try JSONEncoder().encode(events)
            UserDefaults.standard.set(data, forKey: cachedEventsKey)
            print("📱 Cached \(events.count) events locally")
        } catch {
            print("❌ Failed to cache events: \(error)")
        }
    }
    
    nonisolated func getCachedEvents() -> [Event] {
        guard let data = UserDefaults.standard.data(forKey: cachedEventsKey) else {
            return []
        }
        
        do {
            let events = try JSONDecoder().decode([Event].self, from: data)
            print("📱 Retrieved \(events.count) cached events")
            return events
        } catch {
            print("❌ Failed to decode cached events: \(error)")
            return []
        }
    }
    
    func cacheWristbands(_ wristbands: [Wristband], for eventId: String) async {
        var cachedWristbands = getAllCachedWristbands()
        cachedWristbands[eventId] = wristbands
        
        do {
            let data = try JSONEncoder().encode(cachedWristbands)
            UserDefaults.standard.set(data, forKey: cachedWristbandsKey)
            print("📱 Cached \(wristbands.count) wristbands for event \(eventId)")
        } catch {
            print("❌ Failed to cache wristbands: \(error)")
        }
    }
    
    nonisolated func getCachedWristbands(for eventId: String) -> [Wristband] {
        let allCached = getAllCachedWristbands()
        let wristbands = allCached[eventId] ?? []
        print("📱 Retrieved \(wristbands.count) cached wristbands for event \(eventId)")
        return wristbands
    }
    
    nonisolated private func getAllCachedWristbands() -> [String: [Wristband]] {
        guard let data = UserDefaults.standard.data(forKey: cachedWristbandsKey) else {
            return [:]
        }
        
        do {
            return try JSONDecoder().decode([String: [Wristband]].self, from: data)
        } catch {
            print("❌ Failed to decode cached wristbands: \(error)")
            return [:]
        }
    }
    
    // MARK: - Offline Scanning Queue
    
    func queueOfflineScan(_ scan: OfflineScan) {
        Task { @MainActor in
            var pendingScans = getPendingScans()
            pendingScans.append(scan)
            savePendingScans(pendingScans)
            
            pendingSyncCount = pendingScans.count
            print("📱 Queued offline scan. Total pending: \(pendingSyncCount)")
        }
    }
    
    func queueOfflineScanSync(_ scan: OfflineScan) async {
        var pendingScans = getPendingScans()
        pendingScans.append(scan)
        savePendingScans(pendingScans)
        
        pendingSyncCount = pendingScans.count
        print("📱 Queued offline scan. Total pending: \(pendingSyncCount)")
    }
    
    nonisolated func getPendingScans() -> [OfflineScan] {
        guard let data = UserDefaults.standard.data(forKey: pendingScansKey) else {
            return []
        }
        
        do {
            return try JSONDecoder().decode([OfflineScan].self, from: data)
        } catch {
            print("❌ Failed to decode pending scans: \(error)")
            return []
        }
    }
    
    nonisolated private func savePendingScans(_ scans: [OfflineScan]) {
        do {
            let data = try JSONEncoder().encode(scans)
            UserDefaults.standard.set(data, forKey: pendingScansKey)
        } catch {
            print("❌ Failed to save pending scans: \(error)")
        }
    }
    
    private func loadPendingSyncCount() {
        pendingSyncCount = getPendingScans().count
    }
    
    private func loadLastSyncDate() {
        lastSyncDate = UserDefaults.standard.object(forKey: lastSyncKey) as? Date
    }
    
    // MARK: - Sync Operations
    
    func performAutoSync() async {
        guard isOnline && !isSyncing else { return }
        
        print("🔄 Starting auto-sync...")
        await performSync()
    }
    
    func performManualSync() async {
        guard !isSyncing else { return }
        
        print("🔄 Starting manual sync...")
        await performSync()
    }
    
    private func performSync() async {
        isSyncing = true
        
        // Sync pending scans first
        await syncPendingScans()
        
        // Update last sync time
        lastSyncDate = Date()
        UserDefaults.standard.set(lastSyncDate, forKey: lastSyncKey)
        
        print("✅ Sync completed successfully")
        
        isSyncing = false
    }
    
    private func syncPendingScans() async {
        let pendingScans = getPendingScans()
        guard !pendingScans.isEmpty else { return }
        
        print("🔄 Syncing \(pendingScans.count) pending scans...")
        
        var successfulSyncs: [String] = []
        
        for scan in pendingScans {
            do {
                // Attempt to sync each scan
                try await syncScanToServer(scan)
                successfulSyncs.append(scan.id)
                print("✅ Synced scan: \(scan.nfcId)")
            } catch {
                print("❌ Failed to sync scan \(scan.nfcId): \(error)")
                // Keep failed scans in queue for retry
            }
        }
        
        // Remove successfully synced items
        let remainingScans = pendingScans.filter { !successfulSyncs.contains($0.id) }
        savePendingScans(remainingScans)
        pendingSyncCount = remainingScans.count
        
        print("🔄 Sync complete. \(successfulSyncs.count) synced, \(remainingScans.count) remaining")
    }
    
    private func syncScanToServer(_ scan: OfflineScan) async throws {
        // This would integrate with your SupabaseService
        // For now, simulate the sync
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // In real implementation:
        // try await SupabaseService.shared.createCheckinLog(scan.toCheckinLog())
    }
    
    // MARK: - Cleanup
    
    func clearCache() {
        UserDefaults.standard.removeObject(forKey: cachedEventsKey)
        UserDefaults.standard.removeObject(forKey: cachedWristbandsKey)
        UserDefaults.standard.removeObject(forKey: pendingScansKey)
        UserDefaults.standard.removeObject(forKey: lastSyncKey)
        
        pendingSyncCount = 0
        lastSyncDate = nil
        
        print("🗑️ Cleared all offline cache")
    }
}

// MARK: - Offline Scan Model
struct OfflineScan: Codable, Identifiable {
    let id: String
    let eventId: String
    let nfcId: String
    let timestamp: Date
    let location: String?
    let notes: String?
    let staffId: String?
    let seriesId: String?
    
    init(eventId: String, nfcId: String, location: String? = nil, notes: String? = nil, staffId: String? = nil, seriesId: String? = nil) {
        self.id = UUID().uuidString
        self.eventId = eventId
        self.nfcId = nfcId
        self.timestamp = Date()
        self.location = location
        self.notes = notes
        self.staffId = staffId
        self.seriesId = seriesId
    }
    
    func toCheckinLog() -> CheckinLog {
        return CheckinLog(
            id: id,
            eventId: eventId,
            wristbandId: nfcId, // Assuming NFC ID maps to wristband ID
            staffId: staffId,
            timestamp: timestamp,
            location: location,
            notes: notes,
            gateId: nil,
            scannerId: nil,
            appLat: nil,
            appLon: nil,
            appAccuracy: nil,
            bleSeen: nil,
            wifiSSIDs: nil,
            probationTagged: nil,
            seriesId: seriesId
        )
    }
}

// MARK: - Connectivity Status
enum ConnectivityStatus {
    case online
    case offline
    case syncing
    
    var displayText: String {
        switch self {
        case .online: return "Online"
        case .offline: return "Offline"
        case .syncing: return "Syncing..."
        }
    }
    
    var color: String {
        switch self {
        case .online: return "#00C853" // Green
        case .offline: return "#FF5722" // Red
        case .syncing: return "#FF9800" // Orange
        }
    }
}
