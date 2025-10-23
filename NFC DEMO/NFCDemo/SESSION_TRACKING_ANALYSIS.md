# Web Portal Session Tracking & Authentication Analysis
**Quickstrap NFC Web Portal**  
**Analysis Date:** October 20, 2025

---

## Executive Summary

The web portal has a **robust multi-layer session tracking system** designed to:
1. Monitor active user sessions across web portal and mobile apps
2. Track real-time user presence and location within the portal
3. Manage resource locks to prevent simultaneous editing conflicts
4. Log collaboration activity and user mentions
5. Support both regular authenticated sessions and Telegram bot sessions

The current system is **ready to be extended** to track NFC app logins with minimal architectural changes.

---

## 1. Current Session Tracking Architecture

### 1.1 Database Tables Structure

#### **active_sessions** (Primary Session Tracking)
**Location:** `/Users/jew/Desktop/quickstrap_nfc_web/supabase/migrations/20251006000000_phase1_foundation.sql` (lines 196-221)

```sql
CREATE TABLE public.active_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  organization_id uuid REFERENCES organizations(id) ON DELETE CASCADE,
  
  -- Location tracking
  current_route text,                    -- Portal route (e.g., '/events/123')
  current_resource_type text,            -- 'event', 'gate', 'wristband'
  current_resource_id uuid,              -- ID of resource being viewed
  
  -- Device information
  ip_address text,
  user_agent text,
  device_type text,                      -- 'desktop', 'mobile', 'tablet'
  
  -- Activity tracking
  last_activity_at timestamptz DEFAULT now(),
  session_started_at timestamptz DEFAULT now(),
  
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Indexes for performance
CREATE INDEX idx_active_sessions_user ON public.active_sessions(user_id);
CREATE INDEX idx_active_sessions_resource ON public.active_sessions(current_resource_type, current_resource_id);
CREATE INDEX idx_active_sessions_last_activity ON public.active_sessions(last_activity_at);
```

**Key Features:**
- Tracks which portal view/resource each user is currently viewing
- Records device type automatically via User-Agent parsing
- Automatically timestamps last activity
- Supports organization-level session visibility
- Indexes optimized for "who's looking at this resource" queries

#### **resource_locks** (Concurrent Edit Prevention)
**Location:** Lines 224-248

```sql
CREATE TABLE public.resource_locks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  resource_type text NOT NULL,
  resource_id uuid NOT NULL,
  
  locked_by_user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  locked_by_session_id uuid REFERENCES active_sessions(id) ON DELETE CASCADE,
  
  lock_reason text DEFAULT 'editing',
  acquired_at timestamptz DEFAULT now(),
  expires_at timestamptz DEFAULT (now() + interval '15 minutes'),
  
  metadata jsonb DEFAULT '{}',
  created_at timestamptz DEFAULT now(),
  
  UNIQUE(resource_type, resource_id)  -- Only one lock per resource
);
```

**Purpose:** Prevents two users from editing the same resource simultaneously

#### **collaboration_activity** (User Actions Log)
**Location:** Lines 260-285

```sql
CREATE TABLE public.collaboration_activity (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid REFERENCES organizations(id) ON DELETE CASCADE,
  
  activity_type text NOT NULL,        -- 'comment', 'mention', 'edit', 'status_change'
  resource_type text NOT NULL,
  resource_id uuid NOT NULL,
  
  user_id uuid NOT NULL REFERENCES auth.users(id),
  content text,
  mentions uuid[],                     -- Array of @mentioned user IDs
  metadata jsonb DEFAULT '{}',
  
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
```

**Purpose:** Tracks what actions users performed on resources

#### **user_sessions & telegram_sessions** (Planned Tables)
**Referenced in:** `/Users/jew/Desktop/quickstrap_nfc_web/src/services/secureSessionManager.ts` (lines 67-68, 114-115)

These tables are **referenced by the SecureSessionManager service** but do **NOT YET exist** in the database. They're intended for:
- **user_sessions**: Secure browser-based sessions with 24-hour TTL
- **telegram_sessions**: Telegram bot user sessions

Schema inferred from code:
```typescript
interface SessionData {
  user_id: string;
  session_id: string;          // Cryptographically secure 256-bit ID
  created_at: string;
  expires_at: string;          // 24 hours from creation
  ip_address?: string;
  user_agent?: string;
  metadata?: Record<string, any>;
  is_active: boolean;          // Soft delete flag
  invalidated_at?: string;     // When session was ended
}

interface TelegramSession extends SessionData {
  telegram_user_id: number;
  username?: string;
  chat_id?: number;
  platform: 'telegram';        // In metadata
}
```

