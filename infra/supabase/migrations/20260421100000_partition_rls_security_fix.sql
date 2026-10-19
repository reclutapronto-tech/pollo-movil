-- Security fix: close two confirmed multi-tenant data leaks.
--
-- BUG 1 — Event child-partition RLS bypass (CRITICAL).
--   The 9 partitioned event tables (clock_events, photo_events, task_events,
--   note_events, ot_requests, ot_approval_events, alert_events,
--   correction_events, shift_report_events) had RLS + tenant policies on the
--   ROOT only. In Postgres, a parent's policies cascade to partitions, but
--   enforcement on DIRECT child access requires the CHILD to have RLS enabled.
--   The child partitions (e.g. clock_events_2026_06) had RLS disabled and
--   default grants to anon/authenticated, so any user could read every
--   company's data by querying the child table directly through PostgREST.
--   Verified: parent SELECT returned 0 rows for `authenticated`, child returned
--   rows spanning multiple companies.
--   Fix: enable RLS on every existing child partition (parent policies then
--   apply) and revoke direct grants as defense-in-depth. A helper function
--   secures future partitions — partition-creation migrations MUST call it.
--
-- BUG 2 — background_jobs RLS never enabled (CRITICAL).
--   20260418000000 created a deny-all policy on background_jobs but no migration
--   ever ran ENABLE ROW LEVEL SECURITY, so the policy was inert and the async
--   job queue (payload jsonb) was world-readable/writable by anon/authenticated.
--   Fix: enable RLS (activates the existing deny-all policy) + revoke grants.
--
-- service_role has BYPASSRLS, so edge functions (which use the service key) are
-- unaffected by all of the below.

-- ── Helper: secure a single event partition (idempotent) ──────
-- Future partition-creation migrations should call:
--   SELECT public.secure_event_partition('public.clock_events_2026_07');
CREATE OR REPLACE FUNCTION public.secure_event_partition(child regclass)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY', child);
  EXECUTE format('REVOKE ALL ON %s FROM anon, authenticated', child);
END;
$$;

COMMENT ON FUNCTION public.secure_event_partition(regclass) IS
  'Enable RLS + revoke anon/authenticated grants on an event child partition so the partitioned parent''s tenant policies are enforced on direct access. Call this for every new partition.';

-- ── BUG 1: secure all existing child partitions of event roots ──
DO $$
DECLARE
  roots text[] := ARRAY[
    'clock_events','photo_events','task_events','note_events',
    'ot_requests','ot_approval_events','alert_events',
    'correction_events','shift_report_events'
  ];
  r text;
  child regclass;
BEGIN
  FOREACH r IN ARRAY roots LOOP
    -- skip roots that don't exist (defensive)
    IF to_regclass('public.'||r) IS NULL THEN
      CONTINUE;
    END IF;
    FOR child IN
      SELECT inhrelid::regclass
      FROM pg_inherits
      WHERE inhparent = ('public.'||r)::regclass
    LOOP
      PERFORM public.secure_event_partition(child);
    END LOOP;
  END LOOP;
END;
$$;

-- ── BUG 2: activate the dormant deny-all policy on background_jobs ──
ALTER TABLE public.background_jobs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.background_jobs FROM anon, authenticated;
