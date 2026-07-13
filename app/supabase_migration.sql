-- ============================================================
-- BEMENGEDE — SUPABASE MIGRATION SQL
-- Run this in Supabase SQL Editor (Dashboard → SQL Editor → New query)
-- ============================================================

-- ── 1. TRIPS TABLE — rename city/country columns to area + add lat/lng ────────

ALTER TABLE trips
  ADD COLUMN IF NOT EXISTS from_area       TEXT,
  ADD COLUMN IF NOT EXISTS to_area         TEXT,
  ADD COLUMN IF NOT EXISTS from_lat        DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS from_lng        DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS to_lat          DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS to_lng          DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS current_lat     DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS current_lng     DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS last_location_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS price           DOUBLE PRECISION;

-- Migrate existing data (copy old city fields into new area fields)
UPDATE trips SET
  from_area = COALESCE(from_city, 'Unknown'),
  to_area   = COALESCE(to_city,   'Unknown'),
  price     = price_per_kg
WHERE from_area IS NULL;

-- Drop old columns (only after verifying migration looks correct)
-- ALTER TABLE trips DROP COLUMN IF EXISTS from_city;
-- ALTER TABLE trips DROP COLUMN IF EXISTS to_city;
-- ALTER TABLE trips DROP COLUMN IF EXISTS from_country;
-- ALTER TABLE trips DROP COLUMN IF EXISTS to_country;
-- ALTER TABLE trips DROP COLUMN IF EXISTS price_per_kg;

-- ── 2. PACKAGES TABLE — enforce 5kg limit + add expires_at ───────────────────

ALTER TABLE packages
  ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;

-- Database-level weight constraint (blocks anything over 5kg at DB level)
ALTER TABLE packages
  DROP CONSTRAINT IF EXISTS packages_weight_max;
ALTER TABLE packages
  ADD CONSTRAINT packages_weight_max CHECK (weight <= 5);

-- Auto-set expires_at to 2 hours after creation for new packages
CREATE OR REPLACE FUNCTION set_package_expiry()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.expires_at IS NULL THEN
    NEW.expires_at := NOW() + INTERVAL '2 hours';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_package_expiry ON packages;
CREATE TRIGGER trg_package_expiry
  BEFORE INSERT ON packages
  FOR EACH ROW EXECUTE FUNCTION set_package_expiry();

-- ── 3. DELIVERIES TABLE — add pickup_at, expires_at, completed_at ────────────

ALTER TABLE deliveries
  ADD COLUMN IF NOT EXISTS pickup_at     TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS expires_at    TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS completed_at  TIMESTAMPTZ;

-- Auto-set expires_at to 5 hours after pickup when status goes in_transit
CREATE OR REPLACE FUNCTION set_delivery_expiry()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status = 'in_transit' AND OLD.status != 'in_transit' THEN
    NEW.pickup_at  := NOW();
    NEW.expires_at := NOW() + INTERVAL '5 hours';
  END IF;
  IF NEW.status = 'completed' AND OLD.status != 'completed' THEN
    NEW.completed_at := NOW();
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_delivery_expiry ON deliveries;
CREATE TRIGGER trg_delivery_expiry
  BEFORE UPDATE ON deliveries
  FOR EACH ROW EXECUTE FUNCTION set_delivery_expiry();

-- ── 4. RATINGS TABLE ──────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS ratings (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_id UUID REFERENCES deliveries(id) ON DELETE CASCADE,
  rater_id    UUID REFERENCES profiles(id)   ON DELETE CASCADE,
  ratee_id    UUID REFERENCES profiles(id)   ON DELETE CASCADE,
  stars       SMALLINT NOT NULL CHECK (stars BETWEEN 1 AND 5),
  comment     TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- Prevent duplicate ratings on the same delivery by same rater
ALTER TABLE ratings
  DROP CONSTRAINT IF EXISTS ratings_unique_per_delivery;
ALTER TABLE ratings
  ADD CONSTRAINT ratings_unique_per_delivery UNIQUE (delivery_id, rater_id);

-- RLS for ratings
ALTER TABLE ratings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can insert their own ratings"
  ON ratings FOR INSERT
  WITH CHECK (auth.uid() = rater_id);

CREATE POLICY "Ratings are publicly readable"
  ON ratings FOR SELECT
  USING (true);

-- ── 5. PROFILES TABLE — add avg_rating and review_count if missing ────────────

ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS avg_rating   DOUBLE PRECISION DEFAULT 0,
  ADD COLUMN IF NOT EXISTS review_count INTEGER DEFAULT 0;

-- ── 6. AUTO-EXPIRE STALE PACKAGE REQUESTS (Supabase pg_cron) ─────────────────
-- This runs every 30 minutes and expires pending packages nobody accepted.
-- This is the SOURCE OF TRUTH for request expiration — it runs on Supabase's
-- own infra regardless of whether anyone has the app open. The equivalent
-- Dart function (DataService.expireOldRequests) is only kept as a redundant,
-- instant fallback for when a user happens to be in the app; it is NOT
-- required for correctness once this job is scheduled.
--
-- FIX 2026-07-01: this used to require manually toggling pg_cron on in the
-- Dashboard before this file would work. It's now created inline below —
-- Supabase's postgres role is allowed to create this specific extension, so
-- running this whole migration in the SQL Editor is enough on its own.

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;

-- cron.schedule() upserts by job name, so re-running this migration is safe
-- and just replaces the existing schedule rather than erroring or duplicating.
SELECT cron.schedule(
  'expire-pending-packages',
  '*/30 * * * *',
  $$
    UPDATE packages
    SET status = 'expired'
    WHERE status = 'pending'
      AND expires_at IS NOT NULL
      AND expires_at < NOW();
  $$
);

-- Verify it's actually scheduled (run this any time to confirm):
--   SELECT jobname, schedule, active FROM cron.job WHERE jobname = 'expire-pending-packages';
-- Verify it's actually firing (run this to see recent runs):
--   SELECT * FROM cron.job_run_details
--   WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname = 'expire-pending-packages')
--   ORDER BY start_time DESC LIMIT 5;

