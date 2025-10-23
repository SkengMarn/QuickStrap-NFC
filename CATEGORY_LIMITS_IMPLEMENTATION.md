# Category-Based Wristband Limits Implementation

## Overview

This implementation adds category-based limits on how many wristbands can be linked to a single ticket. The limits are configurable per event and per wristband category.

## What Was Implemented

### 1. Database Schema (Already Exists)

#### Tables
- **`event_category_limits`**: Stores the maximum number of wristbands allowed per category per event
  - `id`: Primary key
  - `event_id`: Foreign key to events table
  - `category`: Wristband category name (matches wristbands.category)
  - `max_wristbands`: Maximum number allowed (default: 1)
  - `created_at`, `updated_at`: Timestamps

- **`ticket_wristband_links`**: Many-to-many relationship table for ticket-wristband links
  - `id`: Primary key
  - `ticket_id`: Foreign key to tickets table
  - `wristband_id`: Foreign key to wristbands table (unique - one wristband can only link to one ticket)
  - `linked_at`: Timestamp of when the link was created
  - `linked_by`: User who performed the linking

#### Database Functions

1. **`can_link_wristband_to_ticket(p_ticket_id, p_wristband_id)`**
   - Validates if a wristband can be linked to a ticket
   - Returns: `can_link`, `reason`, `current_count`, `max_allowed`, `category`
   - Checks:
     - Wristband exists and belongs to same event as ticket
     - Wristband is not already linked
     - Current link count is below the category limit

2. **`get_ticket_wristband_count(p_ticket_id)`**
   - Returns current wristband link counts per category for a ticket
   - Returns: `category`, `current_count`, `max_allowed`, `can_link_more`

3. **`enforce_wristband_category_limit()` (Trigger Function)**
   - Automatically enforces category limits when inserting into `ticket_wristband_links`
   - Raises an exception if limit is exceeded
   - Auto-creates default limit entries (max_wristbands=1) if not configured

### 2. Swift Models

Added three new models in `TicketModels.swift`:

- **`EventCategoryLimit`**: Represents category limit configuration
- **`TicketWristbandLink`**: Represents a ticket-wristband link
- **`LinkValidationResult`**: Validation response from database

### 3. Service Layer Updates

Updated `TicketService.swift` with:

- **`validateWristbandLink(ticketId:wristbandId:)`**: Validates if linking is allowed
- **`linkTicketToWristband(ticketId:wristbandId:performedBy:)`**: Updated to use new tables and enforce limits
- **`getTicketWristbandCounts(ticketId:)`**: Gets current link status per category
- **`TicketError.categoryLimitExceeded(String)`**: New error type for limit violations

### 4. ViewModel Updates

Updated `DatabaseScannerViewModel` with:

- **`linkValidation`**: Published property storing validation result
- **`isValidatingLink`**: Loading state for validation
- **`validateSelectedTicketLink()`**: Pre-validates link before user clicks "Link"
- Updated `linkSelectedTicket()` to validate before linking and show detailed feedback

### 5. UI Updates

Updated `TicketLinkingView` to:

- Automatically validate when a ticket is selected
- Display validation results with:
  - Success/error indicator
  - Category name
  - Current count / max allowed (e.g., "2/5 wristbands")
  - Clear reason message
- Disable link button if validation fails
- Change button color based on validation state

## How It Works

### Flow When Scanning a Wristband

1. **Wristband Scanned** → NFC detected
2. **Gate Check** → Validates gate access
3. **Ticket Required?** → Event has `ticket_linking_mode = 'required'` and wristband not linked
4. **Show Ticket Linking UI** → User searches for ticket
5. **Ticket Selected** → Automatically validates:
   - Gets wristband category
   - Checks current linked count for this ticket
   - Checks max allowed for this category
   - Returns validation result
6. **Validation Result Shown** → UI displays:
   - ✅ "Can link wristband (2 out of 5 used for category 'TABLE')" - Green
   - ❌ "Maximum wristbands reached (5 out of 5 for category 'VIP')" - Red
7. **User Clicks Link** → If validation passed:
   - Inserts record into `ticket_wristband_links`
   - Database trigger enforces limit (double-check)
   - Updates ticket status to 'linked'
   - Logs action to `ticket_link_audit`
   - Completes check-in

## Setting Up Category Limits

### Option 1: Direct Database Insert

```sql
-- Set VIP tickets to allow 1 wristband
INSERT INTO public.event_category_limits (event_id, category, max_wristbands)
VALUES ('your-event-id', 'VIP', 1);

-- Set TABLE tickets to allow 5 wristbands
INSERT INTO public.event_category_limits (event_id, category, max_wristbands)
VALUES ('your-event-id', 'TABLE', 5);

-- Set CREW tickets to allow 2 wristbands
INSERT INTO public.event_category_limits (event_id, category, max_wristbands)
VALUES ('your-event-id', 'CREW', 2);
```

### Option 2: Auto-Creation

If no limit is configured, the trigger will auto-create a default entry with `max_wristbands = 1` when the first wristband is linked.

### Checking Current Limits

```sql
-- View all category limits for an event
SELECT category, max_wristbands
FROM public.event_category_limits
WHERE event_id = 'your-event-id';

-- View current links for a ticket
SELECT * FROM public.get_ticket_wristband_count('ticket-id');
```

## Testing Guide

### Prerequisites

1. Event with `ticket_linking_mode = 'required'`
2. Wristbands with different categories (VIP, TABLE, CREW, etc.)
3. Category limits configured in `event_category_limits`
4. Tickets uploaded for the event

### Test Cases

#### Test 1: Link First Wristband (Should Succeed)

1. Scan a wristband (e.g., category='TABLE', limit=5)
2. Select a ticket
3. ✅ Should show: "Can link wristband (0 out of 5 used for category 'TABLE')"
4. Click "Link Selected Ticket"
5. ✅ Should succeed and complete check-in

