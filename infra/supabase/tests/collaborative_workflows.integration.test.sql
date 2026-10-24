BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

-- Isolated transactional fixture: all rows are rolled back by this test file.
CREATE TEMP TABLE pm_validation_ids (name text PRIMARY KEY, id uuid NOT NULL);
INSERT INTO pm_validation_ids VALUES
  ('company', 'f0000000-0000-4000-8000-000000000001'),
  ('branch_a', 'f0000000-0000-4000-8000-000000000011'),
  ('branch_b', 'f0000000-0000-4000-8000-000000000012'),
  ('manager', 'f0000000-0000-4000-8000-000000000101'),
  ('target', 'f0000000-0000-4000-8000-000000000102'),
  ('available_peer', 'f0000000-0000-4000-8000-000000000103'),
  ('occupied_peer', 'f0000000-0000-4000-8000-000000000104'),
  ('other_branch_peer', 'f0000000-0000-4000-8000-000000000105'),
  ('license_admin', 'f0000000-0000-4000-8000-000000000106'),
  ('task_a', 'f0000000-0000-4000-8000-000000000201'),
  ('task_b', 'f0000000-0000-4000-8000-000000000202'),
  ('request_a', 'f0000000-0000-4000-8000-000000000301'),
  ('meal_a', 'f0000000-0000-4000-8000-000000000401');
GRANT SELECT ON pm_validation_ids TO authenticated;

INSERT INTO public.companies (id, name, slug, timezone)
SELECT id, 'Pollo Movil Validation Fixture', 'pm-validation-' || pg_catalog.replace(id::text, '-', ''), 'America/Mexico_City'
FROM pm_validation_ids WHERE name = 'company';

INSERT INTO auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
SELECT id, 'authenticated', 'authenticated', name || '@pm-validation.invalid', '', now(),
  '{}'::jsonb, pg_catalog.jsonb_build_object('company_id', company_id::text,
    'role', 'worker', 'full_name', name), now(), now()
FROM (VALUES
  ('manager', (SELECT id FROM pm_validation_ids WHERE name = 'manager')),
  ('target', (SELECT id FROM pm_validation_ids WHERE name = 'target')),
  ('available-peer', (SELECT id FROM pm_validation_ids WHERE name = 'available_peer')),
  ('occupied-peer', (SELECT id FROM pm_validation_ids WHERE name = 'occupied_peer')),
  ('other-branch-peer', (SELECT id FROM pm_validation_ids WHERE name = 'other_branch_peer'))
) AS people(name, id)
CROSS JOIN (SELECT id AS company_id FROM pm_validation_ids WHERE name = 'company') company;

INSERT INTO public.users (id, company_id, role, full_name, email)
SELECT u.id, company.id, 'worker'::public.user_role, u.email, u.email
FROM auth.users u
CROSS JOIN (SELECT id FROM pm_validation_ids WHERE name = 'company') company
WHERE u.email LIKE '%@pm-validation.invalid'
ON CONFLICT (id) DO NOTHING;

