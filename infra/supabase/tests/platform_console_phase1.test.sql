BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(22);

SELECT has_table('public', 'platform_company_admin_invites', 'corporate administrator invitations have a dedicated outbox table');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'public.platform_company_admin_invites'::regclass), 'corporate invitation records have RLS enabled');
SELECT ok(NOT has_table_privilege('authenticated', 'public.platform_company_admin_invites', 'SELECT'), 'authenticated clients cannot read invitation rows directly');

INSERT INTO auth.users(id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data)
VALUES
  ('e1000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'phase1-admin@example.invalid', '', now(), '{}', '{}'),
  ('e1000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'phase1-corporate@example.invalid', '', now(), '{}', '{}'),
  ('e1000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'phase1-existing@example.invalid', '', now(), '{}', '{}');
INSERT INTO public.platform_admins(auth_user_id, role, full_name, email, is_active)
VALUES ('e1000000-0000-4000-8000-000000000001', 'platform_superadmin', 'Phase 1 fixture', 'phase1-admin@example.invalid', true);

CREATE TEMP TABLE phase1_company_result AS
SELECT public.platform_create_company_with_admin_invite(
  'e1000000-0000-4000-8000-000000000001', 'Phase 1 Fixture', 'phase1-console-fixture',
  'Testing', 'America/Mexico_City', 'phase1-corporate@example.invalid', 'Corporate Fixture',
  '{}'::jsonb, '{phase1-test-company}', repeat('e', 64)
) AS result;

SELECT is((SELECT result->'company'->>'slug' FROM phase1_company_result), 'phase1-console-fixture', 'company and initial invitation are created atomically');
SELECT is((SELECT result->'invite'->>'status' FROM phase1_company_result), 'pending_delivery', 'initial corporate invitation starts in explicit delivery state');
SELECT ok(NOT EXISTS (SELECT 1 FROM public.users WHERE id = 'e1000000-0000-4000-8000-000000000002'), 'invited user receives no company role before claiming');
SELECT is((SELECT count(*)::integer FROM public.admin_audit_log WHERE actor_id = 'e1000000-0000-4000-8000-000000000001' AND action = 'create_company'), 1, 'company creation has an atomic audit event');

INSERT INTO public.companies(id, name, slug, timezone)
VALUES ('e2000000-0000-4000-8000-000000000001', 'Existing Tenant Fixture', 'phase1-existing-tenant', 'America/Mexico_City');
INSERT INTO public.users(id, company_id, role, full_name, email)
VALUES ('e1000000-0000-4000-8000-000000000003', 'e2000000-0000-4000-8000-000000000001', 'admin', 'Existing User', 'phase1-existing@example.invalid');
CREATE TEMP TABLE phase1_existing_identity_invite AS
SELECT public.platform_create_company_with_admin_invite(
  'e1000000-0000-4000-8000-000000000001', 'Identity Target Fixture', 'phase1-identity-target',
  'Testing', 'America/Mexico_City', 'phase1-existing@example.invalid', 'Existing User',
  '{}'::jsonb, '{phase1-test-existing-identity}', repeat('f', 64)
) AS result;
SELECT throws_ok(
  format('SELECT public.platform_claim_company_admin_invite(%L, %L)',
    'e1000000-0000-4000-8000-000000000003', (SELECT result->'invite'->>'id' FROM phase1_existing_identity_invite)),
  '23505', 'ACCOUNT_ALREADY_ASSIGNED', 'existing account cannot be reassigned to a different customer company'
);
SELECT is((SELECT count(*)::integer FROM public.users WHERE id = 'e1000000-0000-4000-8000-000000000003'
  AND company_id = 'e2000000-0000-4000-8000-000000000001'), 1, 'failed cross-company claim leaves the original membership unchanged');

CREATE TEMP TABLE phase1_platform_invite AS
SELECT public.platform_create_admin_invite(
  'e1000000-0000-4000-8000-000000000001',
  (SELECT id FROM public.platform_admins WHERE auth_user_id = 'e1000000-0000-4000-8000-000000000001'),
  'another-admin@example.invalid', repeat('a', 64), now() + interval '1 day'
) AS invite;
SELECT is((SELECT (invite).invite_token FROM phase1_platform_invite), NULL::text, 'new platform invitation does not store a raw token');
SELECT is((SELECT (invite).invite_token_hash FROM phase1_platform_invite), repeat('a', 64), 'new platform invitation stores only its digest');
SELECT ok(NOT EXISTS (SELECT 1 FROM public.admin_audit_log WHERE target_id = (SELECT (invite).id::text FROM phase1_platform_invite) AND after_json ? 'invite_token'), 'invitation audit metadata contains no token field');

SELECT throws_ok(
  format('SELECT public.platform_claim_company_admin_invite(%L, %L)',
    'e1000000-0000-4000-8000-000000000001', (SELECT result->'invite'->>'id' FROM phase1_company_result)),
  '42501', 'INVITE_EMAIL_MISMATCH', 'invitation cannot be claimed by a different email identity'
);
UPDATE public.platform_company_admin_invites
SET expires_at = now() - interval '1 minute'
WHERE id = (SELECT (result->'invite'->>'id')::uuid FROM phase1_company_result);
SELECT throws_ok(
  format('SELECT public.platform_claim_company_admin_invite(%L, %L)',
    'e1000000-0000-4000-8000-000000000002', (SELECT result->'invite'->>'id' FROM phase1_company_result)),
  '22023', 'INVITE_EXPIRED_OR_UNAVAILABLE', 'expired invitation cannot grant company access'
);
UPDATE public.platform_company_admin_invites
SET expires_at = now() + interval '7 days'
WHERE id = (SELECT (result->'invite'->>'id')::uuid FROM phase1_company_result);

SELECT public.platform_claim_company_admin_invite(
  'e1000000-0000-4000-8000-000000000002',
  (SELECT (result->'invite'->>'id')::uuid FROM phase1_company_result)
);
SELECT ok(
  (SELECT company_id = (SELECT (result->'company'->>'id')::uuid FROM phase1_company_result)
    AND role::text = 'owner' FROM public.users WHERE id = 'e1000000-0000-4000-8000-000000000002')
  AND (SELECT status = 'claimed' FROM public.platform_company_admin_invites
    WHERE id = (SELECT (result->'invite'->>'id')::uuid FROM phase1_company_result)),
  'verified invitation claim grants exactly the invited company role'
);

SELECT public.platform_set_company_branch_license_audited(
  'e1000000-0000-4000-8000-000000000001',
  (SELECT (result->'company'->>'id')::uuid FROM phase1_company_result),
  1, 0, 'phase1-contract-fixture', NULL, NULL
);
SELECT ok(EXISTS (SELECT 1 FROM public.platform_license_events WHERE event_type = 'license_authorized'
  AND authorization_reference = 'phase1-contract-fixture'), 'license mutation appends its contractual event');
SELECT ok(EXISTS (SELECT 1 FROM public.admin_audit_log WHERE action = 'set_company_license'
  AND company_id = (SELECT (result->'company'->>'id')::uuid FROM phase1_company_result)), 'license mutation and general audit share one database transaction');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', 'e1000000-0000-4000-8000-000000000002', true);
SELECT ok(public.current_company_id() IS NOT NULL, 'active corporate user resolves its company');
RESET ROLE;
SELECT public.platform_set_company_status(
  'e1000000-0000-4000-8000-000000000001',
  (SELECT (result->'company'->>'id')::uuid FROM phase1_company_result), 'suspended'
);
SET LOCAL ROLE authenticated;
SELECT is(public.current_company_id(), NULL::uuid, 'suspended company loses tenant data context without deleting records');
RESET ROLE;

CREATE TRIGGER phase1_force_audit_failure
BEFORE INSERT ON public.admin_audit_log
FOR EACH ROW WHEN (NEW.action = 'update_company')
EXECUTE FUNCTION private.reject_append_only_mutation();
SELECT throws_ok(
  format('SELECT public.platform_update_company(%L, %L, %L, %L, NULL, NULL, NULL, %L)',
    'e1000000-0000-4000-8000-000000000001',
    (SELECT (result->'company'->>'id')::uuid FROM phase1_company_result),
    'Must Roll Back', 'Testing', 'America/Mexico_City'),
  '42501', 'APPEND_ONLY_RECORD', 'company update fails when required audit insertion fails'
);
DROP TRIGGER phase1_force_audit_failure ON public.admin_audit_log;
SELECT is((SELECT name FROM public.companies WHERE slug = 'phase1-console-fixture'), 'Phase 1 Fixture', 'failed audit leaves the company unchanged');
SELECT throws_ok(
  $$UPDATE public.admin_audit_log SET action = 'tampered' WHERE action = 'create_company' AND target_id = (SELECT (result->'company'->>'id') FROM phase1_company_result)$$,
  '42501', 'APPEND_ONLY_RECORD', 'audit records cannot be updated or erased'
);

SELECT * FROM finish();
ROLLBACK;