#### Test 2: Link Within Limit (Should Succeed)

1. Use a ticket that already has 2 wristbands linked (limit=5)
2. Scan a new wristband of same category
3. ✅ Should show: "Can link wristband (2 out of 5 used for category 'TABLE')"
4. Click "Link Selected Ticket"
5. ✅ Should succeed

#### Test 3: Exceed Category Limit (Should Fail)

1. Use a ticket that already has 5 wristbands linked (limit=5)
2. Scan a new wristband of same category
3. ❌ Should show: "Maximum wristbands reached (5 out of 5 for category 'TABLE')"
4. Link button should be disabled or show error
5. ❌ Attempting to link should fail with error message

#### Test 4: Different Categories (Should Work Independently)

1. Link 5 TABLE wristbands to a ticket (limit=5) - Should succeed
2. Now try to link a VIP wristband to the same ticket (limit=1)
3. ✅ Should show: "Can link wristband (0 out of 1 used for category 'VIP')"
4. ✅ Should succeed

#### Test 5: Database Trigger Enforcement

Even if app validation is bypassed, the database trigger will prevent over-linking:

```sql
-- This should fail if ticket already has max wristbands
INSERT INTO public.ticket_wristband_links (ticket_id, wristband_id)
VALUES ('ticket-with-max-links', 'new-wristband-id');

-- Error: "Ticket already has maximum allowed wristbands (5 out of 5 for category "TABLE")"
```

## Expected Behavior Summary

| Scenario | Current Count | Max Allowed | Can Link? | UI Display |
|----------|--------------|-------------|-----------|------------|
| First link | 0 | 5 | ✅ Yes | "Can link (0/5 for TABLE)" - Green |
| Within limit | 2 | 5 | ✅ Yes | "Can link (2/5 for TABLE)" - Green |
| At limit | 5 | 5 | ❌ No | "Max reached (5/5 for TABLE)" - Red |
| Over limit | N/A | N/A | ❌ No | Database error |
| Different category | 0 | 1 | ✅ Yes | "Can link (0/1 for VIP)" - Green |

## Validation Logic

### Client-Side (App)
1. User selects ticket
2. App calls `validateWristbandLink()`
3. Database function checks all conditions
4. Returns validation result
5. UI shows result and enables/disables link button

### Server-Side (Database Trigger)
1. App attempts to insert into `ticket_wristband_links`
2. Trigger function runs before insert
3. Counts current links for the ticket
4. Checks against category limit
5. If over limit: **RAISES EXCEPTION** (insert fails)
6. If within limit: Allows insert to proceed

## Error Messages

### User-Friendly Messages
- ✅ "Can link wristband (2 out of 5 used for category 'TABLE')"
- ❌ "Maximum wristbands reached (5 out of 5 for category 'TABLE')"
- ❌ "Wristband is already linked to another ticket"
- ❌ "Ticket and wristband belong to different events"

### Database Errors
- "Ticket already has maximum allowed wristbands (5 for category 'TABLE')"
- "Wristband {id} not found"
- "Ticket {id} not found"

## Monitoring and Analytics

### Useful Queries

```sql
-- Count total links per ticket
SELECT ticket_id, COUNT(*) as wristband_count
FROM public.ticket_wristband_links
GROUP BY ticket_id;

-- Find tickets at their limit
SELECT t.ticket_number, ecl.category, COUNT(twl.id) as current, ecl.max_wristbands
FROM public.tickets t
JOIN public.ticket_wristband_links twl ON twl.ticket_id = t.id
JOIN public.wristbands w ON w.id = twl.wristband_id
JOIN public.event_category_limits ecl ON ecl.event_id = t.event_id AND ecl.category = w.category
GROUP BY t.id, t.ticket_number, ecl.category, ecl.max_wristbands
HAVING COUNT(twl.id) >= ecl.max_wristbands;

-- Audit trail of failed link attempts
SELECT *
FROM public.ticket_link_audit
WHERE action = 'link_attempt_failed'
ORDER BY timestamp DESC;
```

## Migration Steps

### If You Need to Apply the Migration

The database tables already exist, but if you need to apply the migration to another environment:

```bash
# Apply the migration
cd "NFC DEMO/NFCDemo"
supabase db push

# Or manually run the migration file
psql -h your-db-host -U your-user -d your-db < supabase/migrations/20251011000000_category_limits.sql
```

## Rollback (If Needed)

To revert this feature:

```sql
-- Remove the trigger
DROP TRIGGER IF EXISTS trg_enforce_wristband_limit ON public.ticket_wristband_links;

-- Remove the functions
DROP FUNCTION IF EXISTS public.enforce_wristband_category_limit();
DROP FUNCTION IF EXISTS public.can_link_wristband_to_ticket(uuid, uuid);
DROP FUNCTION IF EXISTS public.get_ticket_wristband_count(uuid);

-- Drop the tables (WARNING: This deletes all data)
DROP TABLE IF EXISTS public.ticket_wristband_links CASCADE;
DROP TABLE IF EXISTS public.event_category_limits CASCADE;
```

## Future Enhancements

1. **Portal UI**: Add interface in web portal to manage category limits
2. **Auto-Detection**: Automatically detect categories from wristbands and create default limits
3. **Bulk Updates**: Allow bulk updates of category limits across multiple events
4. **Analytics**: Show category limit utilization in event dashboard
5. **Warnings**: Show warnings when approaching category limits (e.g., 80% full)

## Support

For issues or questions:
- Check database logs for trigger errors
- Review `ticket_link_audit` table for failed attempts
- Validate `event_category_limits` configuration
- Ensure wristband categories match exactly (case-sensitive)