---

### 1.2 Session Management Services

#### **presenceService** 
**File:** `/Users/jew/Desktop/quickstrap_nfc_web/src/services/presenceService.ts`

**Active Session Management Functions:**

```typescript
// Create/update session when user navigates
updateSession(location: {
  route: string;
  resourceType?: string;
  resourceId?: string;
}): Promise<ActiveSession>

// Retrieve all active users in organization
getOrganizationSessions(organizationId: string): Promise<ActiveSession[]>
// Filters: active in last 15 minutes

// Find who's currently viewing a specific resource
getResourceViewers(resourceType: string, resourceId: string): Promise<ActiveSession[]>
// Filters: active in last 5 minutes

// End session on logout
endSession(): Promise<void>
```

**Device Detection Logic:**
```typescript
getDeviceType(): string {
  const ua = navigator.userAgent;
  if (/tablet|ipad|playbook|silk/i.test(ua)) return 'tablet';
  if (/mobile|iphone|ipod|android|blackberry|opera mini|opera mobi/i.test(ua)) return 'mobile';
  return 'desktop';
}
```

**Activity Filtering:**
- Active: Last activity < 5 minutes
- Idle: Last activity 5-15 minutes ago  
- Inactive: Last activity > 15 minutes ago

#### **secureSessionManager**
**File:** `/Users/jew/Desktop/quickstrap_nfc_web/src/services/secureSessionManager.ts`

**Features:**
```typescript
createSession(userId, ipAddress?, userAgent?, metadata?): Promise<string>
  // Returns cryptographically secure session ID
  // Stores in user_sessions table
  // 24-hour TTL

validateSession(sessionId, ipAddress?): Promise<SessionData | null>
  // Validates and refreshes session
  // Optional IP address verification
  // Auto-extends expiry on valid validation

invalidateSession(sessionId): Promise<void>
  // Soft delete (sets is_active = false)

invalidateAllUserSessions(userId): Promise<void>
  // Logout all devices for a user

cleanupExpiredSessions(): Promise<void>
  // Runs every 1 hour automatically
  // Invalidates sessions past TTL

getSessionStats(): Promise<{
  totalActive: number;
  totalTelegramActive: number;
  expiredToday: number;
}>
```

**Security Features:**
- 256-bit cryptographically random session IDs
- Optional IP address checking
- Session timeout: 24 hours
- Automatic cleanup of expired sessions (hourly)
- Batch session invalidation capability

#### **auditLogger**
**File:** `/Users/jew/Desktop/quickstrap_nfc_web/src/services/auditLogger.ts`

Logs authentication and authorization events:
```typescript
interface AuditEvent {
  event_type: string;
  event_category: 'authentication' | 'authorization' | 'data_access' | 'data_modification' | 'system' | 'security';
  severity: 'low' | 'medium' | 'high' | 'critical';
  description: string;
  resource_type?: string;
  resource_id?: string;
  ip_address?: string;
  user_agent?: string;
  success: boolean;
}

logEvent(event): Promise<void>
logSecurityEvent(event): Promise<void>
```

---

### 1.3 Frontend Session Tracking

#### **ActiveSessionsTable Component**
**File:** `/Users/jew/Desktop/quickstrap_nfc_web/src/components/events/ActiveSessionsTable.tsx` (562 lines)

**Features:**
- Real-time active sessions display
- Auto-refresh capability (10s, 30s, 1m, 5m intervals)
- Per-session details including:
  - User info (name, email, role, phone)
  - Device type (mobile/tablet/desktop)
  - Browser & OS detection
  - App type detection (Web Portal vs iOS NFC App)
  - Current route/activity
  - IP address
  - Session duration
  - Last activity time

**App Detection Logic:**
```typescript
getAppType(currentRoute: string | null, userAgent: string | null) {
  // iOS NFC App detection
  if (ua.includes('quickstrap') || ua.includes('nfc-scanner')) {
    return { type: 'iOS NFC App', color: 'text-blue-600 bg-blue-50' };
  }
  
  // Web Portal detection
  if (route.includes('dashboard') || route.includes('events') || route.includes('portal')) {
    return { type: 'Web Portal', color: 'text-green-600 bg-green-50' };
  }
  
  return { type: 'Unknown' };
}
```

#### **LoggedInDevicesPage**
**File:** `/Users/jew/Desktop/quickstrap_nfc_web/src/pages/LoggedInDevicesPage.tsx` (145 lines)