-- ── 7. ENFORCE MAX 2 ACTIVE PACKAGES PER TRAVELER (DB function) ───────────────

CREATE OR REPLACE FUNCTION check_traveler_package_limit()
RETURNS TRIGGER AS $$
DECLARE
  active_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO active_count
  FROM delivery_approvals
  WHERE traveler_id = NEW.traveler_id
    AND status IN ('accepted', 'in_transit');

  IF active_count >= 2 THEN
    RAISE EXCEPTION 'Traveler already has 2 active packages. Maximum limit reached.';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_check_package_limit ON delivery_approvals;
CREATE TRIGGER trg_check_package_limit
  BEFORE INSERT ON delivery_approvals
  FOR EACH ROW EXECUTE FUNCTION check_traveler_package_limit();

-- ============================================================
-- DONE. All constraints are now enforced at database level.
-- ============================================================

-- ── ADDITIONAL — server-side overdue delivery notifications ──────────────
-- The Flutter checkAndReportExpiredDeliveries() call only fires when an
-- admin happens to have the dashboard open, which isn't good enough for a
-- 4-hour SLA. This mirrors the pg_cron pattern already used for package/
-- delivery auto-expiry so overdue reporting runs on a schedule regardless
-- of whether anyone has the app open.
--
-- Requires an `overdue_notified BOOLEAN DEFAULT false` column on
-- delivery_approvals so each overdue delivery is only reported once.

ALTER TABLE delivery_approvals
  ADD COLUMN IF NOT EXISTS overdue_notified BOOLEAN DEFAULT false;

CREATE OR REPLACE FUNCTION report_overdue_deliveries()
RETURNS void AS $$
DECLARE
  rec RECORD;
  admin_id UUID;
BEGIN
  SELECT id INTO admin_id FROM profiles WHERE email = 'picklink237@gmail.com';

  FOR rec IN
    SELECT da.id, da.traveler_id, da.sender_id, p.title AS package_title
    FROM delivery_approvals da
    LEFT JOIN packages p ON p.id = da.package_id
    WHERE da.status IN ('accepted', 'in_transit')
      AND da.approved_at < now() - interval '4 hours'
      AND da.overdue_notified = false
  LOOP
    INSERT INTO notifications (user_id, title, body, type, read) VALUES
      (rec.traveler_id, 'Delivery overdue',
       'Your delivery of "' || COALESCE(rec.package_title, 'Package') || '" has exceeded the 4-5 hour limit. Please complete or report the delivery immediately.',
       'delivery_overdue', false),
      (rec.sender_id, 'Delivery delayed',
       'Your package "' || COALESCE(rec.package_title, 'Package') || '" has not been delivered within the expected time. We are investigating.',
       'delivery_overdue', false);

    IF admin_id IS NOT NULL THEN
      INSERT INTO notifications (user_id, title, body, type, read) VALUES
        (admin_id, 'Overdue delivery report',
         'Delivery of "' || COALESCE(rec.package_title, 'Package') || '" (id: ' || rec.id || ') has exceeded 4 hours.',
         'admin_overdue_report', false);
    END IF;

    UPDATE delivery_approvals SET overdue_notified = true WHERE id = rec.id;
  END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Runs every 30 minutes. pg_cron was already enabled in section 6 above —
-- if you're running this block on its own (not as part of the full
-- migration), add `CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;`
-- before this line first.
SELECT cron.schedule(
  'report-overdue-deliveries',
  '*/30 * * * *',
  $$SELECT report_overdue_deliveries();$$
);

-- Verify: SELECT jobname, schedule, active FROM cron.job;

-- ── ADDITIONAL — chat_messages table is now unused ────────────────────────
-- Confirmed: no direct sender-traveler chat, only user-to-support (which
-- already exists via the separate support ticketing system). The Flutter
-- code that wrote to chat_messages has been removed. Left the DROP
-- commented out since it may hold data — uncomment once you've confirmed
-- there's nothing worth keeping.
-- DROP TABLE IF EXISTS chat_messages;

-- ── ADDITIONAL — allow 'paused' as a trip status ──────────────────────────
-- The traveler dashboard's online/offline toggle now sets trips to 'paused'
-- instead of misusing 'completed'. If trips.status has a CHECK constraint,
-- find its name first (Supabase Dashboard → Database → trips → constraints,
-- or `SELECT conname FROM pg_constraint WHERE conrelid = 'trips'::regclass;`)
-- and replace the constraint name below before running this.
--
-- ALTER TABLE trips DROP CONSTRAINT IF EXISTS <your_status_check_constraint_name>;
-- ALTER TABLE trips ADD CONSTRAINT trips_status_check
--   CHECK (status IN ('active', 'paused', 'completed', 'cancelled'));
