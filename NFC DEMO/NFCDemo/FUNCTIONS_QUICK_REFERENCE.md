# 🚀 Enhanced Functions - Quick Reference

## 📱 iOS App Methods

### Gate Operations
```swift
// Get gate scan counts
let counts = try await SupabaseService.shared.fetchGateScanCounts(eventId: "uuid")

// Find nearby gates by category  
let gates = try await SupabaseService.shared.findNearbyGatesByCategory(
    latitude: 40.7128, longitude: -74.0060, 
    eventId: "uuid", category: "VIP", radiusMeters: 50.0
)
```

### Event Analytics
```swift
// Get event categories
let categories = try await SupabaseService.shared.fetchEventCategories(eventId: "uuid")

// Get comprehensive stats
let stats = try await SupabaseService.shared.fetchComprehensiveEventStats(eventId: "uuid")
```

### Batch Processing
```swift
// Process unlinked check-ins
let result = try await SupabaseService.shared.processUnlinkedCheckIns(
    eventId: "uuid", batchLimit: 100
)
```

## 🗄️ SQL Functions

### Core Functions
```sql
-- Distance calculation
SELECT haversine_distance(lat1, lon1, lat2, lon2);

-- Gate scan counts
SELECT * FROM get_gate_scan_counts('event-uuid');

-- Event categories
SELECT * FROM get_event_categories('event-uuid');

-- Nearby gates search
SELECT * FROM find_nearby_gates_by_category(lat, lon, 'event-uuid', 'VIP', 50);

-- Batch processing
SELECT * FROM process_unlinked_checkins('event-uuid', 100);

-- Comprehensive stats
SELECT * FROM get_event_stats_comprehensive('event-uuid');
```

### Database Views
```sql
-- Check-ins with category info
SELECT * FROM checkin_logs_with_category WHERE event_id = 'uuid';

-- Category statistics
SELECT * FROM event_category_stats WHERE event_id = 'uuid';

-- Unlinked check-ins queue
SELECT * FROM unlinked_checkins_with_category WHERE event_id = 'uuid';
```

## ⚡ Enable Real-time Gate Linking
```sql
CREATE TRIGGER trigger_auto_link_checkin 
BEFORE INSERT ON checkin_logs 
FOR EACH ROW 
EXECUTE FUNCTION auto_link_checkin_to_gate();
```

## 🧪 Quick Tests
```sql
-- Test haversine (should return ~8.2km)
SELECT haversine_distance(40.7128, -74.0060, 40.7589, -73.9851);

-- Check functions exist
SELECT routine_name FROM information_schema.routines 
WHERE routine_schema = 'public' AND routine_name LIKE '%gate%';
```

---
*Functions deployed: 2025-10-01 17:50:54 UTC+3*
