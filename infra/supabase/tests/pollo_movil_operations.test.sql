BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(8);
SELECT has_table('public', 'restaurant_branches', 'restaurant branches are migrated');
SELECT has_table('public', 'restaurant_tasks', 'restaurant tasks are migrated');
SELECT has_table('public', 'restaurant_task_events', 'offline task events are persisted');
SELECT has_table('public', 'restaurant_waste_inspection_results', 'waste inspection results are persisted');
SELECT has_column('public', 'restaurant_branches', 'enable_time_clock', 'attendance is configurable per branch');
SELECT has_column('public', 'restaurant_branches', 'require_gps_for_time_clock', 'GPS requirement is configurable per branch');
SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.restaurant_tasks'::regclass),
  'restaurant task rows are protected by RLS'
);
SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'restaurant_tasks'
      AND policyname = 'restaurant_tasks_member_read'
  ),
  'task reads are scoped to branch membership'
);
SELECT * FROM finish();
ROLLBACK;
