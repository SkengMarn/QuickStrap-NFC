# Event Broadcast System - iOS Implementation

## Overview

The iOS app now supports real-time event-specific broadcast messages, mirroring the functionality in the web portal. This allows event organizers to send instant notifications to all staff members using the iOS scanner app.

## Features

### 1. Event-Specific Broadcasts
- Automatically subscribes to broadcasts when selecting an event
- Only receives messages relevant to the current event
- Real-time delivery using Supabase Realtime channels

### 2. Message Types
- **Broadcast**: General announcements (blue)
- **Alert**: Important notices (orange)
- **Emergency**: Critical alerts (red)

### 3. Priority Levels
- **Low**: Informational messages
- **Normal**: Standard notifications
- **High**: Important updates
- **Urgent**: Critical alerts that require immediate attention

### 4. User Interface Components

#### Notification Bell Icon
- Located in the top-right toolbar
- Shows badge with unread message count
- Tap to view all messages

#### Broadcast Banners
- Auto-displays at the top of the screen for new messages
- Color-coded by priority (red, orange, blue, gray)
- Auto-dismisses after 5 seconds (except urgent messages)
- Tap to view full message list
- Swipe or tap X to dismiss

#### Message List
- View all broadcast history for the current event
- Messages marked as read automatically
- Shows time ago, priority badges, and expiration warnings
- Unread messages highlighted with blue dot

## App Lifecycle Handling

### Scene Phase Management
The app monitors lifecycle states:
- **Active**: App in foreground and active
- **Inactive**: App in foreground but not active (e.g., during phone call)
- **Background**: App moved to background (broadcasts continue briefly)

### Termination Handling
When the app terminates:
1. `AppDelegate.applicationWillTerminate` is called
2. `BroadcastService.cleanup()` unsubscribes from all channels
3. Releases resources properly

### Auto-Subscribe/Unsubscribe
- **Subscribe**: Automatically when entering event view
- **Unsubscribe**: Automatically when leaving event view or app terminates

## Architecture

### Components Created

1. **BroadcastModels.swift**
   - `BroadcastMessage`: Main message model
   - `BroadcastMessageType`: Type enum (broadcast, alert, emergency)
   - `BroadcastPriority`: Priority enum (low, normal, high, urgent)
   - `AppNotification`: User-specific notification model
   - `NotificationData`: Additional notification metadata

2. **BroadcastService.swift**
   - Singleton service managing all broadcast operations
   - Supabase Realtime integration
   - Local notification support
   - Message history management
   - Read/unread tracking

3. **BroadcastNotificationView.swift**
   - `BroadcastNotificationBanner`: Toast-style banner
   - `BroadcastMessagesView`: Full message list view
   - `BroadcastMessageRow`: Individual message row
   - `NotificationBellIcon`: Toolbar bell with badge

4. **NFCDemoApp.swift** (Updated)
   - App lifecycle monitoring
   - AppDelegate integration for termination handling
   - Scene phase change tracking

5. **ThreeTabView.swift** (Updated)
   - Integrated notification bell in toolbar
   - Banner overlay system
   - Auto-subscribe/unsubscribe on appear/disappear
   - Message list sheet presentation

## Database Schema

The broadcast system uses the following Supabase tables:

### staff_messages
```sql
CREATE TABLE staff_messages (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  event_id UUID NOT NULL REFERENCES events(id),
  sender_id UUID NOT NULL REFERENCES profiles(id),
  message TEXT NOT NULL,
  message_type TEXT NOT NULL CHECK (message_type IN ('broadcast', 'alert', 'emergency')),
  priority TEXT NOT NULL CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
  sent_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ,
  read_by UUID[]
);
```

