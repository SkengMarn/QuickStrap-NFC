import Foundation
import Combine

/// Service for fraud detection and case management (Portal Parity)
@MainActor
class FraudManagementService: ObservableObject {
    static let shared = FraudManagementService()

    @Published var activeCases: [FraudCase] = []
    @Published var watchlist: [WatchlistEntry] = []
    @Published var fraudRules: [FraudRule] = []
    @Published var unassignedCases: [FraudCase] = []
    @Published var myCases: [FraudCase] = []
    @Published var isLoading = false

    private let supabaseService = SupabaseService.shared
    private var cache: [String: WatchlistEntry] = [:]

    private init() {}

    // MARK: - Fraud Cases

    func fetchFraudCases(for eventId: String) async throws -> [FraudCase] {
        isLoading = true
        defer { isLoading = false }

        print("🔍 Fetching fraud cases for event: \(eventId)")

        do {
            let cases: [FraudCase] = try await supabaseService.makeRequest(
                endpoint: "rest/v1/fraud_cases?event_id=eq.\(eventId)&status=in.(open,investigating)&order=created_at.desc&select=*",
                method: "GET",
                responseType: [FraudCase].self
            )

            activeCases = cases

            // Separate into my cases and unassigned
            if let userId = supabaseService.currentUser?.id {
                myCases = cases.filter { $0.assignedTo == userId }
                unassignedCases = cases.filter { $0.assignedTo == nil }
            }

            print("✅ Found \(cases.count) active fraud cases")
            return cases
        } catch {
            print("❌ Failed to fetch fraud cases: \(error)")
            throw error
        }
    }

