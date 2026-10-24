-- Platform operators are separate from customer tenant users. They have no
-- public.users row and therefore no company_id or restaurant membership.
ALTER TABLE public.platform_admins
  ALTER COLUMN role SET DEFAULT 'platform_superadmin';

CREATE OR REPLACE FUNCTION public.is_platform_admin()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.platform_admins AS admin
    WHERE admin.auth_user_id = auth.uid()
      AND admin.is_active
      AND admin.role IN ('platform_admin', 'platform_superadmin')
  );
$$;

REVOKE ALL ON FUNCTION public.is_platform_admin() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_platform_admin() TO authenticated, service_role;

-- One centrally configurable set of default commercial terms. An explicit
-- contract snapshot is stored per customer license so future catalog changes
-- do not silently alter existing agreements.
CREATE TABLE public.platform_license_terms (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  package_branch_count integer NOT NULL DEFAULT 5 CHECK (package_branch_count > 0),
  monthly_price_per_branch_cents bigint NOT NULL DEFAULT 150000 CHECK (monthly_price_per_branch_cents >= 0),
  additional_branch_monthly_price_cents bigint NOT NULL DEFAULT 200000 CHECK (additional_branch_monthly_price_cents >= 0),
  maximum_additional_branches smallint NOT NULL DEFAULT 1 CHECK (maximum_additional_branches >= 0),
  annual_custom_pricing_enabled boolean NOT NULL DEFAULT true,
  currency text NOT NULL DEFAULT 'MXN' CHECK (currency ~ '^[A-Z]{3}$'),
  updated_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.platform_license_terms(singleton)
VALUES (true)
ON CONFLICT (singleton) DO NOTHING;

CREATE TABLE public.platform_company_licenses (
  company_id uuid PRIMARY KEY REFERENCES public.companies(id) ON DELETE RESTRICT,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'suspended', 'expired')),
  package_branch_count integer NOT NULL CHECK (package_branch_count > 0),
  package_count integer NOT NULL CHECK (package_count > 0),
  additional_branch_count integer NOT NULL DEFAULT 0 CHECK (additional_branch_count >= 0),
  licensed_branch_count bigint GENERATED ALWAYS AS
    (package_branch_count::bigint * package_count + additional_branch_count) STORED,
  monthly_price_per_branch_cents bigint NOT NULL CHECK (monthly_price_per_branch_cents >= 0),
  additional_branch_monthly_price_cents bigint NOT NULL CHECK (additional_branch_monthly_price_cents >= 0),
  currency text NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
  contract_reference text NOT NULL CHECK (length(trim(contract_reference)) BETWEEN 1 AND 200),
  authorized_by uuid NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  authorized_at timestamptz NOT NULL DEFAULT now(),
  annual_price_override_cents bigint CHECK (annual_price_override_cents IS NULL OR annual_price_override_cents >= 0),
  annual_approval_reference text,
  annual_approved_by uuid REFERENCES auth.users(id) ON DELETE RESTRICT,
  annual_approved_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (
    (annual_price_override_cents IS NULL AND annual_approval_reference IS NULL
      AND annual_approved_by IS NULL AND annual_approved_at IS NULL)
    OR
    (annual_price_override_cents IS NOT NULL
      AND length(trim(COALESCE(annual_approval_reference, ''))) BETWEEN 1 AND 200
      AND annual_approved_by IS NOT NULL AND annual_approved_at IS NOT NULL)
  )
);