### notifications
```sql
CREATE TABLE notifications (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES profiles(id),
  type TEXT NOT NULL,
  title TEXT NOT NULL,
  message TEXT NOT NULL,
  data JSONB,
  read BOOLEAN DEFAULT FALSE,
  read_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

## Usage

### For End Users (Scanner App)

1. **Viewing Broadcasts**
   - Look for the bell icon in the top-right corner
   - Blue badge shows unread count
   - Tap bell to view all messages

2. **Responding to Broadcasts**
   - Banners appear automatically for new messages
   - Urgent messages stay on screen until dismissed
   - Normal/High priority messages auto-dismiss after 5 seconds

3. **Marking as Read**
   - Tap any message to mark as read
   - Banner dismissal doesn't mark as read (only tapping in list)

### For Administrators (Web Portal)

Administrators can send broadcasts from the web portal:

```typescript
// From the web app
await broadcastService.sendBroadcast(
  eventId,
  "Important announcement: Gates opening in 15 minutes",
  {
    type: 'alert',
    priority: 'high',
    expiresInMinutes: 60
  }
);
```

### For Developers

#### Sending Broadcasts Programmatically

```swift
// Send a broadcast message
try await BroadcastService.shared.sendBroadcast(
    eventId: "event-uuid",
    message: "Emergency: Please evacuate immediately",
    type: .emergency,
    priority: .urgent,
    expiresInMinutes: nil
)
```

#### Subscribe to Broadcasts

```swift
// Automatically handled by ThreeTabView
// Manual subscription:
await broadcastService.subscribeToBroadcasts(
    eventId: eventId,
    userId: userId
)
```

#### Check Connection Status

```swift
if broadcastService.isConnected {
    print("Connected to broadcast service")
}
```

## Permissions

### iOS Permissions Required

1. **Notification Permissions**
   - Requested automatically on first launch
   - Used for local notifications when app is in background
   - Users can manage in iOS Settings

### Supabase RLS Policies

Ensure proper Row Level Security policies:

```sql
-- Allow users to read messages for their events
CREATE POLICY "Users can read event messages"
ON staff_messages FOR SELECT
USING (
  event_id IN (
    SELECT event_id FROM event_access WHERE user_id = auth.uid()
  )
);

-- Allow admins to send messages
CREATE POLICY "Admins can send messages"
ON staff_messages FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1 FROM event_access
    WHERE user_id = auth.uid()
    AND event_id = staff_messages.event_id
    AND access_level IN ('admin', 'owner')
  )
);
```

## Testing

### Test Broadcast Delivery

1. Open the iOS app and select an event
2. From the web portal, send a test broadcast
3. Verify banner appears in iOS app
4. Check notification list for message history
5. Verify unread count updates correctly

### Test App Lifecycle

1. Send a broadcast while app is active → Should show banner
2. Move app to background, send broadcast → Should receive push notification
3. Kill app, send broadcast → Should see on next launch
4. Verify cleanup on termination (check logs)

## Troubleshooting

### Messages Not Appearing

1. **Check Event Selection**: Ensure event is selected in iOS app
2. **Verify Supabase Connection**: Check console logs for connection errors
3. **Check User Permissions**: Verify user has access to the event
4. **Database Table**: Ensure `staff_messages` table exists

### Connection Issues

```swift
// Check connection status
print("Connected: \(BroadcastService.shared.isConnected)")
print("Event ID: \(BroadcastService.shared.currentEventId ?? "None")")
print("Message Count: \(BroadcastService.shared.messages.count)")
```

### RLS Policy Issues

If broadcasts aren't visible, check RLS policies:
```sql
-- Temporarily disable RLS for testing
ALTER TABLE staff_messages DISABLE ROW LEVEL SECURITY;
```

## Performance Considerations

1. **Message History Limit**: Default 50 messages per event
2. **Auto-dismiss Timers**: Non-urgent messages auto-dismiss after 5 seconds
3. **Background Subscriptions**: Realtime channels pause when app backgrounds
4. **Memory Management**: Service cleans up on termination

## Future Enhancements

Potential improvements:
- [ ] Rich media attachments (images, audio)
- [ ] Message reactions and replies
- [ ] Delivery receipts and read confirmations
- [ ] Broadcast templates
- [ ] Scheduled broadcasts
- [ ] Push notification support (APNs)
- [ ] Message search and filtering
- [ ] Archive older messages
- [ ] Priority inbox/grouping

## Security Notes

1. **API Keys**: Hardcoded for demo - should be moved to secure config
2. **Token Storage**: Uses Keychain for authentication tokens
3. **RLS Enforcement**: All queries respect Row Level Security
4. **Message Encryption**: Consider encrypting sensitive broadcasts
5. **Audit Logging**: Track who sends/reads critical messages

## Related Files

- `/Models/BroadcastModels.swift` - Data models
- `/Services/BroadcastService.swift` - Core service logic
- `/Views/BroadcastNotificationView.swift` - UI components
- `/NFCDemoApp.swift` - App lifecycle handling
- `/Views/ThreeTabView.swift` - Integration point

## Reference

Based on the web implementation:
- `/Users/jew/Desktop/quickstrap_nfc_web/src/services/broadcastService.ts`
- `/Users/jew/Desktop/quickstrap_nfc_web/src/hooks/useBroadcastNotifications.ts`
