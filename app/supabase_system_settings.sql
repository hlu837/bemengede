-- ============================================================
-- BEMENGEDE — Platform Settings: single-row 'system_settings' table
-- Run this in Supabase SQL Editor (Dashboard → SQL Editor → New query)
--
-- Backs the Admin "Platform Settings" screen: escrow account numbers,
-- commission rate, and the list of blocked user ids, all in one row
-- (id = 1) that the app reads with a single SELECT and writes with a
-- single UPSERT.
-- ============================================================

CREATE TABLE IF NOT EXISTS system_settings (
  id                INTEGER PRIMARY KEY DEFAULT 1,
  escrow_telebirr   TEXT,
  escrow_cbe        TEXT,
  escrow_awash      TEXT,
  commission_rate   DOUBLE PRECISION DEFAULT 0,
  blocked_users     TEXT[] DEFAULT ARRAY[]::TEXT[],
  updated_at        TIMESTAMPTZ DEFAULT NOW(),
  CONSTRAINT system_settings_single_row CHECK (id = 1)
);

-- Seed the one row if it doesn't exist yet, so the app's first fetch
-- doesn't come back empty.
INSERT INTO system_settings (id)
VALUES (1)
ON CONFLICT (id) DO NOTHING;

-- Keep updated_at current on every save.
CREATE OR REPLACE FUNCTION touch_system_settings_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_system_settings_updated_at ON system_settings;
CREATE TRIGGER trg_system_settings_updated_at
  BEFORE UPDATE ON system_settings
  FOR EACH ROW EXECUTE FUNCTION touch_system_settings_updated_at();

-- ── One-time migration of any legacy 'blocked:<user_id>' rows ──────────────
-- If you were previously storing blocked users as individual
-- platform_settings rows with keys like 'blocked:<uuid>', this folds them
-- into the new blocked_users array. Safe to run even if there are none.
UPDATE system_settings
SET blocked_users = (
  SELECT COALESCE(array_agg(DISTINCT split_part(setting_key, ':', 2)), ARRAY[]::TEXT[])
  FROM platform_settings
  WHERE setting_key LIKE 'blocked:%'
)
WHERE id = 1
  AND EXISTS (SELECT 1 FROM platform_settings WHERE setting_key LIKE 'blocked:%');

-- Optional cleanup once you've confirmed the migrated list above looks
-- right — removes the old per-user rows so they don't linger unused.
-- DELETE FROM platform_settings WHERE setting_key LIKE 'blocked:%';

-- ── Row Level Security ──────────────────────────────────────────────────
-- system_settings holds escrow account numbers and the blocked-user list —
-- this must NOT be readable/writable by ordinary anon/authenticated
-- clients. Only admins (profiles.role = 'admin') get direct table access.
--
-- The one exception: auth_service.dart's isUserBlocked() runs for EVERY
-- signed-in user at login (to check if *they* are blocked), not just
-- admins. Rather than loosen the table's RLS to let that work, we expose
-- a narrow SECURITY DEFINER function that only ever returns a boolean —
-- it can read blocked_users internally without granting broader access.

ALTER TABLE system_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins can view system settings" ON system_settings;
CREATE POLICY "Admins can view system settings"
  ON system_settings FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid() AND profiles.role = 'admin'
    )
  );

DROP POLICY IF EXISTS "Admins can update system settings" ON system_settings;
CREATE POLICY "Admins can update system settings"
  ON system_settings FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid() AND profiles.role = 'admin'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid() AND profiles.role = 'admin'
    )
  );

DROP POLICY IF EXISTS "Admins can insert system settings" ON system_settings;
CREATE POLICY "Admins can insert system settings"
  ON system_settings FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE profiles.id = auth.uid() AND profiles.role = 'admin'
    )
  );

-- Narrow, safe check usable by any signed-in user — bypasses RLS
-- internally (SECURITY DEFINER) but only ever returns true/false, never
-- escrow details or the full blocked list.
CREATE OR REPLACE FUNCTION is_user_blocked(check_user_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  blocked BOOLEAN;
BEGIN
  SELECT check_user_id::TEXT = ANY(blocked_users) INTO blocked
  FROM system_settings WHERE id = 1;
  RETURN COALESCE(blocked, FALSE);
END;
$$;

GRANT EXECUTE ON FUNCTION is_user_blocked(UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';
