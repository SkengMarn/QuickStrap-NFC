# Actual Database Schema Notes

## Event Series Structure

Your database uses a **separate `event_series` table**, not parent/child events.

### Current Schema:

```sql
-- Main events table
events (
  id uuid,
  name text,
  organization_id uuid,
  lifecycle_status lifecycle_status (draft, scheduled, active, completed, cancelled),
  -- NO parent_event_id or is_series columns
  ...
)

-- Separate series table
event_series (
  id uuid,
  main_event_id uuid → references events(id),  -- The "parent" event
  name text,
  description text,
  start_date timestamp,
  end_date timestamp,
  lifecycle_status text (draft, scheduled, active, completed, cancelled),
  series_type text (standard, knockout, group_stage, round_robin, custom),
  sequence_number integer,
  checkin_window_start_offset interval,
  checkin_window_end_offset interval,
  ...
)

-- Events can belong to a series
wristbands (
  series_id uuid → references event_series(id)
)

checkin_logs (
  series_id uuid → references event_series(id)
)

gates (
  series_id uuid → references event_series(id)
)
```

### How It Works:

1. **Main Event** = The parent (e.g., "KCCA 2025/26 Football Season")
   - Created in `events` table
   - Has `lifecycle_status`, `organization_id`, etc.

2. **Series Events** = Individual matches/days
   - Created in `event_series` table
   - Each has `main_event_id` pointing to parent event
   - Has own `lifecycle_status`, `start_date`, `end_date`
   - Has `sequence_number` for ordering

3. **Resources** (wristbands, checkins, gates) can link to:
   - `event_id` (for single events)
   - `series_id` (for series events)

### iOS App Changes Needed:

1. **Add EventSeries model** to match `event_series` table
2. **Update Event model** - remove `parent_event_id`, `is_series`, `status`
3. **Fetch series** via `event_series` table, not child events
4. **Check if event has series** by querying `event_series.main_event_id`

### Migration Strategy:

**Option 1: Use Existing Schema** (Recommended)
- Update iOS app to work with `event_series` table
- No database changes needed
- Matches web portal exactly

**Option 2: Hybrid Approach**
- Keep my simple implementation for iOS only
- Add columns to events table
- More work, potential conflicts with web portal

## Recommendation:

**Use Option 1** - Update iOS app to match your existing schema. This ensures:
- ✅ Full compatibility with web portal
- ✅ No database migrations needed
- ✅ Access to rich series features (sequence_number, series_type, etc.)
- ✅ Proper lifecycle management

Would you like me to update the iOS app to use the `event_series` table structure?
