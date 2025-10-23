-- =============================================================================
-- DIAGNOSTIC AND FIX SCRIPT FOR AMBIGUOUS event_id ERROR
-- Run this entire script in your Supabase Dashboard SQL Editor
-- =============================================================================

-- STEP 1: Check current function definition
DO $$
DECLARE
    func_def text;
BEGIN
    SELECT pg_get_functiondef(oid) INTO func_def
    FROM pg_proc
    WHERE proname = 'enforce_wristband_category_limit';

    IF func_def LIKE '%FROM public.event_category_limits ecl%' THEN
        RAISE NOTICE '✅ Function already has alias - fix may have been applied';
    ELSIF func_def LIKE '%FROM public.event_category_limits%' THEN
        RAISE NOTICE '❌ Function DOES NOT have alias - needs fix';
    ELSE
        RAISE NOTICE '⚠️  Could not determine function status';
    END IF;
END $$;

-- =============================================================================
-- STEP 2: Drop and recreate the trigger (to ensure clean state)
-- =============================================================================

DROP TRIGGER IF EXISTS trg_enforce_wristband_limit ON public.ticket_wristband_links;

-- =============================================================================
-- STEP 3: Fix the trigger function with explicit aliases everywhere
-- =============================================================================

CREATE OR REPLACE FUNCTION public.enforce_wristband_category_limit()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
DECLARE
  v_current_count integer;
  v_max_allowed integer;
  v_wristband_event_id uuid;
  v_ticket_event_id uuid;
  v_wristband_category text;
BEGIN
  -- Get the wristband's category and event (with explicit alias)
  SELECT w.category, w.event_id
  INTO v_wristband_category, v_wristband_event_id
  FROM public.wristbands w
  WHERE w.id = NEW.wristband_id;

  -- If wristband not found, raise error
  IF v_wristband_category IS NULL THEN
    RAISE EXCEPTION 'Wristband % not found', NEW.wristband_id;
  END IF;

  -- Get the event from the ticket (with explicit alias)
  SELECT t.event_id
  INTO v_ticket_event_id
  FROM public.tickets t
  WHERE t.id = NEW.ticket_id;

  -- Verify ticket exists
  IF v_ticket_event_id IS NULL THEN
    RAISE EXCEPTION 'Ticket % not found', NEW.ticket_id;
  END IF;

  -- Verify ticket and wristband belong to same event
  IF v_wristband_event_id != v_ticket_event_id THEN
    RAISE EXCEPTION 'Ticket and wristband belong to different events';
  END IF;

  -- Count how many wristbands from this category are already linked
  SELECT COUNT(*)
  INTO v_current_count
  FROM public.ticket_wristband_links twl
  INNER JOIN public.wristbands w ON w.id = twl.wristband_id
  WHERE twl.ticket_id = NEW.ticket_id
    AND w.category = v_wristband_category;

  -- Get the maximum allowed (WITH EXPLICIT ALIAS AND TABLE QUALIFICATION)
  SELECT ecl.max_wristbands
  INTO v_max_allowed
  FROM public.event_category_limits AS ecl
  WHERE ecl.event_id = v_wristband_event_id
    AND ecl.category = v_wristband_category;

  -- If no limit is configured, default to 1
  IF v_max_allowed IS NULL THEN
    v_max_allowed := 1;
    -- Auto-create default limit
    PERFORM public.insert_default_category_limit(
      v_wristband_event_id,
      v_wristband_category,
      1
    );
  END IF;

  -- Check if at or over limit
  IF v_current_count >= v_max_allowed THEN
    RAISE EXCEPTION 'Ticket already has maximum allowed wristbands (% out of % for category "%")',
      v_current_count, v_max_allowed, v_wristband_category;
  END IF;

  RETURN NEW;
END;
$function$;

-- =============================================================================
-- STEP 4: Recreate the trigger
-- =============================================================================

CREATE TRIGGER trg_enforce_wristband_limit
  BEFORE INSERT ON public.ticket_wristband_links
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_wristband_category_limit();

-- =============================================================================
-- STEP 5: Also fix the can_link_wristband_to_ticket function
-- =============================================================================

CREATE OR REPLACE FUNCTION public.can_link_wristband_to_ticket(
  p_ticket_id uuid,
  p_wristband_id uuid
)
RETURNS TABLE (
  can_link boolean,
  reason text,
  current_count integer,
  max_allowed integer,
  category text
)
LANGUAGE plpgsql
AS $function$
DECLARE
  v_current_count integer;
  v_max_allowed integer;
  v_category text;
  v_event_id uuid;
  v_ticket_event_id uuid;
BEGIN
  -- Get wristband details (with explicit alias)
  SELECT w.category, w.event_id
  INTO v_category, v_event_id
  FROM public.wristbands w
  WHERE w.id = p_wristband_id;

  IF v_category IS NULL THEN
    RETURN QUERY SELECT false, 'Wristband not found'::text, 0, 0, ''::text;
    RETURN;
  END IF;

  -- Get ticket event (with explicit alias)
  SELECT t.event_id
  INTO v_ticket_event_id
  FROM public.tickets t
  WHERE t.id = p_ticket_id;

  IF v_ticket_event_id IS NULL THEN
    RETURN QUERY SELECT false, 'Ticket not found'::text, 0, 0, v_category;
    RETURN;
  END IF;

  -- Check if events match
  IF v_event_id != v_ticket_event_id THEN
    RETURN QUERY SELECT false, 'Ticket and wristband belong to different events'::text, 0, 0, v_category;
    RETURN;
  END IF;

  -- Check if wristband already linked
  IF EXISTS (
    SELECT 1
    FROM public.ticket_wristband_links twl
    WHERE twl.wristband_id = p_wristband_id
  ) THEN
    RETURN QUERY SELECT false, 'Wristband is already linked to another ticket'::text, 0, 0, v_category;
    RETURN;
  END IF;

  -- Get current count
  SELECT COUNT(*)
  INTO v_current_count
  FROM public.ticket_wristband_links twl
  INNER JOIN public.wristbands w ON w.id = twl.wristband_id
  WHERE twl.ticket_id = p_ticket_id
    AND w.category = v_category;

  -- Get max allowed (WITH EXPLICIT ALIAS)
  SELECT ecl.max_wristbands
  INTO v_max_allowed
  FROM public.event_category_limits AS ecl
  WHERE ecl.event_id = v_event_id
    AND ecl.category = v_category;

  -- Default to 1 if not configured
  IF v_max_allowed IS NULL THEN
    v_max_allowed := 1;
  END IF;

  -- Check if can link more
  IF v_current_count >= v_max_allowed THEN
    RETURN QUERY SELECT
      false,
      format('Maximum wristbands reached (%s out of %s for category "%s")',
        v_current_count, v_max_allowed, v_category)::text,
      v_current_count,
      v_max_allowed,
      v_category;
    RETURN;
  END IF;

  -- All checks passed
  RETURN QUERY SELECT
    true,
    format('Can link wristband (%s out of %s used for category "%s")',
      v_current_count, v_max_allowed, v_category)::text,
    v_current_count,
    v_max_allowed,
    v_category;
END;
$function$;

-- =============================================================================
-- DONE! Verification
-- =============================================================================

DO $$
BEGIN
    RAISE NOTICE '✅ Functions have been recreated with explicit aliases';
    RAISE NOTICE '✅ Trigger has been recreated';
    RAISE NOTICE '📝 Try linking a ticket now - the ambiguity error should be gone';
END $$;
