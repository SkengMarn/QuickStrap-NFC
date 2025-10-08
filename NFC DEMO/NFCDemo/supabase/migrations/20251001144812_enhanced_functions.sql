-- =========================================
-- ENHANCED SUPABASE FUNCTIONS FOR NFC EVENT MANAGEMENT
-- =========================================
-- 
-- This file contains PostgreSQL functions optimized for your actual schema
-- Deploy using: supabase db push or through Supabase Dashboard SQL Editor
--
-- =========================================

-- First, ensure we have the haversine distance function
CREATE OR REPLACE FUNCTION haversine_distance(
  lat1 DOUBLE PRECISION,
  lon1 DOUBLE PRECISION,
  lat2 DOUBLE PRECISION,
  lon2 DOUBLE PRECISION
)
RETURNS DOUBLE PRECISION
LANGUAGE sql
IMMUTABLE
STRICT
AS $$
  SELECT 
    6371000 * 2 * ASIN(
      SQRT(
        POWER(SIN(RADIANS(lat2 - lat1) / 2), 2) +
        COS(RADIANS(lat1)) * COS(RADIANS(lat2)) *
        POWER(SIN(RADIANS(lon2 - lon1) / 2), 2)
      )
    );
$$;

-- =========================================
-- Helper Functions Using Real Schema
-- =========================================

