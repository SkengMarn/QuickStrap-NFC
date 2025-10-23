import Foundation
import Combine
import Supabase
import UserNotifications

/// Service for handling real-time broadcast messages and notifications
class BroadcastService: ObservableObject {
    static let shared = BroadcastService()

    // MARK: - Published Properties

    @Published var messages: [BroadcastMessage] = []
    @Published var unreadCount: Int = 0
    @Published var isConnected: Bool = false
    @Published var notifications: [AppNotification] = []

    // MARK: - Private Properties

    private var supabaseClient: SupabaseClient?
    private var broadcastChannel: RealtimeChannel?
    private var notificationChannel: RealtimeChannel?
    private var cancellables = Set<AnyCancellable>()

    private(set) var currentEventId: String?
    var currentUserId: String?

    // MARK: - Initialization

    private init() {
        print("🔔 BroadcastService initializing...")
        setupSupabaseClient()
        requestNotificationPermissions()
    }

    /// Setup Supabase client for Realtime
    private func setupSupabaseClient() {
        // Initialize Supabase client
        let supabaseURL = URL(string: "https://pmrxyisasfaimumuobvu.supabase.co")!
        let supabaseKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBtcnh5aXNhc2ZhaW11bXVvYnZ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTMyODQ2ODMsImV4cCI6MjA2ODg2MDY4M30.rVsKq08Ynw82RkCntxWFXOTgP8T0cGyhJvqfrnOH4YQ"

        supabaseClient = SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: supabaseKey
        )

