-- ============================================================
-- MINIMAL FIX — works with your EXISTING system_settings table
-- (id uuid, key text, value jsonb, created_at) exactly as-is.
-- Run this in Supabase SQL Editor. That's it — 2 statements.
-- ============================================================

-- 1. Needed so the app can "upsert by key" (update a setting if it
--    already exists, insert it if it doesn't) instead of creating a
--    duplicate row every time Save Settings is pressed.
ALTER TABLE system_settings
  ADD CONSTRAINT system_settings_key_unique UNIQUE (key);

-- 2. Supabase's dashboard enables Row Level Security by default on new
--    tables, and with zero policies that blocks ALL access — every
--    query would silently return nothing (reads) or fail (writes).
--    Disabling it gets you working immediately. This table only holds
--    escrow numbers + a commission rate + a blocked-user list, so it's
--    a reasonable trade-off for now — you can lock it down properly
--    with admin-only RLS policies later when you have time.
ALTER TABLE system_settings DISABLE ROW LEVEL SECURITY;
