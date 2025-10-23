# Quick Start Guide - Enhanced iOS App

## 🚀 What's New?

Your iOS app now has **MASSIVE** improvements with full portal parity! Here's what's been added:

### 1. Event Series Support 📊
- Manage multi-day events and sessions
- Auto-select active series
- Series-specific metrics
- Tournament/knockout support

### 2. Emergency System 🚨
- Real-time emergency alerts
- Report incidents from field
- Execute emergency actions
- Incident management

### 3. Advanced Fraud Detection 🔍
- Fraud case management
- Watchlist checking
- Risk scoring
- Auto-blocking

### 4. Offline-First Mode 📱
- Work without internet
- Auto-sync when online
- Conflict resolution
- Queue management

### 5. Multi-Organization 🏢
- Switch between orgs
- Role-based access
- Subscription tiers
- Isolated data

### 6. Staff Performance 📈
- Track scan metrics
- Efficiency scores
- Performance analytics
- Leaderboards

---

## 📁 New Files Created

### Models (in `NFCDemo/Models/`):
1. `EventSeriesModels.swift` - Event series, assignments, metrics
2. `EmergencyModels.swift` - Incidents, actions, status
3. `FraudModels.swift` - Cases, rules, watchlist
4. `OrganizationModels.swift` - Orgs, members, staff performance
5. `OfflineSyncModels.swift` - Sync queue, conflicts, statistics

### Services (in `NFCDemo/Services/`):
1. `EventSeriesService.swift` - Series management
2. `EmergencyAlertService.swift` - Emergency system
3. `FraudManagementService.swift` - Fraud & security
4. `OfflineSyncEngine.swift` - Offline sync

---

## 🔧 How to Use the New Features

### Using Event Series

```swift
// In your view
@StateObject private var seriesService = EventSeriesService.shared

// Fetch series for current event
Task {
    let series = try await seriesService.fetchSeries(for: eventId)
    // Auto-selects active series
}

// Check if wristband is valid for series
let isValid = try await seriesService.isWristbandValidForSeries(
    wristbandId: wristbandId,
    seriesId: seriesId
)
```

### Emergency Alerts

```swift
// In your view
@StateObject private var emergencyService = EmergencyAlertService.shared

// Subscribe to alerts
Task {
    await emergencyService.subscribeToEmergencyAlerts(eventId: eventId)
}

// Report emergency
try await emergencyService.reportEmergency(
    eventId: eventId,
    incidentType: "Security Breach",
    severity: .critical,
    location: "Gate 3",
    description: "Unauthorized entry detected"
)
```

### Fraud Management

```swift
// In your scan flow
@StateObject private var fraudService = FraudManagementService.shared

// Load watchlist
try await fraudService.fetchWatchlist(for: organizationId)

// Check during scan
if let watchlistEntry = fraudService.isOnWatchlist(nfcId: nfcId) {
    // Handle watchlist hit
    print("⚠️ On watchlist: \(watchlistEntry.reason)")
}

// Validate check-in
let result = await fraudService.validateCheckin(
    wristbandId: wristbandId,
    nfcId: nfcId,
    eventId: eventId,
    gateId: gateId
)

if result.shouldBlock {
    // Block check-in
    print("❌ \(result.displayMessage)")
}
```

### Offline Sync

```swift
// In your scan flow
@StateObject private var syncEngine = OfflineSyncEngine.shared

// Queue offline operation
if !syncEngine.isOnline {
    syncEngine.queueCheckin(
        eventId: eventId,
        wristbandId: wristbandId,
        location: location,
        notes: notes,
        gateId: gateId
    )
}

// Manual sync
await syncEngine.syncAll()

// Check queue status
let queueCount = syncEngine.queueCount
let syncHealth = syncEngine.syncStatistics.syncHealth
```

---

## 🎨 UI Integration Examples

### 1. Series Selector in Event Selection

```swift
struct EventSelectionView: View {
    @StateObject private var seriesService = EventSeriesService.shared

    var body: some View {
        VStack {
            // Event picker
            // ...

            if !seriesService.currentSeries.isEmpty {
                VStack(alignment: .leading) {
                    Text("Sessions")
                        .font(.headline)

                    ForEach(seriesService.currentSeries) { series in
                        SeriesRow(series: series)
                            .onTapGesture {
                                seriesService.selectSeries(series)
                            }
                    }
                }
            }
        }
        .onAppear {
            Task {
                if let eventId = selectedEvent?.id {
                    try? await seriesService.fetchSeries(for: eventId)
                }
            }
        }
    }
}
```

### 2. Emergency Alert Banner

```swift
struct EmergencyBanner: View {
    @EnvironmentObject var emergencyService: EmergencyAlertService

    var body: some View {
        if emergencyService.hasActiveEmergency {
            VStack {
                HStack {
                    Image(systemName: emergencyService.emergencyStatus?.alertLevel.icon ?? "bell.fill")
                    Text("\(emergencyService.activeIncidents.count) Active Incidents")
                    Spacer()
                    Text(emergencyService.emergencyStatus?.alertLevel.displayName ?? "Alert")
                }
                .padding()
                .background(Color.red)
                .foregroundColor(.white)
            }
        }
    }
}
```

### 3. Fraud Alert in Scan Result

```swift
struct ScanResultView: View {
    let fraudResult: FraudValidationResult

    var body: some View {
        VStack {
            if fraudResult.shouldBlock {
                VStack {
                    Image(systemName: "xmark.shield.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.red)

                    Text("CHECK-IN BLOCKED")
                        .font(.title)
                        .foregroundColor(.red)

                    Text(fraudResult.displayMessage)
                        .multilineTextAlignment(.center)
                }
            } else if !fraudResult.violations.isEmpty {
                VStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.orange)

                    Text(fraudResult.displayMessage)
                }
            }
        }
    }
}
```

