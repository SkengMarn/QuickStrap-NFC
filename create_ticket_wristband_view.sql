-- Materialized View for Ticket-Wristband Links with Full Details
-- This view pre-joins ticket_wristband_links with tickets table to avoid ambiguity issues
-- and provides fast lookups for the mobile app

CREATE MATERIALIZED VIEW ticket_wristband_details AS
SELECT 
    -- Link table columns (prefixed with link_)
    twl.id as link_id,
    twl.ticket_id,
    twl.wristband_id,
    twl.linked_at,
    twl.linked_by,
    
    -- Ticket columns (prefixed with ticket_)
    t.id as ticket_internal_id,
    t.event_id as ticket_event_id,
    t.ticket_number,
    t.ticket_category,
    t.holder_name,
    t.holder_email,
    t.holder_phone,
    t.status as ticket_status,
    t.uploaded_at as ticket_uploaded_at,
    t.created_at as ticket_created_at,
    t.updated_at as ticket_updated_at,
    
    -- Computed fields for quick filtering
    CASE 
        WHEN t.status = 'linked' THEN true 
        ELSE false 
    END as is_active_link,
    
    -- Event context for fast filtering
    t.event_id,
    
    -- Timestamps for cache invalidation
    GREATEST(twl.linked_at, t.updated_at) as last_modified

FROM ticket_wristband_links twl
INNER JOIN tickets t ON twl.ticket_id = t.id
WHERE t.status IN ('linked', 'unused'); -- Only include relevant tickets

-- Create indexes for fast lookups
CREATE UNIQUE INDEX idx_ticket_wristband_details_link_id 
ON ticket_wristband_details(link_id);

CREATE INDEX idx_ticket_wristband_details_wristband_id 
ON ticket_wristband_details(wristband_id);

CREATE INDEX idx_ticket_wristband_details_ticket_id 
ON ticket_wristband_details(ticket_id);

CREATE INDEX idx_ticket_wristband_details_event_id 
ON ticket_wristband_details(event_id);

CREATE INDEX idx_ticket_wristband_details_active 
ON ticket_wristband_details(wristband_id, is_active_link) 
WHERE is_active_link = true;

-- Create a function to refresh the materialized view
CREATE OR REPLACE FUNCTION refresh_ticket_wristband_details()
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY ticket_wristband_details;
END;
$$ LANGUAGE plpgsql;

-- Create triggers to auto-refresh the view when data changes
CREATE OR REPLACE FUNCTION trigger_refresh_ticket_wristband_details()
RETURNS trigger AS $$
BEGIN
    -- Use pg_notify to trigger async refresh
    PERFORM pg_notify('refresh_materialized_view', 'ticket_wristband_details');
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Trigger on ticket_wristband_links changes
CREATE TRIGGER trigger_ticket_wristband_links_refresh
    AFTER INSERT OR UPDATE OR DELETE ON ticket_wristband_links
    FOR EACH STATEMENT
    EXECUTE FUNCTION trigger_refresh_ticket_wristband_details();

-- Trigger on tickets changes (only for status updates)
CREATE TRIGGER trigger_tickets_refresh
    AFTER UPDATE OF status ON tickets
    FOR EACH STATEMENT
    EXECUTE FUNCTION trigger_refresh_ticket_wristband_details();

-- Grant permissions for the app to use this view
GRANT SELECT ON ticket_wristband_details TO authenticated;
GRANT SELECT ON ticket_wristband_details TO anon;

-- Initial population of the materialized view
REFRESH MATERIALIZED VIEW ticket_wristband_details;

-- Optional: Create a scheduled job to refresh every 5 minutes as backup
-- (You can set this up in Supabase Dashboard -> Database -> Cron Jobs)
/*
SELECT cron.schedule(
    'refresh-ticket-wristband-details',
    '*/5 * * * *', -- Every 5 minutes
    'SELECT refresh_ticket_wristband_details();'
);
*/

COMMENT ON MATERIALIZED VIEW ticket_wristband_details IS 
'Pre-joined view of ticket_wristband_links and tickets for fast mobile app queries. 
Eliminates SQL ambiguity issues and improves performance for ticket validation.';
