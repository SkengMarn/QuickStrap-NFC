import Foundation
import Combine
import Network

/// Enhanced offline sync engine with conflict resolution (Portal Parity)
@MainActor
class OfflineSyncEngine: ObservableObject {
    static let shared = OfflineSyncEngine()

    @Published var isSyncing = false
    @Published var queueCount = 0
    @Published var syncProgress: Double = 0.0
    @Published var syncStatistics = SyncStatistics(
        totalPending: 0,
        totalFailed: 0,
        totalCompleted: 0,
        lastSyncAt: nil,
        averageSyncTimeMs: 0,
        conflictCount: 0,
        retryCount: 0
    )
    @Published var conflicts: [SyncConflict] = []
    @Published var isOnline = true

    private let supabaseService = SupabaseService.shared
    private var localQueue: [MobileSyncQueue] = []
    private var networkMonitor: NWPathMonitor?
    private var syncTimer: Timer?
    private let maxRetries = 3
    private let retryDelay: TimeInterval = 5.0

    private init() {
        setupNetworkMonitoring()
        loadLocalQueue()
        startAutoSync()
    }

    // MARK: - Network Monitoring

    private func setupNetworkMonitoring() {
        networkMonitor = NWPathMonitor()
        networkMonitor?.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                let wasOffline = !(self?.isOnline ?? true)
                self?.isOnline = path.status == .satisfied

                if wasOffline && self?.isOnline == true {
                    print("🌐 Back online - triggering sync")
                    await self?.syncAll()
                } else if self?.isOnline == false {
                    print("📴 Went offline - queuing operations")
                }
            }
        }
        networkMonitor?.start(queue: DispatchQueue.global(qos: .background))
    }

    // MARK: - Queue Management

    func queueOperation(
        actionType: SyncActionType,
        tableName: String,
        recordData: [String: String]
    ) {
        guard let userId = supabaseService.currentUser?.id else {
            print("❌ Cannot queue - no user ID")
            return
        }

        let queueItem = MobileSyncQueue(
            id: UUID().uuidString,
            userId: userId,
            actionType: actionType,
            tableName: tableName,
            recordData: recordData,
            syncStatus: .pending,
            retryCount: 0,
            lastError: nil,
            createdAt: Date()
        )

        localQueue.append(queueItem)
        queueCount = localQueue.count
        saveLocalQueue()

        print("➕ Queued \(actionType.rawValue) operation for \(tableName)")

        // Try to sync immediately if online
        if isOnline {
            Task {
                await syncAll()
            }
        }
    }

    /// Queue a check-in for offline sync
    func queueCheckin(
        eventId: String,
        wristbandId: String,
        location: String?,
        notes: String?,
        gateId: String?,
        timestamp: Date = Date()
    ) {
        let recordData: [String: String] = [
            "event_id": eventId,
            "wristband_id": wristbandId,
            "location": location ?? "",
            "notes": notes ?? "",
            "gate_id": gateId ?? "",
            "timestamp": ISO8601DateFormatter().string(from: timestamp),
            "staff_id": supabaseService.currentUser?.id ?? ""
        ]

        queueOperation(
            actionType: .checkin,
            tableName: "checkin_logs",
            recordData: recordData
        )
    }

    // MARK: - Sync Operations

    func syncAll() async {
        guard !isSyncing, isOnline else {
            print("⏸️ Skipping sync - already syncing or offline")
            return
        }

        guard !localQueue.isEmpty else {
            print("✅ No items to sync")
            return
        }

        isSyncing = true
        syncProgress = 0.0
        let startTime = Date()

        print("🔄 Starting sync of \(localQueue.count) items...")

        var successCount = 0
        var failureCount = 0
        var conflictCount = 0

        let totalItems = Double(localQueue.count)
        var processedItems = 0.0

        for (index, item) in localQueue.enumerated() {
            guard item.syncStatus != .completed else {
                processedItems += 1
                syncProgress = processedItems / totalItems
                continue
            }

            do {
                try await syncItem(item)
                successCount += 1

                // Remove from queue
                if let itemIndex = localQueue.firstIndex(where: { $0.id == item.id }) {
                    localQueue.remove(at: itemIndex)
                }
            } catch {
                failureCount += 1
                print("❌ Sync failed for item \(item.id): \(error)")

                // Update retry count
                if let itemIndex = localQueue.firstIndex(where: { $0.id == item.id }) {
                    var updatedItem = item
                    if var mutableItem = localQueue[itemIndex] as? MobileSyncQueue {
                        // Handle retry logic
                        let newRetryCount = item.retryCount + 1
                        if newRetryCount >= maxRetries {
                            print("⚠️ Max retries reached for item \(item.id)")
                            // Mark as failed
                            localQueue.remove(at: itemIndex)
                            conflictCount += 1
                        }
                    }
                }
            }

            processedItems += 1
            syncProgress = processedItems / totalItems
        }

        // Update statistics
        let syncDuration = Date().timeIntervalSince(startTime)
        let avgTimeMs = totalItems > 0 ? (syncDuration / totalItems) * 1000 : 0

        syncStatistics = SyncStatistics(
            totalPending: localQueue.count,
            totalFailed: syncStatistics.totalFailed + failureCount,
            totalCompleted: syncStatistics.totalCompleted + successCount,
            lastSyncAt: Date(),
            averageSyncTimeMs: avgTimeMs,
            conflictCount: syncStatistics.conflictCount + conflictCount,
            retryCount: syncStatistics.retryCount + failureCount
        )

        queueCount = localQueue.count
        isSyncing = false
        saveLocalQueue()

        print("✅ Sync complete - Success: \(successCount), Failed: \(failureCount), Remaining: \(localQueue.count)")
    }

    private func syncItem(_ item: MobileSyncQueue) async throws {
        print("🔄 Syncing \(item.actionType.rawValue) for \(item.tableName)")

        switch item.actionType {
        case .checkin:
            try await syncCheckin(item)
        case .create:
            try await syncCreate(item)
        case .update:
            try await syncUpdate(item)
        case .delete:
            try await syncDelete(item)
        case .linkTicket:
            try await syncLinkTicket(item)
        }
    }

    private func syncCheckin(_ item: MobileSyncQueue) async throws {
        let data = item.recordData

        guard let eventId = data["event_id"],
              let wristbandId = data["wristband_id"] else {
            throw NSError(domain: "OfflineSyncEngine", code: 400, userInfo: [NSLocalizedDescriptionKey: "Missing required fields"])
        }

        _ = try await supabaseService.recordCheckIn(
            wristbandId: wristbandId,
            eventId: eventId,
            location: data["location"],
            notes: data["notes"],
            gateId: data["gate_id"]
        )

        print("✅ Check-in synced successfully")
    }

    private func syncCreate(_ item: MobileSyncQueue) async throws {
        // Convert dictionary to JSON data
        let jsonData = try JSONSerialization.data(withJSONObject: item.recordData)

        let _: [[String: String]] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/\(item.tableName)",
            method: "POST",
            body: jsonData,
            responseType: [[String: String]].self
        )

        print("✅ Create synced successfully")
    }

    private func syncUpdate(_ item: MobileSyncQueue) async throws {
        guard let recordId = item.recordData["id"] else {
            throw NSError(domain: "OfflineSyncEngine", code: 400, userInfo: [NSLocalizedDescriptionKey: "Missing record ID"])
        }

        let jsonData = try JSONSerialization.data(withJSONObject: item.recordData)

        let _: [[String: String]] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/\(item.tableName)?id=eq.\(recordId)",
            method: "PATCH",
            body: jsonData,
            responseType: [[String: String]].self
        )

        print("✅ Update synced successfully")
    }

    private func syncDelete(_ item: MobileSyncQueue) async throws {
        guard let recordId = item.recordData["id"] else {
            throw NSError(domain: "OfflineSyncEngine", code: 400, userInfo: [NSLocalizedDescriptionKey: "Missing record ID"])
        }

        let _: [[String: String]] = try await supabaseService.makeRequest(
            endpoint: "rest/v1/\(item.tableName)?id=eq.\(recordId)",
            method: "DELETE",
            responseType: [[String: String]].self
        )

        print("✅ Delete synced successfully")
    }

    private func syncLinkTicket(_ item: MobileSyncQueue) async throws {
        // TODO: Implement ticket linking sync
        print("ℹ️ Ticket linking sync not yet implemented")
    }

    // MARK: - Auto Sync

    private func startAutoSync() {
        // Sync every 60 seconds when online
        syncTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                if self?.isOnline == true && !(self?.localQueue.isEmpty ?? true) {
                    await self?.syncAll()
                }
            }
        }
    }

    // MARK: - Persistence

    private func saveLocalQueue() {
        do {
            let data = try JSONEncoder().encode(localQueue)
            UserDefaults.standard.set(data, forKey: "offline_sync_queue")
            print("💾 Saved \(localQueue.count) items to local queue")
        } catch {
            print("❌ Failed to save local queue: \(error)")
        }
    }

    private func loadLocalQueue() {
        guard let data = UserDefaults.standard.data(forKey: "offline_sync_queue") else {
            print("ℹ️ No local queue found")
            return
        }

        do {
            localQueue = try JSONDecoder().decode([MobileSyncQueue].self, from: data)
            queueCount = localQueue.count
            print("✅ Loaded \(localQueue.count) items from local queue")

            // Try to sync if online
            if isOnline && !localQueue.isEmpty {
                Task {
                    await syncAll()
                }
            }
        } catch {
            print("❌ Failed to load local queue: \(error)")
        }
    }

    // MARK: - Manual Controls

    func retryAll() async {
        print("🔄 Retrying all failed items...")
        await syncAll()
    }

    func clearCompleted() {
        localQueue.removeAll { $0.syncStatus == .completed }
        queueCount = localQueue.count
        saveLocalQueue()
        print("🗑️ Cleared completed items")
    }

    func clearAll() {
        localQueue.removeAll()
        queueCount = 0
        conflicts.removeAll()
        saveLocalQueue()
        print("🗑️ Cleared all queue items")
    }

    // MARK: - Cleanup

    func cleanup() {
        syncTimer?.invalidate()
        syncTimer = nil
        networkMonitor?.cancel()
        networkMonitor = nil
        saveLocalQueue()
    }
}