    func assignCaseToMe(caseId: String) async throws {
        guard let userId = supabaseService.currentUser?.id else {
            throw NSError(domain: "FraudManagementService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }

        print("👤 Assigning case \(caseId) to current user")

        let updateData: [String: Any] = [
            "assigned_to": userId,
            "assigned_at": ISO8601DateFormatter().string(from: Date()),
            "status": FraudCaseStatus.investigating.rawValue
        ]

        do {
            let _: [FraudCase] = try await supabaseService.makeRequest(
                endpoint: "rest/v1/fraud_cases?id=eq.\(caseId)",
                method: "PATCH",
                body: try JSONSerialization.data(withJSONObject: updateData),
                responseType: [FraudCase].self
            )

            print("✅ Case assigned successfully")

            // Refresh cases
            if let eventId = activeCases.first(where: { $0.id == caseId })?.eventId {
                try await fetchFraudCases(for: eventId)
            }
        } catch {
            print("❌ Failed to assign case: \(error)")
            throw error
        }
    }

    func resolveCase(
        caseId: String,
        resolutionNotes: String,
        newStatus: FraudCaseStatus
    ) async throws {
        guard let userId = supabaseService.currentUser?.id else {
            throw NSError(domain: "FraudManagementService", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }

        print("✅ Resolving case \(caseId) as \(newStatus.rawValue)")

        let updateData: [String: Any] = [
            "status": newStatus.rawValue,
            "resolution_notes": resolutionNotes,
            "resolved_by": userId,
            "resolved_at": ISO8601DateFormatter().string(from: Date())
        ]

        do {
            let _: [FraudCase] = try await supabaseService.makeRequest(
                endpoint: "rest/v1/fraud_cases?id=eq.\(caseId)",
                method: "PATCH",
                body: try JSONSerialization.data(withJSONObject: updateData),
                responseType: [FraudCase].self
            )

            print("✅ Case resolved successfully")

            // Refresh cases
            if let eventId = activeCases.first(where: { $0.id == caseId })?.eventId {
                try await fetchFraudCases(for: eventId)
            }
        } catch {
            print("❌ Failed to resolve case: \(error)")
            throw error
        }
    }

    // MARK: - Watchlist Management

    func fetchWatchlist(for organizationId: String) async throws -> [WatchlistEntry] {
        print("📋 Fetching watchlist for organization: \(organizationId)")

        do {
            let entries: [WatchlistEntry] = try await supabaseService.makeRequest(
                endpoint: "rest/v1/watchlist?organization_id=eq.\(organizationId)&is_active=eq.true&order=created_at.desc&select=*",
                method: "GET",
                responseType: [WatchlistEntry].self
            )

            watchlist = entries

            // Build cache for fast lookup
            cache.removeAll()
            for entry in entries {
                cache[entry.entityValue] = entry
            }

            print("✅ Loaded \(entries.count) watchlist entries")
            return entries
        } catch {
            print("❌ Failed to fetch watchlist: \(error)")
            throw error
        }
    }

    /// Check if wristband NFC ID is on watchlist
    func isOnWatchlist(nfcId: String) -> WatchlistEntry? {
        return cache[nfcId]
    }

    /// Check if email is on watchlist
    func isEmailOnWatchlist(email: String) -> WatchlistEntry? {
        return cache[email]
    }

    /// Add wristband to watchlist
    func addToWatchlist(
        organizationId: String,
        entityType: WatchlistEntityType,
        entityValue: String,
        reason: String,
        riskLevel: RiskLevel,
        autoBlock: Bool = true,
        relatedCaseId: String? = nil
    ) async throws -> WatchlistEntry {
        print("➕ Adding to watchlist: \(entityValue) (\(entityType.rawValue))")

        var relatedCases: [String] = []
        if let caseId = relatedCaseId {
            relatedCases.append(caseId)
        }

        let entryData: [String: Any] = [
            "organization_id": organizationId,
            "entity_type": entityType.rawValue,
            "entity_value": entityValue,
            "reason": reason,
            "risk_level": riskLevel.rawValue,
            "auto_block": autoBlock,
            "auto_flag": true,
            "related_case_ids": relatedCases.isEmpty ? NSNull() : relatedCases,
            "is_active": true,
            "added_by": supabaseService.currentUser?.id ?? NSNull()
        ]

        do {
            let entries: [WatchlistEntry] = try await supabaseService.makeRequest(
                endpoint: "rest/v1/watchlist",
                method: "POST",
                body: try JSONSerialization.data(withJSONObject: entryData),
                responseType: [WatchlistEntry].self
            )

            guard let entry = entries.first else {
                throw NSError(domain: "FraudManagementService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to create watchlist entry"])
            }

            print("✅ Added to watchlist: \(entry.id)")

            // Update cache
            cache[entityValue] = entry
            watchlist.append(entry)

            return entry
        } catch {
            print("❌ Failed to add to watchlist: \(error)")
            throw error
        }
    }

    func removeFromWatchlist(entryId: String) async throws {
        print("❌ Removing from watchlist: \(entryId)")

        let updateData: [String: Any] = [
            "is_active": false
        ]

        do {
            let _: [WatchlistEntry] = try await supabaseService.makeRequest(
                endpoint: "rest/v1/watchlist?id=eq.\(entryId)",
                method: "PATCH",
                body: try JSONSerialization.data(withJSONObject: updateData),
                responseType: [WatchlistEntry].self
            )

            print("✅ Removed from watchlist")

            // Update local state
            if let index = watchlist.firstIndex(where: { $0.id == entryId }) {
                let removedEntry = watchlist.remove(at: index)
                cache.removeValue(forKey: removedEntry.entityValue)
            }
        } catch {
            print("❌ Failed to remove from watchlist: \(error)")
            throw error
        }
    }

    // MARK: - Fraud Rules

    func fetchFraudRules(for organizationId: String, eventId: String? = nil) async throws -> [FraudRule] {
        print("📜 Fetching fraud rules")

        var endpoint = "rest/v1/fraud_rules?organization_id=eq.\(organizationId)&is_active=eq.true"
        if let eventId = eventId {
            endpoint += "&event_id=eq.\(eventId)"
        }
        endpoint += "&order=risk_score.desc&select=*"

        do {
            let rules: [FraudRule] = try await supabaseService.makeRequest(
                endpoint: endpoint,
                method: "GET",
                responseType: [FraudRule].self
            )

            fraudRules = rules
            print("✅ Loaded \(rules.count) fraud rules")
            return rules
        } catch {
            print("❌ Failed to fetch fraud rules: \(error)")
            throw error
        }
    }

    // MARK: - Fraud Detection Logic

    /// Check for duplicate check-in violations (within 30 minutes)
    func checkForDuplicateCheckin(
        wristbandId: String,
        eventId: String
    ) async throws -> Bool {
        print("🔍 Checking for duplicate check-in: \(wristbandId)")

        // Get recent check-ins for this wristband (last 30 minutes)
        let thirtyMinutesAgo = Date().addingTimeInterval(-30 * 60)
        let dateString = ISO8601DateFormatter().string(from: thirtyMinutesAgo)

        do {
            let logs: [CheckinLog] = try await supabaseService.makeRequest(
                endpoint: "rest/v1/checkin_logs?wristband_id=eq.\(wristbandId)&event_id=eq.\(eventId)&timestamp=gte.\(dateString)&select=*",
                method: "GET",
                responseType: [CheckinLog].self
            )

            let hasDuplicate = !logs.isEmpty
            if hasDuplicate {
                print("⚠️ Duplicate check-in detected - last scan \(Int(Date().timeIntervalSince(logs[0].timestamp)/60)) minutes ago")
            }
            return hasDuplicate
        } catch {
            print("❌ Failed to check for duplicates: \(error)")
            return false
        }
    }

    /// Validate check-in against all fraud rules
    func validateCheckin(
        wristbandId: String,
        nfcId: String,
        eventId: String,
        gateId: String?
    ) async -> FraudValidationResult {
        var violations: [String] = []
        var riskScore = 0

        // Check watchlist
        if let watchlistEntry = isOnWatchlist(nfcId: nfcId) {
            violations.append("Wristband on watchlist: \(watchlistEntry.reason)")
            riskScore += 50

            if watchlistEntry.autoBlock {
                return FraudValidationResult(
                    isValid: false,
                    violations: violations,
                    riskScore: 100,
                    shouldBlock: true,
                    watchlistEntry: watchlistEntry
                )
            }
        }

        // Check for duplicate check-in
        if let isDuplicate = try? await checkForDuplicateCheckin(wristbandId: wristbandId, eventId: eventId), isDuplicate {
            violations.append("Duplicate check-in detected within 30 minutes")
            riskScore += 30
        }

        // Apply fraud rules
        for rule in fraudRules where rule.isActive {
            // TODO: Implement specific rule logic based on rule.ruleType
            // For now, just log
            print("🔍 Applying fraud rule: \(rule.name)")
        }

        let shouldBlock = riskScore >= 75
        return FraudValidationResult(
            isValid: !shouldBlock,
            violations: violations,
            riskScore: riskScore,
            shouldBlock: shouldBlock,
            watchlistEntry: nil
        )
    }

    // MARK: - Helper Methods

    func clearCache() {
        cache.removeAll()
        activeCases.removeAll()
        watchlist.removeAll()
        fraudRules.removeAll()
    }
}

// MARK: - Fraud Validation Result

struct FraudValidationResult {
    let isValid: Bool
    let violations: [String]
    let riskScore: Int
    let shouldBlock: Bool
    let watchlistEntry: WatchlistEntry?

    var riskLevel: RiskLevel {
        switch riskScore {
        case 0..<25: return .low
        case 25..<50: return .medium
        case 50..<75: return .high
        default: return .critical
        }
    }

    var displayMessage: String {
        if shouldBlock {
            return "❌ CHECK-IN BLOCKED\n\(violations.joined(separator: "\n"))"
        } else if !violations.isEmpty {
            return "⚠️ Warning: \(violations.joined(separator: ", "))"
        } else {
            return "✅ Check-in validated"
        }
    }
}
