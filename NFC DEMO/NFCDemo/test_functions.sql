-- Test script to verify enhanced functions are deployed
-- Run this in Supabase Dashboard SQL Editor

-- Test 1: Haversine distance function
SELECT 'Testing haversine_distance function...' as test;
SELECT haversine_distance(40.7128, -74.0060, 40.7589, -73.9851) as distance_meters;

-- Test 2: Check if functions exist
SELECT 'Checking if functions exist...' as test;
SELECT routine_name, routine_type 
FROM information_schema.routines 
WHERE routine_schema = 'public' 
AND (routine_name LIKE '%gate%' OR routine_name LIKE '%event%' OR routine_name = 'haversine_distance')
ORDER BY routine_name;

-- Test 3: Check if views exist
SELECT 'Checking if views exist...' as test;
SELECT table_name, table_type
FROM information_schema.tables 
WHERE table_schema = 'public' 
AND table_type = 'VIEW'
AND (table_name LIKE '%checkin%' OR table_name LIKE '%category%' OR table_name LIKE '%unlinked%')
ORDER BY table_name;

-- Test 4: Test with sample data (replace with your actual event ID)
-- SELECT 'Testing with sample data...' as test;
-- SELECT * FROM get_event_categories('your-actual-event-id-here') LIMIT 5;

-- Test 5: Check permissions
SELECT 'Checking function permissions...' as test;
SELECT routine_name, specific_name
FROM information_schema.routine_privileges 
WHERE routine_schema = 'public' 
AND grantee = 'authenticated'
AND (routine_name LIKE '%gate%' OR routine_name LIKE '%event%' OR routine_name = 'haversine_distance')
ORDER BY routine_name;
