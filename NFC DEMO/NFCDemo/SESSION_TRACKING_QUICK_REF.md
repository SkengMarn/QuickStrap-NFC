# Quick Reference: Web Portal Session Tracking

## Key Files & Locations

### Database Schema
- **active_sessions table**: `/supabase/migrations/20251006000000_phase1_foundation.sql` (lines 196-221)
- **resource_locks table**: `/supabase/migrations/20251006000000_phase1_foundation.sql` (lines 224-248)
- **collaboration_activity table**: `/supabase/migrations/20251006000000_phase1_foundation.sql` (lines 260-285)

### Services
- **presenceService**: `/src/services/presenceService.ts` - Session lifecycle (create, update, end, lock management)
- **secureSessionManager**: `/src/services/secureSessionManager.ts` - Secure session storage for browser/telegram (NOT YET IN DB)
- **auditLogger**: `/src/services/auditLogger.ts` - Security event logging
- **staffService**: `/src/services/staffService.ts` - Staff activity tracking

### UI Components
- **ActiveSessionsTable**: `/src/components/events/ActiveSessionsTable.tsx` - Real-time sessions display (562 lines)
- **LoggedInDevicesPage**: `/src/pages/LoggedInDevicesPage.tsx` - Devices dashboard

## Current Session Tracking Capabilities

| Feature | Status | Details |
|---------|--------|---------|
| **Active Sessions** | ✅ | Shows who's online, what they're viewing |
| **Device Detection** | ✅ | Desktop/mobile/tablet via User-Agent |
| **Organization Filtering** | ✅ | Multi-tenant ready |
| **Activity Tracking** | ✅ | last_activity_at timestamps |
| **Resource Viewing** | ✅ | Know who's looking at each event/gate |
| **Resource Locks** | ✅ | Prevent simultaneous editing |
| **Collaboration Feed** | ✅ | Comments, mentions, status changes |
| **App Type Detection** | ✅ | Web Portal vs iOS NFC App |
| **Audit Logging** | ✅ | Security events tracked |
| **Session Cleanup** | ✅ | Auto-cleanup of expired sessions |

## Critical Gap for NFC App Tracking

**Problem**: No explicit "app login" event is recorded. Sessions only appear after first navigation.

**Solution**: Add `app_logins` table to record:
- Login timestamp
- Device ID & model
- OS version
- App version
- Login method (credentials/biometric)
- Success/failure status
- IP address
- Geographic location

## Active Sessions Query

```sql
SELECT 
  as.id,
  u.email,
  p.full_name,
  as.device_type,
  as.current_route,
  as.last_activity_at,
  EXTRACT(EPOCH FROM (now() - as.session_started_at)) / 60 as session_minutes
FROM active_sessions as
JOIN auth.users u ON as.user_id = u.id
JOIN profiles p ON u.id = p.id
WHERE as.organization_id = $1
ORDER BY as.last_activity_at DESC;
```

## To Track NFC App Logins

1. **Create app_logins table** with fields for:
   - user_id, app_type ('ios_nfc', 'android_nfc'), app_version
   - device_id, device_model, os_version
   - login_at, logout_at, session_duration
   - login_status, failure_reason

2. **Create appLoginService** with methods:
   - recordAppLogin(data)
   - recordAppLogout(userId, appType)
   - getAppLoginHistory(userId)
   - getLoginStats(appType)

3. **Update NFC App** to:
   - Call API endpoint after successful login
   - Send device info (ID, model, OS)
   - Call logout endpoint on app exit

4. **Build Analytics Dashboard** showing:
   - Active app sessions by type
   - Device/OS distribution
   - Failed login attempts
   - Geographic distribution
   - Session duration trends

## App Detection Current Logic

```typescript
// In ActiveSessionsTable.tsx
if (ua.includes('quickstrap') || ua.includes('nfc-scanner')) {
  return 'iOS NFC App';
} 
if (route.includes('dashboard') || route.includes('events')) {
  return 'Web Portal';
}
return 'Unknown';
```

**Improvement Needed**: Consistent User-Agent from NFC app like:
- `QuickStrap-iOS/1.0 (iPhone; OS 17.0)`
- `QuickStrap-Android/1.0 (Pixel 8; Android 14)`

## Database Schema Preview

```sql
CREATE TABLE public.app_logins (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id),
  app_type text NOT NULL, -- 'ios_nfc', 'android_nfc', 'web_portal'
  app_version text,
  device_id text,
  device_model text,
  os_version text,
  login_at timestamptz DEFAULT now(),
  logout_at timestamptz,
  session_duration_seconds integer,
  login_status text DEFAULT 'success',
  failure_reason text,
  ip_address text,
  country text,
  metadata jsonb DEFAULT '{}',
  organization_id uuid NOT NULL,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX idx_app_logins_user ON app_logins(user_id);
CREATE INDEX idx_app_logins_app_type ON app_logins(app_type);
CREATE INDEX idx_app_logins_login_at ON app_logins(login_at);
CREATE INDEX idx_app_logins_device ON app_logins(device_id);
```

## Implementation Timeline

- **Day 1-2**: Design review, create migration
- **Day 3-5**: Build appLoginService, create API endpoint, add RLS policies
- **Day 6-7**: Update NFC app to send login/logout events
- **Week 2**: Build analytics dashboard, add geographic tracking
- **Week 3**: ML anomaly detection, risk scoring

## Security Checklist

- [ ] RLS policies for app_logins (organization isolation)
- [ ] IP address logging - GDPR compliant? 
- [ ] Device ID logging - user consent needed?
- [ ] Rate limiting on login endpoint
- [ ] Failed login attempt alerting
- [ ] Session timeout configuration per org
- [ ] Encryption for sensitive fields (ip_address, device_id)

## Testing Queries

```sql
-- Active sessions right now
SELECT COUNT(*) FROM active_sessions 
WHERE last_activity_at > now() - interval '5 minutes';

-- App logins today
SELECT app_type, COUNT(*) FROM app_logins 
WHERE login_at > now() - interval '1 day'
GROUP BY app_type;

-- Failed logins
SELECT COUNT(*), failure_reason FROM app_logins
WHERE login_status = 'failed' 
  AND login_at > now() - interval '24 hours'
GROUP BY failure_reason;

-- Most common devices
SELECT device_model, COUNT(*) as login_count
FROM app_logins
WHERE login_at > now() - interval '30 days'
GROUP BY device_model
ORDER BY login_count DESC
LIMIT 10;
```

## Related Documentation

- See full analysis: `SESSION_TRACKING_ANALYSIS.md`
- Supabase Realtime docs: https://supabase.com/docs/guides/realtime
- Row Level Security: https://supabase.com/docs/guides/auth/row-level-security

