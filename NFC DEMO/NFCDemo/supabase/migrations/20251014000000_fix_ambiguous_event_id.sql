-- Migration: Fix ambiguous event_id column reference
-- Created: 2025-10-14
-- Description: Fixes "column reference 'event_id' is ambiguous" error in trigger functions
--              by adding explicit table aliases to queries

-- ============================================================================
-- 1. Update enforce_wristband_category_limit function
-- ============================================================================

CREATE OR REPLACE FUNCTION public.enforce_wristband_category_limit()
RETURNS trigger AS $$
DECLARE
  current_count integer;
  max_allowed integer;
  category_name text;
  wristband_event_id uuid;
  ticket_event_id uuid;
  wristband_category text;
BEGIN
  -- Get the wristband's category and event
  SELECT w.category, w.event_id INTO wristband_category, wristband_event_id
  FROM public.wristbands w
  WHERE w.id = NEW.wristband_id;

  -- If wristband not found, raise error
  IF wristband_category IS NULL THEN
    RAISE EXCEPTION 'Wristband % not found', NEW.wristband_id;
  END IF;

  -- Get the event from the ticket to ensure consistency
  SELECT t.event_id INTO ticket_event_id
  FROM public.tickets t
  WHERE t.id = NEW.ticket_id;

  -- Verify ticket exists
  IF ticket_event_id IS NULL THEN
    RAISE EXCEPTION 'Ticket % not found', NEW.ticket_id;
  END IF;

  -- Verify ticket and wristband belong to same event
  IF wristband_event_id != ticket_event_id THEN
    RAISE EXCEPTION 'Ticket and wristband belong to different events';
  END IF;

  -- Count how many wristbands from this category are already linked to this ticket
  SELECT COUNT(*) INTO current_count
  FROM public.ticket_wristband_links twl
  JOIN public.wristbands w ON w.id = twl.wristband_id
  WHERE twl.ticket_id = NEW.ticket_id AND w.category = wristband_category;

  -- Get the maximum allowed wristbands for this category in this event
  -- FIXED: Added table alias 'ecl' to prevent ambiguity
  SELECT ecl.max_wristbands INTO max_allowed
  FROM public.event_category_limits ecl
  WHERE ecl.event_id = wristband_event_id AND ecl.category = wristband_category;

  -- If no limit is configured for this category, default to 1
  IF max_allowed IS NULL THEN
    max_allowed := 1;

    -- Auto-create a default limit entry using SECURITY DEFINER function
    PERFORM public.insert_default_category_limit(wristband_event_id, wristband_category, 1);
  END IF;

  -- Check if we're at or over the limit
  IF current_count >= max_allowed THEN
    RAISE EXCEPTION 'Ticket already has maximum allowed wristbands (% out of % for category "%")',
      current_count, max_allowed, wristband_category;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- 2. Update can_link_wristband_to_ticket function
-- ============================================================================

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
) AS $$
DECLARE
  v_current_count integer;
  v_max_allowed integer;
  v_category text;
  v_event_id uuid;
  v_ticket_event_id uuid;
BEGIN
  -- Get wristband details
  SELECT w.category, w.event_id INTO v_category, v_event_id
  FROM public.wristbands w
  WHERE w.id = p_wristband_id;

  IF v_category IS NULL THEN
    RETURN QUERY SELECT false, 'Wristband not found'::text, 0, 0, ''::text;
    RETURN;
  END IF;

  -- Get ticket event
  SELECT t.event_id INTO v_ticket_event_id
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

  -- Check if wristband is already linked
  IF EXISTS (SELECT 1 FROM public.ticket_wristband_links WHERE wristband_id = p_wristband_id) THEN
    RETURN QUERY SELECT false, 'Wristband is already linked to another ticket'::text, 0, 0, v_category;
    RETURN;
  END IF;

  -- Get current count for this ticket and category
  SELECT COUNT(*) INTO v_current_count
  FROM public.ticket_wristband_links twl
  JOIN public.wristbands w ON w.id = twl.wristband_id
  WHERE twl.ticket_id = p_ticket_id AND w.category = v_category;

  -- Get max allowed for this category
  -- FIXED: Added table alias 'ecl' to prevent ambiguity
  SELECT ecl.max_wristbands INTO v_max_allowed
  FROM public.event_category_limits ecl
  WHERE ecl.event_id = v_event_id AND ecl.category = v_category;

  -- Default to 1 if not configured
  IF v_max_allowed IS NULL THEN
    v_max_allowed := 1;
  END IF;

  -- Check if we can link more
  IF v_current_count >= v_max_allowed THEN
    RETURN QUERY SELECT
      false,
      format('Maximum wristbands reached (%s out of %s for category "%s")', v_current_count, v_max_allowed, v_category)::text,
      v_current_count,
      v_max_allowed,
      v_category;
    RETURN;
  END IF;

  -- All checks passed
  RETURN QUERY SELECT
    true,
    format('Can link wristband (%s out of %s used for category "%s")', v_current_count, v_max_allowed, v_category)::text,
    v_current_count,
    v_max_allowed,
    v_category;
END;
$$ LANGUAGE plpgsql;
