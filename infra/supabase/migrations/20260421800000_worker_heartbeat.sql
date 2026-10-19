-- ========================================================
-- Migration: 20260421800000_worker_heartbeat
-- Purpose:   FUX-015 — worker "last seen" heartbeat.
--
-- Mobile pings public.touch_last_seen() every few minutes while the app is
-- foregrounded (and on resume). /workers and /crew can then render
-- "last ping 18 min ago"; a clocked-in worker whose phone has gone dark
-- (dead battery, out of coverage, app killed) shows amber >30 min and red
-- >2 h instead of silently looking on-shift forever.
--
-- Design notes:
--   * Column on users (not a separate table): one row per user, overwrite
--     semantics, no growth, no partitioning concerns. app_version comes
--     along because "worker is on a 3-week-old build" answers half of all
--     support tickets.
--   * SECURITY DEFINER RPC instead of an UPDATE policy on users: workers
--     have no UPDATE grant on users today and widening that for two columns
--     would invite privilege creep. The RPC updates only auth.uid()'s row.
--   * No RLS change needed for reads — company SELECT policy on users
--     already exposes the new columns to teammates.
-- ========================================================

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS last_seen_at timestamptz,
  ADD COLUMN IF NOT EXISTS last_seen_app_version text;

COMMENT ON COLUMN public.users.last_seen_at IS
  'Last mobile-app heartbeat (touch_last_seen RPC). NULL = never pinged (e.g. web-only users).';

CREATE OR REPLACE FUNCTION public.touch_last_seen(app_version text DEFAULT NULL)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE public.users
     SET last_seen_at = now(),
         last_seen_app_version = COALESCE(app_version, last_seen_app_version)
   WHERE id = auth.uid();
$$;

COMMENT ON FUNCTION public.touch_last_seen(text) IS
  'Heartbeat: stamps last_seen_at (and optionally app version) on the caller''s own users row. Called by the mobile app every ~4 minutes while foregrounded.';

REVOKE ALL ON FUNCTION public.touch_last_seen(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.touch_last_seen(text) TO authenticated;

-- ========================================================
-- Summary (2026-07-05):
--   * users.last_seen_at + users.last_seen_app_version columns.
--   * touch_last_seen(app_version) RPC — SECURITY DEFINER, self-row only,
--     EXECUTE granted to authenticated.
-- ========================================================
