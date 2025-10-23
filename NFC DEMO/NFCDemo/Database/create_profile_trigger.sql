-- =====================================================
-- Enhanced Automatic Profile Creation System
-- =====================================================
-- Features:
-- - Automatic profile creation with error handling
-- - Audit logging for troubleshooting
-- - Safe handling of metadata
-- - Updated timestamp management
-- =====================================================

-- Create audit log table for profile creation events
CREATE TABLE IF NOT EXISTS public.profile_creation_log (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id uuid NOT NULL,
  email text,
  success boolean DEFAULT true,
  error_message text,
  metadata jsonb,
  created_at timestamp with time zone DEFAULT now()
);

-- Enhanced function to handle new user creation
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER 
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  user_full_name text;
  user_role text := 'scanner';
BEGIN
  -- Safely extract full name from metadata
  BEGIN
    user_full_name := COALESCE(
      NEW.raw_user_meta_data->>'full_name',
      NEW.raw_user_meta_data->>'name',
      SPLIT_PART(NEW.email, '@', 1) -- Fallback to email username
    );
  EXCEPTION WHEN OTHERS THEN
    user_full_name := SPLIT_PART(NEW.email, '@', 1);
  END;

  -- Check if user should be admin based on metadata
  IF (NEW.raw_user_meta_data->>'role' = 'admin') THEN
    user_role := 'admin';
  END IF;

  -- Insert profile with conflict handling
  BEGIN
    INSERT INTO public.profiles (
      id, 
      email, 
      role, 
      full_name, 
      phone,
      created_at, 
      updated_at,
      last_sign_in
    )
    VALUES (
      NEW.id,
      NEW.email,
      user_role,
      user_full_name,
      NEW.raw_user_meta_data->>'phone',
      NOW(),
      NOW(),
      NEW.last_sign_in_at
    )
    ON CONFLICT (id) DO UPDATE SET
      email = EXCLUDED.email,
      updated_at = NOW(),
      last_sign_in = EXCLUDED.last_sign_in;

    -- Log successful profile creation
    INSERT INTO public.profile_creation_log (
      user_id,
      email,
      success,
      metadata
    ) VALUES (
      NEW.id,
      NEW.email,
      true,
      jsonb_build_object(
        'role', user_role,
        'full_name', user_full_name,
        'trigger_time', NOW()
      )
    );

  EXCEPTION WHEN OTHERS THEN
    -- Log failed profile creation
    INSERT INTO public.profile_creation_log (
      user_id,
      email,
      success,
      error_message,
      metadata
    ) VALUES (
      NEW.id,
      NEW.email,
      false,
      SQLERRM,
      jsonb_build_object(
        'error_detail', SQLSTATE,
        'trigger_time', NOW()
      )
    );
    
    -- Don't fail the auth.users insert if profile creation fails
    RAISE WARNING 'Profile creation failed for user %: %', NEW.id, SQLERRM;
  END;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop and recreate trigger
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- =====================================================
-- Trigger for updating last_sign_in timestamp
-- =====================================================

CREATE OR REPLACE FUNCTION public.handle_user_signin()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Update last_sign_in when user logs in
  IF NEW.last_sign_in_at IS DISTINCT FROM OLD.last_sign_in_at THEN
    UPDATE public.profiles
    SET 
      last_sign_in = NEW.last_sign_in_at,
      updated_at = NOW()
    WHERE id = NEW.id;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop and create signin trigger
DROP TRIGGER IF EXISTS on_auth_user_signin ON auth.users;

CREATE TRIGGER on_auth_user_signin
  AFTER UPDATE ON auth.users
  FOR EACH ROW
  WHEN (NEW.last_sign_in_at IS DISTINCT FROM OLD.last_sign_in_at)
  EXECUTE FUNCTION public.handle_user_signin();

-- =====================================================
-- Backfill Profiles for Existing Users
-- =====================================================

