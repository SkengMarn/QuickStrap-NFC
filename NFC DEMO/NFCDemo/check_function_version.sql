-- Check if the enforce_wristband_category_limit function has been fixed
-- Run this to see the current function definition

SELECT
    proname as function_name,
    pg_get_functiondef(oid) as function_definition
FROM pg_proc
WHERE proname = 'enforce_wristband_category_limit';

-- If the function_definition contains "FROM public.event_category_limits ecl"
-- then the fix has been applied.
-- If it contains "FROM public.event_category_limits" without an alias,
-- then you need to run the fix.
