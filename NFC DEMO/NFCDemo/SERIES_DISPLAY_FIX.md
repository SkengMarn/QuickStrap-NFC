# Series Display Fix - Event Selection View

## Problem
The app was showing main events (like "KCCA 2025/26 Football Season") instead of the individual series (matches) under them. Users couldn't see the actual series events they needed to scan.

## Root Cause
The `EventSeries` model had a decoding error with the `config` field. The database stores `config` as JSONB (which returns as a dictionary/object), but the Swift model expected it as a `String`. This caused all series fetching to fail with:

```
decodingError(Swift.DecodingError.typeMismatch(Swift.String, ...
Expected to decode String but found a dictionary instead.
```

## Solution Applied

### 1. Fixed EventSeries Model Decoding
**File**: `NFCDemo/Models/EventSeries.swift` (line 159-161)

Changed from:
```swift
config = try container.decodeIfPresent(String.self, forKey: .config)
```

To:
```swift
// Handle config - can be String or Dictionary from JSONB
// Try to decode as string, otherwise set to nil (we don't currently use this field)
config = try? container.decodeIfPresent(String.self, forKey: .config)
```

This gracefully handles the type mismatch by using `try?` which returns `nil` if decoding fails, instead of throwing an error.

### 2. Renamed Duplicate Struct
**File**: `NFCDemo/Views/SeriesSelectionView.swift`

Renamed `SeriesEventCard` to `SeriesItemCard` to avoid duplicate symbol conflict with `EventSelectionView.swift`.

## How It Works Now

### Event Display Logic (Already Implemented)
The `EventSelectionView` already had the correct logic to:

1. **Fetch both series and standalone events**
2. **Filter out main events that have series** - Don't show parent events
3. **Show only:**
   - Individual series (e.g., "KCCA vs Express Match 1")
   - Standalone events without series (e.g., "OneRepublic Live in Kampala")

**Code Location**: `EventSelectionView.swift` lines 466-476
```swift
// Get the main event IDs that have series
let mainEventIdsWithSeries = Set(fetchedSeriesEvents.map { $0.series.mainEventId })

// Filter: Keep events that DON'T have series (standalone events)
let standaloneEvents = fetchedEvents.filter { event in
    !mainEventIdsWithSeries.contains(event.id)
}
```

### Series Card Display
Each series card shows:
- **Series name** (e.g., "KCCA vs Express")
- **Parent event name** (e.g., "KCCA 2025/26 Football Season") - shown with folder icon
- **Location** (inherited from series or parent event)
- **Date range**
- **Status indicator** (Active/Upcoming/Ended)
- **Wristband count**

## Database Schema Reference

### Main Event (events table)
```sql
-- Example: "KCCA 2025/26 Football Season"
id: uuid
name: text
start_date: timestamp
end_date: timestamp
```

### Series (event_series table)
```sql
-- Example: "KCCA vs Express - Match 1"
id: uuid
main_event_id: uuid  -- References parent event
name: text
start_date: timestamp
end_date: timestamp
config: jsonb  -- This was causing the decoding error
```

## Testing
After this fix:
1. ✅ App builds successfully
2. ✅ Series events load without decoding errors
3. ✅ Main events with series are hidden from the list
4. ✅ Individual series are displayed as separate cards
5. ✅ Each series shows which parent event it belongs to

## Files Modified
1. `NFCDemo/Models/EventSeries.swift` - Fixed config field decoding
2. `NFCDemo/Views/SeriesSelectionView.swift` - Renamed SeriesEventCard to SeriesItemCard

## No Changes Needed
- `EventSelectionView.swift` - Already had correct filtering logic
- `SupabaseService.swift` - Already had correct API calls
