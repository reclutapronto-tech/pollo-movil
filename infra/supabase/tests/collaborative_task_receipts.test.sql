BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(9);
SELECT has_table('public', 'restaurant_task_receipts', 'task receipt is modeled independently from task completion');
SELECT has_table('public', 'restaurant_collaboration_requests', 'coworker notices have a persisted lifecycle');
SELECT has_table('public', 'restaurant_collaboration_events', 'collaboration actions have an event history');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'public.restaurant_task_receipts'::regclass),
  'receipt rows enforce row-level security');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'public.restaurant_collaboration_requests'::regclass),
  'notice rows enforce row-level security');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'public.restaurant_collaboration_events'::regclass),
  'event history enforces row-level security');
SELECT ok(NOT has_function_privilege('authenticated',
    'public.claim_restaurant_collaboration_request(uuid,uuid,uuid,integer)', 'EXECUTE'),
  'clients cannot bypass the authenticated Edge Function to claim a notice');
SELECT ok(has_function_privilege('service_role',
    'public.claim_restaurant_collaboration_request(uuid,uuid,uuid,integer)', 'EXECUTE'),
  'the trusted Edge Function can invoke the atomic claim operation');
SELECT ok(EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'restaurant_collaboration_events_append_only' AND NOT tgisinternal),
  'collaboration event history rejects direct mutation');

SELECT * FROM finish();
ROLLBACK;