-- Get gate scan counts (CORRECTED)
CREATE OR REPLACE FUNCTION get_gate_scan_counts(event_id_param uuid)
RETURNS TABLE (gate_id uuid, count bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT 
    gate_id,
    COUNT(*) as count
  FROM checkin_logs
  WHERE event_id = event_id_param
    AND gate_id IS NOT NULL
  GROUP BY gate_id;
$$;

-- Get categories for an event (from wristbands table)
CREATE OR REPLACE FUNCTION get_event_categories(event_id_param uuid)
RETURNS TABLE (category text, wristband_count bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT 
    category,
    COUNT(*) as wristband_count
  FROM wristbands
  WHERE event_id = event_id_param
    AND is_active = true
  GROUP BY category
  ORDER BY COUNT(*) DESC;
$$;

-- Find nearby gates with category filter
CREATE OR REPLACE FUNCTION find_nearby_gates_by_category(
  search_lat DOUBLE PRECISION,
  search_lon DOUBLE PRECISION,
  search_event_id uuid,
  search_category text,
  radius_meters DOUBLE PRECISION DEFAULT 50
)
RETURNS TABLE (
  gate_id uuid,
  gate_name text,
  distance_meters DOUBLE PRECISION
)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT 
    g.id as gate_id,
    g.name as gate_name,
    haversine_distance(search_lat, search_lon, g.latitude, g.longitude) as distance_meters
  FROM gates g
  INNER JOIN gate_bindings gb ON g.id = gb.gate_id
  WHERE g.event_id = search_event_id
    AND gb.category = search_category
    AND gb.status != 'unbound'
    AND g.latitude IS NOT NULL 
    AND g.longitude IS NOT NULL
    AND haversine_distance(search_lat, search_lon, g.latitude, g.longitude) <= radius_meters
  ORDER BY distance_meters ASC;
$$;

-- =========================================
-- Auto-Link Check-ins (CORRECTED)
-- =========================================

CREATE OR REPLACE FUNCTION auto_link_checkin_to_gate()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  nearby_gate_id uuid;
  wristband_category text;
BEGIN
  -- Only process if gate_id is NULL and location exists
  IF NEW.gate_id IS NULL AND NEW.app_lat IS NOT NULL AND NEW.app_lon IS NOT NULL THEN
    
    -- Get category from wristbands table (JOIN)
    SELECT w.category INTO wristband_category
    FROM wristbands w
    WHERE w.id = NEW.wristband_id;
    
    -- Skip if category not found
    IF wristband_category IS NULL THEN
      RETURN NEW;
    END IF;
    
    -- Find nearest gate within 50m that serves this category
    SELECT g.id INTO nearby_gate_id
    FROM gates g
    INNER JOIN gate_bindings gb ON g.id = gb.gate_id
    WHERE g.event_id = NEW.event_id
      AND gb.category = wristband_category
      AND gb.status != 'unbound'
      AND g.latitude IS NOT NULL
      AND g.longitude IS NOT NULL
      AND haversine_distance(NEW.app_lat, NEW.app_lon, g.latitude, g.longitude) <= 50
    ORDER BY haversine_distance(NEW.app_lat, NEW.app_lon, g.latitude, g.longitude) ASC
    LIMIT 1;
    
    -- If found, link the check-in
    IF nearby_gate_id IS NOT NULL THEN
      NEW.gate_id := nearby_gate_id;
      
      -- Update gate binding sample count
      UPDATE gate_bindings
      SET 
        sample_count = sample_count + 1,
        confidence = LEAST(1.0, confidence + 0.01)
      WHERE gate_id = nearby_gate_id
        AND category = wristband_category;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;

-- =========================================
-- Useful Views
-- =========================================

-- View: Check-ins with category information
CREATE OR REPLACE VIEW checkin_logs_with_category AS
SELECT 
  cl.*,
  w.category as wristband_category,
  w.nfc_id,
  g.name as gate_name,
  gb.status as gate_status,
  gb.confidence as gate_confidence
FROM checkin_logs cl
LEFT JOIN wristbands w ON cl.wristband_id = w.id
LEFT JOIN gates g ON cl.gate_id = g.id
LEFT JOIN gate_bindings gb ON g.id = gb.gate_id AND w.category = gb.category;

-- View: Category summary by event
CREATE OR REPLACE VIEW event_category_stats AS
SELECT 
  e.id as event_id,
  e.name as event_name,
  w.category,
  COUNT(DISTINCT w.id) as total_wristbands,
  COUNT(DISTINCT cl.id) as total_checkins,
  COUNT(DISTINCT cl.gate_id) as unique_gates_used
FROM events e
LEFT JOIN wristbands w ON w.event_id = e.id
LEFT JOIN checkin_logs cl ON cl.wristband_id = w.id
GROUP BY e.id, e.name, w.category
ORDER BY e.id, COUNT(DISTINCT cl.id) DESC;

-- View: Unlinked check-ins with category
CREATE OR REPLACE VIEW unlinked_checkins_with_category AS
SELECT 
  cl.id,
  cl.event_id,
  cl.wristband_id,
  w.category,
  cl.app_lat,
  cl.app_lon,
  cl.app_accuracy,
  cl.timestamp
FROM checkin_logs cl
INNER JOIN wristbands w ON cl.wristband_id = w.id
WHERE cl.gate_id IS NULL
  AND cl.app_lat IS NOT NULL
  AND cl.app_lon IS NOT NULL
ORDER BY cl.timestamp DESC;

-- =========================================
-- Batch Processing Function
-- =========================================

-- Process unlinked check-ins in batch
CREATE OR REPLACE FUNCTION process_unlinked_checkins(
  event_id_param uuid,
  batch_limit integer DEFAULT 100
)
RETURNS TABLE (
  processed_count integer,
  linked_count integer
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  checkin_record RECORD;
  nearby_gate_id uuid;
  processed integer := 0;
  linked integer := 0;
BEGIN
  -- Process unlinked check-ins
  FOR checkin_record IN 
    SELECT 
      cl.id,
      cl.event_id,
      cl.app_lat,
      cl.app_lon,
      w.category
    FROM checkin_logs cl
    INNER JOIN wristbands w ON cl.wristband_id = w.id
    WHERE cl.event_id = event_id_param
      AND cl.gate_id IS NULL
      AND cl.app_lat IS NOT NULL
      AND cl.app_lon IS NOT NULL
    ORDER BY cl.timestamp DESC
    LIMIT batch_limit
  LOOP
    processed := processed + 1;
    
    -- Find nearest gate
    SELECT g.id INTO nearby_gate_id
    FROM gates g
    INNER JOIN gate_bindings gb ON g.id = gb.gate_id
    WHERE g.event_id = checkin_record.event_id
      AND gb.category = checkin_record.category
      AND gb.status != 'unbound'
      AND g.latitude IS NOT NULL
      AND g.longitude IS NOT NULL
      AND haversine_distance(
        checkin_record.app_lat, 
        checkin_record.app_lon, 
        g.latitude, 
        g.longitude
      ) <= 50
    ORDER BY haversine_distance(
      checkin_record.app_lat, 
      checkin_record.app_lon, 
      g.latitude, 
      g.longitude
    ) ASC
    LIMIT 1;
    
    -- Update if gate found
    IF nearby_gate_id IS NOT NULL THEN
      UPDATE checkin_logs
      SET gate_id = nearby_gate_id
      WHERE id = checkin_record.id;
      
      UPDATE gate_bindings
      SET 
        sample_count = sample_count + 1,
        confidence = LEAST(1.0, confidence + 0.01)
      WHERE gate_id = nearby_gate_id
        AND category = checkin_record.category;
      
      linked := linked + 1;
    END IF;
  END LOOP;
  
  RETURN QUERY SELECT processed, linked;
END;
$$;

-- =========================================
-- Additional Utility Functions
-- =========================================

-- Get comprehensive event statistics
CREATE OR REPLACE FUNCTION get_event_stats_comprehensive(event_id_param uuid)
RETURNS TABLE (
  total_wristbands bigint,
  total_checkins bigint,
  unique_checkins bigint,
  linked_checkins bigint,
  unlinked_checkins bigint,
  total_gates bigint,
  active_gates bigint,
  categories_count bigint,
  avg_checkins_per_gate numeric
)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  WITH stats AS (
    SELECT 
      (SELECT COUNT(*) FROM wristbands WHERE event_id = event_id_param AND is_active = true) as total_wristbands,
      (SELECT COUNT(*) FROM checkin_logs WHERE event_id = event_id_param) as total_checkins,
      (SELECT COUNT(DISTINCT wristband_id) FROM checkin_logs WHERE event_id = event_id_param) as unique_checkins,
      (SELECT COUNT(*) FROM checkin_logs WHERE event_id = event_id_param AND gate_id IS NOT NULL) as linked_checkins,
      (SELECT COUNT(*) FROM checkin_logs WHERE event_id = event_id_param AND gate_id IS NULL) as unlinked_checkins,
      (SELECT COUNT(*) FROM gates WHERE event_id = event_id_param) as total_gates,
      (SELECT COUNT(DISTINCT gate_id) FROM checkin_logs WHERE event_id = event_id_param AND gate_id IS NOT NULL) as active_gates,
      (SELECT COUNT(DISTINCT category) FROM wristbands WHERE event_id = event_id_param AND is_active = true) as categories_count
  )
  SELECT 
    total_wristbands,
    total_checkins,
    unique_checkins,
    linked_checkins,
    unlinked_checkins,
    total_gates,
    active_gates,
    categories_count,
    CASE 
      WHEN active_gates > 0 THEN ROUND(linked_checkins::numeric / active_gates::numeric, 2)
      ELSE 0
    END as avg_checkins_per_gate
  FROM stats;
$$;

-- =========================================
-- Grant Permissions
-- =========================================

GRANT EXECUTE ON FUNCTION haversine_distance TO authenticated;
GRANT EXECUTE ON FUNCTION get_gate_scan_counts TO authenticated;
GRANT EXECUTE ON FUNCTION get_event_categories TO authenticated;
GRANT EXECUTE ON FUNCTION find_nearby_gates_by_category TO authenticated;
GRANT EXECUTE ON FUNCTION process_unlinked_checkins TO authenticated;
GRANT EXECUTE ON FUNCTION get_event_stats_comprehensive TO authenticated;

GRANT SELECT ON checkin_logs_with_category TO authenticated;
GRANT SELECT ON event_category_stats TO authenticated;
GRANT SELECT ON unlinked_checkins_with_category TO authenticated;

-- =========================================
-- Optional: Enable Auto-Link Trigger
-- =========================================
-- 
-- Uncomment the following lines to enable automatic gate linking
-- for new check-ins. This will process check-ins in real-time.
-- 
-- DROP TRIGGER IF EXISTS trigger_auto_link_checkin ON checkin_logs;
-- CREATE TRIGGER trigger_auto_link_checkin
--   BEFORE INSERT ON checkin_logs
--   FOR EACH ROW
--   EXECUTE FUNCTION auto_link_checkin_to_gate();

-- =========================================
-- Testing and Validation Queries
-- =========================================

/*
-- Test: Get categories for your event
SELECT * FROM get_event_categories('your-event-id');

-- Test: See unlinked check-ins with their categories
SELECT * FROM unlinked_checkins_with_category 
WHERE event_id = 'your-event-id'
LIMIT 10;

-- Test: Process unlinked check-ins
SELECT * FROM process_unlinked_checkins('your-event-id', 100);

-- Test: Category stats
SELECT * FROM event_category_stats 
WHERE event_id = 'your-event-id';

-- Test: Check-ins with full info
SELECT * FROM checkin_logs_with_category
WHERE event_id = 'your-event-id'
ORDER BY timestamp DESC
LIMIT 20;

-- Test: Comprehensive event stats
SELECT * FROM get_event_stats_comprehensive('your-event-id');

-- Test: Haversine distance function
SELECT haversine_distance(40.7128, -74.0060, 40.7589, -73.9851) as distance_meters;
*/
