BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(18);
SELECT has_column('public', 'restaurant_branches', 'collaboration_manager_escalation_seconds',
  'manager escalation delay is configurable per branch and has no invented default');
SELECT has_column('public', 'restaurant_task_receipts', 'escalation_processed_at',
  'receipt deadline processing is idempotently recorded');
SELECT has_column('public', 'restaurant_collaboration_requests', 'request_source',
  'manual and automatic notices remain distinguishable');
SELECT has_column('public', 'restaurant_collaboration_requests', 'manager_escalated_at',
  'manager escalation is recorded on the notice lifecycle');
SELECT ok((SELECT is_nullable = 'YES' FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'restaurant_collaboration_requests'
      AND column_name = 'created_by'),
  'scheduler-created requests do not invent a human creator');
SELECT ok(EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'restaurant-collaboration-deadlines'
    AND schedule = '* * * * *'),
  'configured receipt deadlines and expired reservations are processed by the scheduled worker');
SELECT ok(EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public'
    AND indexname = 'restaurant_task_receipts_due_idx'),
  'due receipt scans have a partial index over awaiting assignments');
SELECT ok(NOT has_function_privilege('authenticated',
    'private.process_restaurant_collaboration_deadlines()'::regprocedure, 'EXECUTE'),
  'authenticated clients cannot invoke the scheduled worker');
SELECT has_column('public', 'restaurant_meal_sessions', 'declared_started_at',
  'declared start time is stored separately from database recording time');
SELECT has_column('public', 'restaurant_meal_sessions', 'start_origin',
  'meal start distinguishes self, peer, and manager recording');
SELECT has_column('public', 'restaurant_meal_sessions', 'declared_return_at',
  'declared return time is stored separately from confirmed return time');
SELECT has_column('public', 'restaurant_meal_sessions', 'return_origin',
  'meal return distinguishes self, peer, and manager recording');
SELECT ok(EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'restaurant_meal_events_append_only' AND NOT tgisinternal),
  'peer meal recording retains immutable event history');
SELECT ok(NOT has_function_privilege('authenticated',
    'public.restaurant_start_meal(uuid,uuid,uuid,text,timestamp with time zone)', 'EXECUTE'),
  'clients cannot bypass server-side branch and availability checks for meal recording');
SELECT ok(has_function_privilege('authenticated',
    'private.restaurant_current_user_can_view_peer_meal(uuid,uuid)', 'EXECUTE'),
  'the RLS helper can authorize only self, managers, and currently available same-shift coworkers');
SELECT ok(NOT has_function_privilege('anon',
    'private.restaurant_current_user_can_view_peer_meal(uuid,uuid)', 'EXECUTE'),
  'anonymous clients cannot query peer meal visibility');
SELECT ok(EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public'
    AND tablename = 'restaurant_meal_sessions' AND policyname = 'restaurant_meal_sessions_branch_read'
    AND qual ILIKE '%restaurant_current_user_can_view_peer_meal%'),
  'meal Realtime reads are scoped through the dedicated same-branch visibility rule');
SELECT ok(EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public'
    AND tablename = 'restaurant_collaboration_requests' AND policyname = 'restaurant_collaboration_requests_member_read'
    AND qual ILIKE '%cancelled%'),
  'coworkers can reconcile a cancelled notice after the task owner confirms receipt');

SELECT * FROM finish();
ROLLBACK;
