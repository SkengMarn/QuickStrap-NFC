-- Database Optimization for NFC Event Management App
-- Execute these commands in your Supabase SQL Editor

-- ============================================================================
-- INDICES FOR PERFORMANCE
-- ============================================================================

-- Wristbands table indices
CREATE INDEX IF NOT EXISTS idx_wristbands_event_id
    ON wristbands(event_id);

CREATE INDEX IF NOT EXISTS idx_wristbands_nfc_id
    ON wristbands(nfc_id);

CREATE INDEX IF NOT EXISTS idx_wristbands_event_category
    ON wristbands(event_id, category);

CREATE INDEX IF NOT EXISTS idx_wristbands_active
    ON wristbands(is_active)
    WHERE is_active = true;

CREATE INDEX IF NOT EXISTS idx_wristbands_created
    ON wristbands(created_at DESC);

-- Check-in logs indices
CREATE INDEX IF NOT EXISTS idx_checkin_logs_event_id
    ON checkin_logs(event_id);

CREATE INDEX IF NOT EXISTS idx_checkin_logs_wristband_id
    ON checkin_logs(wristband_id);

CREATE INDEX IF NOT EXISTS idx_checkin_logs_timestamp
    ON checkin_logs(timestamp DESC);

CREATE INDEX IF NOT EXISTS idx_checkin_logs_event_timestamp
    ON checkin_logs(event_id, timestamp DESC);

CREATE INDEX IF NOT EXISTS idx_checkin_logs_gate_id
    ON checkin_logs(gate_id)
    WHERE gate_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_checkin_logs_staff_id
    ON checkin_logs(staff_id)
    WHERE staff_id IS NOT NULL;

-- Events table indices
CREATE INDEX IF NOT EXISTS idx_events_start_date
    ON events(start_date DESC);

CREATE INDEX IF NOT EXISTS idx_events_created_by
    ON events(created_by);

-- Gates table indices
CREATE INDEX IF NOT EXISTS idx_gates_event_id
    ON gates(event_id);

CREATE INDEX IF NOT EXISTS idx_gates_location
    ON gates(latitude, longitude)
    WHERE latitude IS NOT NULL AND longitude IS NOT NULL;

-- Gate bindings indices
CREATE INDEX IF NOT EXISTS idx_gate_bindings_gate_id
    ON gate_bindings(gate_id);

CREATE INDEX IF NOT EXISTS idx_gate_bindings_category
    ON gate_bindings(category);

CREATE INDEX IF NOT EXISTS idx_gate_bindings_status
    ON gate_bindings(status);

-- Tickets table indices (if using ticket linking)
CREATE INDEX IF NOT EXISTS idx_tickets_event_id
    ON tickets(event_id);

CREATE INDEX IF NOT EXISTS idx_tickets_linked_wristband
    ON tickets(linked_wristband_id)
    WHERE linked_wristband_id IS NOT NULL;

-- ============================================================================
-- COMPOSITE INDICES FOR COMPLEX QUERIES
-- ============================================================================

-- Wristband lookup by event and NFC ID (most common query)
CREATE INDEX IF NOT EXISTS idx_wristbands_event_nfc_active
    ON wristbands(event_id, nfc_id, is_active);

-- Check-in logs by event and time range (for stats)
CREATE INDEX IF NOT EXISTS idx_checkin_logs_event_time_range
    ON checkin_logs(event_id, timestamp DESC, wristband_id);

-- Gate bindings with event context
CREATE INDEX IF NOT EXISTS idx_gate_bindings_event_gate_category
    ON gate_bindings(event_id, gate_id, category);

-- ============================================================================
-- PARTIAL INDICES (for specific queries)
-- ============================================================================

-- Only active wristbands
CREATE INDEX IF NOT EXISTS idx_wristbands_active_only
    ON wristbands(event_id, category)
    WHERE is_active = true;

-- Only recent check-ins (last 30 days)
CREATE INDEX IF NOT EXISTS idx_checkin_logs_recent
    ON checkin_logs(event_id, timestamp DESC)
    WHERE timestamp > (NOW() - INTERVAL '30 days');

-- Only probation-tagged check-ins
CREATE INDEX IF NOT EXISTS idx_checkin_logs_probation
    ON checkin_logs(event_id, wristband_id, timestamp)
    WHERE probation_tagged = true;

-- ============================================================================
-- MATERIALIZED VIEWS FOR COMPLEX AGGREGATIONS
-- ============================================================================

-- Event statistics view (pre-computed)
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_event_stats AS
SELECT
    e.id as event_id,
    e.name as event_name,
    COUNT(DISTINCT w.id) as total_wristbands,
    COUNT(DISTINCT CASE WHEN cl.id IS NOT NULL THEN w.id END) as checked_in_wristbands,
    COUNT(cl.id) as total_checkins,
    COUNT(DISTINCT cl.staff_id) as unique_staff,
    MAX(cl.timestamp) as last_checkin_time
FROM events e
LEFT JOIN wristbands w ON w.event_id = e.id AND w.is_active = true
LEFT JOIN checkin_logs cl ON cl.wristband_id = w.id
GROUP BY e.id, e.name;

