# Series Wristband Filtering Fix

## Problem
The iOS app was showing **0 wristbands** when viewing series events, even though 100 wristbands were uploaded in the web portal. The root cause was that the app was querying wristbands by `event_id` only, without considering the `series_id` column.

## Database Schema (from Web Portal)
```
For Parent Event Wristbands:
  event_id = Parent Event ID
  series_id = NULL ✅

For Series Event Wristbands:
  event_id = Parent Event ID (FK requirement)
  series_id = Series ID ✅
```

## Changes Made

### 1. **Event Model** (`DatabaseModels.swift`)
- ✅ Added `seriesId: String?` property to track if an Event represents a series
- ✅ Updated `CodingKeys` to include `seriesId = "series_id"`
- ✅ Updated initializers to accept and store `seriesId`

### 2. **EventSelectionView** (`EventSelectionView.swift`)
- ✅ Updated `selectSeriesEvent()` to pass `seriesId` when creating the Event object
- ✅ This marks the event as a series event so downstream code knows to query by `series_id`

### 3. **DatabaseWristbandsView** (`DatabaseWristbandsView.swift`)
- ✅ Updated `loadData()` to check if `currentEvent.seriesId` exists
- ✅ If `seriesId` exists: calls `fetchWristbandsForSeries(seriesId)`
- ✅ If `seriesId` is nil: calls `fetchWristbands(eventId)` for parent event

### 4. **SupabaseService** (`SupabaseService.swift`)
- ✅ Updated `fetchWristbands(for eventId:)` to filter by `series_id=is.null`
- ✅ Query: `rest/v1/wristbands?event_id=eq.\(eventId)&is_active=eq.true&series_id=is.null&select=*`
- ✅ This ensures parent events only show their own wristbands (not series wristbands)
- ✅ Updated `fetchWristbandsForSeries(seriesId:)` to query wristbands directly by `series_id`
- ✅ Query: `rest/v1/wristbands?series_id=eq.\(seriesId)&is_active=eq.true&select=*`

### 5. **WristbandRepository** (`WristbandRepository.swift`)
- ✅ Updated `fetchWristbands(for eventId:)` to also filter by `series_id=is.null`
- ✅ Maintains consistency with SupabaseService

## Result
✅ **Parent events** show only their own wristbands (`series_id = NULL`)  
✅ **Series events** show only their specific wristbands (`series_id = series ID`)  
✅ **No double counting** - each wristband belongs to exactly one entity  
✅ **Proper separation** - series wristbands don't inflate parent event counts  

## Testing
1. Open the app and navigate to the events list
2. Tap on a **series event** (e.g., "Match Day 1: Kcca Fc vs Kitara FC")
3. Navigate to the **Wristbands** tab
4. You should now see the 100 wristbands uploaded for that series

## Logging
The app now includes detailed logging:
- `🔍 WristbandsViewModel: Loading data for SERIES <id>` - when viewing a series
- `🔍 WristbandsViewModel: Loading data for PARENT EVENT <id>` - when viewing a parent event
- `✅ Fetched X wristbands for series <id>` - series wristband count
- `✅ Found X parent event wristbands for event <id> (excluding series wristbands)` - parent event count

## Database Query Examples

### Parent Event Query (iOS App)
```
GET /rest/v1/wristbands?event_id=eq.<parent_id>&is_active=eq.true&series_id=is.null
```

### Series Event Query (iOS App)
```
GET /rest/v1/wristbands?series_id=eq.<series_id>&is_active=eq.true
```

This matches the web portal's filtering logic exactly - wristbands are stored directly with `series_id` set in the wristbands table.
