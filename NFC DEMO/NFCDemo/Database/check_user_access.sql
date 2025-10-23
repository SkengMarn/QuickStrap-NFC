-- =====================================================
-- User Access Verification Queries
-- =====================================================
-- Check what events a user has access to and their roles
-- =====================================================

-- 1. Get user's global role from profiles table
SELECT 
  email,
  role as global_role,
  full_name,
  created_at,
  last_sign_in
FROM profiles 
WHERE email = 'jayssemujju@gmail.com';

-- Expected: Should show role = 'admin'
-- Note: Admins can see ALL events regardless of event_access table

-- =====================================================

-- 2. Check event_access table for specific event permissions
SELECT 
  ea.event_id,
  e.name as event_name,
  ea.access_level,
  ea.granted_at,
  ea.granted_by
FROM event_access ea
JOIN events e ON e.id = ea.event_id
JOIN profiles p ON p.id = ea.user_id
WHERE p.email = 'jayssemujju@gmail.com'
ORDER BY ea.granted_at DESC;

-- Expected: May be empty if you're only using global admin role
-- This table is for granular per-event permissions

-- =====================================================

-- 3. Get user ID for reference
SELECT 
  au.id as auth_user_id,
  au.email,
  p.role as profile_role
FROM auth.users au
LEFT JOIN profiles p ON p.id = au.id
WHERE au.email = 'jayssemujju@gmail.com';

-- =====================================================

-- 4. Check ALL events in database (what admin can see)
SELECT 
  id,
  name,
  location,
  start_date,
  end_date,
  created_by,
  ticket_linking_mode
FROM events
ORDER BY start_date DESC;

-- Expected: All events in the system
-- As admin, you should see all of these in the app

-- =====================================================

-- 5. Detailed access breakdown by role type
WITH user_info AS (
  SELECT id, email, role 
  FROM profiles 
  WHERE email = 'jayssemujju@gmail.com'
)
SELECT 
  ui.email,
  ui.role as global_role,
  CASE 
    WHEN ui.role = 'admin' THEN 'ALL EVENTS (Admin has full access)'
    WHEN ui.role = 'owner' THEN 'Events via event_access table'
    WHEN ui.role = 'scanner' THEN 'Events via event_access table'
    ELSE 'No access'
  END as access_type,
  (SELECT COUNT(*) FROM events) as total_events_in_db,
  (SELECT COUNT(*) FROM event_access WHERE user_id = ui.id) as explicit_event_grants
FROM user_info ui;

-- =====================================================

-- 6. If you want to grant specific event access (for non-admins)
-- Uncomment and modify as needed:

/*
INSERT INTO event_access (user_id, event_id, access_level, granted_by)
SELECT 
  p.id as user_id,
  e.id as event_id,
  'full' as access_level,  -- Options: 'full', 'read_only', 'scan_only'
  (SELECT id FROM profiles WHERE role = 'admin' LIMIT 1) as granted_by
FROM profiles p
CROSS JOIN events e
WHERE p.email = 'jayssemujju@gmail.com'
  AND e.name = 'Your Event Name Here'
ON CONFLICT (user_id, event_id) DO NOTHING;
*/

-- =====================================================

-- 7. View access levels explanation
SELECT 
  'admin' as role,
  'Can see ALL events, manage everything' as permissions
UNION ALL
SELECT 
  'owner' as role,
  'Can see events granted in event_access table, full event management' as permissions
UNION ALL
SELECT 
  'scanner' as role,
  'Can see events granted in event_access table, scan wristbands only' as permissions;

-- =====================================================
-- Summary
-- =====================================================
-- Global Roles (profiles.role):
--   - admin: Full access to ALL events (bypasses event_access)
--   - owner: Access to specific events via event_access table
--   - scanner: Access to specific events via event_access table
--
-- Event Access Levels (event_access.access_level):
--   - full: Can manage event, scan, view analytics
--   - read_only: Can view event data only
--   - scan_only: Can only scan wristbands
--
-- Current Setup:
--   - jayssemujju@gmail.com has role = 'admin'
--   - Therefore: Can see ALL events without event_access entries
--   - The app checks: if (role == admin) { fetch all events }
-- =====================================================
