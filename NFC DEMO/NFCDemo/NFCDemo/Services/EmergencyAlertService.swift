import Foundation
import Combine

/// Service for emergency alerts and incident management (Portal Parity)
@MainActor
class EmergencyAlertService: ObservableObject {
    static let shared = EmergencyAlertService()

    @Published var activeIncidents: [EmergencyIncident] = []
    @Published var emergencyStatus: EmergencyStatus?
    @Published var recentActions: [EmergencyAction] = []
    @Published var unreadAlerts: Int = 0
    @Published var isLoading = false

    private let supabaseService = SupabaseService.shared
    private var realtimeSubscription: Task<Void, Never>?

    private init() {}

    // MARK: - Fetch Emergency Status

    func fetchEmergencyStatus(for organizationId: String) async throws -> EmergencyStatus? {
        print("🚨 Fetching emergency status for org: \(organizationId)")

        do {
            let statuses: [EmergencyStatus] = try await supabaseService.makeRequest(
                endpoint: "rest/v1/emergency_status?organization_id=eq.\(organizationId)&select=*",
                method: "GET",
                responseType: [EmergencyStatus].self
            )

            emergencyStatus = statuses.first

            if let status = statuses.first {
                print("⚠️ Emergency Status: \(status.alertLevel.rawValue) - Active: \(status.isActive)")
            }

            return statuses.first
        } catch {
            print("❌ Failed to fetch emergency status: \(error)")
            throw error
        }
    }

    // MARK: - Fetch Active Incidents

    func fetchActiveIncidents(for eventId: String) async throws -> [EmergencyIncident] {
        isLoading = true
        defer { isLoading = false }

        print("🚨 Fetching active incidents for event: \(eventId)")

        do {
            let incidents: [EmergencyIncident] = try await supabaseService.makeRequest(
                endpoint: "rest/v1/emergency_incidents?event_id=eq.\(eventId)&status=in.(active,investigating)&order=reported_at.desc&select=*",
                method: "GET",
                responseType: [EmergencyIncident].self
            )

            activeIncidents = incidents
            unreadAlerts = incidents.count

            print("✅ Found \(incidents.count) active incidents")
            return incidents
        } catch {
            print("❌ Failed to fetch incidents: \(error)")
            throw error
        }
    }

    // MARK: - Report Emergency