Dashboard showing:
- Total sessions count
- Unique users count
- Web portal sessions
- Mobile app sessions
- Auto-refresh settings
- Session status legends (Active/Idle/Inactive)

---

### 1.4 Authentication Flow

**Login Flow:**
1. User enters credentials on LoginPage (`/src/pages/LoginPage.tsx`)
2. Rate limiting applied via `rateLimiter` service
3. Supabase `auth.signInWithPassword()` called
4. On success, `onAuthStateChange` listener triggers in App.tsx
5. Session state updated in React component
6. User redirected to Dashboard

**Session Creation Timing:**
- Currently: Sessions are created in `presenceService.updateSession()` when user navigates
- Triggered by route changes or manual update calls
- NOT automatically created on login

**Current Gap:** No explicit "login recorded" event in active_sessions. Sessions only appear when user navigates to a route.

---

## 2. Key Findings for App Login Tracking

### 2.1 What's Already in Place

| Component | Status | Readiness |
|-----------|--------|-----------|
| **active_sessions table** | ✅ Exists | Ready to use |
| **Session creation logic** | ✅ Implemented | In presenceService |
| **Device type detection** | ✅ Implemented | Via User-Agent parsing |
| **Organization filtering** | ✅ Implemented | Full multi-tenant support |
| **Activity tracking** | ✅ Implemented | last_activity_at updates |
| **Resource lock system** | ✅ Implemented | Prevents edit conflicts |
| **Audit logging** | ✅ Implemented | In auditLogger service |
| **Session cleanup** | ✅ Implemented | Auto-cleanup in secureSessionManager |

### 2.2 What Needs to Be Built

To track NFC app logins specifically:

1. **App Login Event Detection**
   - Currently: Sessions created on first navigation
   - Needed: Explicit login event logged immediately after auth

2. **App Type Differentiation**
   - Currently: Detected from User-Agent string
   - Challenge: Need consistent User-Agent from NFC app

3. **App-Specific Session Table (Optional)**
   - Could create `app_logins` table for mobile/NFC app-specific tracking
   - Or reuse active_sessions with app_source field

4. **Mobile Session Endpoints**
   - Currently: Web portal only via presenceService
   - Needed: Mobile app endpoint/API to record login

---

## 3. Database Schema For App Login Tracking

### 3.1 Recommended Extension: app_logins Table

```sql
CREATE TABLE public.app_logins (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Session reference
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  active_session_id uuid REFERENCES active_sessions(id) ON DELETE SET NULL,
  
  -- App identification
  app_type text NOT NULL CHECK (app_type IN ('ios_nfc', 'android_nfc', 'web_portal', 'telegram', 'api')),
  app_version text,
  
  -- Login details
  login_method text DEFAULT 'credentials',  -- 'credentials', 'biometric', 'token', etc.
  login_status text DEFAULT 'success' CHECK (login_status IN ('success', 'failed', 'pending')),
  failure_reason text,
  
  -- Device info
  device_id text,                          -- UDID for iOS, Android ID for Android
  device_model text,
  os_name text,
  os_version text,
  
  -- Network info
  ip_address text,
  country text,
  
  -- Session lifecycle
  login_at timestamptz DEFAULT now(),
  logout_at timestamptz,
  session_duration_seconds integer,
  
  -- Metadata
  metadata jsonb DEFAULT '{}',  -- App-specific data
  
  organization_id uuid REFERENCES organizations(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX idx_app_logins_user ON public.app_logins(user_id);
CREATE INDEX idx_app_logins_app_type ON public.app_logins(app_type);
CREATE INDEX idx_app_logins_login_at ON public.app_logins(login_at);
CREATE INDEX idx_app_logins_device ON public.app_logins(device_id);
```

### 3.2 Alternative: Enhanced active_sessions

Could add columns to existing active_sessions table:

```sql
ALTER TABLE public.active_sessions
ADD COLUMN app_type text DEFAULT 'web_portal' 
  CHECK (app_type IN ('web_portal', 'ios_nfc', 'android_nfc', 'telegram', 'api')),
ADD COLUMN app_version text,
ADD COLUMN device_id text,
ADD COLUMN login_method text DEFAULT 'credentials',
ADD COLUMN login_at timestamptz;
```

**Recommendation:** Use separate `app_logins` table for:
- Better data isolation
- Easier querying of app-specific metrics
- Cleaner schema separation of concerns

---

## 4. Implementation Plan For NFC App Tracking

### 4.1 Database Setup (SQL)

