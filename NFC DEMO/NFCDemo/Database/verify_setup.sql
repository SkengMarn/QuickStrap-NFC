-- =====================================================
-- Verification Queries
-- Run these to confirm your setup is working
-- =====================================================

-- 1. Check your profile
SELECT 
  id,
  email,
  role,
  full_name,
  phone,
  created_at,
  updated_at,
  last_sign_in
FROM profiles 
WHERE email = 'jayssemujju@gmail.com';

-- Expected result: Should show your profile with role = 'admin'

-- 2. Check how many events exist
SELECT COUNT(*) as total_events FROM events;

-- Expected result: Should show the number of events in your database

-- 3. Check profile creation logs
SELECT 
  created_at,
  email,
  success,
  metadata->>'role' as role,
  metadata->>'full_name' as full_name
FROM profile_creation_log
ORDER BY created_at DESC
LIMIT 10;

-- Expected result: Should show recent profile creation activity

-- 4. Check for any errors
SELECT * FROM public.get_profile_creation_errors(10);

-- Expected result: Should be empty if everything worked

-- 5. Verify triggers are active
SELECT 
  tgname as trigger_name,
  tgenabled as enabled,
  tgrelid::regclass as table_name
FROM pg_trigger 
WHERE tgname IN ('on_auth_user_created', 'on_auth_user_signin');

-- Expected result: Both triggers should show as enabled

-- =====================================================
-- All checks passed? You're ready to test the app!
-- =====================================================
-- Next steps:
-- 1. Open the iOS app
-- 2. Sign out (if already signed in)
-- 3. Sign back in with: jayssemujju@gmail.com
-- 4. You should now see all events!
-- =====================================================
