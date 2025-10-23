# Security Setup Guide

## Overview
This document outlines the security measures and setup required for the NFC Event Management app.

## Database Setup

### 1. Profile Creation Trigger

The app requires users to have profiles in the `profiles` table. Run the SQL in `Database/create_profile_trigger.sql` to:

- Automatically create profiles for new users
- Backfill profiles for existing users
- Set default roles

```bash
# Run in Supabase SQL Editor
psql -f Database/create_profile_trigger.sql
```

### 2. Row Level Security (RLS)

Ensure RLS is enabled on all tables:

```sql
-- Enable RLS on profiles table
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- Users can read their own profile
CREATE POLICY "Users can read own profile"
ON profiles FOR SELECT
USING (auth.uid() = id);

-- Only admins can update roles
CREATE POLICY "Admins can update profiles"
ON profiles FOR UPDATE
USING (
  EXISTS (
    SELECT 1 FROM profiles
    WHERE id = auth.uid() AND role = 'admin'
  )
);
```

### 3. Admin User Setup

**NEVER hardcode user credentials or IDs in the app.**

To grant admin access:

1. User signs up normally through the app
2. Database admin runs SQL to grant admin role:

```sql
-- Grant admin role to specific user
UPDATE profiles 
SET role = 'admin', updated_at = NOW()
WHERE email = 'admin@example.com';
```

## Security Best Practices

### ✅ DO:
- Use environment variables for API keys
- Store tokens in iOS Keychain
- Use parameterized queries
- Enable RLS on all tables
- Log security events (without sensitive data)
- Use HTTPS for all API calls
- Implement certificate pinning
- Validate JWT tokens
- Use refresh tokens

### ❌ DON'T:
- Hardcode user IDs or emails
- Log sensitive data (passwords, tokens, PII)
- Store tokens in UserDefaults (use Keychain)
- Expose API keys in source code
- Trust client-side role checks (always verify server-side)
- Log full error messages in production

## Token Management

### Access Tokens
- Stored in iOS Keychain via `SecureTokenStorage`
- Validated before each API request
- Automatically refreshed when expired

### Refresh Tokens
- Stored in iOS Keychain
- Used to obtain new access tokens
- Rotated on each refresh

## Logging

### Production Logging
```swift
#if DEBUG
print("Debug info: \(sensitiveData)")
#endif
// Production logs never include sensitive data
print("Operation completed successfully")
```

### Security Events to Log
- Authentication attempts (success/failure)
- Token refresh events
- Permission denied errors
- Invalid token attempts

### Never Log
- Passwords
- Full tokens (only first/last few chars for debugging)
- User emails in production
- Personal information
- Database credentials

## API Security

### Certificate Pinning
Implemented in `CertificatePinner.swift` to prevent MITM attacks.

### Request Authentication
All API requests include:
- Bearer token in Authorization header
- API key in apikey header
- Content-Type validation

## User Roles

### Admin
- Can see all events
- Can manage all wristbands
- Can view all analytics
- Can manage gates

### Owner
- Can see assigned events
- Can manage event wristbands
- Can view event analytics
- Can manage event gates

### Scanner
- Can see assigned events
- Can scan wristbands
- Limited analytics access
- No management permissions

## Emergency Procedures

### Compromised Token
1. User signs out (invalidates local tokens)
2. Admin revokes refresh token in Supabase
3. User must sign in again

### Compromised API Key
1. Rotate API key in Supabase dashboard
2. Update app configuration
3. Force app update for all users

### Data Breach
1. Notify affected users
2. Force password reset
3. Audit access logs
4. Review RLS policies

## Compliance

### Data Protection
- User data encrypted at rest (Supabase)
- Tokens encrypted in Keychain
- TLS 1.3 for all network traffic
- Certificate pinning enabled

### Access Control
- Role-based access control (RBAC)
- Row-level security (RLS)
- Event-based permissions
- Audit logging

## Testing Security

### Checklist
- [ ] RLS enabled on all tables
- [ ] Profile trigger working
- [ ] Token refresh working
- [ ] Certificate pinning active
- [ ] No hardcoded credentials
- [ ] No sensitive data in logs
- [ ] Keychain storage working
- [ ] Admin role enforcement working
- [ ] Event access control working

## Support

For security issues, contact the development team immediately.
**Do not post security issues in public forums or repositories.**
