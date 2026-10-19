-- Fix get_dashboard_overview: remove invalid 'done' task_status value
--
-- Bug: the function body included `t.status IN ('completed', 'done')` but
-- public.task_status enum is ('not_started', 'in_progress', 'blocked',
-- 'completed', 'skipped') — no 'done'. Postgres tried to cast the text
-- literal 'done' to the enum at runtime and raised, causing PostgREST to
-- return 400 to the browser. The dashboard hit this on every load for any
-- authenticated company (v_company_id resolves, CTE runs, enum cast fails).
--
-- Root cause: pre-RPC code in page.tsx was JS-side and compared with loose
-- equality against both 'completed' and 'done'; I carried that redundancy
-- into SQL without checking that 'done' was never a real enum member.
--
-- Fix: compare to 'completed' only. Same behavior — the JS check for 'done'
-- was dead code against this schema.

CREATE OR REPLACE FUNCTION public.get_dashboard_overview(p_job_limit integer DEFAULT 20)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
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
    active_jobs AS (
      SELECT j.id, j.name, j.code, j.status, j.site_name, j.geofence_radius_m
      FROM jobs j
      WHERE j.company_id = v_company_id
        AND j.deleted_at IS NULL
        AND j.status IN ('active', 'in_progress')
      ORDER BY j.created_at DESC
      LIMIT GREATEST(p_job_limit, 1)
    ),

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

    job_task_counts AS (
      SELECT
        t.job_id,
        COUNT(*)::int AS total,
        -- task_status enum is ('not_started', 'in_progress', 'blocked', 'completed', 'skipped').
        -- Earlier version included 'done' which isn't a valid enum value → Postgres raised,
        -- returning 400 to the browser. Drop it.
        COUNT(*) FILTER (WHERE t.status = 'completed')::int AS completed
      FROM tasks t
      JOIN active_jobs aj ON aj.id = t.job_id
      GROUP BY t.job_id
    ),

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

GRANT EXECUTE ON FUNCTION public.get_dashboard_overview(integer) TO authenticated;
