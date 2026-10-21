BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;

SELECT plan(19);

SELECT has_table('public', 'platform_license_terms', 'commercial terms are stored centrally');
SELECT has_table('public', 'platform_company_licenses', 'licenses are contract-scoped per company');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'public.platform_company_licenses'::regclass), 'license rows have RLS enabled');
SELECT is((SELECT package_branch_count FROM public.platform_license_terms WHERE singleton), 5, 'default package contains five branches');
SELECT is((SELECT monthly_price_per_branch_cents FROM public.platform_license_terms WHERE singleton), 150000::bigint, 'default package price is 1500 MXN per branch/month');
SELECT is((SELECT additional_branch_monthly_price_cents FROM public.platform_license_terms WHERE singleton), 200000::bigint, 'additional branch price is 2000 MXN/month');

INSERT INTO auth.users(id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data)
VALUES
  ('d1000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'platform-test@example.invalid', '', now(), '{}', '{}'),
  ('d1000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'tenant-a@example.invalid', '', now(), '{}', '{}'),
  ('d1000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'tenant-b@example.invalid', '', now(), '{}', '{}'),
  ('d1000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'manager-a@example.invalid', '', now(), '{}', '{}');

INSERT INTO public.companies(id, name, slug, timezone)
VALUES
  ('d2000000-0000-4000-8000-000000000001', 'Fixture A', 'fixture-a-platform-test', 'America/Mexico_City'),
  ('d2000000-0000-4000-8000-000000000002', 'Fixture B', 'fixture-b-platform-test', 'America/Mexico_City');

INSERT INTO public.users(id, company_id, role, full_name, email)
VALUES
  ('d1000000-0000-4000-8000-000000000002', 'd2000000-0000-4000-8000-000000000001', 'admin', 'Tenant A', 'tenant-a@example.invalid'),
  ('d1000000-0000-4000-8000-000000000003', 'd2000000-0000-4000-8000-000000000002', 'admin', 'Tenant B', 'tenant-b@example.invalid'),
  ('d1000000-0000-4000-8000-000000000004', 'd2000000-0000-4000-8000-000000000001', 'supervisor', 'Branch manager A', 'manager-a@example.invalid');

INSERT INTO public.platform_admins(auth_user_id, role, full_name, email, is_active)
VALUES ('d1000000-0000-4000-8000-000000000001', 'platform_superadmin', 'Platform fixture', 'platform-test@example.invalid', true);

INSERT INTO public.platform_company_licenses(
  company_id, status, package_branch_count, package_count, additional_branch_count,
  monthly_price_per_branch_cents, additional_branch_monthly_price_cents, currency,
  contract_reference, authorized_by
)
VALUES
 ('d2000000-0000-4000-8000-000000000001', 'active', 5, 1, 0, 150000, 200000, 'MXN', 'fixture-contract-a', 'd1000000-0000-4000-8000-000000000001'),
 ('d2000000-0000-4000-8000-000000000002', 'active', 5, 1, 0, 150000, 200000, 'MXN', 'fixture-contract-b', 'd1000000-0000-4000-8000-000000000001');

INSERT INTO public.restaurant_branches(id, company_id, name, timezone, created_by)
SELECT ('d3000000-0000-4000-8000-' || lpad(branch_no::text, 12, '0'))::uuid,
       'd2000000-0000-4000-8000-000000000001', 'A-' || branch_no,
       'America/Mexico_City', 'd1000000-0000-4000-8000-000000000002'
FROM generate_series(1, 5) AS branch_no;
INSERT INTO public.restaurant_branches(id, company_id, name, timezone, created_by)
VALUES ('d3000000-0000-4000-8000-000000000006', 'd2000000-0000-4000-8000-000000000002', 'B-1', 'America/Mexico_City', 'd1000000-0000-4000-8000-000000000003');

INSERT INTO public.restaurant_memberships(branch_id, company_id, user_id, access_role, created_by)
VALUES
 ('d3000000-0000-4000-8000-000000000001', 'd2000000-0000-4000-8000-000000000001', 'd1000000-0000-4000-8000-000000000002', 'admin', 'd1000000-0000-4000-8000-000000000002'),
 ('d3000000-0000-4000-8000-000000000006', 'd2000000-0000-4000-8000-000000000002', 'd1000000-0000-4000-8000-000000000003', 'admin', 'd1000000-0000-4000-8000-000000000003'),
 ('d3000000-0000-4000-8000-000000000001', 'd2000000-0000-4000-8000-000000000001', 'd1000000-0000-4000-8000-000000000004', 'supervisor', 'd1000000-0000-4000-8000-000000000002');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', 'd1000000-0000-4000-8000-000000000001', true);
SELECT ok(public.is_platform_admin(), 'platform superadmin identity is recognized without a tenant profile');
SELECT is(public.current_company_id(), NULL::uuid, 'platform superadmin has no company membership');
SELECT is((SELECT count(*)::integer FROM public.companies), 0, 'platform superadmin does not gain tenant-table access');

SELECT set_config('request.jwt.claim.sub', 'd1000000-0000-4000-8000-000000000002', true);
SELECT ok(NOT public.is_platform_admin(), 'corporate admin is not a platform administrator');
SELECT is(public.current_company_id(), 'd2000000-0000-4000-8000-000000000001'::uuid, 'corporate admin resolves only its own company');
SELECT is((SELECT count(*)::integer FROM public.restaurant_branches WHERE company_id = 'd2000000-0000-4000-8000-000000000001'), 5, 'corporate admin can manage branches across its own company');
SELECT is((SELECT count(*)::integer FROM public.companies WHERE id = 'd2000000-0000-4000-8000-000000000002'), 0, 'tenant A cannot read tenant B company');
SELECT is((SELECT count(*)::integer FROM public.restaurant_branches WHERE company_id = 'd2000000-0000-4000-8000-000000000002'), 0, 'tenant A cannot read tenant B branches');
SELECT ok(NOT has_table_privilege('authenticated', 'public.platform_company_licenses', 'SELECT'), 'tenant users cannot read billing license tables directly');
SELECT ok(NOT has_function_privilege('authenticated', 'public.platform_set_company_branch_license(uuid,uuid,integer,integer,text,bigint,text)', 'EXECUTE'), 'tenant users cannot call the platform license RPC');

SELECT set_config('request.jwt.claim.sub', 'd1000000-0000-4000-8000-000000000004', true);
SELECT ok(private.restaurant_has_access('d3000000-0000-4000-8000-000000000001'), 'branch manager can access an explicitly assigned branch');
SELECT ok(NOT private.restaurant_has_access('d3000000-0000-4000-8000-000000000005'), 'branch manager cannot access an unassigned branch in the same company');

RESET ROLE;
SELECT throws_ok(
  $$INSERT INTO public.restaurant_branches(company_id, name, timezone, created_by)
    VALUES ('d2000000-0000-4000-8000-000000000001', 'A-over-capacity', 'America/Mexico_City', 'd1000000-0000-4000-8000-000000000002')$$,
  '23514', 'BRANCH_LICENSE_CAPACITY_EXCEEDED', 'branch activation beyond contracted capacity is rejected'
);

SELECT * FROM finish();
ROLLBACK;
