CREATE INDEX IF NOT EXISTS restaurant_task_pause_context_idx
  ON public.restaurant_task_events (branch_id, task_id, occurred_at DESC)
  WHERE event_type = 'pause' AND note IS NOT NULL;

CREATE INDEX IF NOT EXISTS restaurant_time_sessions_branch_clock_in_idx
  ON public.restaurant_time_sessions (branch_id, clock_in_at DESC);

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_publication WHERE pubname = 'supabase_realtime')
    AND NOT EXISTS (
      SELECT 1 FROM pg_catalog.pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = 'restaurant_time_sessions'
    ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.restaurant_time_sessions;
  END IF;
END;
$$;