1. Create `app_logins` table
2. Create indexes for performance
3. Add RLS policies for org-level data isolation

**Migration File Name:** `20251020000000_app_login_tracking.sql`

### 4.2 Service Layer (TypeScript)

Create new file: `/src/services/appLoginService.ts`

```typescript
interface AppLoginRecord {
  id?: string;
  user_id: string;
  active_session_id?: string;
  app_type: 'ios_nfc' | 'android_nfc' | 'web_portal' | 'telegram' | 'api';
  app_version?: string;
  login_method: string;
  device_id?: string;
  device_model?: string;
  os_name?: string;
  os_version?: string;
  ip_address?: string;
  country?: string;
  metadata?: Record<string, any>;
}

class AppLoginService {
  async recordAppLogin(data: AppLoginRecord): Promise<void>
  async recordAppLogout(userId: string, appType: string): Promise<void>
  async getAppLoginHistory(userId: string, days?: number): Promise<AppLoginRecord[]>
  async getOrganizationAppLogins(orgId: string): Promise<AppLoginRecord[]>
  async getActiveAppSessions(appType: string): Promise<AppLoginRecord[]>
  async getLoginStats(appType: string): Promise<LoginStats>
}
```

### 4.3 API Endpoint (for NFC App to call)

New endpoint: `POST /api/v1/app/login`

```typescript
// Request
{
  userId: string;
  appType: 'ios_nfc' | 'android_nfc';
  appVersion: string;
  deviceId: string;
  deviceModel: string;
  osVersion: string;
  country?: string;
}

// Response
{
  sessionId: string;
  status: 'success' | 'failed';
  expiresAt: string;
}
```

### 4.4 NFC App Integration

Changes needed in NFC app (iOS/Android):

1. **After successful login:**
   ```swift
   await appLoginService.recordAppLogin(
     userId: user.id,
     appType: .iosNfc,
     appVersion: bundleVersion,
     deviceId: UIDevice.current.identifierForVendor?.uuidString,
     osVersion: UIDevice.current.systemVersion
   )
   ```

2. **Before logout:**
   ```swift
   await appLoginService.recordAppLogout(
     userId: currentUser.id,
     appType: .iosNfc
   )
   ```

3. **Update User-Agent for consistency:**
   ```
   QuickStrap-iOS/1.0 (iPhone; OS 17.0)
   QuickStrap-Android/1.0 (Pixel 8; Android 14)
   ```

---

## 5. Query Examples For Portal Analytics

### 5.1 Get All Active App Sessions

```sql
SELECT 
  al.id,
  al.user_id,
  p.email,
  p.full_name,
  al.app_type,
  al.app_version,
  al.device_model,
  al.login_at,
  EXTRACT(EPOCH FROM (now() - al.login_at)) / 60 as session_minutes,
  al.ip_address
FROM public.app_logins al
JOIN auth.users u ON al.user_id = u.id
JOIN public.profiles p ON u.id = p.id
WHERE al.logout_at IS NULL
  AND al.organization_id = $1
ORDER BY al.login_at DESC;
```

### 5.2 App Usage Statistics

```sql
SELECT 
  app_type,
  COUNT(*) as total_logins,
  COUNT(DISTINCT user_id) as unique_users,
  AVG(session_duration_seconds) as avg_session_duration,
  MAX(login_at) as last_login
FROM public.app_logins
WHERE login_at > now() - interval '7 days'
  AND organization_id = $1
GROUP BY app_type;
```

### 5.3 Device Breakdown

```sql
SELECT 
  device_model,
  os_name,
  os_version,
  COUNT(*) as login_count,
  COUNT(DISTINCT user_id) as unique_users,
  AVG(EXTRACT(EPOCH FROM session_duration) / 60) as avg_session_minutes
FROM public.app_logins
WHERE login_at > now() - interval '30 days'
GROUP BY device_model, os_name, os_version
ORDER BY login_count DESC;
```

### 5.4 Failed Login Attempts

```sql
SELECT 
  al.user_id,
  p.email,
  al.app_type,
  COUNT(*) as failed_attempts,
  MAX(al.login_at) as last_failed_attempt,
  al.failure_reason
FROM public.app_logins al
JOIN auth.users u ON al.user_id = u.id
JOIN public.profiles p ON u.id = p.id
WHERE al.login_status = 'failed'
  AND al.login_at > now() - interval '24 hours'
GROUP BY al.user_id, p.email, al.app_type, al.failure_reason
ORDER BY failed_attempts DESC;
```

