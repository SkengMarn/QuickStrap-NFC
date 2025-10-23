# Series Check-in and Analytics Fix

## Problem
Manual check-ins and analytics were not working correctly for series events because:
1. Check-in logs were being created with the wrong `event_id` (series ID instead of parent event ID)
2. Check-in logs weren't including the `series_id` column
3. Analytics queries were fetching data by `event_id` only, missing series-specific check-ins

## Database Schema for Check-ins
```
For Parent Event Check-ins:
  event_id = Parent Event ID
  series_id = NULL

For Series Event Check-ins:
  event_id = Parent Event ID (FK requirement)
  series_id = Series ID
```

## Changes Made

### 1. **CheckinLog Model** (`DatabaseModels.swift`)
- ✅ Added `seriesId: String?` property to track series check-ins
- ✅ Updated `CodingKeys` to include `seriesId = "series_id"`

### 2. **SupabaseService - recordCheckIn** (`SupabaseService.swift`)
- ✅ Added `seriesId` parameter to method signature
- ✅ Updated to include `series_id` in check-in data when provided
- ✅ Logs now correctly store both parent event ID and series ID

### 3. **SupabaseService - fetchCheckinLogsForSeries** (`SupabaseService.swift`)
- ✅ Added new method to fetch check-in logs by `series_id`
- ✅ Query: `rest/v1/checkin_logs?series_id=eq.\(seriesId)&order=timestamp.desc&limit=\(limit)`

### 4. **SupabaseService - fetchEventStats** (`SupabaseService.swift`)
- ✅ Added optional `seriesId` parameter
- ✅ Fetches wristbands and check-in logs based on series vs parent event context
- ✅ For series: queries by `series_id`
- ✅ For parent events: queries by `event_id` with `series_id IS NULL` filter

### 5. **DatabaseWristbandsView - manualCheckIn** (`DatabaseWristbandsView.swift`)
- ✅ Updated to determine correct `event_id` and `series_id` based on context
- ✅ For series events:
  - Uses `wristband.eventId` (parent event ID) for `event_id`
  - Uses `currentEvent.seriesId` for `series_id`
- ✅ For parent events:
  - Uses `currentEvent.id` for `event_id`
  - Sets `series_id` to `nil`

### 6. **DatabaseWristbandsView - loadData** (`DatabaseWristbandsView.swift`)
- ✅ Updated to fetch check-in logs using the correct method:
  - Series events: calls `fetchCheckinLogsForSeries(seriesId)`
  - Parent events: calls `fetchCheckinLogs(eventId)`

### 7. **DatabaseStatsView - loadStats** (`DatabaseStatsView.swift`)
- ✅ Updated to pass `seriesId` to `fetchEventStats`
- ✅ Analytics now correctly show series-specific data

## Result

### Manual Check-in
✅ **Parent events**: Check-ins logged with `event_id = parent ID`, `series_id = NULL`  
✅ **Series events**: Check-ins logged with `event_id = parent ID`, `series_id = series ID`  
✅ **Correct association**: Check-ins are properly linked to both parent and series  
✅ **Check-in status**: Wristbands correctly show as checked-in after manual check-in

### Analytics Tab
✅ **Parent events**: Shows analytics for parent event wristbands only  
✅ **Series events**: Shows analytics for series-specific wristbands and check-ins  
✅ **Category breakdown**: Correctly calculated for each context  
✅ **Recent activity**: Shows check-ins relevant to the current view  
✅ **Time-based stats**: Filtered correctly by series or parent event

## Testing Checklist

### Manual Check-in Feature
1. ✅ Open a **series event** (e.g., "Match Day 1")
2. ✅ Navigate to **Wristbands** tab
3. ✅ Tap "Check In" on a wristband
4. ✅ Verify wristband shows as checked-in (green checkmark)
5. ✅ Check database: `checkin_logs` should have:
   - `event_id` = parent event ID
   - `series_id` = series ID
   - `wristband_id` = wristband ID

### Analytics Tab
1. ✅ Open a **series event**
2. ✅ Navigate to **Analytics** tab
3. ✅ Verify stats show:
   - Total wristbands for this series
   - Check-ins for this series only
   - Category breakdown for series wristbands
4. ✅ Open a **parent event**
5. ✅ Verify stats show:
   - Total wristbands for parent event (excluding series)
   - Check-ins for parent event only
   - Category breakdown for parent wristbands

## Database Queries

### Manual Check-in (Series Event)
```sql
INSERT INTO checkin_logs (
  event_id,      -- Parent Event ID
  series_id,     -- Series ID
  wristband_id,
  staff_id,
  timestamp,
  location,
  notes
) VALUES (...)
```

### Fetch Check-in Logs (Series Event)
```sql
SELECT * FROM checkin_logs
WHERE series_id = '<series_id>'
ORDER BY timestamp DESC
LIMIT 100
```

### Fetch Analytics (Series Event)
```sql
-- Wristbands
SELECT * FROM wristbands
WHERE series_id = '<series_id>'
AND is_active = true

-- Check-in Logs
SELECT * FROM checkin_logs
WHERE series_id = '<series_id>'
AND timestamp >= '<start_date>'
AND timestamp <= '<end_date>'
ORDER BY timestamp DESC
```

## Logging
Enhanced logging for debugging:
- `🔄 Starting manual check-in for SERIES wristband: <nfc_id>`
- `   Parent Event ID: <parent_id>, Series ID: <series_id>`
- `✅ Manual check-in successful for <category> wristband: <nfc_id>`
- `📊 Fetching stats for SERIES: <series_id>`
- `✅ Fetched X wristbands and Y logs for series <series_id>`
