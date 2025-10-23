-- =====================================================
-- Event Series Setup
-- =====================================================
-- This script helps you set up event series support
-- =====================================================

-- 1. Add series columns to events table (if not already present)
ALTER TABLE events 
ADD COLUMN IF NOT EXISTS parent_event_id uuid REFERENCES events(id) ON DELETE CASCADE,
ADD COLUMN IF NOT EXISTS is_series boolean DEFAULT false,
ADD COLUMN IF NOT EXISTS status text DEFAULT 'active';

-- 2. Create index for faster child event queries
CREATE INDEX IF NOT EXISTS idx_events_parent_event_id ON events(parent_event_id);
CREATE INDEX IF NOT EXISTS idx_events_status ON events(status);
CREATE INDEX IF NOT EXISTS idx_events_is_series ON events(is_series);

-- 3. Add check constraint for valid status values
ALTER TABLE events 
DROP CONSTRAINT IF EXISTS events_status_check;

ALTER TABLE events 
ADD CONSTRAINT events_status_check 
CHECK (status IN ('draft', 'active', 'completed', 'cancelled', 'standard'));

-- =====================================================
-- Example: Convert existing event to series
-- =====================================================
-- Step 1: Mark the parent event as a series
/*
UPDATE events 
SET is_series = true,
    status = 'active'
WHERE name = 'KCCA 2025/26 Football Season';
*/

-- Step 2: Link child events to the parent
/*
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
*/

-- =====================================================
-- Helper Functions
-- =====================================================

-- Function to get all active child events for a series
CREATE OR REPLACE FUNCTION get_active_child_events(parent_id uuid)
RETURNS TABLE (
    id uuid,
    name text,
    start_date timestamp with time zone,
    end_date timestamp with time zone,
    location text,
    status text
)
LANGUAGE sql
STABLE
AS $$
    SELECT 
        id,
        name,
        start_date,
        end_date,
        location,
        status
    FROM events
    WHERE parent_event_id = parent_id
      AND status = 'active'
      AND (end_date IS NULL OR end_date >= NOW())
    ORDER BY start_date ASC;
$$;

-- Function to count child events in a series
CREATE OR REPLACE FUNCTION count_child_events(parent_id uuid)
RETURNS integer
LANGUAGE sql
STABLE
AS $$
    SELECT COUNT(*)::integer
    FROM events
    WHERE parent_event_id = parent_id;
$$;

-- Function to mark a series event as a series
CREATE OR REPLACE FUNCTION mark_as_series(event_id uuid)
RETURNS boolean
LANGUAGE plpgsql
AS $$
DECLARE
    child_count integer;
BEGIN
    -- Check if event has children
    SELECT COUNT(*) INTO child_count
    FROM events
    WHERE parent_event_id = event_id;
    
    IF child_count > 0 THEN
        UPDATE events
        SET is_series = true
        WHERE id = event_id;
        RETURN true;
    ELSE
        RAISE NOTICE 'Event has no child events';
        RETURN false;
    END IF;
END;
$$;

-- =====================================================
-- Verification Queries
-- =====================================================

-- View all series events
/*
SELECT 
    id,
    name,
    is_series,
    status,
    start_date,
    end_date,
    (SELECT COUNT(*) FROM events WHERE parent_event_id = e.id) as child_count
FROM events e
WHERE is_series = true
ORDER BY start_date DESC;
*/

-- View child events for a specific series
/*
SELECT 
    e.name as child_event,
    e.start_date,
    e.status,
    p.name as parent_series
FROM events e
JOIN events p ON e.parent_event_id = p.id
WHERE p.name = 'KCCA 2025/26 Football Season'
ORDER BY e.start_date;
*/

-- Find events that should be marked as series (have children but not marked)
/*
SELECT 
    e.id,
    e.name,
    e.is_series,
    COUNT(c.id) as child_count
FROM events e
LEFT JOIN events c ON c.parent_event_id = e.id
GROUP BY e.id, e.name, e.is_series
HAVING COUNT(c.id) > 0 AND e.is_series = false;
*/

-- =====================================================
-- Usage Examples
-- =====================================================

-- Example 1: Get active child events for KCCA series
/*
SELECT * FROM get_active_child_events(
    (SELECT id FROM events WHERE name = 'KCCA 2025/26 Football Season')
);
*/

-- Example 2: Count children in a series
/*
SELECT count_child_events(
    (SELECT id FROM events WHERE name = 'KCCA 2025/26 Football Season')
);
*/

-- Example 3: Automatically mark event as series if it has children
/*
SELECT mark_as_series(
    (SELECT id FROM events WHERE name = 'KCCA 2025/26 Football Season')
);
*/

-- =====================================================
-- Maintenance
-- =====================================================

-- Auto-update is_series flag based on children (run periodically)
/*
UPDATE events e
SET is_series = (
    SELECT COUNT(*) > 0
    FROM events c
    WHERE c.parent_event_id = e.id
);
*/

-- Clean up orphaned child events (events with non-existent parents)
/*
UPDATE events
SET parent_event_id = NULL
WHERE parent_event_id IS NOT NULL
  AND parent_event_id NOT IN (SELECT id FROM events);
*/

-- =====================================================
-- Notes
-- =====================================================
-- Status values:
--   - draft: Event is being created
--   - active: Event is live and can be selected
--   - completed: Event has finished
--   - cancelled: Event was cancelled
--   - standard: Legacy/default status
--
-- Series structure:
--   - Parent event: is_series = true, parent_event_id = NULL
--   - Child events: is_series = false, parent_event_id = <parent_id>
--
-- App behavior:
--   - If event.isSeries = true: Show series selection screen
--   - If event.isSeries = false: Go directly to scanner
--   - Only shows child events with status = 'active' and not in past
-- =====================================================
