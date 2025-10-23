import Foundation
import Combine
import SwiftUI
import UserNotifications

/// Service for monitoring event capacity and triggering threshold alerts
@MainActor
class CapacityMonitoringService: ObservableObject {
    static let shared = CapacityMonitoringService()

    // MARK: - Published Properties

    @Published var currentCapacity: Int = 0
    @Published var capacityPercentage: Double = 0
    @Published var lastAlertTime: Date?
    @Published var hasReachedThreshold: Bool = false

    // MARK: - Private Properties

    private var currentEvent: Event?
    private var supabaseService: SupabaseService?
    private var alertThresholdCrossed: Bool = false  // Track if we've already alerted for current threshold
    private let logger = AppLogger.shared

    private init() {
        logger.info("CapacityMonitoringService initialized", category: "Capacity")
        requestNotificationPermissions()
    }

    // MARK: - Setup

    /// Configure the service for a specific event
    func configure(for event: Event, supabaseService: SupabaseService) {
        self.currentEvent = event
        self.supabaseService = supabaseService
        self.alertThresholdCrossed = false  // Reset when switching events

        logger.info("CapacityMonitoringService configured for event: \(event.name)", category: "Capacity")

        // Load initial capacity
        Task {
            await refreshCapacity()
        }
    }

    /// Reset monitoring state
    func reset() {
        currentCapacity = 0
        capacityPercentage = 0
        lastAlertTime = nil
        hasReachedThreshold = false
        alertThresholdCrossed = false
        currentEvent = nil
        supabaseService = nil

        logger.info("CapacityMonitoringService reset", category: "Capacity")
    }

    // MARK: - Capacity Tracking

    /// Refresh current capacity from database
    func refreshCapacity() async {
        guard let event = currentEvent,
              let supabaseService = supabaseService else {
            logger.warning("Cannot refresh capacity: missing event or service", category: "Capacity")
            return
        }

        do {
            // Query checkin_logs for unique wristband check-ins for this event
            struct CheckinCount: Codable {
                let count: Int
            }

            let result: [CheckinCount] = try await supabaseService.makeRequest(
                endpoint: "rest/v1/checkin_logs?event_id=eq.\(event.id)&status=eq.success&select=wristband_id",
                method: "GET",
                body: nil,
                responseType: [CheckinCount].self
            )

            // Count unique wristbands
            let capacity = result.first?.count ?? 0

            await updateCapacity(capacity)

        } catch {
            logger.error("Failed to refresh capacity: \(error.localizedDescription)", category: "Capacity")
        }
    }

    /// Update capacity and check threshold
    private func updateCapacity(_ newCapacity: Int) async {
        currentCapacity = newCapacity

        guard let event = currentEvent,
              let capacitySettings = event.capacitySettings else {
            return
        }

        // Calculate percentage
        capacityPercentage = capacitySettings.capacityPercentage(currentCount: newCapacity)

        // Check if threshold is reached
        let thresholdReached = capacitySettings.hasReachedThreshold(currentCount: newCapacity)
        hasReachedThreshold = thresholdReached

        logger.info("Capacity updated: \(newCapacity) (\(String(format: "%.1f", capacityPercentage))%)", category: "Capacity")

        // Trigger alert if threshold just crossed and we haven't alerted yet
        if thresholdReached && !alertThresholdCrossed {
            await triggerCapacityAlert(
                currentCount: newCapacity,
                percentage: capacityPercentage,
                threshold: capacitySettings.alertThreshold,
                maxCapacity: capacitySettings.maxCapacity ?? 0
            )
            alertThresholdCrossed = true
        } else if !thresholdReached && alertThresholdCrossed {
            // Reset if capacity drops back below threshold
            alertThresholdCrossed = false
        }
    }

    /// Increment capacity after a successful check-in
    func incrementCapacity() async {
        await updateCapacity(currentCapacity + 1)
    }

    // MARK: - Alert System

