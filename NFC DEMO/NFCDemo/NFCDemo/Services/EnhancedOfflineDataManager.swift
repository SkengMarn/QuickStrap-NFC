import Foundation
import Combine

/// Enhanced offline data manager with conflict resolution
class EnhancedOfflineDataManager: ObservableObject {
    static let shared = EnhancedOfflineDataManager()

    private let logger = AppLogger.shared
    private let fileManager = FileManager.default

    @Published var isOnline = true
    @Published var pendingSyncCount = 0
    @Published var lastSyncDate: Date?

    // Conflict resolution strategy
    var conflictResolutionStrategy: ConflictResolutionStrategy = .lastWriteWins

    // Sync queue
    private var syncQueue: [SyncOperation] = []
    private var isSyncing = false

    private init() {
        setupStorageDirectories()
        loadPendingOperations()
        startConnectivityMonitoring()
    }

    // MARK: - Setup

    private func setupStorageDirectories() {
        guard let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }

        let offlineDir = documentsPath.appendingPathComponent("Offline", isDirectory: true)
        try? fileManager.createDirectory(at: offlineDir, withIntermediateDirectories: true)
    }

    // MARK: - Connectivity Monitoring

    private func startConnectivityMonitoring() {
        // Monitor network reachability
        // In production, use Network framework or Reachability library
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.checkConnectivity()
        }
    }

    private func checkConnectivity() {
        // Simple connectivity check
        // In production, use proper reachability check
        let previousState = isOnline

        // Placeholder - replace with actual network check
        isOnline = true  // Assume online for now

        if !previousState && isOnline {
            // Just came back online
            logger.info("Network connectivity restored", category: "Offline")
            Task {
                await syncPendingOperations()
            }
        }
    }

    // MARK: - Offline Operations

    /// Queue an operation for later sync
    func queueOperation(_ operation: SyncOperation) {
        syncQueue.append(operation)
        pendingSyncCount = syncQueue.count
        saveOperationsToStorage()

        logger.info("Queued operation: \(operation.type) for \(operation.entityType)", category: "Offline")

        // Try to sync immediately if online
        if isOnline {
            Task {
                await syncPendingOperations()
            }
        }
    }

    /// Sync all pending operations
    func syncPendingOperations() async {
        guard !isSyncing && !syncQueue.isEmpty else { return }

        isSyncing = true
        logger.info("Starting sync of \(syncQueue.count) operations", category: "Offline")

        var failedOperations: [SyncOperation] = []

        for operation in syncQueue {
            do {
                try await syncOperation(operation)
                logger.info("Synced operation: \(operation.id)", category: "Offline")
            } catch {
                logger.error("Failed to sync operation \(operation.id): \(error)", category: "Offline")
                failedOperations.append(operation)
            }
        }

        // Update queue with failed operations
        syncQueue = failedOperations
        await MainActor.run {
            pendingSyncCount = syncQueue.count
            lastSyncDate = Date()
        }

        saveOperationsToStorage()
        isSyncing = false

        logger.info("Sync complete. \(failedOperations.count) operations failed", category: "Offline")
    }

    // MARK: - Individual Operation Sync

    private func syncOperation(_ operation: SyncOperation) async throws {
        switch operation.type {
        case .create:
            try await syncCreateOperation(operation)
        case .update:
            try await syncUpdateOperation(operation)
        case .delete:
            try await syncDeleteOperation(operation)
        }
    }

    private func syncCreateOperation(_ operation: SyncOperation) async throws {
        // Check if item already exists on server (conflict detection)
        if let conflict = try await detectConflict(operation) {
            try await resolveConflict(conflict)
        } else {
            // No conflict, proceed with creation
            try await performServerOperation(operation)
        }
    }

    private func syncUpdateOperation(_ operation: SyncOperation) async throws {
        // Check for conflicts
        if let conflict = try await detectConflict(operation) {
            try await resolveConflict(conflict)
        } else {
            try await performServerOperation(operation)
        }
    }

    private func syncDeleteOperation(_ operation: SyncOperation) async throws {
        // Deletion conflicts are simpler - just check if item exists
        try await performServerOperation(operation)
    }

    // MARK: - Conflict Detection

    private func detectConflict(_ operation: SyncOperation) async throws -> SyncConflict? {
        // Fetch current server state
        guard let serverData = try await fetchServerData(operation) else {
            return nil  // No conflict if item doesn't exist on server
        }

        // Compare timestamps
        let serverTimestamp = serverData.updatedAt
        let localTimestamp = operation.timestamp

        if serverTimestamp > localTimestamp {
            return SyncConflict(
                operation: operation,
                serverData: serverData,
                type: .serverNewer
            )
        }

        // Check for concurrent modifications
        if let lastSyncTime = lastSyncDate,
           serverTimestamp > lastSyncTime && localTimestamp > lastSyncTime {
            return SyncConflict(
                operation: operation,
                serverData: serverData,
                type: .concurrent
            )
        }

        return nil
    }

    private func fetchServerData(_ operation: SyncOperation) async throws -> ServerDataSnapshot? {
        // Fetch current state from server based on entity type
        // This is a simplified version - in production, use proper repository methods

        switch operation.entityType {
        case "wristband":
            // Fetch wristband from server
            return nil  // Placeholder
        case "checkin":
            // Fetch checkin from server
            return nil  // Placeholder
        default:
            return nil
        }
    }

    // MARK: - Conflict Resolution

    private func resolveConflict(_ conflict: SyncConflict) async throws {
        logger.warning("Resolving conflict for \(conflict.operation.entityType)", category: "Offline")

        let resolution = resolveConflictWithStrategy(conflict)

        switch resolution {
        case .useLocal:
            // Force update with local data
            try await performServerOperation(conflict.operation, force: true)

        case .useServer:
            // Discard local changes, keep server data
            logger.info("Discarding local changes (server wins)", category: "Offline")

        case .merge(let mergedData):
            // Apply merged data
            var mergedOperation = conflict.operation
            mergedOperation.data = mergedData
            try await performServerOperation(mergedOperation)

        case .askUser:
            // In a real app, you'd present a UI to the user
            // For now, fall back to strategy
            try await resolveConflict(conflict)
        }
    }

    private func resolveConflictWithStrategy(_ conflict: SyncConflict) -> ConflictResolution {
        switch conflictResolutionStrategy {
        case .serverWins:
            return .useServer

        case .clientWins:
            return .useLocal

        case .lastWriteWins:
            if conflict.serverData.updatedAt > conflict.operation.timestamp {
                return .useServer
            } else {
                return .useLocal
            }

        case .merge:
            // Simple merge strategy - in production, implement proper merging logic
            let mergedData = mergeData(local: conflict.operation.data, server: conflict.serverData.data)
            return .merge(mergedData)

        case .manual:
            return .askUser
        }
    }

    private func mergeData(local: [String: Any], server: [String: Any]) -> [String: Any] {
        var merged = server  // Start with server data

        // Merge non-conflicting fields from local
        for (key, value) in local {
            if merged[key] == nil {
                merged[key] = value
            }
        }

        return merged
    }

    // MARK: - Server Operations

    private func performServerOperation(_ operation: SyncOperation, force: Bool = false) async throws {
        // Perform the actual server operation using NetworkClient
        // This is a simplified version - in production, use repositories

        let client = NetworkClient.shared
        let endpoint = getEndpoint(for: operation)

        switch operation.type {
        case .create:
            let _: EmptyResponse = try await client.post(
                endpoint: endpoint,
                body: try JSONSerialization.data(withJSONObject: operation.data),
                responseType: EmptyResponse.self
            )

        case .update:
            let _: EmptyResponse = try await client.patch(
                endpoint: "\(endpoint)?id=eq.\(operation.entityId)",
                body: try JSONSerialization.data(withJSONObject: operation.data),
                responseType: EmptyResponse.self
            )

        case .delete:
            try await client.delete(endpoint: "\(endpoint)?id=eq.\(operation.entityId)")
        }
    }

    private func getEndpoint(for operation: SyncOperation) -> String {
        switch operation.entityType {
        case "wristband":
            return "rest/v1/wristbands"
        case "checkin":
            return "rest/v1/checkin_logs"
        case "gate":
            return "rest/v1/gates"
        default:
            return "rest/v1/\(operation.entityType)s"
        }
    }

    // MARK: - Persistence

    private func saveOperationsToStorage() {
        guard let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }

        let filePath = documentsPath.appendingPathComponent("Offline/pending_operations.json")

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(syncQueue)
            try data.write(to: filePath)
        } catch {
            logger.error("Failed to save pending operations: \(error)", category: "Offline")
        }
    }

    private func loadPendingOperations() {
        guard let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }

        let filePath = documentsPath.appendingPathComponent("Offline/pending_operations.json")

        do {
            let data = try Data(contentsOf: filePath)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            syncQueue = try decoder.decode([SyncOperation].self, from: data)
            pendingSyncCount = syncQueue.count

            logger.info("Loaded \(syncQueue.count) pending operations", category: "Offline")
        } catch {
            logger.debug("No pending operations to load", category: "Offline")
        }
    }

    // MARK: - Public API

    /// Manually trigger sync
    func forceSyncNow() async {
        await syncPendingOperations()
    }

    /// Clear all pending operations (use with caution!)
    func clearPendingOperations() {
        syncQueue.removeAll()
        pendingSyncCount = 0
        saveOperationsToStorage()
        logger.warning("Cleared all pending operations", category: "Offline")
    }

    /// Get pending operations count
    func getPendingCount() -> Int {
        return syncQueue.count
    }
}

