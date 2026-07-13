-- ============================================================
-- ONLY run this if the diagnostic query showed system_settings has
-- an 'id uuid' column and NO rows you care about losing.
-- This drops the mistyped table so it can be recreated correctly.
-- ============================================================

DROP TABLE IF EXISTS system_settings CASCADE;

-- After running the DROP above, go back and re-run the full
-- supabase_system_settings.sql script from earlier — it will now
-- succeed, since the table no longer exists with the wrong id type.