DO $$
DECLARE
  inserted_count integer := 0;
  failed_count integer := 0;
BEGIN
  -- Create profiles for existing auth users
  WITH inserted_profiles AS (
    INSERT INTO public.profiles (id, email, role, full_name, phone, created_at, updated_at, last_sign_in)
    SELECT 
      au.id,
      au.email,
      'scanner' as role,
      COALESCE(
        au.raw_user_meta_data->>'full_name',
        au.raw_user_meta_data->>'name',
        SPLIT_PART(au.email, '@', 1)
      ) as full_name,
      au.raw_user_meta_data->>'phone' as phone,
      au.created_at,
      NOW() as updated_at,
      au.last_sign_in_at as last_sign_in
    FROM auth.users au
    WHERE au.id NOT IN (SELECT id FROM public.profiles)
    ON CONFLICT (id) DO NOTHING
    RETURNING id
  )
  SELECT COUNT(*) INTO inserted_count FROM inserted_profiles;

  RAISE NOTICE 'Backfilled % profile(s) for existing users', inserted_count;
  
  -- Log the backfill operation
  INSERT INTO public.profile_creation_log (
    user_id,
    email,
    success,
    metadata
  ) 
  SELECT 
    id,
    'BACKFILL_OPERATION',
    true,
    jsonb_build_object(
      'operation', 'backfill',
      'count', inserted_count,
      'timestamp', NOW()
    )
  FROM (SELECT gen_random_uuid() as id) t;
  
END $$;

-- =====================================================
-- Helper Functions
-- =====================================================

-- Function to grant admin role to a user
CREATE OR REPLACE FUNCTION public.grant_admin_role(user_email text)
RETURNS boolean
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  updated_count integer;
BEGIN
  UPDATE public.profiles 
  SET 
    role = 'admin',
    updated_at = NOW()
  WHERE email = user_email;
  
  GET DIAGNOSTICS updated_count = ROW_COUNT;
  
  IF updated_count > 0 THEN
    RAISE NOTICE 'Granted admin role to user: %', user_email;
    RETURN true;
  ELSE
    RAISE NOTICE 'User not found: %', user_email;
    RETURN false;
  END IF;
END;
$$ LANGUAGE plpgsql;

-- Function to revoke admin role
CREATE OR REPLACE FUNCTION public.revoke_admin_role(user_email text)
RETURNS boolean
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  updated_count integer;
BEGIN
  UPDATE public.profiles 
  SET 
    role = 'scanner',
    updated_at = NOW()
  WHERE email = user_email;
  
  GET DIAGNOSTICS updated_count = ROW_COUNT;
  
  IF updated_count > 0 THEN
    RAISE NOTICE 'Revoked admin role from user: %', user_email;
    RETURN true;
  ELSE
    RAISE NOTICE 'User not found: %', user_email;
    RETURN false;
  END IF;
END;
$$ LANGUAGE plpgsql;

-- Function to view profile creation errors
CREATE OR REPLACE FUNCTION public.get_profile_creation_errors(limit_count integer DEFAULT 50)
RETURNS TABLE (
  created_at timestamp with time zone,
  user_id uuid,
  email text,
  error_message text
)
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    pcl.created_at,
    pcl.user_id,
    pcl.email,
    pcl.error_message
  FROM public.profile_creation_log pcl
  WHERE pcl.success = false
  ORDER BY pcl.created_at DESC
  LIMIT limit_count;
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- Usage Examples
-- =====================================================
-- Grant admin role:
-- SELECT public.grant_admin_role('admin@example.com');

-- Revoke admin role:
-- SELECT public.revoke_admin_role('user@example.com');

-- View recent profile creation errors:
-- SELECT * FROM public.get_profile_creation_errors(25);

-- View all profile creation logs:
-- SELECT * FROM public.profile_creation_log ORDER BY created_at DESC LIMIT 100;
-- =====================================================
