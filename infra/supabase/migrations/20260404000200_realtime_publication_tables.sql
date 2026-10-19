-- ========================================================
-- Migration: 20260404000200_realtime_publication_tables
-- Purpose:   Register app tables with Supabase Realtime publication.
--            Without these entries, postgres_changes subscriptions
--            never receive inserts/updates from the local database.
-- ========================================================

DO $$
DECLARE
  realtime_table text;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication
    WHERE pubname = 'supabase_realtime'
  ) THEN
    RAISE NOTICE 'supabase_realtime publication does not exist; skipping registration';
    RETURN;
  END IF;

  FOREACH realtime_table IN ARRAY ARRAY[
    'public.clock_events',
    'public.photo_events',
    'public.task_events',
    'public.note_events',
    'public.ot_approval_events',
    'public.correction_events',
    'public.users',
    'public.jobs'
  ]
  LOOP
    IF NOT EXISTS (
      SELECT 1
      FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = split_part(realtime_table, '.', 1)
        AND tablename = split_part(realtime_table, '.', 2)
    ) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE %s', realtime_table);
    END IF;
  END LOOP;
END $$;