    /// Request notification permissions
    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("✅ Notification permissions granted for capacity alerts")
            } else if let error = error {
                print("❌ Notification permission error: \(error.localizedDescription)")
            }
        }
    }

    /// Trigger capacity threshold alert
    private func triggerCapacityAlert(currentCount: Int, percentage: Double, threshold: Int, maxCapacity: Int) async {
        guard let event = currentEvent else { return }

        logger.warning("⚠️ CAPACITY ALERT: Event '\(event.name)' has reached \(threshold)% capacity (\(currentCount)/\(maxCapacity))", category: "Capacity")

        lastAlertTime = Date()

        // Trigger haptic feedback (heavy impact for urgent alert)
        await triggerHapticAlert()

        // Show local notification
        await showCapacityNotification(
            eventName: event.name,
            currentCount: currentCount,
            percentage: percentage,
            threshold: threshold,
            maxCapacity: maxCapacity
        )

        // Log alert to database (for audit trail)
        await logCapacityAlert(
            eventId: event.id,
            currentCount: currentCount,
            percentage: percentage,
            threshold: threshold
        )
    }

    /// Trigger haptic feedback
    private func triggerHapticAlert() async {
        await MainActor.run {
            // Use notification feedback for important alerts
            let notification = UINotificationFeedbackGenerator()
            notification.notificationOccurred(.warning)

            // Follow with heavy impact for emphasis
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                let impact = UIImpactFeedbackGenerator(style: .heavy)
                impact.impactOccurred()
            }
        }
    }

    /// Show local push notification
    private func showCapacityNotification(
        eventName: String,
        currentCount: Int,
        percentage: Double,
        threshold: Int,
        maxCapacity: Int
    ) async {
        let content = UNMutableNotificationContent()
        content.title = "⚠️ Capacity Alert: \(eventName)"
        content.body = String(format: "Event capacity at %.1f%% (%d/%d). Threshold: %d%%",
                              percentage, currentCount, maxCapacity, threshold)
        content.sound = .defaultCritical
        content.interruptionLevel = .timeSensitive
        content.badge = 1

        // Create trigger (immediately)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)

        // Create request
        let request = UNNotificationRequest(
            identifier: "capacity-alert-\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        // Schedule notification
        do {
            try await UNUserNotificationCenter.current().add(request)
            logger.info("Capacity notification scheduled", category: "Capacity")
        } catch {
            logger.error("Failed to schedule capacity notification: \(error.localizedDescription)", category: "Capacity")
        }
    }

    /// Log capacity alert to database
    private func logCapacityAlert(
        eventId: String,
        currentCount: Int,
        percentage: Double,
        threshold: Int
    ) async {
        guard let supabaseService = supabaseService,
              let staffId = supabaseService.currentUser?.id else {
            return
        }

        do {
            let alertData: [String: Any] = [
                "event_id": eventId,
                "alert_type": "capacity_threshold",
                "current_count": currentCount,
                "capacity_percentage": percentage,
                "threshold": threshold,
                "triggered_by": staffId,
                "triggered_at": ISO8601DateFormatter().string(from: Date())
            ]

            let jsonData = try JSONSerialization.data(withJSONObject: alertData)

            // Note: You may need to create a capacity_alerts table in your database
            // For now, we'll log it to staff_messages as a system broadcast
            let broadcastData: [String: Any] = [
                "event_id": eventId,
                "sender_id": staffId,
                "message": String(format: "⚠️ Capacity Alert: %.1f%% full (%d attendees)", percentage, currentCount),
                "message_type": "alert",
                "priority": "high",
                "sent_at": ISO8601DateFormatter().string(from: Date())
            ]

            let broadcastJson = try JSONSerialization.data(withJSONObject: broadcastData)

            let _: EmptyResponse = try await supabaseService.makeRequest(
                endpoint: "rest/v1/staff_messages",
                method: "POST",
                body: broadcastJson,
                responseType: EmptyResponse.self
            )

            logger.info("Capacity alert logged to database", category: "Capacity")

        } catch {
            logger.error("Failed to log capacity alert: \(error.localizedDescription)", category: "Capacity")
        }
    }

    // MARK: - Status Information

    /// Get human-readable capacity status
    func getCapacityStatus() -> String {
        guard let event = currentEvent,
              let capacitySettings = event.capacitySettings,
              let maxCapacity = capacitySettings.maxCapacity else {
            return "Capacity tracking unavailable"
        }

        let percentage = String(format: "%.1f", capacityPercentage)
        return "\(currentCapacity)/\(maxCapacity) (\(percentage)%)"
    }

    /// Check if close to capacity (within 10% of threshold)
    func isNearThreshold() -> Bool {
        guard let event = currentEvent,
              let capacitySettings = event.capacitySettings else {
            return false
        }

        let warningThreshold = Double(capacitySettings.alertThreshold) - 10
        return capacityPercentage >= warningThreshold && capacityPercentage < Double(capacitySettings.alertThreshold)
    }
}
