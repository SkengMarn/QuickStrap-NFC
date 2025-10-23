# Database Setup Instructions

## Quick Start

### Step 1: Run the Enhanced Profile System

Open Supabase SQL Editor and run the entire `create_profile_trigger.sql` file.

This will:
- ✅ Create the `profile_creation_log` audit table
- ✅ Set up automatic profile creation for new signups
- ✅ Create profiles for all existing users (backfill)
- ✅ Set up sign-in tracking
- ✅ Create helper functions for role management

### Step 2: Grant Admin Access

After running the setup, grant yourself admin access:

```sql
-- Option 1: Using the helper function (recommended)
SELECT public.grant_admin_role('your-email@example.com');

-- Option 2: Direct SQL
UPDATE profiles 
SET role = 'admin', updated_at = NOW()
WHERE email = 'your-email@example.com';
```

### Step 3: Verify Setup

Check that everything worked:

```sql
-- View your profile
SELECT id, email, role, full_name, last_sign_in 
FROM profiles 
WHERE email = 'your-email@example.com';

-- Check backfill results
SELECT * FROM profile_creation_log 
WHERE email = 'BACKFILL_OPERATION';

-- View any errors
SELECT * FROM public.get_profile_creation_errors(10);
```

### Step 4: Sign Out and Back In

1. Open the iOS app
2. Sign out
3. Sign back in
4. You should now see all events!

## Features

### Automatic Profile Creation
- New users automatically get profiles when they sign up
- Default role: `scanner`
- Extracts full name from signup metadata
- Handles errors gracefully without breaking signup

### Sign-In Tracking
- `last_sign_in` timestamp updated automatically
- Useful for user activity monitoring
- No app changes needed

### Audit Logging
- All profile creation attempts logged
- Success and failure tracking
- Detailed error messages for troubleshooting

### Helper Functions

#### Grant Admin Role
```sql
SELECT public.grant_admin_role('user@example.com');
```

#### Revoke Admin Role
```sql
SELECT public.revoke_admin_role('user@example.com');
```

#### View Profile Creation Errors
```sql
SELECT * FROM public.get_profile_creation_errors(25);
```

#### View All Logs
```sql
SELECT * FROM profile_creation_log 
ORDER BY created_at DESC 
LIMIT 100;
```

## Troubleshooting

### "No events found" in app

**Check 1: Profile exists?**
```sql
SELECT * FROM profiles WHERE email = 'your-email@example.com';
```

**Check 2: Role is admin?**
```sql
SELECT email, role FROM profiles WHERE email = 'your-email@example.com';
```

**Check 3: Events exist in database?**
```sql
SELECT COUNT(*) FROM events;
```

### Profile not created automatically

**Check trigger is active:**
```sql
SELECT tgname, tgenabled 
FROM pg_trigger 
WHERE tgname = 'on_auth_user_created';
```

**Check for errors:**
```sql
SELECT * FROM public.get_profile_creation_errors(10);
```

### Can't grant admin role

**Verify user exists:**
```sql
SELECT id, email FROM auth.users WHERE email = 'user@example.com';
SELECT id, email FROM profiles WHERE email = 'user@example.com';
```

**If profile missing, create manually:**
```sql
INSERT INTO profiles (id, email, role, full_name, created_at, updated_at)
SELECT id, email, 'admin', email, created_at, NOW()
FROM auth.users
WHERE email = 'user@example.com'
ON CONFLICT (id) DO UPDATE SET role = 'admin';
```

## Security Notes

- ✅ All functions use `SECURITY DEFINER` with `search_path = public`
- ✅ No user input directly in SQL (parameterized)
- ✅ Error handling prevents signup failures
- ✅ Audit logging for compliance
- ✅ Role changes tracked with timestamps

## Database Schema

### profiles table
```sql
- id: uuid (primary key, matches auth.users.id)
- email: text (unique)
- role: text (admin, owner, scanner)
- full_name: text
- phone: text (optional)
- created_at: timestamp
- updated_at: timestamp
- last_sign_in: timestamp (optional)
```

### profile_creation_log table
```sql
- id: uuid (primary key)
- user_id: uuid
- email: text
- success: boolean
- error_message: text (optional)
- metadata: jsonb
- created_at: timestamp
```

## Maintenance

### View Recent Activity
```sql
SELECT 
  email,
  role,
  last_sign_in,
  updated_at
FROM profiles
WHERE last_sign_in > NOW() - INTERVAL '7 days'
ORDER BY last_sign_in DESC;
```

### Clean Old Logs (optional)
```sql
DELETE FROM profile_creation_log
WHERE created_at < NOW() - INTERVAL '90 days';
```

### Bulk Role Updates
```sql
-- Promote all owners to admin
UPDATE profiles 
SET role = 'admin', updated_at = NOW()
WHERE role = 'owner';
```

## Support

If you encounter issues:
1. Check the audit logs: `SELECT * FROM public.get_profile_creation_errors()`
2. Verify triggers are enabled
3. Check RLS policies aren't blocking access
4. Review app console logs for detailed errors
