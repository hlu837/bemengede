-- ============================================================
-- BEMENGEDE — FIX: "optional" Add Trip fields being enforced as mandatory
-- Run this in Supabase SQL Editor (Dashboard → SQL Editor → New query)
--
-- Root cause: the Flutter form never actually required these fields
-- client-side, so the block was coming from the database — either the
-- column doesn't exist yet, or it was created NOT NULL. This makes sure
-- both optional trip columns exist and are nullable.
-- ============================================================

-- Custom Pricing Description — genuinely optional, must allow NULL.
ALTER TABLE trips
  ADD COLUMN IF NOT EXISTS custom_price_description TEXT;
ALTER TABLE trips
  ALTER COLUMN custom_price_description DROP NOT NULL;

-- Max Weight (kg) — required in the UI, but make sure it exists as a
-- normal nullable numeric column too (no CHECK/NOT NULL leftover from an
-- earlier schema) so a bad client-side value never breaks other rows.
ALTER TABLE trips
  ADD COLUMN IF NOT EXISTS available_weight DOUBLE PRECISION;
ALTER TABLE trips
  ALTER COLUMN available_weight DROP NOT NULL;

-- Quick sanity check — run this after the above to confirm nullability:
-- SELECT column_name, is_nullable, data_type
-- FROM information_schema.columns
-- WHERE table_name = 'trips'
--   AND column_name IN ('custom_price_description', 'available_weight');
