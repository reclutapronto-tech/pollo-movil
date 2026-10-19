-- Add geofence enforcement toggle to jobs.
--
-- Background: some workers (remote / hybrid / office-based supporting field
-- crews) need to clock in from anywhere. Previously every job required the
-- worker to be inside `geofence_radius_m` of `site_lat/site_lng` — this is
-- enforced by `sync_events` edge function via a haversine distance check.
--
-- With this flag, supervisors can opt-out of geofence enforcement per job.
-- When `geofence_enforced = false`, clock-in is allowed from anywhere as long
-- as the GPS coordinates are valid (we still log the location for audit).
--
-- Default is `true` so existing jobs keep their current strict behavior.

ALTER TABLE jobs
  ADD COLUMN IF NOT EXISTS geofence_enforced boolean NOT NULL DEFAULT true;

COMMENT ON COLUMN jobs.geofence_enforced IS
  'When false, clock-in skips the haversine distance check. Workers can clock in from anywhere with valid GPS. Default true keeps existing strict behavior.';