// MARK: - Models

struct SyncOperation: Codable, Identifiable {
    let id: String
    let type: OperationType
    let entityType: String
    let entityId: String
    var data: [String: Any]
    let timestamp: Date

    enum OperationType: String, Codable {
        case create, update, delete
    }

    enum CodingKeys: String, CodingKey {
        case id, type, entityType, entityId, timestamp
    }

    // Custom encoding/decoding for [String: Any]
    init(id: String = UUID().uuidString, type: OperationType, entityType: String, entityId: String, data: [String: Any], timestamp: Date = Date()) {
        self.id = id
        self.type = type
        self.entityType = entityType
        self.entityId = entityId
        self.data = data
        self.timestamp = timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(OperationType.self, forKey: .type)
        entityType = try container.decode(String.self, forKey: .entityType)
        entityId = try container.decode(String.self, forKey: .entityId)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        data = [:]  // Simplified - in production, properly decode this
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(entityType, forKey: .entityType)
        try container.encode(entityId, forKey: .entityId)
        try container.encode(timestamp, forKey: .timestamp)
    }
}

struct SyncConflict {
    let operation: SyncOperation
    let serverData: ServerDataSnapshot
    let type: ConflictType

    enum ConflictType {
        case serverNewer
        case concurrent
        case deleted
    }
}

struct ServerDataSnapshot {
    let data: [String: Any]
    let updatedAt: Date
}

enum ConflictResolutionStrategy {
    case serverWins
    case clientWins
    case lastWriteWins
    case merge
    case manual
}

enum ConflictResolution {
    case useLocal
    case useServer
    case merge([String: Any])
    case askUser
}
