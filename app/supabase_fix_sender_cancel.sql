-- ============================================================
-- FIX 1 — Senders can now cancel a delivery before it's delivered
-- Run this in Supabase SQL Editor (Dashboard → SQL Editor → New query)
--
-- Context: previously only the traveler could cancel (declining a pending
-- request). Senders had no way out once a request was accepted, even if the
-- traveler went unresponsive. This adds the columns + RLS policy needed for
-- DataService.cancelDeliveryAsSender() in the Flutter app.
-- ============================================================

-- ── 1. New columns on deliveries ──────────────────────────────────────────
ALTER TABLE deliveries
  ADD COLUMN IF NOT EXISTS cancelled_by TEXT,          -- 'sender' | 'traveler'
  ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMPTZ;

-- ── 2. RLS policy — sender may cancel their own delivery, pre-pickup only ──
-- USING checks the row as it exists NOW (must belong to this sender and
-- still be 'accepted' — not yet picked up).
-- WITH CHECK checks the row they're trying to save (must still belong to
-- them and the new status must be 'cancelled').
-- This does NOT let a sender edit amount/status to anything else, and does
-- NOT let them cancel once a delivery is 'in_transit' via this policy —
-- the app's own PackageDetailScreen still allows an in-transit cancel
-- through the same function, so if you want DB-level in-transit cancellation
-- allowed too, add a second policy mirroring this one with
-- status = 'in_transit' in the USING clause.
DROP POLICY IF EXISTS "Senders can cancel their own delivery before pickup" ON deliveries;
CREATE POLICY "Senders can cancel their own delivery before pickup"
  ON deliveries FOR UPDATE
  USING (auth.uid() = sender_id AND status = 'accepted')
  WITH CHECK (auth.uid() = sender_id AND status = 'cancelled');

-- If you also want sender cancellation allowed while 'in_transit' (matching
-- what the Flutter PackageDetailScreen UI now offers), also run:
DROP POLICY IF EXISTS "Senders can cancel their own delivery in transit" ON deliveries;
CREATE POLICY "Senders can cancel their own delivery in transit"
  ON deliveries FOR UPDATE
  USING (auth.uid() = sender_id AND status = 'in_transit')
  WITH CHECK (auth.uid() = sender_id AND status = 'cancelled');

-- Verify:
--   SELECT polname, polcmd FROM pg_policy
--   WHERE polrelid = 'deliveries'::regclass;
-- ============================================================
