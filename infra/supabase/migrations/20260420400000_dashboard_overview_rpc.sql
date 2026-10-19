-- Dashboard overview RPC
--
-- Background: the supervisor dashboard previously fired 6 parallel Supabase
-- queries on every open, including a `tasks` scan with no LIMIT that could
-- return every task in the company. At ~500 jobs × 20 tasks that's 10k rows
-- shipped over the wire to render a single "completed/total" progress bar.
--
-- This RPC consolidates the dashboard payload into one round-trip with the
-- aggregations done server-side. It runs STABLE + SECURITY INVOKER so RLS on
-- the underlying tables keeps multi-tenant isolation intact — callers only
-- see their own company's data. The function takes no args; it resolves the
-- caller's company via current_company_id() to avoid trust issues with a
-- client-supplied parameter.
--
-- Return shape (jsonb):
--   {
--     "stats":              { "totalJobs", "activeWorkers", "photosToday", "pendingOT" },
--     "jobs":               [ { id, name, code, status, site_name, geofence_radius_m } ],
--     "activeWorkers":      [ { user_id, full_name, status, hours, first_clock_in_at } ],
--     "jobTaskCounts":      [ { job_id, total, completed } ]
--   }
--
-- `jobs` is capped at 20 rows (first page). The dashboard still has its own
-- loadMoreJobs() that paginates via the jobs table directly for page 2+.

CREATE OR REPLACE FUNCTION public.get_dashboard_overview(p_job_limit integer DEFAULT 20)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER  -- RLS on underlying tables enforces tenant isolation.
STABLE
SET search_path = public
AS $$
DECLARE
  v_company_id uuid := current_company_id();
  v_today_start timestamptz := date_trunc('day', now());
  v_result jsonb;
BEGIN
  IF v_company_id IS NULL THEN
    RETURN jsonb_build_object(
      'stats',         jsonb_build_object('totalJobs', 0, 'activeWorkers', 0, 'photosToday', 0, 'pendingOT', 0),
      'jobs',          '[]'::jsonb,
      'activeWorkers', '[]'::jsonb,
      'jobTaskCounts', '[]'::jsonb
    );
  END IF;

  WITH
    -- First page of active jobs (same order the dashboard already uses).
    active_jobs AS (
      SELECT j.id, j.name, j.code, j.status, j.site_name, j.geofence_radius_m
      FROM jobs j
      WHERE j.company_id = v_company_id
        AND j.deleted_at IS NULL
        AND j.status IN ('active', 'in_progress')
      ORDER BY j.created_at DESC
      LIMIT GREATEST(p_job_limit, 1)
    ),

    -- All clock events today for the company (used for both activeWorkers list
    -- and the activeWorkers count stat).
    today_clock AS (
      SELECT
        ce.user_id,
        ce.event_subtype,
        ce.occurred_at,
        u.full_name
      FROM clock_events ce
      JOIN users u ON u.id = ce.user_id
      WHERE ce.company_id = v_company_id
        AND ce.occurred_at >= v_today_start
        AND ce.event_subtype IN ('clock_in', 'clock_out', 'break_start', 'break_end')
    ),

    -- Per-worker: their LATEST event today + their EARLIEST clock_in today.
    -- A worker is "active" when their latest event is not a clock_out.
    worker_latest AS (
      SELECT DISTINCT ON (user_id)
        user_id, full_name, event_subtype AS latest_subtype, occurred_at AS latest_at
      FROM today_clock
      ORDER BY user_id, occurred_at DESC
    ),
    worker_first_in AS (
      SELECT user_id, MIN(occurred_at) AS first_in_at
      FROM today_clock
      WHERE event_subtype = 'clock_in'
      GROUP BY user_id
    ),
    active_workers AS (
      SELECT
        wl.user_id,
        wl.full_name,
        CASE WHEN wl.latest_subtype = 'break_start' THEN 'break' ELSE 'working' END AS status,
        wfi.first_in_at
      FROM worker_latest wl
      LEFT JOIN worker_first_in wfi ON wfi.user_id = wl.user_id
      WHERE wl.latest_subtype <> 'clock_out'
    ),

    -- Task aggregates per active job only (no full-table scan).
    job_task_counts AS (
      SELECT
        t.job_id,
        COUNT(*)::int AS total,
        COUNT(*) FILTER (WHERE t.status IN ('completed', 'done'))::int AS completed
      FROM tasks t
      JOIN active_jobs aj ON aj.id = t.job_id
      GROUP BY t.job_id
    ),

    -- Scalar stats.
    stats AS (
      SELECT
        (SELECT COUNT(*) FROM active_jobs)::int AS total_jobs,
        (SELECT COUNT(DISTINCT user_id) FROM today_clock WHERE event_subtype = 'clock_in')::int AS active_workers,
        (SELECT COUNT(*) FROM photo_events
          WHERE company_id = v_company_id AND occurred_at >= v_today_start)::int AS photos_today,
        (SELECT COUNT(*) FROM ot_requests
          WHERE company_id = v_company_id AND status = 'pending')::int AS pending_ot
    )

  SELECT jsonb_build_object(
    'stats', (
      SELECT jsonb_build_object(
        'totalJobs',     s.total_jobs,
        'activeWorkers', s.active_workers,
        'photosToday',   s.photos_today,
        'pendingOT',     s.pending_ot
      ) FROM stats s
    ),
    'jobs', COALESCE(
      (SELECT jsonb_agg(to_jsonb(aj)) FROM active_jobs aj),
      '[]'::jsonb
    ),
    'activeWorkers', COALESCE(
      (SELECT jsonb_agg(jsonb_build_object(
        'user_id',          aw.user_id,
        'full_name',        aw.full_name,
        'status',           aw.status,
        'first_clock_in_at', aw.first_in_at
      )) FROM active_workers aw),
      '[]'::jsonb
    ),
    'jobTaskCounts', COALESCE(
      (SELECT jsonb_agg(jsonb_build_object(
        'job_id',    jtc.job_id,
        'total',     jtc.total,
        'completed', jtc.completed
      )) FROM job_task_counts jtc),
      '[]'::jsonb
    )
  )
  INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.get_dashboard_overview(integer) IS
  'Single-round-trip dashboard payload. Resolves company from the caller via current_company_id(); RLS on jobs/clock_events/photo_events/ot_requests/tasks/users still applies under SECURITY INVOKER. Replaces 6 parallel queries + an unbounded tasks scan.';

-- Grants: authenticated users call this; RLS handles which company's data they see.
GRANT EXECUTE ON FUNCTION public.get_dashboard_overview(integer) TO authenticated;
