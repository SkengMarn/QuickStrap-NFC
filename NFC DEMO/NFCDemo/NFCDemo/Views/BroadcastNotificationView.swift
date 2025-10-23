import SwiftUI

// MARK: - Broadcast Notification Banner

/// A banner that displays broadcast messages at the top of the screen
struct BroadcastNotificationBanner: View {
    let message: BroadcastMessage
    let onDismiss: () -> Void
    let onTap: () -> Void

    @State private var offset: CGFloat = -200

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Icon
                Image(systemName: message.messageType.icon)
                    .font(.title3)
                    .foregroundColor(iconColor)

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.messageType.displayTitle)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.9))

                    Text(message.message)
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .lineLimit(2)
                }

                Spacer()

                // Dismiss button
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .padding()
            .background(backgroundColor)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
            .padding(.horizontal)
            .padding(.top, 8)
            .offset(y: offset)
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                    offset = 0
                }

                // Auto-dismiss for non-urgent messages
                if message.priority != .urgent {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        dismissWithAnimation()
                    }
                }
            }
            .onTapGesture {
                onTap()
            }

            Spacer()
        }
    }

    private var backgroundColor: Color {
        switch message.priority {
        case .urgent:
            return Color.red
        case .high:
            return Color.orange
        case .normal:
            return Color.blue
        case .low:
            return Color.gray
        }
    }

    private var iconColor: Color {
        return .white
    }

    private func dismissWithAnimation() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            offset = -200
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onDismiss()
        }
    }
}

// MARK: - Broadcast Messages List View

/// View to display all broadcast messages
struct BroadcastMessagesView: View {
    @EnvironmentObject var broadcastService: BroadcastService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                if broadcastService.messages.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "tray")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)

                        Text("No messages yet")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Text("You'll see broadcast messages here when they're sent")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(broadcastService.messages) { message in
                        BroadcastMessageRow(message: message)
                            .onTapGesture {
                                Task {
                                    await broadcastService.markAsRead(messageId: message.id)
                                }
                            }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Broadcasts")
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

// MARK: - Message Row

/// A row displaying a single broadcast message
struct BroadcastMessageRow: View {
    let message: BroadcastMessage
    @EnvironmentObject var broadcastService: BroadcastService

    private var isRead: Bool {
        if let userId = broadcastService.currentUserId {
            return message.isReadBy(userId: userId)
        }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: message.messageType.icon)
                    .foregroundColor(priorityColor)

                Text(message.messageType.displayTitle)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(priorityColor)

                Spacer()

                if !isRead {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                }

                Text(timeAgo(from: message.sentAt))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Message
            Text(message.message)
                .font(.subheadline)
                .foregroundColor(.primary)
                .lineLimit(3)

            // Priority badge
            if message.priority != .normal {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption2)

                    Text(message.priority.displayName)
                        .font(.caption2)
                }
                .foregroundColor(priorityColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(priorityColor.opacity(0.1))
                .cornerRadius(8)
            }

            // Expiration warning
            if let expiresAt = message.expiresAt {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)

                    Text("Expires \(timeAgo(from: expiresAt))")
                        .font(.caption2)
                }
                .foregroundColor(.orange)
            }
        }
        .padding(.vertical, 8)
        .opacity(isRead ? 0.6 : 1.0)
    }

    private var priorityColor: Color {
        switch message.priority {
        case .urgent:
            return .red
        case .high:
            return .orange
        case .normal:
            return .blue
        case .low:
            return .gray
        }
    }

    private func timeAgo(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let minutes = Int(interval / 60)
        let hours = minutes / 60
        let days = hours / 24

        if days > 0 {
            return "\(days)d ago"
        } else if hours > 0 {
            return "\(hours)h ago"
        } else if minutes > 0 {
            return "\(minutes)m ago"
        } else {
            return "Just now"
        }
    }
}

// MARK: - Notification Bell Icon

/// A bell icon with badge showing unread count
struct NotificationBellIcon: View {
    let unreadCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: unreadCount > 0 ? "bell.fill" : "bell")
                    .font(.title3)
                    .foregroundColor(unreadCount > 0 ? .blue : .primary)

                if unreadCount > 0 {
                    Text("\(min(unreadCount, 99))")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(Color.red)
                        .clipShape(Circle())
                        .offset(x: 8, y: -8)
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Message Banner") {
    BroadcastNotificationBanner(
        message: BroadcastMessage(
            id: "1",
            eventId: "event1",
            senderId: "user1",
            message: "Emergency: Please evacuate the venue immediately through the nearest exit.",
            messageType: .emergency,
            priority: .urgent,
            sentAt: Date(),
            expiresAt: nil,
            readBy: nil
        ),
        onDismiss: {},
        onTap: {}
    )
}

#Preview("Messages List") {
    BroadcastMessagesView()
        .environmentObject(BroadcastService.shared)
}
