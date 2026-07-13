-- supabase_add_requested_by.sql
--
-- Two-way request model: a delivery_approvals row can now be created by
-- EITHER side —
--   'traveler' → traveler saw the package in "Available Packages" and
--                requested to carry it (sender must approve)
--   'sender'   → sender saw the trip in "Find Commuters" and requested
--                that traveler (traveler must approve)
--
-- The receiving side sees it in their "Requests" inbox and approves or
-- declines. Approving one request for a package auto-rejects every other
-- still-pending request for that same package (see app-side
-- respondToDeliveryApproval), so multiple travelers can request the same
-- package but only one ever wins it.

ALTER TABLE delivery_approvals
  ADD COLUMN IF NOT EXISTS requested_by TEXT NOT NULL DEFAULT 'traveler'
  CHECK (requested_by IN ('traveler', 'sender'));

-- Existing rows all came from the traveler-accepts flow, so the default
-- above backfills them correctly with no further action needed.
