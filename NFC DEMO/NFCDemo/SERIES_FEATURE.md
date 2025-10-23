# Event Series Feature

## Overview

The app now supports **event series** - parent events that contain multiple child events (like a football season with individual match days).

## User Experience

### For Series Events (e.g., "KCCA 2025/26 Football Season")
1. User sees event with a blue "Series" badge
2. Taps on the series event
3. **Series Selection Screen appears** showing all active child events
4. User selects a specific match/event from the series
5. Scanner screen opens for that specific event

### For Single Events (e.g., "OneRepublic Live in Kampala")
1. User sees event (no series badge)
2. Taps on the event
3. **Scanner screen opens immediately**

## Database Schema

### New Fields in `events` Table

```sql
parent_event_id uuid      -- References parent event (NULL for parent/single events)
is_series boolean         -- true if this event has child events
status text              -- 'draft', 'active', 'completed', 'cancelled', 'standard'
```

### Structure

**Parent Event (Series):**
- `is_series = true`
- `parent_event_id = NULL`
- Example: "KCCA 2025/26 Football Season"

**Child Events:**
- `is_series = false`
- `parent_event_id = <parent_event_id>`
- Example: "Match Day 1: Kcca Fc vs Kitara FC"

**Single Events:**
- `is_series = false`
- `parent_event_id = NULL`
- Example: "OneRepublic Live in Kampala"

## Setup Instructions

### 1. Run Database Migration

```bash
# In Supabase SQL Editor, run:
Database/setup_event_series.sql
```

This will:
- Add required columns to `events` table
- Create indexes for performance
- Add helper functions

### 2. Configure Your Events

#### Option A: Mark Existing Event as Series

```sql
-- Step 1: Mark parent as series
UPDATE events 
SET is_series = true, status = 'active'
WHERE name = 'KCCA 2025/26 Football Season';

-- Step 2: Link child events
UPDATE events 
SET parent_event_id = (
    SELECT id FROM events 
    WHERE name = 'KCCA 2025/26 Football Season'
),
status = 'active'
WHERE name IN (
    'Match Day 1: Kcca Fc vs Kitara FC',
    'Match Day 2: Kcca Fc vs NEC FC'
);
```

#### Option B: Create New Series

```sql
-- Create parent event
INSERT INTO events (
    id, name, description, location, 
    start_date, end_date, is_series, status
) VALUES (
    gen_random_uuid(),
    'KCCA 2025/26 Football Season',
    'Full season of KCCA matches',
    'MTN Phillip Omondo Stadium',
    '2025-10-30',
    '2026-08-30',
    true,
    'active'
);

-- Create child events
INSERT INTO events (
    id, name, location, start_date, 
    parent_event_id, is_series, status
) VALUES (
    gen_random_uuid(),
    'Match Day 1: KCCA vs Kitara',
    'MTN Phillip Omondo Stadium',
    '2025-10-30 15:00:00',
    (SELECT id FROM events WHERE name = 'KCCA 2025/26 Football Season'),
    false,
    'active'
);
```

## Filtering Logic

The app **only shows child events** that are:
1. ✅ `status = 'active'`
2. ✅ Not in the past (`end_date >= NOW()` or `end_date IS NULL`)

This ensures users only see relevant, upcoming events in a series.

## iOS Implementation

### Models

**Event Model** (`DatabaseModels.swift`):
```swift
struct Event {
    let parentEventId: String?
    let isSeries: Bool
    let status: EventStatus?
    
    var isActiveAndCurrent: Bool {
        let notPast = !isPast
        let isActive = status == .active || status == nil
        return notPast && isActive
    }
}
```

### Services

**SupabaseService** (`SupabaseService.swift`):
```swift
func fetchChildEvents(for parentEventId: String) async throws -> [Event] {
    // Fetches and filters child events
    // Returns only active, non-past events
    // Sorted by start date
}
```

### Views

**EventSelectionView**:
- Shows "Series" badge on series events
- Handles tap to show series selection or scanner

**SeriesSelectionView** (new):
- Displays list of child events
- Shows date, time, location
- Filters to active & current events only

## Verification

### Check Series Setup

```sql
-- View all series
SELECT 
    name,
    is_series,
    status,
    (SELECT COUNT(*) FROM events WHERE parent_event_id = e.id) as child_count
FROM events e
WHERE is_series = true;

-- View child events for a series
SELECT 
    e.name,
    e.start_date,
    e.status,
    p.name as parent_series
FROM events e
JOIN events p ON e.parent_event_id = p.id
WHERE p.name = 'KCCA 2025/26 Football Season'
ORDER BY e.start_date;
```

### Test in App

1. ✅ Series events show "Series" badge
2. ✅ Tapping series shows child event list
3. ✅ Only active, future events appear
4. ✅ Tapping child event opens scanner
5. ✅ Single events go straight to scanner

## Helper Functions

```sql
-- Get active child events
SELECT * FROM get_active_child_events('<parent_id>');

-- Count children
SELECT count_child_events('<parent_id>');

-- Auto-mark as series
SELECT mark_as_series('<event_id>');
```

## Maintenance

### Auto-update Series Flags

```sql
-- Run periodically to keep is_series accurate
UPDATE events e
SET is_series = (
    SELECT COUNT(*) > 0
    FROM events c
    WHERE c.parent_event_id = e.id
);
```

### Clean Orphaned Events

```sql
-- Remove invalid parent references
UPDATE events
SET parent_event_id = NULL
WHERE parent_event_id IS NOT NULL
  AND parent_event_id NOT IN (SELECT id FROM events);
```

## Benefits

1. **Better Organization**: Group related events together
2. **Improved UX**: Users select specific match/event from series
3. **Flexible**: Works for seasons, festivals, multi-day events
4. **Backward Compatible**: Single events work as before
5. **Smart Filtering**: Only shows relevant, active events

## Examples

### Football Season
- Parent: "KCCA 2025/26 Football Season"
- Children: "Match Day 1", "Match Day 2", etc.

### Music Festival
- Parent: "Nyege Nyege Festival 2025"
- Children: "Day 1", "Day 2", "Day 3", "Day 4"

### Conference
- Parent: "Tech Summit 2025"
- Children: "Keynote Day", "Workshop Day", "Networking Day"

## Support

For issues or questions:
1. Check `Database/setup_event_series.sql` for SQL examples
2. Review `SeriesSelectionView.swift` for UI implementation
3. Check console logs for debugging info
