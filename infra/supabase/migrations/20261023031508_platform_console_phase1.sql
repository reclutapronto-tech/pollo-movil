-- Phase 1 platform console hardening and company-administrator invitations.
-- Additive only: no existing customer, license, or audit rows are rewritten.

CREATE SCHEMA IF NOT EXISTS private;

-- Keep old platform invitations claimable while all newly-created ones store
-- only a one-way digest. Existing plaintext values are not modified here.
ALTER TABLE public.platform_admin_invites
  ALTER COLUMN invite_token DROP NOT NULL;
ALTER TABLE public.platform_admin_invites
  ADD COLUMN IF NOT EXISTS invite_token_hash text;
CREATE UNIQUE INDEX IF NOT EXISTS platform_admin_invites_token_hash_uidx
  ON public.platform_admin_invites(invite_token_hash)
  WHERE invite_token_hash IS NOT NULL;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'platform_admin_invites_token_hash_format') THEN
    ALTER TABLE public.platform_admin_invites ADD CONSTRAINT platform_admin_invites_token_hash_format
      CHECK (invite_token_hash IS NULL OR invite_token_hash ~ '^[0-9a-f]{64}$');
  END IF;
END;
$$;

CREATE TABLE public.platform_company_admin_invites (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE RESTRICT,
  email text NOT NULL CHECK (length(trim(email)) BETWEEN 3 AND 254),
  full_name text NOT NULL CHECK (length(trim(full_name)) BETWEEN 2 AND 120),
  created_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  auth_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'pending_delivery'
    CHECK (status IN ('pending_delivery', 'sent', 'delivery_failed', 'claimed', 'revoked')),
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '7 days'),
  delivery_attempts integer NOT NULL DEFAULT 0 CHECK (delivery_attempts >= 0),
  delivery_error_code text,
  idempotency_key text NOT NULL CHECK (length(trim(idempotency_key)) BETWEEN 1 AND 200),
  request_hash text NOT NULL CHECK (request_hash ~ '^[0-9a-f]{64}$'),
  claimed_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (created_by, idempotency_key),
  CHECK ((status = 'claimed') = (claimed_at IS NOT NULL)),
  CHECK ((status = 'revoked') = (revoked_at IS NOT NULL))
);
CREATE INDEX platform_company_admin_invites_company_created_idx
  ON public.platform_company_admin_invites(company_id, created_at DESC);
CREATE INDEX platform_company_admin_invites_status_idx
  ON public.platform_company_admin_invites(status, expires_at);
CREATE UNIQUE INDEX platform_company_admin_invites_one_open_per_email
  ON public.platform_company_admin_invites(company_id, lower(email))
  WHERE status IN ('pending_delivery', 'sent', 'delivery_failed');
ALTER TABLE public.platform_company_admin_invites ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.platform_company_admin_invites FROM anon, authenticated;
GRANT SELECT ON public.platform_company_admin_invites TO service_role;
CREATE POLICY platform_company_admin_invites_service_only
  ON public.platform_company_admin_invites FOR ALL TO authenticated
  USING (false) WITH CHECK (false);

CREATE OR REPLACE VIEW public.platform_company_branch_summary AS
SELECT company_id, count(*)::bigint AS branch_count,
  count(*) FILTER (WHERE is_active)::bigint AS active_branch_count
FROM public.restaurant_branches
GROUP BY company_id;
REVOKE ALL ON public.platform_company_branch_summary FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.platform_company_branch_summary TO service_role;

CREATE OR REPLACE FUNCTION private.reject_append_only_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  RAISE EXCEPTION 'APPEND_ONLY_RECORD' USING ERRCODE = '42501';
END;
$$;

DROP TRIGGER IF EXISTS admin_audit_log_append_only ON public.admin_audit_log;
CREATE TRIGGER admin_audit_log_append_only
  BEFORE UPDATE OR DELETE ON public.admin_audit_log
  FOR EACH ROW EXECUTE FUNCTION private.reject_append_only_mutation();
DROP TRIGGER IF EXISTS platform_license_events_append_only ON public.platform_license_events;
CREATE TRIGGER platform_license_events_append_only
  BEFORE UPDATE OR DELETE ON public.platform_license_events
  FOR EACH ROW EXECUTE FUNCTION private.reject_append_only_mutation();