        print("✅ Supabase client initialized for broadcast service")
    }

    // MARK: - Notification Permissions

    /// Request notification permissions from user
    func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("✅ Notification permissions granted")
            } else if let error = error {
                print("❌ Notification permission error: \(error.localizedDescription)")
            } else {
                print("⚠️ Notification permissions denied")
            }
        }
    }

    // MARK: - Subscribe to Broadcasts

    /// Subscribe to event-specific broadcasts
    /// - Parameters:
    ///   - eventId: The event ID to subscribe to
    ///   - userId: The current user ID
    func subscribeToBroadcasts(eventId: String, userId: String) async {
        guard let supabaseClient = supabaseClient else {
            print("❌ Supabase client not initialized")
            return
        }

        // Unsubscribe from previous subscriptions
        await unsubscribeAll()

        currentEventId = eventId
        currentUserId = userId

        print("📡 Subscribing to broadcasts for event: \(eventId)")

        // Note: Realtime subscriptions temporarily disabled due to API compatibility issues
        // TODO: Update to match Supabase Swift SDK 2.34.0 Realtime API
        
        await MainActor.run {
            isConnected = true
        }

        // Load message history
        await loadBroadcastHistory(eventId: eventId)

        print("✅ Broadcast service initialized (realtime disabled)")
    }

    /// Subscribe to user-specific notifications
    private func subscribeToNotifications(userId: String) async {
        // Note: Realtime subscriptions temporarily disabled due to API compatibility issues
        // TODO: Update to match Supabase Swift SDK 2.34.0 Realtime API
        print("📡 Notification subscription disabled (realtime API update needed)")
    }

    // MARK: - Message Handling

    /// Handle incoming broadcast message
    private func handleBroadcastMessage(_ record: AnyJSON) async {
        print("📨 Received broadcast message")

        do {
            let data = try JSONEncoder().encode(record)
            let message = try JSONDecoder().decode(BroadcastMessage.self, from: data)

            // Check if message is expired
            if message.isExpired {
                print("⏰ Message expired, ignoring")
                return
            }

            await MainActor.run {
                // Add to messages list
                messages.insert(message, at: 0)

                // Check if already read
                if let userId = currentUserId, !message.isReadBy(userId: userId) {
                    unreadCount += 1
                }
            }

            // Show local notification
            await showLocalNotification(for: message)

            print("✅ Broadcast message processed: \(message.messageType.displayTitle)")

        } catch {
            print("❌ Failed to decode broadcast message: \(error.localizedDescription)")
        }
    }

    /// Handle incoming notification
    private func handleNotification(_ record: AnyJSON) async {
        print("📨 Received notification")

        do {
            let data = try JSONEncoder().encode(record)
            let notification = try JSONDecoder().decode(AppNotification.self, from: data)

            await MainActor.run {
                notifications.insert(notification, at: 0)

                if !notification.read {
                    unreadCount += 1
                }
            }

            // Show local notification for high priority
            if let priority = notification.data?.priority,
               (priority == "high" || priority == "urgent") {
                await showLocalNotification(
                    title: notification.title,
                    body: notification.message,
                    priority: priority
                )
            }

            print("✅ Notification processed")

        } catch {
            print("❌ Failed to decode notification: \(error.localizedDescription)")
        }
    }

    // MARK: - Local Notifications

    /// Show local notification
    private func showLocalNotification(for message: BroadcastMessage) async {
        await showLocalNotification(
            title: message.messageType.displayTitle,
            body: message.message,
            priority: message.priority.rawValue
        )
    }

    /// Show local notification with custom content
    private func showLocalNotification(title: String, body: String, priority: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        // Set badge and interruption level based on priority
        if priority == "urgent" {
            content.interruptionLevel = .critical
            content.badge = NSNumber(value: unreadCount)
        } else if priority == "high" {
            content.interruptionLevel = .timeSensitive
        }

        // Create trigger (immediately)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)

        // Create request
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )

        // Schedule notification
        do {
            try await UNUserNotificationCenter.current().add(request)
            print("✅ Local notification scheduled")
        } catch {
            print("❌ Failed to schedule notification: \(error.localizedDescription)")
        }
    }

    // MARK: - Message History

    /// Load broadcast message history for an event
    func loadBroadcastHistory(eventId: String, limit: Int = 50) async {
        print("📚 Loading broadcast history for event: \(eventId)")

        guard let supabaseClient = supabaseClient else { return }

        do {
            let response: [BroadcastMessage] = try await supabaseClient.database
                .from("staff_messages")
                .select()
                .eq("event_id", value: eventId)
                .order("sent_at", ascending: false)
                .limit(limit)
                .execute()
                .value

            await MainActor.run {
                messages = response

                // Count unread messages
                if let userId = currentUserId {
                    unreadCount = response.filter { !$0.isReadBy(userId: userId) }.count
                }
            }

            print("✅ Loaded \(response.count) broadcast messages")

        } catch {
            print("❌ Failed to load broadcast history: \(error.localizedDescription)")
        }
    }

    // MARK: - Mark as Read

    /// Mark a broadcast message as read
    func markAsRead(messageId: String) async {
        guard let userId = currentUserId else {
            print("❌ No user ID available")
            return
        }

        print("✅ Marking message as read: \(messageId)")

        do {
            // Update notification as read
            struct NotificationUpdate: Encodable {
                let read: Bool
                let read_at: String
            }
            
            let update = NotificationUpdate(
                read: true,
                read_at: ISO8601DateFormatter().string(from: Date())
            )
            
            try await supabaseClient?.database
                .from("notifications")
                .update(update)
                .contains("data->broadcast_id", value: messageId)
                .eq("user_id", value: userId)
                .execute()

            await MainActor.run {
                unreadCount = max(0, unreadCount - 1)
            }

            print("✅ Message marked as read")

        } catch {
            print("❌ Failed to mark message as read: \(error.localizedDescription)")
        }
    }

    // MARK: - Unsubscribe

    /// Unsubscribe from all channels
    func unsubscribeAll() async {
        print("🔌 Unsubscribing from all broadcast channels")

        if let channel = broadcastChannel {
            await channel.unsubscribe()
            broadcastChannel = nil
        }

        if let channel = notificationChannel {
            await channel.unsubscribe()
            notificationChannel = nil
        }

        await MainActor.run {
            isConnected = false
            currentEventId = nil
            currentUserId = nil
        }

        print("✅ Unsubscribed from all channels")
    }

    // MARK: - Send Broadcast (Admin functionality)

    /// Send a broadcast message to all users in an event
    func sendBroadcast(
        eventId: String,
        message: String,
        type: BroadcastMessageType = .broadcast,
        priority: BroadcastPriority = .normal,
        expiresInMinutes: Int? = nil
    ) async throws {
        guard let userId = currentUserId else {
            throw NSError(domain: "BroadcastService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Not authenticated"
            ])
        }

        guard let supabaseClient = supabaseClient else {
            throw NSError(domain: "BroadcastService", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Supabase client not initialized"
            ])
        }

        let sentAt = Date()
        var expiresAt: Date? = nil
        if let minutes = expiresInMinutes {
            expiresAt = sentAt.addingTimeInterval(TimeInterval(minutes * 60))
        }

        struct BroadcastInsert: Encodable {
            let event_id: String
            let message: String
            let message_type: String
            let priority: String
            let sent_at: String
            let expires_at: String?
        }
        
        let broadcastData = BroadcastInsert(
            event_id: eventId,
            message: message,
            message_type: type.rawValue,
            priority: priority.rawValue,
            sent_at: ISO8601DateFormatter().string(from: sentAt),
            expires_at: expiresAt.map { ISO8601DateFormatter().string(from: $0) }
        )

        print("📤 Sending broadcast message...")

        do {
            let _: [BroadcastMessage] = try await supabaseClient.database
                .from("staff_messages")
                .insert(broadcastData)
                .execute()
                .value

            print("✅ Broadcast message sent successfully")

        } catch {
            print("❌ Failed to send broadcast: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Cleanup

    /// Cleanup resources when app terminates
    func cleanup() {
        Task {
            await unsubscribeAll()
        }
        print("🧹 BroadcastService cleaned up")
    }
}