INSERT INTO auth.users (id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
VALUES ((SELECT id FROM pm_validation_ids WHERE name = 'license_admin'), 'authenticated',
  'authenticated', 'license-admin@pm-validation.invalid', '', now(), '{}'::jsonb, '{}'::jsonb, now(), now());
INSERT INTO public.platform_admins (auth_user_id, email, full_name, role, is_active)
VALUES ((SELECT id FROM pm_validation_ids WHERE name = 'license_admin'),
  'license-admin@pm-validation.invalid', 'Temporary CI License Admin', 'platform_superadmin', true);
DO $$ BEGIN
  PERFORM public.platform_set_company_branch_license(
    (SELECT id FROM pm_validation_ids WHERE name = 'license_admin'),
    (SELECT id FROM pm_validation_ids WHERE name = 'company'), 1, 0,
    'CI:collaborative-workflows', NULL, NULL);
END $$;

INSERT INTO public.restaurant_branches (id, company_id, name, timezone, created_by,
  meal_duration_minutes, receipt_escalation_seconds_by_priority,
  collaboration_manager_escalation_seconds)
SELECT id, (SELECT id FROM pm_validation_ids WHERE name = 'company'),
  CASE name WHEN 'branch_a' THEN 'Fixture A' ELSE 'Fixture B' END,
  'America/Mexico_City', (SELECT id FROM pm_validation_ids WHERE name = 'manager'),
  30, '{"1":30}'::jsonb,
  CASE WHEN name = 'branch_a' THEN 30 ELSE NULL END
FROM pm_validation_ids WHERE name IN ('branch_a', 'branch_b');

INSERT INTO public.restaurant_memberships (branch_id, company_id, user_id, access_role, created_by)
SELECT branch_id, (SELECT id FROM pm_validation_ids WHERE name = 'company'), user_id, access_role,
  (SELECT id FROM pm_validation_ids WHERE name = 'manager')
FROM (VALUES
  ((SELECT id FROM pm_validation_ids WHERE name = 'branch_a'), (SELECT id FROM pm_validation_ids WHERE name = 'manager'), 'admin'),
  ((SELECT id FROM pm_validation_ids WHERE name = 'branch_a'), (SELECT id FROM pm_validation_ids WHERE name = 'target'), 'employee'),
  ((SELECT id FROM pm_validation_ids WHERE name = 'branch_a'), (SELECT id FROM pm_validation_ids WHERE name = 'available_peer'), 'employee'),
  ((SELECT id FROM pm_validation_ids WHERE name = 'branch_a'), (SELECT id FROM pm_validation_ids WHERE name = 'occupied_peer'), 'employee'),
  ((SELECT id FROM pm_validation_ids WHERE name = 'branch_b'), (SELECT id FROM pm_validation_ids WHERE name = 'other_branch_peer'), 'employee')
) AS members(branch_id, user_id, access_role);

INSERT INTO public.restaurant_shifts (branch_id, employee_id, shift_date, start_time, end_time, status, created_by)
SELECT m.branch_id, m.user_id, (now() AT TIME ZONE 'America/Mexico_City')::date,
  time '00:00', time '23:59', 'published', (SELECT id FROM pm_validation_ids WHERE name = 'manager')
FROM public.restaurant_memberships m
WHERE (m.branch_id = (SELECT id FROM pm_validation_ids WHERE name = 'branch_a')
    AND m.user_id IN ((SELECT id FROM pm_validation_ids WHERE name = 'target'),
      (SELECT id FROM pm_validation_ids WHERE name = 'available_peer'),
      (SELECT id FROM pm_validation_ids WHERE name = 'occupied_peer')))
  OR (m.branch_id = (SELECT id FROM pm_validation_ids WHERE name = 'branch_b')
    AND m.user_id = (SELECT id FROM pm_validation_ids WHERE name = 'other_branch_peer'));

INSERT INTO public.restaurant_member_operational_states (branch_id, employee_id, state, changed_by, note)
VALUES ((SELECT id FROM pm_validation_ids WHERE name = 'branch_a'),
  (SELECT id FROM pm_validation_ids WHERE name = 'occupied_peer'), 'occupied',
  (SELECT id FROM pm_validation_ids WHERE name = 'manager'), 'fixture unavailable');

INSERT INTO public.restaurant_tasks (id, branch_id, scheduled_for, name, assigned_to,
  estimated_minutes, difficulty, priority, created_by)
SELECT (SELECT id FROM pm_validation_ids WHERE name = task_name), branch_id,
  (now() AT TIME ZONE 'America/Mexico_City')::date, 'Validation ' || task_name,
  employee_id, 15, 1, 1, (SELECT id FROM pm_validation_ids WHERE name = 'manager')
FROM (VALUES
  ('task_a', (SELECT id FROM pm_validation_ids WHERE name = 'branch_a'), (SELECT id FROM pm_validation_ids WHERE name = 'target')),
  ('task_b', (SELECT id FROM pm_validation_ids WHERE name = 'branch_b'), (SELECT id FROM pm_validation_ids WHERE name = 'other_branch_peer'))
) AS tasks(task_name, branch_id, employee_id);

UPDATE public.restaurant_task_receipts
SET assignment_recorded_at = now() - interval '2 minutes', escalation_processed_at = NULL
WHERE task_id IN (SELECT id FROM pm_validation_ids WHERE name IN ('task_a', 'task_b'));

SELECT plan(33);

SELECT is((SELECT authorization_reference FROM public.platform_license_events
    WHERE company_id = (SELECT id FROM pm_validation_ids WHERE name = 'company')
      AND event_type = 'license_authorized'), 'CI:collaborative-workflows',
  'the fixture authorizes initial branch capacity through the real platform license function');

SELECT is(private.process_restaurant_collaboration_deadlines() >= 2, true,
  'the scheduled processor creates automatic notices for configured overdue receipts');
SELECT is((SELECT count(*)::integer FROM public.restaurant_collaboration_requests
    WHERE branch_id = (SELECT id FROM pm_validation_ids WHERE name = 'branch_a')
      AND task_id = (SELECT id FROM pm_validation_ids WHERE name = 'task_a')
      AND status IN ('open', 'claimed')), 1,
  'an overdue assigned task has exactly one active collaboration request');
SELECT is((SELECT request_source FROM public.restaurant_collaboration_requests
    WHERE task_id = (SELECT id FROM pm_validation_ids WHERE name = 'task_a')), 'receipt_timeout',
  'the scheduler identifies its request source as receipt timeout');
SELECT ok((SELECT created_by IS NULL FROM public.restaurant_collaboration_requests
    WHERE task_id = (SELECT id FROM pm_validation_ids WHERE name = 'task_a')),
  'automatic requests do not fabricate a human creator');
SELECT is((SELECT count(*)::integer FROM public.restaurant_collaboration_events e
    JOIN public.restaurant_collaboration_requests r ON r.id = e.request_id
    WHERE r.task_id = (SELECT id FROM pm_validation_ids WHERE name = 'task_a')
      AND e.event_type = 'receipt_deadline_triggered'), 1,
  'the receipt timeout event is appended once');
SELECT is((SELECT count(*)::integer FROM public.restaurant_notifications n
    WHERE n.entity_type = 'collaboration_request'
      AND n.recipient_id = (SELECT id FROM pm_validation_ids WHERE name = 'available_peer')
      AND n.data ->> 'task_id' = (SELECT id::text FROM pm_validation_ids WHERE name = 'task_a')), 1,
  'a same-branch available coworker receives the automatic notice');
SELECT is((SELECT count(*)::integer FROM public.restaurant_notifications n
    WHERE n.entity_type = 'collaboration_request'
      AND n.recipient_id IN ((SELECT id FROM pm_validation_ids WHERE name = 'occupied_peer'),
        (SELECT id FROM pm_validation_ids WHERE name = 'other_branch_peer'))
      AND n.data ->> 'task_id' = (SELECT id::text FROM pm_validation_ids WHERE name = 'task_a')), 0,
  'occupied and other-branch workers are excluded from the notice');
SELECT is((SELECT status FROM public.restaurant_tasks WHERE id = (SELECT id FROM pm_validation_ids WHERE name = 'task_a')), 'pending',
  'creating an automatic notice does not complete the task');
SELECT lives_ok('SELECT private.process_restaurant_collaboration_deadlines()',
  'reprocessing due receipts is safe and idempotent');
SELECT is((SELECT count(*)::integer FROM public.restaurant_collaboration_requests
    WHERE task_id = (SELECT id FROM pm_validation_ids WHERE name = 'task_a')
      AND status IN ('open', 'claimed')), 1,
  'reprocessing does not duplicate the active request');

UPDATE pm_validation_ids SET id = (SELECT r.id FROM public.restaurant_collaboration_requests r
  WHERE r.task_id = (SELECT id FROM pm_validation_ids WHERE name = 'task_a')) WHERE name = 'request_a';
SELECT is((public.claim_restaurant_collaboration_request(
    (SELECT id FROM pm_validation_ids WHERE name = 'branch_a'),
    (SELECT id FROM pm_validation_ids WHERE name = 'request_a'),
    (SELECT id FROM pm_validation_ids WHERE name = 'available_peer'), 30) ->> 'claimed')::boolean,
  true, 'an available same-branch coworker can atomically reserve the notice');
SELECT throws_ok($$SELECT public.claim_restaurant_collaboration_request(
    (SELECT id FROM pm_validation_ids WHERE name = 'branch_a'),
    (SELECT id FROM pm_validation_ids WHERE name = 'request_a'),
    (SELECT id FROM pm_validation_ids WHERE name = 'other_branch_peer'), 30)$$,
  'P0001', 'COLLABORATOR_NOT_AVAILABLE', 'another-branch user cannot claim a notice');

UPDATE public.restaurant_collaboration_requests SET claimed_until = now() - interval '1 second',
  created_at = now() - interval '2 minutes'
 WHERE id = (SELECT id FROM pm_validation_ids WHERE name = 'request_a');
SELECT lives_ok('SELECT private.process_restaurant_collaboration_deadlines()',
  'the scheduler releases an expired reservation');
SELECT is((SELECT status FROM public.restaurant_collaboration_requests
    WHERE id = (SELECT id FROM pm_validation_ids WHERE name = 'request_a')), 'open',
  'an expired claim returns to the open inbox');
SELECT is((SELECT count(*)::integer FROM public.restaurant_collaboration_events
    WHERE request_id = (SELECT id FROM pm_validation_ids WHERE name = 'request_a')
      AND event_type = 'claim_released'), 1,
  'reservation release is recorded in the append-only event ledger');
SELECT ok((SELECT manager_escalated_at IS NOT NULL FROM public.restaurant_collaboration_requests
    WHERE id = (SELECT id FROM pm_validation_ids WHERE name = 'request_a')),
  'gerencia is escalated after the configured delay');
SELECT is((SELECT count(*)::integer FROM public.restaurant_notifications
    WHERE notification_type = 'collaboration_escalated'
      AND recipient_id = (SELECT id FROM pm_validation_ids WHERE name = 'manager')), 1,
  'manager escalation creates a targeted notification');
SELECT ok((SELECT manager_escalated_at IS NULL FROM public.restaurant_collaboration_requests
    WHERE task_id = (SELECT id FROM pm_validation_ids WHERE name = 'task_b')),
  'a branch with no manager escalation policy is not escalated');
SELECT is((SELECT status FROM public.restaurant_collaboration_requests
    WHERE task_id = (SELECT id FROM pm_validation_ids WHERE name = 'task_b')), 'open',
  'the no-policy branch keeps its notice open without inventing escalation');

SELECT is((public.confirm_restaurant_task_receipt(
    (SELECT id FROM pm_validation_ids WHERE name = 'branch_a'),
    (SELECT id FROM pm_validation_ids WHERE name = 'task_a'),
    (SELECT id FROM pm_validation_ids WHERE name = 'target')) ->> 'task_completed')::boolean,
  false, 'receipt confirmation explicitly leaves the task incomplete');
SELECT is((SELECT status FROM public.restaurant_tasks WHERE id = (SELECT id FROM pm_validation_ids WHERE name = 'task_a')), 'pending',
  'receipt confirmation does not change the task status');
SELECT is((SELECT status FROM public.restaurant_collaboration_requests
    WHERE id = (SELECT id FROM pm_validation_ids WHERE name = 'request_a')), 'cancelled',
  'owner receipt confirmation resolves the obsolete coworker request');

INSERT INTO public.restaurant_member_operational_states (branch_id, employee_id, state, changed_by, note)
VALUES ((SELECT id FROM pm_validation_ids WHERE name = 'branch_a'),
  (SELECT id FROM pm_validation_ids WHERE name = 'available_peer'), 'occupied',
  (SELECT id FROM pm_validation_ids WHERE name = 'manager'), 'fixture unavailable')
ON CONFLICT (branch_id, employee_id) DO UPDATE SET state = EXCLUDED.state,
  changed_by = EXCLUDED.changed_by, changed_at = now(), note = EXCLUDED.note;
SELECT throws_ok($$SELECT public.restaurant_start_meal(
    (SELECT id FROM pm_validation_ids WHERE name = 'branch_a'),
    (SELECT id FROM pm_validation_ids WHERE name = 'target'),
    (SELECT id FROM pm_validation_ids WHERE name = 'available_peer'), 'peer test', now())$$,
  'P0001', 'COLLABORATOR_NOT_AVAILABLE', 'an occupied coworker cannot register another worker meal');
SELECT throws_ok($$SELECT public.restaurant_start_meal(
    (SELECT id FROM pm_validation_ids WHERE name = 'branch_a'),
    (SELECT id FROM pm_validation_ids WHERE name = 'target'),
    (SELECT id FROM pm_validation_ids WHERE name = 'other_branch_peer'), 'cross-branch test', now())$$,
  'P0001', 'BRANCH_ACCESS_REQUIRED', 'a different-branch coworker cannot register the meal');

UPDATE public.restaurant_member_operational_states SET state = 'available'
WHERE branch_id = (SELECT id FROM pm_validation_ids WHERE name = 'branch_a')
  AND employee_id = (SELECT id FROM pm_validation_ids WHERE name = 'available_peer');
UPDATE pm_validation_ids SET id = public.restaurant_start_meal(
  (SELECT id FROM pm_validation_ids WHERE name = 'branch_a'),
  (SELECT id FROM pm_validation_ids WHERE name = 'target'),
  (SELECT id FROM pm_validation_ids WHERE name = 'available_peer'),
  'recorded by coworker', now() - interval '2 minutes') WHERE name = 'meal_a';
SELECT is((SELECT start_origin FROM public.restaurant_meal_sessions
    WHERE id = (SELECT id FROM pm_validation_ids WHERE name = 'meal_a')), 'peer',
  'meal start keeps the peer origin and worker identity');
SELECT ok((SELECT started_by = (SELECT id FROM pm_validation_ids WHERE name = 'available_peer')
      AND employee_id = (SELECT id FROM pm_validation_ids WHERE name = 'target')
      AND declared_started_at < started_at
    FROM public.restaurant_meal_sessions WHERE id = (SELECT id FROM pm_validation_ids WHERE name = 'meal_a')),
  'meal start preserves recorder, worker, declared time, and database time separately');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', (SELECT id::text FROM pm_validation_ids WHERE name = 'available_peer'), true);
SELECT set_config('pm_validation.peer_meal_rows', (SELECT count(*)::text FROM public.restaurant_meal_sessions
  WHERE id = (SELECT id FROM pm_validation_ids WHERE name = 'meal_a')), true);
RESET ROLE;
SELECT is(current_setting('pm_validation.peer_meal_rows')::integer, 1,
  'an available same-branch worker can read the meal through Realtime RLS');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', (SELECT id::text FROM pm_validation_ids WHERE name = 'occupied_peer'), true);
SELECT set_config('pm_validation.occupied_meal_rows', (SELECT count(*)::text FROM public.restaurant_meal_sessions
  WHERE id = (SELECT id FROM pm_validation_ids WHERE name = 'meal_a')), true);
RESET ROLE;
SELECT is(current_setting('pm_validation.occupied_meal_rows')::integer, 0,
  'an occupied same-branch worker cannot read coworker meal Realtime rows');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', (SELECT id::text FROM pm_validation_ids WHERE name = 'other_branch_peer'), true);
SELECT set_config('pm_validation.other_branch_meal_rows', (SELECT count(*)::text FROM public.restaurant_meal_sessions
  WHERE id = (SELECT id FROM pm_validation_ids WHERE name = 'meal_a')), true);
RESET ROLE;
SELECT is(current_setting('pm_validation.other_branch_meal_rows')::integer, 0,
  'a different branch cannot read the meal through Realtime RLS');

SELECT lives_ok($$SELECT public.restaurant_confirm_meal_return(
    (SELECT id FROM pm_validation_ids WHERE name = 'branch_a'),
    (SELECT id FROM pm_validation_ids WHERE name = 'meal_a'),
    (SELECT id FROM pm_validation_ids WHERE name = 'available_peer'), 'available', now() - interval '1 minute')$$,
  'an available coworker can record a confirmed return');
SELECT ok((SELECT return_origin = 'peer'
      AND return_confirmed_by = (SELECT id FROM pm_validation_ids WHERE name = 'available_peer')
      AND declared_return_at < return_confirmed_at
    FROM public.restaurant_meal_sessions WHERE id = (SELECT id FROM pm_validation_ids WHERE name = 'meal_a')),
  'meal return preserves peer recorder, declared time, and effective confirmation time');
SELECT throws_ok($$UPDATE public.restaurant_meal_events SET details = '{}'::jsonb
    WHERE meal_session_id = (SELECT id FROM pm_validation_ids WHERE name = 'meal_a')$$,
  'P0001', 'OPERATIONAL_EVENTS_APPEND_ONLY', 'meal event history rejects mutation');

SELECT * FROM finish();
ROLLBACK;