---

## 6. Frontend Components To Build

### 6.1 App Sessions Dashboard

**File:** `/src/components/AppSessionsDashboard.tsx`

Features:
- Real-time app session list (iOS, Android, Web)
- Device breakdown charts
- Geographic distribution
- Session duration analytics
- App version distribution
- Geofencing/capacity alerts

### 6.2 App Login Analytics Page

**File:** `/src/pages/AppLoginAnalyticsPage.tsx`

Show:
- Daily login trends by app
- Device model popularity
- OS version distribution
- Failed login attempts
- Geographic heatmap
- User retention metrics

### 6.3 Individual Device Session Detail

Show per-device:
- Login/logout times
- Session duration
- Last activity
- Device specs
- IP/location history
- Session security indicators

---

## 7. Existing Portal Files Reference

| File | Purpose | Location |
|------|---------|----------|
| presenceService.ts | Session lifecycle management | `/src/services/presenceService.ts` |
| secureSessionManager.ts | Secure session storage & validation | `/src/services/secureSessionManager.ts` |
| ActiveSessionsTable.tsx | Live sessions UI component | `/src/components/events/ActiveSessionsTable.tsx` |
| LoggedInDevicesPage.tsx | Devices dashboard page | `/src/pages/LoggedInDevicesPage.tsx` |
| auditLogger.ts | Security event logging | `/src/services/auditLogger.ts` |
| LoginPage.tsx | Authentication form | `/src/pages/LoginPage.tsx` |
| Phase 1 migration | Database schema | `/supabase/migrations/20251006000000_phase1_foundation.sql` |
| Collaboration migration | active_sessions table | `/3c_collaboration_monitoring.sql` |

---

## 8. Security Considerations

### 8.1 RLS Policies Needed

```sql
-- app_logins table should respect organization_id
CREATE POLICY app_logins_org_isolation ON app_logins
FOR SELECT USING (
  organization_id = auth.uid()::uuid OR
  EXISTS (
    SELECT 1 FROM organization_members om
    WHERE om.organization_id = app_logins.organization_id
    AND om.user_id = auth.uid()
    AND om.role IN ('owner', 'admin')
  )
);
```

### 8.2 Data Privacy

- IP addresses are logged - may need GDPR/privacy policy
- Device IDs are logged - ensure user consent
- Metadata field should not contain sensitive data
- Consider encryption for ip_address column

### 8.3 Session Timeout

- Recommended: 30 days for app logins (vs 24 hours for secure sessions)
- Can be configured per org in organization_settings.session_timeout_minutes

---

## 9. Next Steps Summary

### Immediate (1-2 days)
1. Review this analysis with stakeholders
2. Decide: `app_logins` table vs enhanced `active_sessions`
3. Create database migration

### Short-term (1 week)
1. Implement `appLoginService.ts`
2. Create API endpoint for app login recording
3. Add RLS policies
4. Build sample analytics dashboard

### Medium-term (2-3 weeks)
1. Update NFC app to call login endpoint
2. Build full App Sessions Dashboard
3. Add geographic/device analytics
4. Set up failed login alerts

### Long-term (ongoing)
1. Machine learning on login patterns (anomaly detection)
2. Device fingerprinting
3. Risk scoring for logins from unusual locations/devices
4. Integration with fraud detection system

---

## 10. Comparison: Current vs. Proposed Architecture

```
CURRENT STATE:
┌─────────────┐
│ Web Portal  │ ──→ presenceService.updateSession()
│ (Browser)   │     Creates active_sessions record
└─────────────┘

FUTURE STATE:
┌─────────────┐     ┌──────────────────────┐
│ Web Portal  │ ──→ │ presenceService      │ ──→ active_sessions
│ (Browser)   │     │ recordPortalSession()│
└─────────────┘     └──────────────────────┘
                              ↓
                    ┌──────────────────────┐
                    │ appLoginService      │
                    │ recordWebLogin()     │
                    └──────────────────────┘
                              ↓
                          app_logins

┌─────────────┐     ┌──────────────────────┐
│ NFC App     │ ──→ │ appLoginService      │ ──→ app_logins +
│ (iOS/Android)│    │ recordAppLogin()     │     active_sessions
└─────────────┘     │ recordAppLogout()    │
                    └──────────────────────┘

┌──────────┐        ┌──────────────────────┐
│ Telegram │ ──────→ │ secureSessionManager │ ──→ telegram_sessions
│ Bot      │        │ createTelegramSession│
└──────────┘        └──────────────────────┘
```

