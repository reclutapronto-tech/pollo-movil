-- ========================================================
-- Migration: 20260420300000_permits_expiry_cron_schedule
-- Purpose:   Schedule permits_expiry_cron edge function hourly
--            via pg_cron + pg_net. Flips work_permits rows past
--            expires_at from 'issued' → 'expired' so reports and
--            the supervisor UI stay honest. The mobile clock-in
--            gate already computes 'active' inline, so a
--            late/skipped run never lets an expired permit pass
--            the gate — this job only keeps the admin UI honest.
-- Convention: matches the existing 'media-optimize' cron job.
--             Pulls CRON_SECRET + SUPABASE_URL from Vault secrets
--             that are already seeded on this project.
-- Idempotent: unschedule-if-exists before re-scheduling. Safe to
--             re-run. No-op for pg_cron / pg_net (already enabled).
-- ========================================================

-- pg_cron + pg_net are enabled project-wide. Ensure-only (no-op if present).
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_net  WITH SCHEMA extensions;

-- Unschedule any prior job of the same name so this migration is
-- safe to re-run on a project where it's already scheduled.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'permits-expiry') THEN
    PERFORM cron.unschedule('permits-expiry');
  END IF;
END
$$;

-- Schedule: minute 5 of every hour. Cheap, idempotent, and matches
-- the async posture of media-optimize (fire-and-forget http_post).
SELECT cron.schedule(
  'permits-expiry',
  '5 * * * *',
  $cron$
  SELECT net.http_post(
    url     := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'SUPABASE_URL')
               || '/functions/v1/permits_expiry_cron',
    headers := jsonb_build_object(
      'x-cron-secret', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'CRON_SECRET')
    )::jsonb,
    body    := '{}'::jsonb
  )
  $cron$
);

-- ========================================================
-- Summary (2026-04-20):
--   * Hourly cron 'permits-expiry' at '5 * * * *'.
--   * POSTs to {SUPABASE_URL}/functions/v1/permits_expiry_cron.
--   * x-cron-secret header pulled from Vault at call time.
--   * Reuses the pre-existing CRON_SECRET + SUPABASE_URL vault
--     secrets (same ones used by media-optimize).
-- ========================================================
