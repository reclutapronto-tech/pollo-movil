-- ========================================================
-- Migration: 20260421700000_event_partition_horizon
-- Purpose:   Close the event-store partition gap and stop it recurring.
--
-- BUG (found 2026-07-05): the 9 partitioned event roots were created with
-- monthly partitions for 2026-04..2026-06 only. From 2026-07-01 every new
-- clock/photo/task/OT/alert event lands in the *_default catch-all
-- partition — no pruning, dashboard queries degrade linearly forever, and
-- rows must be manually migrated out of DEFAULT before a proper partition
-- for that month can ever be attached (Postgres blocks overlapping ranges
-- while DEFAULT holds rows in-range).
--
-- Fix, in three parts:
--   1. ensure_event_partitions(months_ahead): creates any missing monthly
--      partitions from the current month through now()+months_ahead for all
--      9 roots, calling secure_event_partition() (20260421100000) on each so
--      new partitions inherit the RLS lockdown.
--      If the *_default partition already holds rows for a target month, the
--      function moves them into the new partition first (safe at beta scale;
--      revisit if _default ever exceeds ~100k rows).
--   2. Run it now for +6 months.
--   3. pg_cron job 'ensure-event-partitions' runs monthly so the horizon
--      keeps rolling without human intervention.
-- ========================================================

CREATE OR REPLACE FUNCTION public.ensure_event_partitions(months_ahead int DEFAULT 6)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  roots CONSTANT text[] := ARRAY[
    'clock_events','photo_events','task_events','note_events',
    'ot_requests','ot_approval_events','alert_events',
    'correction_events','shift_report_events'
  ];
  root         text;
  part_col     text;
  month_start  date;
  month_end    date;
  part_name    text;
  created      int := 0;
  moved        bigint;
BEGIN
  FOR i IN 0..months_ahead LOOP
    month_start := date_trunc('month', now())::date + (i || ' months')::interval;
    month_end   := month_start + interval '1 month';
    FOREACH root IN ARRAY roots LOOP
      IF to_regclass('public.' || root) IS NULL THEN
        CONTINUE;  -- defensive: root missing in this environment
      END IF;

      -- Partition column differs per root (ot_requests → requested_at,
      -- alert_events → triggered_at, rest → occurred_at). Resolve it from
      -- the catalog instead of assuming.
      SELECT a.attname INTO part_col
        FROM pg_partitioned_table pt
        JOIN pg_attribute a
          ON a.attrelid = pt.partrelid AND a.attnum = pt.partattrs[0]
       WHERE pt.partrelid = ('public.' || root)::regclass;
      IF part_col IS NULL THEN
        CONTINUE;  -- not actually partitioned; skip
      END IF;
      part_name := format('%s_%s', root, to_char(month_start, 'YYYY_MM'));
      IF to_regclass('public.' || part_name) IS NOT NULL THEN
        CONTINUE;  -- partition already exists
      END IF;

      -- If the DEFAULT partition holds rows inside the target range, park
      -- them in a temp table first — Postgres refuses to attach a range
      -- partition that overlaps rows currently in DEFAULT.
      EXECUTE format(
        'CREATE TEMP TABLE _repart AS
           SELECT * FROM %I_default
           WHERE %I >= %L AND %I < %L',
        root, part_col, month_start, part_col, month_end);
      EXECUTE format(
        'DELETE FROM %I_default
           WHERE %I >= %L AND %I < %L',
        root, part_col, month_start, part_col, month_end);

      EXECUTE format(
        'CREATE TABLE %I PARTITION OF %I FOR VALUES FROM (%L) TO (%L)',
        part_name, root, month_start, month_end);
      PERFORM public.secure_event_partition(('public.' || part_name)::regclass);

      EXECUTE format('INSERT INTO %I SELECT * FROM _repart', root);
      GET DIAGNOSTICS moved = ROW_COUNT;
      IF moved > 0 THEN
        RAISE NOTICE 'ensure_event_partitions: moved % rows from %_default into %',
          moved, root, part_name;
      END IF;
      DROP TABLE _repart;

      created := created + 1;
    END LOOP;
  END LOOP;
  RETURN created;
END;
$$;

COMMENT ON FUNCTION public.ensure_event_partitions(int) IS
  'Creates missing monthly partitions for the 9 event roots through now()+months_ahead, securing each with secure_event_partition() and rescuing any rows that already fell into the DEFAULT partition. Returns the number of partitions created. Scheduled monthly via pg_cron job ensure-event-partitions.';

-- Run immediately: cover the current gap plus a 6-month horizon.
SELECT public.ensure_event_partitions(6);

-- Keep the horizon rolling: 1st of every month at 02:10 UTC.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'ensure-event-partitions') THEN
    PERFORM cron.unschedule('ensure-event-partitions');
  END IF;
END
$$;

SELECT cron.schedule(
  'ensure-event-partitions',
  '10 2 1 * *',
  $cron$ SELECT public.ensure_event_partitions(6) $cron$
);

-- ========================================================
-- Summary (2026-07-05):
--   * ensure_event_partitions(months_ahead) helper (SECURITY DEFINER).
--   * Immediate run: creates 2026-07 .. 2027-01 partitions for all 9 roots,
--     each secured via secure_event_partition().
--   * pg_cron 'ensure-event-partitions' monthly on the 1st, 02:10 UTC.
--   * DEFAULT-partition rows in range are migrated into the new partition.
-- ========================================================