CREATE TABLE public.platform_license_events (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  company_id uuid REFERENCES public.companies(id) ON DELETE SET NULL,
  actor_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  event_type text NOT NULL CHECK (event_type IN ('terms_updated', 'license_authorized')),
  authorization_reference text NOT NULL CHECK (length(trim(authorization_reference)) BETWEEN 1 AND 200),
  before_json jsonb,
  after_json jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX platform_company_licenses_status_idx
  ON public.platform_company_licenses(status, company_id);
CREATE INDEX platform_license_events_company_created_idx
  ON public.platform_license_events(company_id, created_at DESC);

ALTER TABLE public.platform_license_terms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_company_licenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_license_events ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.platform_license_terms, public.platform_company_licenses,
  public.platform_license_events FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.platform_license_terms,
  public.platform_company_licenses, public.platform_license_events TO service_role;
GRANT USAGE, SELECT ON SEQUENCE public.platform_license_events_id_seq TO service_role;

-- Keep customer/license data inaccessible through direct client table APIs.
CREATE POLICY platform_license_terms_service_only ON public.platform_license_terms
  FOR ALL TO authenticated USING (false) WITH CHECK (false);
CREATE POLICY platform_company_licenses_service_only ON public.platform_company_licenses
  FOR ALL TO authenticated USING (false) WITH CHECK (false);
CREATE POLICY platform_license_events_service_only ON public.platform_license_events
  FOR ALL TO authenticated USING (false) WITH CHECK (false);

CREATE OR REPLACE FUNCTION public.platform_update_license_terms(
  p_actor_id uuid,
  p_package_branch_count integer,
  p_monthly_price_per_branch_cents bigint,
  p_additional_branch_monthly_price_cents bigint,
  p_maximum_additional_branches smallint,
  p_annual_custom_pricing_enabled boolean,
  p_currency text,
  p_authorization_reference text
)
RETURNS public.platform_license_terms
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_before public.platform_license_terms%ROWTYPE;
  v_after public.platform_license_terms%ROWTYPE;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.platform_admins AS admin
    WHERE admin.auth_user_id = p_actor_id
      AND admin.is_active
      AND admin.role IN ('platform_admin', 'platform_superadmin')
  ) THEN
    RAISE EXCEPTION 'PLATFORM_ADMIN_REQUIRED' USING ERRCODE = '42501';
  END IF;
  IF p_package_branch_count <= 0 OR p_monthly_price_per_branch_cents < 0
     OR p_additional_branch_monthly_price_cents < 0 OR p_maximum_additional_branches < 0
     OR p_currency !~ '^[A-Z]{3}$'
     OR length(trim(COALESCE(p_authorization_reference, ''))) NOT BETWEEN 1 AND 200 THEN
    RAISE EXCEPTION 'INVALID_LICENSE_TERMS' USING ERRCODE = '22023';
  END IF;

  PERFORM 1 FROM public.platform_license_terms WHERE singleton FOR UPDATE;
  SELECT * INTO STRICT v_before FROM public.platform_license_terms WHERE singleton;

  UPDATE public.platform_license_terms
  SET package_branch_count = p_package_branch_count,
      monthly_price_per_branch_cents = p_monthly_price_per_branch_cents,
      additional_branch_monthly_price_cents = p_additional_branch_monthly_price_cents,
      maximum_additional_branches = p_maximum_additional_branches,
      annual_custom_pricing_enabled = p_annual_custom_pricing_enabled,
      currency = p_currency,
      updated_by = p_actor_id,
      updated_at = now()
  WHERE singleton
  RETURNING * INTO v_after;

  INSERT INTO public.platform_license_events(
    event_type, actor_id, authorization_reference, before_json, after_json
  ) VALUES (
    'terms_updated', p_actor_id, trim(p_authorization_reference),
    to_jsonb(v_before), to_jsonb(v_after)
  );
  RETURN v_after;
