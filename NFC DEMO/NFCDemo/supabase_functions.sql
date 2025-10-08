-- =====================================================
-- Supabase Database Functions for NFC Event Management
-- =====================================================
-- 
-- This file contains PostgreSQL functions that should be created
-- in your Supabase database to support the enhanced batch operations
-- and optimized queries in the iOS app.
--
-- To apply these functions:
-- 1. Go to your Supabase Dashboard
-- 2. Navigate to SQL Editor
-- 3. Copy and paste each function below
-- 4. Execute them one by one
--
-- =====================================================

-- Function: get_gate_scan_counts
-- Purpose: Efficiently aggregate scan counts per gate for an event
-- Used by: SupabaseService.fetchGateScanCounts()
-- 
-- This function provides much better performance than client-side aggregation
-- especially for events with large numbers of check-ins.

CREATE OR REPLACE FUNCTION get_gate_scan_counts(event_id_param uuid)
RETURNS TABLE (gate_id uuid, count bigint)
LANGUAGE sql
STABLE
AS $$
  SELECT 
    gate_id,
    COUNT(*) as count
  FROM checkin_logs
  WHERE event_id = event_id_param
    AND gate_id IS NOT NULL
  GROUP BY gate_id
  ORDER BY count DESC;
$$;

-- Grant execute permissions to authenticated users
GRANT EXECUTE ON FUNCTION get_gate_scan_counts(uuid) TO authenticated;

-- =====================================================

-- Function: get_event_stats_summary
-- Purpose: Get comprehensive event statistics in a single query
-- Used by: Future optimization for EventStats fetching
-- 
-- This function combines multiple statistics queries into one efficient call

CREATE OR REPLACE FUNCTION get_event_stats_summary(event_id_param uuid)
RETURNS TABLE (
  total_wristbands bigint,
  total_checked_in bigint,
  total_scans_today bigint,
  unique_scanners bigint,
  avg_scans_per_hour numeric
)
LANGUAGE sql
STABLE
AS $$
  WITH event_stats AS (
    SELECT 
      (SELECT COUNT(*) FROM wristbands WHERE event_id = event_id_param AND is_active = true) as total_wristbands,
      (SELECT COUNT(DISTINCT wristband_id) FROM checkin_logs WHERE event_id = event_id_param) as total_checked_in,
      (SELECT COUNT(*) FROM checkin_logs 
       WHERE event_id = event_id_param 
       AND timestamp >= CURRENT_DATE) as total_scans_today,
      (SELECT COUNT(DISTINCT staff_id) FROM checkin_logs 
       WHERE event_id = event_id_param 
       AND staff_id IS NOT NULL) as unique_scanners
  )
  SELECT 
    total_wristbands,
    total_checked_in,
    total_scans_today,
    unique_scanners,
    CASE 
      WHEN total_scans_today > 0 THEN 
        ROUND(total_scans_today::numeric / EXTRACT(HOUR FROM (NOW() - CURRENT_DATE))::numeric, 2)
      ELSE 0
    END as avg_scans_per_hour
  FROM event_stats;
$$;

-- Grant execute permissions to authenticated users
GRANT EXECUTE ON FUNCTION get_event_stats_summary(uuid) TO authenticated;

-- =====================================================

-- Function: batch_update_checkin_gates
-- Purpose: Efficiently update multiple check-in records with gate IDs
-- Used by: SupabaseService.batchUpdateCheckInGates()
-- 
-- This function provides atomic batch updates with better error handling

CREATE OR REPLACE FUNCTION batch_update_checkin_gates(
  updates jsonb
)
RETURNS TABLE (
  updated_count integer,
  failed_ids text[]
)
LANGUAGE plpgsql
AS $$
DECLARE
  update_record jsonb;
  success_count integer := 0;
  failed_list text[] := '{}';
  checkin_id uuid;
  gate_id_val uuid;
BEGIN
  -- Iterate through each update in the JSON array
  FOR update_record IN SELECT * FROM jsonb_array_elements(updates)
  LOOP
    BEGIN
      -- Extract values from JSON
      checkin_id := (update_record->>'id')::uuid;
      gate_id_val := (update_record->>'gate_id')::uuid;
      
      -- Perform the update
      UPDATE checkin_logs 
      SET gate_id = gate_id_val, updated_at = NOW()
      WHERE id = checkin_id;
      
      -- Check if update was successful
      IF FOUND THEN
        success_count := success_count + 1;
      ELSE
        failed_list := array_append(failed_list, checkin_id::text);
      END IF;
      
    EXCEPTION WHEN OTHERS THEN
      -- Add to failed list if any error occurs
      failed_list := array_append(failed_list, checkin_id::text);
    END;
  END LOOP;
  
  -- Return results
  RETURN QUERY SELECT success_count, failed_list;
END;
$$;

-- Grant execute permissions to authenticated users
GRANT EXECUTE ON FUNCTION batch_update_checkin_gates(jsonb) TO authenticated;

-- =====================================================

-- Function: get_checkins_with_gates
-- Purpose: Efficiently fetch check-ins with related gate information
-- Used by: SupabaseService.fetchCheckInsWithGates()
-- 
-- This function provides optimized JOIN queries with proper indexing