REVOKE UPDATE, DELETE, TRUNCATE ON public.admin_audit_log,
  public.platform_license_events FROM anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.current_company_id()
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
  SELECT company_user.company_id
  FROM public.users AS company_user
  JOIN public.companies AS company ON company.id = company_user.company_id
  WHERE company_user.id = auth.uid()
    AND company_user.is_active
    AND company_user.deleted_at IS NULL
    AND company.status = 'active'
    AND company.deleted_at IS NULL
$$;

CREATE OR REPLACE FUNCTION public.current_user_role()
RETURNS text
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
  SELECT company_user.role::text
  FROM public.users AS company_user
  JOIN public.companies AS company ON company.id = company_user.company_id
  WHERE company_user.id = auth.uid()
    AND company_user.is_active
    AND company_user.deleted_at IS NULL
    AND company.status = 'active'
    AND company.deleted_at IS NULL
$$;

CREATE OR REPLACE FUNCTION private.require_platform_actor(p_actor_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.platform_admins AS admin
    WHERE admin.auth_user_id = p_actor_id
      AND admin.is_active
      AND admin.role IN ('platform_admin', 'platform_superadmin')
  ) THEN
    RAISE EXCEPTION 'PLATFORM_ADMIN_REQUIRED' USING ERRCODE = '42501';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION private.require_platform_actor(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.require_platform_actor(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.platform_create_company_with_admin_invite(
  p_actor_id uuid,
  p_name text,
  p_slug text,
  p_industry text,
  p_timezone text,
  p_admin_email text,
  p_admin_name text,
  p_settings jsonb,
  p_idempotency_key text,
  p_request_hash text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_company public.companies%ROWTYPE;
  v_invite public.platform_company_admin_invites%ROWTYPE;
  v_existing public.platform_company_admin_invites%ROWTYPE;
BEGIN
  PERFORM private.require_platform_actor(p_actor_id);
  IF length(trim(COALESCE(p_name, ''))) NOT BETWEEN 2 AND 160
     OR length(trim(COALESCE(p_slug, ''))) NOT BETWEEN 2 AND 100
     OR p_slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$'
     OR length(trim(COALESCE(p_admin_email, ''))) NOT BETWEEN 3 AND 254
     OR length(trim(COALESCE(p_admin_name, ''))) NOT BETWEEN 2 AND 120
     OR length(trim(COALESCE(p_idempotency_key, ''))) NOT BETWEEN 1 AND 200
     OR p_request_hash !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'INVALID_COMPANY_INVITE' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_existing
  FROM public.platform_company_admin_invites
  WHERE created_by = p_actor_id AND idempotency_key = p_idempotency_key
  FOR UPDATE;
  IF FOUND THEN
    IF v_existing.request_hash <> p_request_hash THEN
      RAISE EXCEPTION 'IDEMPOTENCY_CONFLICT' USING ERRCODE = '23505';
    END IF;
    SELECT * INTO STRICT v_company FROM public.companies WHERE id = v_existing.company_id;
    RETURN jsonb_build_object('company', to_jsonb(v_company), 'invite', to_jsonb(v_existing), 'replayed', true);
  END IF;

  INSERT INTO public.companies(name, slug, industry, timezone, status, settings, settings_version)
  VALUES (trim(p_name), lower(trim(p_slug)), nullif(trim(p_industry), ''),
    COALESCE(nullif(trim(p_timezone), ''), 'America/Mexico_City'), 'active',
    COALESCE(p_settings, '{}'::jsonb), 1)
  RETURNING * INTO v_company;

  INSERT INTO public.platform_company_admin_invites(
    company_id, email, full_name, created_by, idempotency_key, request_hash
  ) VALUES (
    v_company.id, lower(trim(p_admin_email)), trim(p_admin_name), p_actor_id,
    p_idempotency_key, p_request_hash
  ) RETURNING * INTO v_invite;

  INSERT INTO public.admin_audit_log(
    actor_id, action, target_type, target_id, before_json, after_json
  ) VALUES (
    p_actor_id, 'create_company', 'company', v_company.id::text, NULL,
    jsonb_build_object('name', v_company.name, 'slug', v_company.slug,
      'admin_invite_id', v_invite.id, 'admin_email', v_invite.email)
  );
  RETURN jsonb_build_object('company', to_jsonb(v_company), 'invite', to_jsonb(v_invite), 'replayed', false);
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_update_company(
  p_actor_id uuid,
  p_company_id uuid,
  p_name text,
  p_industry text,
  p_address text,
  p_phone text,
  p_email text,
  p_timezone text
)
RETURNS public.companies
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_before public.companies%ROWTYPE; v_after public.companies%ROWTYPE;
BEGIN
  PERFORM private.require_platform_actor(p_actor_id);
  SELECT * INTO STRICT v_before FROM public.companies WHERE id = p_company_id AND deleted_at IS NULL FOR UPDATE;
  IF length(trim(COALESCE(p_name, ''))) NOT BETWEEN 2 AND 160
     OR length(trim(COALESCE(p_timezone, ''))) NOT BETWEEN 1 AND 100 THEN
    RAISE EXCEPTION 'INVALID_COMPANY_PROFILE' USING ERRCODE = '22023';
  END IF;
  UPDATE public.companies SET name = trim(p_name), industry = nullif(trim(p_industry), ''),
    address = nullif(trim(p_address), ''), phone = nullif(trim(p_phone), ''),
    email = nullif(lower(trim(p_email)), ''), timezone = trim(p_timezone)
  WHERE id = p_company_id RETURNING * INTO v_after;
  INSERT INTO public.admin_audit_log(actor_id, company_id, action, target_type, target_id, before_json, after_json)
  VALUES (p_actor_id, p_company_id, 'update_company', 'company', p_company_id::text,
    jsonb_build_object('name', v_before.name, 'industry', v_before.industry, 'address', v_before.address,
      'phone', v_before.phone, 'email', v_before.email, 'timezone', v_before.timezone),
    jsonb_build_object('name', v_after.name, 'industry', v_after.industry, 'address', v_after.address,
      'phone', v_after.phone, 'email', v_after.email, 'timezone', v_after.timezone));
  RETURN v_after;
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_set_company_status(
  p_actor_id uuid, p_company_id uuid, p_status text
)
RETURNS public.companies
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_before public.companies%ROWTYPE; v_after public.companies%ROWTYPE;
BEGIN
  PERFORM private.require_platform_actor(p_actor_id);
  IF p_status NOT IN ('active', 'suspended') THEN
    RAISE EXCEPTION 'INVALID_COMPANY_STATUS' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO STRICT v_before FROM public.companies WHERE id = p_company_id AND deleted_at IS NULL FOR UPDATE;
  IF v_before.status = p_status THEN RAISE EXCEPTION 'COMPANY_STATUS_UNCHANGED' USING ERRCODE = '22023'; END IF;
  UPDATE public.companies SET status = p_status WHERE id = p_company_id RETURNING * INTO v_after;
  INSERT INTO public.admin_audit_log(actor_id, company_id, action, target_type, target_id, before_json, after_json)
  VALUES (p_actor_id, p_company_id,
    CASE WHEN p_status = 'suspended' THEN 'suspend_company' ELSE 'reactivate_company' END,
    'company', p_company_id::text, jsonb_build_object('status', v_before.status),
    jsonb_build_object('status', v_after.status));
  RETURN v_after;
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_record_company_invite_delivery(
  p_actor_id uuid, p_invite_id uuid, p_status text, p_auth_user_id uuid DEFAULT NULL,
  p_error_code text DEFAULT NULL
)
RETURNS public.platform_company_admin_invites
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_before public.platform_company_admin_invites%ROWTYPE; v_after public.platform_company_admin_invites%ROWTYPE;
BEGIN
  PERFORM private.require_platform_actor(p_actor_id);
  IF p_status NOT IN ('sent', 'delivery_failed') THEN RAISE EXCEPTION 'INVALID_INVITE_STATE' USING ERRCODE = '22023'; END IF;
  SELECT * INTO STRICT v_before FROM public.platform_company_admin_invites WHERE id = p_invite_id FOR UPDATE;
  IF v_before.status NOT IN ('pending_delivery', 'sent', 'delivery_failed') THEN
    RAISE EXCEPTION 'INVITE_NOT_PENDING' USING ERRCODE = '22023';
  END IF;
  UPDATE public.platform_company_admin_invites SET status = p_status,
    auth_user_id = COALESCE(p_auth_user_id, auth_user_id),
    delivery_error_code = CASE WHEN p_status = 'delivery_failed' THEN left(COALESCE(p_error_code, 'delivery_failed'), 80) ELSE NULL END,
    delivery_attempts = delivery_attempts + 1, updated_at = now()
  WHERE id = p_invite_id RETURNING * INTO v_after;
  INSERT INTO public.admin_audit_log(actor_id, company_id, action, target_type, target_id, before_json, after_json)
  VALUES (p_actor_id, v_after.company_id, 'company_admin_invite_delivery', 'company_admin_invite', v_after.id::text,
    jsonb_build_object('status', v_before.status),
    jsonb_build_object('status', v_after.status, 'error_code', v_after.delivery_error_code,
      'delivery_attempts', v_after.delivery_attempts));
  RETURN v_after;
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_revoke_company_admin_invite(
  p_actor_id uuid, p_invite_id uuid
)
RETURNS public.platform_company_admin_invites
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_invite public.platform_company_admin_invites%ROWTYPE;
BEGIN
  PERFORM private.require_platform_actor(p_actor_id);
  SELECT * INTO STRICT v_invite FROM public.platform_company_admin_invites WHERE id = p_invite_id FOR UPDATE;
  IF v_invite.status NOT IN ('pending_delivery', 'sent', 'delivery_failed') THEN
    RAISE EXCEPTION 'INVITE_NOT_PENDING' USING ERRCODE = '22023';
  END IF;
  UPDATE public.platform_company_admin_invites SET status = 'revoked', revoked_at = now(), updated_at = now()
  WHERE id = p_invite_id RETURNING * INTO v_invite;
  INSERT INTO public.admin_audit_log(actor_id, company_id, action, target_type, target_id, before_json, after_json)
  VALUES (p_actor_id, v_invite.company_id, 'revoke_company_admin_invite', 'company_admin_invite', v_invite.id::text,
    jsonb_build_object('status', 'pending'), jsonb_build_object('status', 'revoked'));
  RETURN v_invite;
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_prepare_company_admin_invite_delivery(
  p_actor_id uuid, p_invite_id uuid
)
RETURNS public.platform_company_admin_invites
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_invite public.platform_company_admin_invites%ROWTYPE; v_before_status text;
BEGIN
  PERFORM private.require_platform_actor(p_actor_id);
  SELECT * INTO STRICT v_invite FROM public.platform_company_admin_invites WHERE id = p_invite_id FOR UPDATE;
  IF v_invite.status IN ('claimed', 'revoked') THEN RAISE EXCEPTION 'INVITE_NOT_PENDING' USING ERRCODE = '22023'; END IF;
  v_before_status := v_invite.status;
  UPDATE public.platform_company_admin_invites SET status = 'pending_delivery',
    expires_at = now() + interval '7 days', delivery_error_code = NULL, updated_at = now()
  WHERE id = p_invite_id RETURNING * INTO v_invite;
  INSERT INTO public.admin_audit_log(actor_id, company_id, action, target_type, target_id, before_json, after_json)
  VALUES (p_actor_id, v_invite.company_id, 'resend_company_admin_invite', 'company_admin_invite', v_invite.id::text,
    jsonb_build_object('status', v_before_status), jsonb_build_object('status', 'pending_delivery', 'expires_at', v_invite.expires_at));
  RETURN v_invite;
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_claim_company_admin_invite(
  p_actor_id uuid, p_invite_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_invite public.platform_company_admin_invites%ROWTYPE; v_auth auth.users%ROWTYPE;
BEGIN
  SELECT * INTO STRICT v_auth FROM auth.users WHERE id = p_actor_id;
  IF v_auth.email_confirmed_at IS NULL THEN RAISE EXCEPTION 'VERIFIED_EMAIL_REQUIRED' USING ERRCODE = '42501'; END IF;
  SELECT * INTO STRICT v_invite FROM public.platform_company_admin_invites WHERE id = p_invite_id FOR UPDATE;
  IF lower(v_invite.email) <> lower(COALESCE(v_auth.email, '')) THEN RAISE EXCEPTION 'INVITE_EMAIL_MISMATCH' USING ERRCODE = '42501'; END IF;
  IF v_invite.status NOT IN ('sent', 'delivery_failed', 'pending_delivery') OR v_invite.expires_at <= now() THEN
    RAISE EXCEPTION 'INVITE_EXPIRED_OR_UNAVAILABLE' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (SELECT 1 FROM public.users WHERE id = p_actor_id) THEN
    RAISE EXCEPTION 'ACCOUNT_ALREADY_ASSIGNED' USING ERRCODE = '23505';
  END IF;
  INSERT INTO public.users(id, company_id, role, full_name, email, is_active)
  VALUES (p_actor_id, v_invite.company_id, 'owner'::public.user_role, v_invite.full_name, lower(v_invite.email), true);
  UPDATE public.platform_company_admin_invites SET status = 'claimed', auth_user_id = p_actor_id,
    claimed_at = now(), updated_at = now() WHERE id = p_invite_id;
  INSERT INTO public.admin_audit_log(actor_id, company_id, action, target_type, target_id, after_json)
  VALUES (p_actor_id, v_invite.company_id, 'claim_company_admin_invite', 'company_admin_invite', v_invite.id::text,
    jsonb_build_object('auth_user_id', p_actor_id, 'email', lower(v_invite.email)));
  RETURN jsonb_build_object('company_id', v_invite.company_id, 'user_id', p_actor_id, 'status', 'claimed');
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_find_auth_user_by_email(p_email text)
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
  SELECT id FROM auth.users WHERE lower(email) = lower(trim(p_email)) ORDER BY created_at LIMIT 1
$$;

CREATE OR REPLACE FUNCTION public.platform_create_admin_invite(
  p_actor_id uuid, p_platform_admin_id uuid, p_email text, p_token_hash text, p_expires_at timestamptz
)
RETURNS public.platform_admin_invites
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_invite public.platform_admin_invites%ROWTYPE;
BEGIN
  PERFORM private.require_platform_actor(p_actor_id);
  IF length(trim(COALESCE(p_email, ''))) NOT BETWEEN 3 AND 254
     OR p_email !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
     OR p_token_hash !~ '^[0-9a-f]{64}$' OR p_expires_at <= now() THEN
    RAISE EXCEPTION 'INVALID_INVITE' USING ERRCODE = '22023';
  END IF;
  INSERT INTO public.platform_admin_invites(email, invite_token, invite_token_hash, created_by, expires_at)
  VALUES (lower(trim(p_email)), NULL, p_token_hash, p_platform_admin_id, p_expires_at)
  RETURNING * INTO v_invite;
  INSERT INTO public.admin_audit_log(actor_id, action, target_type, target_id, after_json)
  VALUES (p_actor_id, 'create_invite', 'platform_admin_invite', v_invite.id::text,
    jsonb_build_object('email', v_invite.email, 'expires_at', v_invite.expires_at));
  RETURN v_invite;
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_claim_admin_invite(
  p_invite_id uuid, p_auth_user_id uuid, p_email text, p_full_name text
)
RETURNS public.platform_admins
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_invite public.platform_admin_invites%ROWTYPE; v_admin public.platform_admins%ROWTYPE;
BEGIN
  SELECT * INTO STRICT v_invite FROM public.platform_admin_invites WHERE id = p_invite_id FOR UPDATE;
  IF v_invite.claimed_at IS NOT NULL OR v_invite.expires_at <= now()
     OR lower(v_invite.email) <> lower(trim(p_email)) THEN
    RAISE EXCEPTION 'INVITE_UNAVAILABLE' USING ERRCODE = '42501';
  END IF;
  UPDATE public.platform_admin_invites SET claimed_at = now() WHERE id = p_invite_id AND claimed_at IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'INVITE_ALREADY_CLAIMED' USING ERRCODE = '23505'; END IF;
  INSERT INTO public.platform_admins(auth_user_id, full_name, email, role, is_active)
  VALUES (p_auth_user_id, trim(p_full_name), lower(trim(p_email)), 'platform_superadmin', true)
  RETURNING * INTO v_admin;
  INSERT INTO public.admin_audit_log(actor_id, action, target_type, target_id, after_json)
  VALUES (p_auth_user_id, 'claim_invite', 'platform_admin', p_auth_user_id::text,
    jsonb_build_object('email', lower(trim(p_email)), 'full_name', trim(p_full_name), 'invite_id', p_invite_id));
  RETURN v_admin;
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_update_license_terms_audited(
  p_actor_id uuid, p_package_branch_count integer, p_monthly_price_per_branch_cents bigint,
  p_additional_branch_monthly_price_cents bigint, p_maximum_additional_branches smallint,
  p_annual_custom_pricing_enabled boolean, p_currency text, p_authorization_reference text
)
RETURNS public.platform_license_terms
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_terms public.platform_license_terms%ROWTYPE;
BEGIN
  v_terms := public.platform_update_license_terms(p_actor_id, p_package_branch_count,
    p_monthly_price_per_branch_cents, p_additional_branch_monthly_price_cents,
    p_maximum_additional_branches, p_annual_custom_pricing_enabled, p_currency, p_authorization_reference);
  INSERT INTO public.admin_audit_log(actor_id, action, target_type, target_id, after_json)
  VALUES (p_actor_id, 'update_license_terms', 'license_terms', 'default',
    jsonb_build_object('authorization_reference', p_authorization_reference, 'terms', to_jsonb(v_terms)));
  RETURN v_terms;
END;
$$;

CREATE OR REPLACE FUNCTION public.platform_set_company_branch_license_audited(
  p_actor_id uuid, p_company_id uuid, p_package_count integer, p_additional_branch_count integer,
  p_contract_reference text, p_annual_price_override_cents bigint DEFAULT NULL,
  p_annual_approval_reference text DEFAULT NULL
)
RETURNS public.platform_company_licenses
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE v_license public.platform_company_licenses%ROWTYPE;
BEGIN
  v_license := public.platform_set_company_branch_license(p_actor_id, p_company_id,
    p_package_count, p_additional_branch_count, p_contract_reference,
    p_annual_price_override_cents, p_annual_approval_reference);
  INSERT INTO public.admin_audit_log(actor_id, company_id, action, target_type, target_id, after_json)
  VALUES (p_actor_id, p_company_id, 'set_company_license', 'branch_license', p_company_id::text,
    jsonb_build_object('contract_reference', p_contract_reference, 'license', to_jsonb(v_license)));
  RETURN v_license;
END;
$$;

REVOKE ALL ON FUNCTION public.platform_create_company_with_admin_invite(uuid,text,text,text,text,text,text,jsonb,text,text),
  public.platform_update_company(uuid,uuid,text,text,text,text,text,text),
  public.platform_set_company_status(uuid,uuid,text),
  public.platform_record_company_invite_delivery(uuid,uuid,text,uuid,text),
  public.platform_revoke_company_admin_invite(uuid,uuid),
  public.platform_prepare_company_admin_invite_delivery(uuid,uuid),
  public.platform_claim_company_admin_invite(uuid,uuid),
  public.platform_find_auth_user_by_email(text),
  public.platform_create_admin_invite(uuid,uuid,text,text,timestamptz),
  public.platform_claim_admin_invite(uuid,uuid,text,text),
  public.platform_update_license_terms_audited(uuid,integer,bigint,bigint,smallint,boolean,text,text),
  public.platform_set_company_branch_license_audited(uuid,uuid,integer,integer,text,bigint,text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.platform_create_company_with_admin_invite(uuid,text,text,text,text,text,text,jsonb,text,text),
  public.platform_update_company(uuid,uuid,text,text,text,text,text,text),
  public.platform_set_company_status(uuid,uuid,text),
  public.platform_record_company_invite_delivery(uuid,uuid,text,uuid,text),
  public.platform_revoke_company_admin_invite(uuid,uuid),
  public.platform_prepare_company_admin_invite_delivery(uuid,uuid),
  public.platform_claim_company_admin_invite(uuid,uuid),
  public.platform_find_auth_user_by_email(text),
  public.platform_create_admin_invite(uuid,uuid,text,text,timestamptz),
  public.platform_claim_admin_invite(uuid,uuid,text,text),
  public.platform_update_license_terms_audited(uuid,integer,bigint,bigint,smallint,boolean,text,text),
  public.platform_set_company_branch_license_audited(uuid,uuid,integer,integer,text,bigint,text)
  TO service_role;