END;
$$;
CREATE OR REPLACE FUNCTION public.platform_set_company_branch_license(
  p_actor_id uuid,
  p_company_id uuid,
  p_package_count integer,
  p_additional_branch_count integer,
  p_contract_reference text,
  p_annual_price_override_cents bigint DEFAULT NULL,
  p_annual_approval_reference text DEFAULT NULL
)
RETURNS public.platform_company_licenses
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_terms public.platform_license_terms%ROWTYPE;
  v_before public.platform_company_licenses%ROWTYPE;
  v_after public.platform_company_licenses%ROWTYPE;
  v_active_branches bigint;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.platform_admins AS admin
    WHERE admin.auth_user_id = p_actor_id
      AND admin.is_active
      AND admin.role IN ('platform_admin', 'platform_superadmin')
  ) THEN
    RAISE EXCEPTION 'PLATFORM_ADMIN_REQUIRED' USING ERRCODE = '42501';
  END IF;
  IF p_package_count <= 0 OR p_additional_branch_count < 0
     OR length(trim(COALESCE(p_contract_reference, ''))) NOT BETWEEN 1 AND 200 THEN
    RAISE EXCEPTION 'INVALID_LICENSE_AUTHORIZATION' USING ERRCODE = '22023';
  END IF;
  IF p_annual_price_override_cents IS NULL
     AND length(trim(COALESCE(p_annual_approval_reference, ''))) > 0 THEN
    RAISE EXCEPTION 'ANNUAL_APPROVAL_WITHOUT_OVERRIDE' USING ERRCODE = '22023';
  END IF;

  PERFORM 1 FROM public.companies WHERE id = p_company_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'COMPANY_NOT_FOUND' USING ERRCODE = 'P0002'; END IF;

  SELECT * INTO STRICT v_terms
  FROM public.platform_license_terms
  WHERE singleton
  FOR SHARE;

  IF p_additional_branch_count > v_terms.maximum_additional_branches THEN
    RAISE EXCEPTION 'PACKAGE_EXPANSION_REQUIRED' USING ERRCODE = '22023';
  END IF;
  IF p_annual_price_override_cents IS NOT NULL
     AND (NOT v_terms.annual_custom_pricing_enabled
       OR length(trim(COALESCE(p_annual_approval_reference, ''))) NOT BETWEEN 1 AND 200) THEN
    RAISE EXCEPTION 'ANNUAL_PRICE_REQUIRES_EXPLICIT_APPROVAL' USING ERRCODE = '42501';
  END IF;

  SELECT count(*) INTO v_active_branches
  FROM public.restaurant_branches
  WHERE company_id = p_company_id AND is_active;
  IF v_active_branches > (v_terms.package_branch_count::bigint * p_package_count + p_additional_branch_count) THEN
    RAISE EXCEPTION 'LICENSE_BELOW_ACTIVE_BRANCH_COUNT' USING ERRCODE = '23514';
  END IF;

  SELECT * INTO v_before
  FROM public.platform_company_licenses
  WHERE company_id = p_company_id
  FOR UPDATE;

  INSERT INTO public.platform_company_licenses(
    company_id, status, package_branch_count, package_count, additional_branch_count,
    monthly_price_per_branch_cents, additional_branch_monthly_price_cents, currency,
    contract_reference, authorized_by, authorized_at,
    annual_price_override_cents, annual_approval_reference,
    annual_approved_by, annual_approved_at, updated_at
  ) VALUES (
    p_company_id, 'active', v_terms.package_branch_count, p_package_count, p_additional_branch_count,
    v_terms.monthly_price_per_branch_cents, v_terms.additional_branch_monthly_price_cents, v_terms.currency,
    trim(p_contract_reference), p_actor_id, now(),
    p_annual_price_override_cents,
    CASE WHEN p_annual_price_override_cents IS NULL THEN NULL ELSE trim(p_annual_approval_reference) END,
    CASE WHEN p_annual_price_override_cents IS NULL THEN NULL ELSE p_actor_id END,
    CASE WHEN p_annual_price_override_cents IS NULL THEN NULL ELSE now() END,
    now()
  )
  ON CONFLICT (company_id) DO UPDATE SET
    status = 'active',
    package_branch_count = EXCLUDED.package_branch_count,
    package_count = EXCLUDED.package_count,
    additional_branch_count = EXCLUDED.additional_branch_count,
    monthly_price_per_branch_cents = EXCLUDED.monthly_price_per_branch_cents,
    additional_branch_monthly_price_cents = EXCLUDED.additional_branch_monthly_price_cents,
    currency = EXCLUDED.currency,
    contract_reference = EXCLUDED.contract_reference,
    authorized_by = EXCLUDED.authorized_by,
    authorized_at = EXCLUDED.authorized_at,
    annual_price_override_cents = EXCLUDED.annual_price_override_cents,
    annual_approval_reference = EXCLUDED.annual_approval_reference,
    annual_approved_by = EXCLUDED.annual_approved_by,
    annual_approved_at = EXCLUDED.annual_approved_at,
    updated_at = now()
  RETURNING * INTO v_after;

  INSERT INTO public.platform_license_events(
    company_id, actor_id, event_type, authorization_reference, before_json, after_json
  ) VALUES (
    p_company_id, p_actor_id, 'license_authorized', trim(p_contract_reference),
    CASE WHEN v_before.company_id IS NULL THEN NULL ELSE to_jsonb(v_before) END,
    to_jsonb(v_after)
  );
  RETURN v_after;
END;
$$;

REVOKE ALL ON FUNCTION public.platform_update_license_terms(uuid, integer, bigint, bigint, smallint, boolean, text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.platform_update_license_terms(uuid, integer, bigint, bigint, smallint, boolean, text, text)
  TO service_role;
REVOKE ALL ON FUNCTION public.platform_set_company_branch_license(uuid, uuid, integer, integer, text, bigint, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.platform_set_company_branch_license(uuid, uuid, integer, integer, text, bigint, text)
  TO service_role;

CREATE OR REPLACE FUNCTION public.enforce_restaurant_branch_license_capacity()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  v_license public.platform_company_licenses%ROWTYPE;
  v_active_branches bigint;
BEGIN
  IF TG_OP = 'UPDATE' AND NOT NEW.is_active THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND OLD.is_active AND NEW.company_id = OLD.company_id THEN RETURN NEW; END IF;

  -- Serialize concurrent branch activations and contract changes by company.
  PERFORM 1 FROM public.companies WHERE id = NEW.company_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'COMPANY_NOT_FOUND' USING ERRCODE = '23503'; END IF;

  SELECT * INTO v_license
  FROM public.platform_company_licenses
  WHERE company_id = NEW.company_id AND status = 'active'
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'BRANCH_LICENSE_REQUIRED' USING ERRCODE = '23514'; END IF;

  SELECT count(*) INTO v_active_branches
  FROM public.restaurant_branches
  WHERE company_id = NEW.company_id AND is_active AND id <> NEW.id;
  IF v_active_branches >= v_license.licensed_branch_count THEN
    RAISE EXCEPTION 'BRANCH_LICENSE_CAPACITY_EXCEEDED' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS enforce_restaurant_branch_license_capacity ON public.restaurant_branches;
CREATE TRIGGER enforce_restaurant_branch_license_capacity
  BEFORE INSERT OR UPDATE ON public.restaurant_branches
  FOR EACH ROW EXECUTE FUNCTION public.enforce_restaurant_branch_license_capacity();