CREATE OR REPLACE FUNCTION get_checkins_with_gates(
  event_id_param uuid,
  limit_param integer DEFAULT 1000
)
RETURNS TABLE (
  checkin_id uuid,
  event_id uuid,
  wristband_id uuid,
  staff_id uuid,
  timestamp timestamptz,
  location text,
  notes text,
  gate_id uuid,
  gate_name text,
  gate_location text,
  scanner_id uuid,
  app_lat double precision,
  app_lon double precision,
  app_accuracy double precision,
  ble_seen jsonb,
  wifi_ssids jsonb,
  probation_tagged boolean
)
LANGUAGE sql
STABLE
AS $$
  SELECT 
    cl.id as checkin_id,
    cl.event_id,
    cl.wristband_id,
    cl.staff_id,
    cl.timestamp,
    cl.location,
    cl.notes,
    cl.gate_id,
    g.name as gate_name,
    g.location as gate_location,
    cl.scanner_id,
    cl.app_lat,
    cl.app_lon,
    cl.app_accuracy,
    cl.ble_seen,
    cl.wifi_ssids,
    cl.probation_tagged
  FROM checkin_logs cl
  LEFT JOIN gates g ON cl.gate_id = g.id
  WHERE cl.event_id = event_id_param
  ORDER BY cl.timestamp DESC
  LIMIT limit_param;
$$;

-- Grant execute permissions to authenticated users
GRANT EXECUTE ON FUNCTION get_checkins_with_gates(uuid, integer) TO authenticated;

-- =====================================================

-- Index Optimizations
-- Purpose: Improve query performance for common operations
-- 
-- These indexes should significantly improve the performance of
-- the batch operations and aggregation queries

-- Index for gate scan count queries
CREATE INDEX IF NOT EXISTS idx_checkin_logs_event_gate 
ON checkin_logs(event_id, gate_id) 
WHERE gate_id IS NOT NULL;

-- Index for timestamp-based queries (today's scans, etc.)
CREATE INDEX IF NOT EXISTS idx_checkin_logs_event_timestamp 
ON checkin_logs(event_id, timestamp DESC);

-- Index for wristband-based queries
CREATE INDEX IF NOT EXISTS idx_checkin_logs_wristband 
ON checkin_logs(wristband_id, timestamp DESC);

-- Index for staff-based queries
CREATE INDEX IF NOT EXISTS idx_checkin_logs_staff 
ON checkin_logs(staff_id, event_id) 
WHERE staff_id IS NOT NULL;

-- Composite index for gate operations
CREATE INDEX IF NOT EXISTS idx_gates_event_active 
ON gates(event_id, is_active) 
WHERE is_active = true;

-- =====================================================

-- Row Level Security (RLS) Policies
-- Purpose: Ensure data security while allowing efficient queries
-- 
-- These policies should be reviewed and adjusted based on your
-- specific security requirements

-- Enable RLS on checkin_logs if not already enabled
ALTER TABLE checkin_logs ENABLE ROW LEVEL SECURITY;

-- Policy for reading check-in logs (users can read logs for events they have access to)
CREATE POLICY IF NOT EXISTS "Users can read checkin logs for accessible events" 
ON checkin_logs FOR SELECT 
USING (
  EXISTS (
    SELECT 1 FROM event_access ea 
    WHERE ea.event_id = checkin_logs.event_id 
    AND ea.user_id = auth.uid()
  )
);

-- Policy for inserting check-in logs (users can insert logs for events they have access to)
CREATE POLICY IF NOT EXISTS "Users can insert checkin logs for accessible events" 
ON checkin_logs FOR INSERT 
WITH CHECK (
  EXISTS (
    SELECT 1 FROM event_access ea 
    WHERE ea.event_id = checkin_logs.event_id 
    AND ea.user_id = auth.uid()
  )
);

-- Policy for updating check-in logs (users can update logs for events they have access to)
CREATE POLICY IF NOT EXISTS "Users can update checkin logs for accessible events" 
ON checkin_logs FOR UPDATE 
USING (
  EXISTS (
    SELECT 1 FROM event_access ea 
    WHERE ea.event_id = checkin_logs.event_id 
    AND ea.user_id = auth.uid()
  )
);

-- =====================================================

-- Performance Monitoring Views
-- Purpose: Help monitor the performance of batch operations
-- 
-- These views can be used to track the effectiveness of the optimizations

CREATE OR REPLACE VIEW batch_operation_stats AS
SELECT 
  DATE_TRUNC('hour', timestamp) as hour,
  COUNT(*) as total_checkins,
  COUNT(DISTINCT gate_id) as unique_gates,
  COUNT(DISTINCT staff_id) as unique_staff,
  AVG(EXTRACT(EPOCH FROM (updated_at - timestamp))) as avg_processing_time_seconds
FROM checkin_logs 
WHERE timestamp >= NOW() - INTERVAL '24 hours'
GROUP BY DATE_TRUNC('hour', timestamp)
ORDER BY hour DESC;

-- Grant select permissions to authenticated users
GRANT SELECT ON batch_operation_stats TO authenticated;

-- =====================================================
-- 
-- INSTALLATION NOTES:
-- 
-- 1. Execute these functions in your Supabase SQL Editor
-- 2. Verify that the functions are created successfully
-- 3. Test the functions with sample data
-- 4. Monitor performance improvements in your app
-- 
-- TROUBLESHOOTING:
-- 
-- If you encounter permission errors:
-- - Ensure your database user has the necessary privileges
-- - Check that RLS policies are not blocking function execution
-- 
-- If functions fail to create:
-- - Verify that all referenced tables exist
-- - Check that column names match your schema
-- - Ensure UUID extensions are enabled: CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
-- 
-- =====================================================
