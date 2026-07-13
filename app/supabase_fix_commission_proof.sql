-- ============================================================
-- FIX 2 — Commission payment proof (screenshot upload + admin review)
-- Run this in Supabase SQL Editor (Dashboard → SQL Editor → New query)
--
-- Context: previously an admin could mark a commission "received" just by
-- typing a reference number, with nothing to back it up. This adds a real
-- submit → review → approve/reject loop: traveler pays, screenshots the
-- receipt, uploads it; admin reviews the image and approves or rejects
-- (with a reason, so the traveler knows what to fix on resubmit).
-- ============================================================

-- ── 1. New columns on deliveries ──────────────────────────────────────────
ALTER TABLE deliveries
  ADD COLUMN IF NOT EXISTS commission_proof_url          TEXT,
  ADD COLUMN IF NOT EXISTS commission_proof_submitted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS commission_rejection_reason   TEXT;

-- payment_status now cycles through:
--   commission_due → commission_proof_submitted → commission_paid
--   (or back to commission_due with commission_rejection_reason set, if
--   the admin rejects the proof)

-- ── 2. Storage bucket for proof screenshots ───────────────────────────────
-- Mirrors the existing 'kyc-documents' bucket pattern. Public read (same
-- trust model the app already uses for KYC docs via getPublicUrl) — if you
-- want these locked down further than KYC docs currently are, switch this
-- bucket to private and use createSignedUrl() instead of getPublicUrl() in
-- DataService.uploadCommissionProofFile().
INSERT INTO storage.buckets (id, name, public)
VALUES ('commission-proofs', 'commission-proofs', true)
ON CONFLICT (id) DO NOTHING;

-- Only the traveler on a delivery may upload proof for that delivery.
-- Path convention written by the app: '<delivery_id>/<timestamp>_proof'.
DROP POLICY IF EXISTS "Travelers can upload their own commission proof" ON storage.objects;
CREATE POLICY "Travelers can upload their own commission proof"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'commission-proofs'
    AND EXISTS (
      SELECT 1 FROM deliveries d
      WHERE d.id::text = (storage.foldername(name))[1]
        AND d.traveler_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Commission proofs are publicly readable" ON storage.objects;
CREATE POLICY "Commission proofs are publicly readable"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'commission-proofs');

-- ── 3. RLS — traveler can submit proof, only on their own delivery ────────
-- USING: row must belong to this traveler and currently be commission_due
-- (covers first submission AND resubmission after a rejection, since
-- rejection resets payment_status back to commission_due).
-- WITH CHECK: new row must still belong to them and move to
-- commission_proof_submitted only.
DROP POLICY IF EXISTS "Travelers can submit commission proof" ON deliveries;
CREATE POLICY "Travelers can submit commission proof"
  ON deliveries FOR UPDATE
  USING (auth.uid() = traveler_id AND payment_status = 'commission_due')
  WITH CHECK (auth.uid() = traveler_id AND payment_status = 'commission_proof_submitted');

-- ── 4. RLS — only admin can approve/reject proof ──────────────────────────
-- Adjust the email if your admin identification differs elsewhere in the
-- app (NotificationService.adminEmail is 'picklink237@gmail.com' today).
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

-- Verify:
--   SELECT polname, polcmd FROM pg_policy WHERE polrelid = 'deliveries'::regclass;
--   SELECT * FROM storage.buckets WHERE id = 'commission-proofs';
-- ============================================================