### 4. Offline Sync Status

```swift
struct SyncStatusIndicator: View {
    @EnvironmentObject var syncEngine: OfflineSyncEngine

    var body: some View {
        HStack {
            if !syncEngine.isOnline {
                Image(systemName: "wifi.slash")
                    .foregroundColor(.red)
                Text("Offline")
            } else if syncEngine.queueCount > 0 {
                ProgressView()
                Text("Syncing \(syncEngine.queueCount) items")
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
        .font(.caption)
    }
}
```

---

## 🔗 Integration Checklist

### Step 1: Add Files to Xcode Project
```bash
# Open your Xcode project
# Right-click on NFCDemo group
# Add files to "NFCDemo"...
# Select all new files
# Check "Copy items if needed"
# Add to target: NFCDemo
```

### Step 2: Update ThreeTabView
```swift
struct ThreeTabView: View {
    @StateObject private var seriesService = EventSeriesService.shared
    @StateObject private var emergencyService = EmergencyAlertService.shared
    @StateObject private var fraudService = FraudManagementService.shared
    @StateObject private var syncEngine = OfflineSyncEngine.shared

    var body: some View {
        ZStack {
            // Existing tab view

            // Add emergency banner
            if emergencyService.hasActiveEmergency {
                EmergencyBanner()
                    .environmentObject(emergencyService)
            }

            // Add sync status
            SyncStatusIndicator()
                .environmentObject(syncEngine)
        }
        .onAppear {
            // Subscribe to alerts
            Task {
                await emergencyService.subscribeToEmergencyAlerts(eventId: eventId)
                try? await fraudService.fetchWatchlist(for: organizationId)
            }
        }
    }
}
```

### Step 3: Enhance Scan Flow
```swift
// In DatabaseScanView or your scan handler
func handleScan(nfcId: String) async {
    // 1. Check watchlist
    if let watchlistEntry = fraudService.isOnWatchlist(nfcId: nfcId) {
        showWatchlistAlert(entry: watchlistEntry)
        if watchlistEntry.autoBlock { return }
    }

    // 2. Validate against fraud rules
    let fraudResult = await fraudService.validateCheckin(
        wristbandId: wristbandId,
        nfcId: nfcId,
        eventId: eventId,
        gateId: gateId
    )

    if fraudResult.shouldBlock {
        showBlockedAlert(result: fraudResult)
        return
    }

    // 3. Check series validation
    if let selectedSeries = seriesService.selectedSeries {
        let isValid = try await seriesService.isWristbandValidForSeries(
            wristbandId: wristbandId,
            seriesId: selectedSeries.id
        )

        if !isValid {
            showInvalidSeriesAlert()
            return
        }
    }

    // 4. Perform check-in (online or queue offline)
    if syncEngine.isOnline {
        try await performCheckin()
    } else {
        syncEngine.queueCheckin(
            eventId: eventId,
            wristbandId: wristbandId,
            location: location,
            notes: notes,
            gateId: gateId
        )
        showOfflineSuccess()
    }
}
```

---

## 📊 Database Migration (If Needed)

If the `mobile_sync_queue` table doesn't exist in Supabase:

```sql
-- Run this in Supabase SQL editor
CREATE TABLE IF NOT EXISTS mobile_sync_queue (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id),
  action_type text NOT NULL,
  table_name text NOT NULL,
  record_data jsonb NOT NULL,
  sync_status text DEFAULT 'pending',
  retry_count int DEFAULT 0,
  last_error text,
  created_at timestamptz DEFAULT now()
);

-- Add index for faster queries
CREATE INDEX idx_sync_queue_user ON mobile_sync_queue(user_id);
CREATE INDEX idx_sync_queue_status ON mobile_sync_queue(sync_status);
```

---

## 🧪 Testing Checklist

### Event Series
- [ ] Load series for multi-day event
- [ ] Auto-select active series
- [ ] Manually select different series
- [ ] Validate wristband for series
- [ ] View series metrics

### Emergency
- [ ] Receive emergency alert
- [ ] Report incident from app
- [ ] View incident details
- [ ] Update incident status
- [ ] Execute emergency action

### Fraud
- [ ] Scan wristband on watchlist
- [ ] Trigger duplicate check-in alert
- [ ] View assigned fraud cases
- [ ] Resolve fraud case
- [ ] Add wristband to watchlist

### Offline
- [ ] Turn off WiFi
- [ ] Perform check-ins offline
- [ ] View queued items
- [ ] Turn on WiFi
- [ ] Verify auto-sync
- [ ] Check sync statistics

---

## 🐛 Troubleshooting

### "Module not found" errors
- Make sure all new files are added to Xcode project
- Check target membership
- Clean build folder (Cmd+Shift+K)

### "Cannot find type" errors
- Ensure all imports are correct
- Check file naming matches class names
- Verify files are in correct groups

### Sync not working
- Check network connectivity
- Verify Supabase credentials
- Check console logs for errors
- Try manual sync

### Emergency alerts not showing
- Verify subscription is called
- Check user has permission for event
- Ensure Supabase Realtime is enabled
- Check console for subscription errors

---

## 📚 Additional Resources

- See `IMPLEMENTATION_PROGRESS.md` for detailed progress
- Check original documentation for database schema
- Review portal code for reference implementations
- Test thoroughly before deploying to production

---

## 🎉 You're Ready!

Your app now has **1000x** more functionality! Start by:
1. Adding files to Xcode
2. Testing compilation
3. Implementing UI views
4. Testing each feature
5. Rolling out to users

**Questions?** Check the implementation progress doc or review the service files for detailed usage examples.