-- Index on materialized view
CREATE INDEX IF NOT EXISTS idx_mv_event_stats_event_id
    ON mv_event_stats(event_id);

-- Category breakdown view
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_category_stats AS
SELECT
    w.event_id,
    w.category,
    COUNT(w.id) as total_wristbands,
    COUNT(DISTINCT cl.wristband_id) as checked_in_wristbands,
    COUNT(cl.id) as total_checkins
FROM wristbands w
LEFT JOIN checkin_logs cl ON cl.wristband_id = w.id
WHERE w.is_active = true
GROUP BY w.event_id, w.category;

-- Index on category stats
CREATE INDEX IF NOT EXISTS idx_mv_category_stats_event_category
    ON mv_category_stats(event_id, category);

-- ============================================================================
-- REFRESH FUNCTIONS FOR MATERIALIZED VIEWS
-- ============================================================================

-- Function to refresh event stats (call after significant data changes)
CREATE OR REPLACE FUNCTION refresh_event_stats()
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_event_stats;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_category_stats;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- AUTOMATIC REFRESH (Optional - use with caution on high-traffic systems)
-- ============================================================================

-- Refresh stats every hour (adjust as needed)
-- Note: Uncomment only if your database can handle the load

-- CREATE EXTENSION IF NOT EXISTS pg_cron;
--
-- SELECT cron.schedule('refresh-stats', '0 * * * *', $$
--     SELECT refresh_event_stats();
-- $$);

-- ============================================================================
-- QUERY OPTIMIZATION FUNCTIONS
-- ============================================================================

-- Function to get wristband with latest check-in (optimized)
CREATE OR REPLACE FUNCTION get_wristband_with_latest_checkin(p_wristband_id UUID)
RETURNS TABLE (
    wristband_id UUID,
    nfc_id TEXT,
    category TEXT,
    latest_checkin_time TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        w.id,
        w.nfc_id,
        w.category,
        MAX(cl.timestamp) as latest_checkin_time
    FROM wristbands w
    LEFT JOIN checkin_logs cl ON cl.wristband_id = w.id
    WHERE w.id = p_wristband_id
    GROUP BY w.id, w.nfc_id, w.category;
END;
$$ LANGUAGE plpgsql;

-- Function to get event check-in rate (optimized)
CREATE OR REPLACE FUNCTION get_event_checkin_rate(p_event_id UUID)
RETURNS NUMERIC AS $$
DECLARE
    total_wristbands INTEGER;
    checked_in_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO total_wristbands
    FROM wristbands
    WHERE event_id = p_event_id AND is_active = true;

    SELECT COUNT(DISTINCT wristband_id) INTO checked_in_count
    FROM checkin_logs
    WHERE event_id = p_event_id;

    IF total_wristbands = 0 THEN
        RETURN 0;
    END IF;

    RETURN (checked_in_count::NUMERIC / total_wristbands::NUMERIC) * 100;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- VACUUM AND ANALYZE
-- ============================================================================

-- Run these periodically to maintain performance
VACUUM ANALYZE wristbands;
VACUUM ANALYZE checkin_logs;
VACUUM ANALYZE events;
VACUUM ANALYZE gates;
VACUUM ANALYZE gate_bindings;

-- ============================================================================
-- MONITORING QUERIES
-- ============================================================================

-- Check index usage
SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY idx_scan DESC;

-- Check table sizes
SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- Check slow queries (requires pg_stat_statements extension)
-- SELECT
--     query,
--     calls,
--     total_exec_time,
--     mean_exec_time,
--     max_exec_time
-- FROM pg_stat_statements
-- WHERE query LIKE '%wristbands%' OR query LIKE '%checkin_logs%'
-- ORDER BY mean_exec_time DESC
-- LIMIT 20;

-- ============================================================================
-- RECOMMENDED MAINTENANCE SCHEDULE
-- ============================================================================

-- Daily:
--   - Check slow query log
--   - Monitor table growth

-- Weekly:
--   - VACUUM ANALYZE on main tables
--   - Refresh materialized views (if using)
--   - Review index usage

-- Monthly:
--   - Full database backup
--   - Review and optimize slow queries
--   - Check for unused indices
--   - Analyze table statistics

-- ============================================================================
-- NOTES
-- ============================================================================

-- 1. These indices will improve query performance but will slightly slow down writes
-- 2. Monitor index usage and remove unused indices
-- 3. Adjust materialized view refresh frequency based on your workload
-- 4. Consider partitioning check-in logs table if it grows very large
-- 5. Use EXPLAIN ANALYZE to test query performance before/after optimization
-- 6. Keep statistics up-to-date with regular ANALYZE commands

-- Example query to test optimization:
-- EXPLAIN ANALYZE
-- SELECT w.*, cl.timestamp as last_checkin
-- FROM wristbands w
-- LEFT JOIN LATERAL (
--     SELECT timestamp
--     FROM checkin_logs
--     WHERE wristband_id = w.id
--     ORDER BY timestamp DESC
--     LIMIT 1
-- ) cl ON true
-- WHERE w.event_id = 'your-event-id'
-- AND w.is_active = true;
