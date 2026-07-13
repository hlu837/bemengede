-- ============================================================
-- FIX 3 — Remaining gaps from code review (2026-07-08)
-- Run this in Supabase SQL Editor (Dashboard → SQL Editor → New query)
--
-- Closes, at the database layer (so it holds regardless of client bugs):
--   #4  Dual-role self-match — a user could be matched with themselves
--       via delivery_approvals / deliveries / traveler_offers. The app
--       already blocks this in the two request-flow screens, but nothing
--       stopped it at the data layer.
--   #6  Disputes had no teeth — filing one just inserted a row; nothing
--       stopped the commission-payment flow from continuing underneath
--       an open dispute. This adds a has_open_dispute flag, kept in sync
--       by trigger, and wires it into the commission RLS policies so the
--       money can't move while a dispute is open.
-- ============================================================

-- ── 1. Self-match — DB-level CHECK constraints ─────────────────────────────
-- deliveries and delivery_approvals both carry sender_id + traveler_id on
-- the same row, so a simple CHECK is enough.

ALTER TABLE deliveries
  DROP CONSTRAINT IF EXISTS deliveries_no_self_match;
ALTER TABLE deliveries
  ADD CONSTRAINT deliveries_no_self_match CHECK (sender_id <> traveler_id);

ALTER TABLE delivery_approvals
  DROP CONSTRAINT IF EXISTS delivery_approvals_no_self_match;
ALTER TABLE delivery_approvals
  ADD CONSTRAINT delivery_approvals_no_self_match CHECK (sender_id <> traveler_id);

-- traveler_offers only carries traveler_id directly — sender is reached via
-- package_id → packages.sender_id — so a CHECK constraint can't express
-- this on its own; use a trigger instead.

CREATE OR REPLACE FUNCTION check_traveler_offer_not_self_match()
RETURNS TRIGGER AS $$
DECLARE
  pkg_sender_id UUID;
BEGIN
  SELECT sender_id INTO pkg_sender_id FROM packages WHERE id = NEW.package_id;
  IF pkg_sender_id IS NOT NULL AND pkg_sender_id = NEW.traveler_id THEN
    RAISE EXCEPTION 'You cannot make an offer on your own package.';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_traveler_offer_no_self_match ON traveler_offers;
CREATE TRIGGER trg_traveler_offer_no_self_match
  BEFORE INSERT OR UPDATE ON traveler_offers
  FOR EACH ROW EXECUTE FUNCTION check_traveler_offer_not_self_match();

-- ── 2. Disputes get teeth — has_open_dispute flag on deliveries ───────────

ALTER TABLE deliveries
  ADD COLUMN IF NOT EXISTS has_open_dispute BOOLEAN NOT NULL DEFAULT false;

-- Keep the flag in sync with the disputes table automatically, so it's
-- correct no matter which admin action (or future code path) changes a
-- dispute's status.
CREATE OR REPLACE FUNCTION sync_delivery_dispute_flag()
RETURNS TRIGGER AS $$
DECLARE
  target_delivery_id UUID;
  still_open BOOLEAN;
BEGIN
  target_delivery_id := COALESCE(NEW.delivery_id, OLD.delivery_id);

  SELECT EXISTS (
    SELECT 1 FROM disputes
    WHERE delivery_id = target_delivery_id AND status = 'open'
  ) INTO still_open;

  UPDATE deliveries SET has_open_dispute = still_open WHERE id = target_delivery_id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_delivery_dispute_flag ON disputes;
CREATE TRIGGER trg_sync_delivery_dispute_flag
  AFTER INSERT OR UPDATE OR DELETE ON disputes
  FOR EACH ROW EXECUTE FUNCTION sync_delivery_dispute_flag();

-- Backfill existing rows so the flag is correct before the trigger takes over.
UPDATE deliveries d
SET has_open_dispute = EXISTS (
  SELECT 1 FROM disputes s WHERE s.delivery_id = d.id AND s.status = 'open'
);

-- Wire the flag into the commission-proof RLS policies from FIX 2 so the
-- payment can't move forward while a dispute is open on the delivery.
DROP POLICY IF EXISTS "Travelers can submit commission proof" ON deliveries;
CREATE POLICY "Travelers can submit commission proof"
  ON deliveries FOR UPDATE
  USING (auth.uid() = traveler_id AND payment_status = 'commission_due' AND NOT has_open_dispute)
  WITH CHECK (auth.uid() = traveler_id AND payment_status = 'commission_proof_submitted');

DROP POLICY IF EXISTS "Admin can approve or reject commission proof" ON deliveries;
CREATE POLICY "Admin can approve or reject commission proof"
  ON deliveries FOR UPDATE
  USING (
    payment_status = 'commission_proof_submitted'
    AND EXISTS (
      SELECT 1 FROM profiles p
      WHERE p.id = auth.uid() AND p.email = 'picklink237@gmail.com'
    )
  )
  WITH CHECK (
    payment_status IN ('commission_paid', 'commission_due')
    AND EXISTS (
      SELECT 1 FROM profiles p
      WHERE p.id = auth.uid() AND p.email = 'picklink237@gmail.com'
    )
  );

-- Manual override (admin marking paid without proof — see app change in
-- FIX 3) also needs to be blocked while a dispute is open. This policy
-- covers the commission_due → commission_paid transition directly.
DROP POLICY IF EXISTS "Admin can manually mark commission paid" ON deliveries;
CREATE POLICY "Admin can manually mark commission paid"
  ON deliveries FOR UPDATE
  USING (
    payment_status = 'commission_due'
    AND NOT has_open_dispute
    AND EXISTS (
      SELECT 1 FROM profiles p
      WHERE p.id = auth.uid() AND p.email = 'picklink237@gmail.com'
    )
  )
  WITH CHECK (
    payment_status = 'commission_paid'
    AND EXISTS (
      SELECT 1 FROM profiles p
      WHERE p.id = auth.uid() AND p.email = 'picklink237@gmail.com'
    )
  );

-- Verify:
--   SELECT conname FROM pg_constraint WHERE conname LIKE '%no_self_match%';
--   SELECT tgname FROM pg_trigger WHERE tgname IN
--     ('trg_traveler_offer_no_self_match', 'trg_sync_delivery_dispute_flag');
--   SELECT id, has_open_dispute FROM deliveries WHERE has_open_dispute = true;
-- ============================================================
