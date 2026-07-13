-- ============================================================
-- BEMENGEDE — FIX: "Failed to load payments" PGRST200 error
-- Run this in Supabase SQL Editor (Dashboard → SQL Editor → New query)
--
-- Root cause: lib/services/data_service.dart's fetchAllPayments() asks
-- PostgREST to embed profiles via a foreign key named
-- 'deliveries_sender_id_fkey', but no such constraint exists on
-- deliveries.sender_id -> profiles.id. Other tables (packages,
-- delivery_approvals, trips) already have this pattern; deliveries
-- was missed.
-- ============================================================

-- Add the FK only if it doesn't already exist under this name.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'deliveries_sender_id_fkey'
  ) THEN
    ALTER TABLE deliveries
      ADD CONSTRAINT deliveries_sender_id_fkey
      FOREIGN KEY (sender_id) REFERENCES profiles(id);
  END IF;
END $$;

-- While we're here, deliveries.traveler_id has the same "column exists,
-- FK missing" pattern used elsewhere for travelers — add it too so
-- admin/traveler-facing joins on deliveries don't hit the same error later.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'deliveries_traveler_id_fkey'
  ) THEN
    ALTER TABLE deliveries
      ADD CONSTRAINT deliveries_traveler_id_fkey
      FOREIGN KEY (traveler_id) REFERENCES profiles(id);
  END IF;
END $$;

-- PostgREST caches the schema — tell it to reload immediately instead of
-- waiting for the next automatic refresh.
NOTIFY pgrst, 'reload schema';

-- Sanity check — confirms both FKs now exist:
-- SELECT conname, conrelid::regclass AS table_name, confrelid::regclass AS references_table
-- FROM pg_constraint
-- WHERE conname IN ('deliveries_sender_id_fkey', 'deliveries_traveler_id_fkey');