    func reportEmergency(
        eventId: String,
        incidentType: String,
        severity: EmergencySeverity,
        location: String?,
        description: String,
        estimatedAffected: Int = 0
    ) async throws -> EmergencyIncident {
        print("🚨 Reporting emergency: \(incidentType) - \(severity.rawValue)")

        let incidentData: [String: Any] = [
            "event_id": eventId,
            "incident_type": incidentType,
            "severity": severity.rawValue,
            "location": location ?? NSNull(),
            "description": description,
            "status": IncidentStatus.active.rawValue,
            "reported_by_user_id": supabaseService.currentUser?.id ?? NSNull(),
            "estimated_affected": estimatedAffected,
            "reported_at": ISO8601DateFormatter().string(from: Date())
        ]

        do {
            let incidents: [EmergencyIncident] = try await supabaseService.makeRequest(
                endpoint: "rest/v1/emergency_incidents",
                method: "POST",
                body: try JSONSerialization.data(withJSONObject: incidentData),
                responseType: [EmergencyIncident].self
            )

            guard let incident = incidents.first else {
                throw NSError(domain: "EmergencyAlertService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to create incident"])
            }

            print("✅ Emergency reported successfully: \(incident.id)")

            // Refresh active incidents
            try await fetchActiveIncidents(for: eventId)

            return incident
        } catch {
            print("❌ Failed to report emergency: \(error)")
            throw error
        }
    }

    // MARK: - Update Incident Status

    func updateIncidentStatus(
        incidentId: String,
        newStatus: IncidentStatus,
        resolutionNotes: String? = nil
    ) async throws {
        print("🔄 Updating incident \(incidentId) to status: \(newStatus.rawValue)")

        var updateData: [String: Any] = [
            "status": newStatus.rawValue,
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]

        if newStatus == .resolved || newStatus == .closed {
            updateData["resolved_by"] = supabaseService.currentUser?.id ?? NSNull()
            updateData["resolved_at"] = ISO8601DateFormatter().string(from: Date())
            if let notes = resolutionNotes {
                updateData["resolution_notes"] = notes
            }
        }

        do {
            let _: [EmergencyIncident] = try await supabaseService.makeRequest(
                endpoint: "rest/v1/emergency_incidents?id=eq.\(incidentId)",
                method: "PATCH",
                body: try JSONSerialization.data(withJSONObject: updateData),
                responseType: [EmergencyIncident].self
            )

            print("✅ Incident status updated")

            // Refresh active incidents
            if let eventId = activeIncidents.first(where: { $0.id == incidentId })?.eventId {
                try await fetchActiveIncidents(for: eventId)
            }
        } catch {
            print("❌ Failed to update incident: \(error)")
            throw error
        }
    }

    // MARK: - Emergency Actions

    func executeEmergencyAction(
        eventId: String,
        incidentId: String?,
        actionType: EmergencyActionType,
        title: String,
        description: String?,
        severity: EmergencySeverity,
        affectedGates: [String]? = nil
    ) async throws -> EmergencyAction {
        print("⚡ Executing emergency action: \(actionType.rawValue)")

        let actionData: [String: Any] = [
            "event_id": eventId,
            "incident_id": incidentId ?? NSNull(),
            "action_type": actionType.rawValue,
            "action_title": title,
            "action_description": description ?? NSNull(),
            "severity": severity.rawValue,
            "executed_by": supabaseService.currentUser?.id ?? NSNull(),
            "executed_at": ISO8601DateFormatter().string(from: Date()),
            "status": ActionStatus.executing.rawValue,
            "affected_gates": affectedGates ?? NSNull()
        ]

        do {
            let actions: [EmergencyAction] = try await supabaseService.makeRequest(
                endpoint: "rest/v1/emergency_actions",
                method: "POST",
                body: try JSONSerialization.data(withJSONObject: actionData),
                responseType: [EmergencyAction].self
            )

            guard let action = actions.first else {
                throw NSError(domain: "EmergencyAlertService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to create action"])
            }

            print("✅ Emergency action executed: \(action.id)")
            recentActions.insert(action, at: 0)

            return action
        } catch {
            print("❌ Failed to execute emergency action: \(error)")
            throw error
        }
    }

    // MARK: - Fetch Recent Actions

    func fetchRecentActions(for eventId: String, limit: Int = 10) async throws -> [EmergencyAction] {
        print("📜 Fetching recent emergency actions")

        do {
            let actions: [EmergencyAction] = try await supabaseService.makeRequest(
                endpoint: "rest/v1/emergency_actions?event_id=eq.\(eventId)&order=executed_at.desc&limit=\(limit)&select=*",
                method: "GET",
                responseType: [EmergencyAction].self
            )

            recentActions = actions
            print("✅ Found \(actions.count) recent actions")
            return actions
        } catch {
            print("❌ Failed to fetch recent actions: \(error)")
            throw error
        }
    }

    // MARK: - Real-time Subscriptions

    func subscribeToEmergencyAlerts(eventId: String) {
        print("🔔 Subscribing to emergency alerts for event: \(eventId)")

        // TODO: Implement Supabase Realtime subscription when available
        // For now, poll every 30 seconds
        realtimeSubscription = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                try? await fetchActiveIncidents(for: eventId)
            }
        }
    }

    func unsubscribeFromEmergencyAlerts() {
        print("🔕 Unsubscribing from emergency alerts")
        realtimeSubscription?.cancel()
        realtimeSubscription = nil
    }

    // MARK: - Helper Methods

    func clearAlerts() {
        activeIncidents = []
        recentActions = []
        unreadAlerts = 0
    }

    func markAlertsAsRead() {
        unreadAlerts = 0
    }

    var hasActiveEmergency: Bool {
        emergencyStatus?.isActive == true || !activeIncidents.isEmpty
    }

    var criticalIncidentsCount: Int {
        activeIncidents.filter { $0.severity == .critical }.count
    }

    func cleanup() {
        unsubscribeFromEmergencyAlerts()
        clearAlerts()
    }
}
