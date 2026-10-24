BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(26);
SELECT has_column('public', 'restaurant_branches', 'receipt_escalation_seconds_by_priority',
  'unconfirmed task receipt escalation deadlines are configurable by branch and priority');
SELECT has_column('public', 'restaurant_positions', 'area_id',
  'positions can be explicitly linked to one same-branch area');
SELECT has_column('public', 'restaurant_branches', 'minimum_area_coverage',
  'minimum coverage is configured per branch rather than hardcoded');
SELECT has_table('public', 'restaurant_operational_recommendations',
  'coverage findings are persisted with their source and human decision');
SELECT has_table('public', 'restaurant_operational_state_events',
  'availability transitions retain a separate operational history');
SELECT ok(EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'restaurant_operational_state_events_append_only' AND NOT tgisinternal),
  'availability event history cannot be rewritten or deleted');
SELECT ok(NOT has_table_privilege('authenticated', 'public.restaurant_operational_state_events', 'INSERT'),
  'employees cannot forge availability history directly');
SELECT has_table('public', 'restaurant_meal_plan_proposals',
  'meal plans persist separately from actually started meals');
SELECT has_table('public', 'restaurant_meal_plan_slots',
  'approved meal schedules synchronize per employee without exposing coworkers');
SELECT has_column('public', 'restaurant_task_reports', 'recorded_by',
  'collaborative task reports preserve the recorder identity separately');
SELECT has_column('public', 'restaurant_meal_sessions', 'return_confirmed_at',
  'meal return is confirmed explicitly rather than inferred from elapsed time');
SELECT has_column('public', 'restaurant_meal_plan_proposals', 'planning_inputs',
  'proposal constraints are retained for later manager-edited schedule validation');
SELECT ok(EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public'
    AND indexname = 'restaurant_coverage_recommendation_interval_uidx'),
  'repeated analysis of the same area and time interval is deduplicated atomically');
SELECT ok(NOT has_function_privilege('authenticated',
    'public.restaurant_record_coverage_recommendation(uuid,uuid,timestamp with time zone,timestamp with time zone,jsonb,text,text)', 'EXECUTE'),
  'clients cannot write recommendations directly');
SELECT ok(has_function_privilege('service_role',
    'public.restaurant_record_coverage_recommendation(uuid,uuid,timestamp with time zone,timestamp with time zone,jsonb,text,text)', 'EXECUTE'),
  'the trusted operation endpoint can record manager-authorized findings');
SELECT ok(has_function_privilege('service_role',
    'public.restaurant_get_available_collaborator_ids(uuid)', 'EXECUTE'),
  'the trusted API can filter active coworker notices by operational availability');
SELECT ok(NOT has_function_privilege('authenticated',
    'public.restaurant_get_available_collaborator_ids(uuid)', 'EXECUTE'),
  'employees cannot enumerate coworkers availability outside their own UI');
SELECT ok(EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public'
    AND tablename = 'restaurant_meal_sessions' AND policyname = 'restaurant_meal_sessions_branch_read'
    AND qual ILIKE '%employee_id%'),
  'meal session Realtime reads are limited to the employee and branch management');
SELECT ok(EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public'
    AND indexname = 'restaurant_meal_one_open_per_employee'),
  'the database prevents concurrent active meal sessions for one employee');
SELECT ok(EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public'
    AND tablename = 'restaurant_meal_plan_slots' AND policyname = 'restaurant_meal_plan_slots_member_read'
    AND qual ILIKE '%employee_id%'),
  'approved meal schedule Realtime is visible only to its employee and branch managers');
SELECT ok(EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public'
    AND indexname = 'restaurant_recommendation_source_uidx'),
  'repeated historical analyses update one source-identified recommendation instead of duplicating it');
SELECT ok(NOT has_function_privilege('authenticated',
    'public.restaurant_record_operational_recommendation(uuid,uuid,text,timestamp with time zone,timestamp with time zone,jsonb,text,text)', 'EXECUTE'),
  'recommendations cannot be inserted by clients outside the manager-validated endpoint');
SELECT ok(EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public'
    AND tablename = 'restaurant_task_reports' AND policyname = 'restaurant_task_reports_branch_read'
    AND qual ILIKE '%recorded_by%'),
  'peer task report reads preserve participant isolation');
SELECT ok(EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public'
    AND tablename = 'restaurant_meal_plan_proposals' AND policyname = 'restaurant_meal_plan_branch_read'
    AND qual ILIKE '%manager%'),
  'proposed meal plans are not exposed to workers through direct database reads');
SELECT ok(EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'restaurant_task_reports_append_only' AND NOT tgisinternal),
  'reported task activity remains append-only');
SELECT ok(EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'restaurant_task_report_reviews_append_only' AND NOT tgisinternal),
  'independent review history remains append-only');

SELECT * FROM finish();
ROLLBACK;
