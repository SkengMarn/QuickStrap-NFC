-- Migration: Category-based wristband limits for tickets
-- Created: 2025-10-11
-- Description: Adds event_category_limits and ticket_wristband_links tables
--              to support many-to-many ticket-wristband relationships with
--              per-category limits on how many wristbands can be linked per ticket.

-- ============================================================================
-- 1. Create event_category_limits table
-- ============================================================================
-- This table stores the maximum number of wristbands that can be linked
-- to a ticket for each category within an event.

CREATE TABLE IF NOT EXISTS public.event_category_limits (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id uuid NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  category text NOT NULL,
  max_wristbands integer NOT NULL DEFAULT 1,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE (event_id, category)
);

-- Add indexes for performance
CREATE INDEX idx_event_category_limits_event_id ON public.event_category_limits(event_id);
CREATE INDEX idx_event_category_limits_lookup ON public.event_category_limits(event_id, category);

-- Add comments
COMMENT ON TABLE public.event_category_limits IS 'Defines the maximum number of wristbands that can be linked to a ticket per category per event';
COMMENT ON COLUMN public.event_category_limits.category IS 'Wristband category name - must match categories in wristbands table';
COMMENT ON COLUMN public.event_category_limits.max_wristbands IS 'Maximum number of wristbands from this category that can be linked to a single ticket';

-- ============================================================================
-- 2. Create ticket_wristband_links table
-- ============================================================================
-- This table creates a many-to-many relationship between tickets and wristbands,
-- replacing the old 1:1 linked_wristband_id field.

CREATE TABLE IF NOT EXISTS public.ticket_wristband_links (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id uuid NOT NULL REFERENCES public.tickets(id) ON DELETE CASCADE,
  wristband_id uuid NOT NULL REFERENCES public.wristbands(id) ON DELETE CASCADE,
  linked_at timestamptz DEFAULT now(),
  linked_by uuid REFERENCES public.users(id),
  created_at timestamptz DEFAULT now(),
  UNIQUE (wristband_id)
);

-- Add indexes for performance
CREATE INDEX idx_ticket_wristband_links_ticket_id ON public.ticket_wristband_links(ticket_id);
CREATE INDEX idx_ticket_wristband_links_wristband_id ON public.ticket_wristband_links(wristband_id);

-- Add comments
COMMENT ON TABLE public.ticket_wristband_links IS 'Many-to-many relationship table linking tickets to wristbands';
COMMENT ON COLUMN public.ticket_wristband_links.ticket_id IS 'Reference to the ticket';
COMMENT ON COLUMN public.ticket_wristband_links.wristband_id IS 'Reference to the wristband - must be unique (one wristband can only link to one ticket)';
COMMENT ON COLUMN public.ticket_wristband_links.linked_by IS 'User who performed the linking';

-- ============================================================================
-- 3. Helper function to insert default category limits (SECURITY DEFINER)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.insert_default_category_limit(
  p_event_id uuid,
  p_category text,
  p_max_wristbands integer
)
RETURNS void AS $$
BEGIN
  INSERT INTO public.event_category_limits (event_id, category, max_wristbands)
  VALUES (p_event_id, p_category, p_max_wristbands)
  ON CONFLICT (event_id, category) DO NOTHING;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add comment
COMMENT ON FUNCTION public.insert_default_category_limit(uuid, text, integer) IS 'Security definer function to allow staff to auto-create default category limits';

-- ============================================================================
-- 4. Create trigger function to enforce category limits
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

-- Add comment
COMMENT ON FUNCTION public.enforce_wristband_category_limit() IS 'Enforces per-category wristband limits when linking wristbands to tickets';

-- ============================================================================
-- 4. Create trigger on ticket_wristband_links
-- ============================================================================

CREATE TRIGGER trg_enforce_wristband_limit
BEFORE INSERT ON public.ticket_wristband_links
FOR EACH ROW
EXECUTE FUNCTION public.enforce_wristband_category_limit();

-- Add comment
COMMENT ON TRIGGER trg_enforce_wristband_limit ON public.ticket_wristband_links IS 'Prevents linking more wristbands than allowed per category';

-- ============================================================================
-- 5. Create function to get current link counts per ticket
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_ticket_wristband_count(p_ticket_id uuid)
RETURNS TABLE (
  category text,
  current_count bigint,
  max_allowed integer,
  can_link_more boolean
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    ecl.category,
    COALESCE(COUNT(w.id), 0) as current_count,
    ecl.max_wristbands as max_allowed,
    COALESCE(COUNT(w.id), 0) < ecl.max_wristbands as can_link_more
  FROM public.event_category_limits ecl
  INNER JOIN public.tickets t ON t.event_id = ecl.event_id
  LEFT JOIN public.ticket_wristband_links twl ON twl.ticket_id = t.id
  LEFT JOIN public.wristbands w ON w.id = twl.wristband_id AND w.category = ecl.category
  WHERE t.id = p_ticket_id
  GROUP BY ecl.category, ecl.max_wristbands;
END;
$$ LANGUAGE plpgsql;

-- Add comment
COMMENT ON FUNCTION public.get_ticket_wristband_count(uuid) IS 'Returns wristband link counts and limits per category for a given ticket';

-- ============================================================================
-- 6. Create function to check if a wristband can be linked to a ticket
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

-- Add comment
COMMENT ON FUNCTION public.can_link_wristband_to_ticket(uuid, uuid) IS 'Checks if a wristband can be linked to a ticket and returns detailed information';

-- ============================================================================
-- 7. Enable Row Level Security (RLS)
-- ============================================================================

ALTER TABLE public.event_category_limits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ticket_wristband_links ENABLE ROW LEVEL SECURITY;

-- Policy for event_category_limits: Admins can do everything
CREATE POLICY event_category_limits_admin_all ON public.event_category_limits
  FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE users.id = auth.uid() AND users.role IN ('admin', 'super_admin')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE users.id = auth.uid() AND users.role IN ('admin', 'super_admin')
    )
  );

-- Policy for event_category_limits: Staff can read
CREATE POLICY event_category_limits_staff_read ON public.event_category_limits
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE users.id = auth.uid() AND users.role IN ('staff', 'admin', 'super_admin')
    )
  );

-- Policy for ticket_wristband_links: Staff can create links
CREATE POLICY ticket_wristband_links_staff_insert ON public.ticket_wristband_links
  FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE users.id = auth.uid() AND users.role IN ('staff', 'admin', 'super_admin')
    )
  );

-- Policy for ticket_wristband_links: Staff can read links
CREATE POLICY ticket_wristband_links_staff_read ON public.ticket_wristband_links
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE users.id = auth.uid() AND users.role IN ('staff', 'admin', 'super_admin')
    )
  );

-- Policy for ticket_wristband_links: Only admins can delete links (unlink)
CREATE POLICY ticket_wristband_links_admin_delete ON public.ticket_wristband_links
  FOR DELETE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE users.id = auth.uid() AND users.role IN ('admin', 'super_admin')
    )
  );

-- ============================================================================
-- 8. Grant permissions
-- ============================================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON public.event_category_limits TO authenticated;
GRANT SELECT, INSERT, DELETE ON public.ticket_wristband_links TO authenticated;
GRANT USAGE ON SCHEMA public TO authenticated;

-- ============================================================================
-- 9. Create updated_at trigger for event_category_limits
-- ============================================================================

CREATE TRIGGER set_updated_at
BEFORE UPDATE ON public.event_category_limits
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at_column();

-- Note: The update_updated_at_column() function should already exist.
-- If not, create it:

CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
