-- Company administrators can manage every branch in their own company; branch
-- managers and workers remain limited to explicit active memberships.
CREATE OR REPLACE FUNCTION private.restaurant_user_role(
  p_branch_id uuid,
  p_user_id uuid DEFAULT auth.uid()
)
RETURNS text
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
  SELECT CASE
    WHEN EXISTS (
      SELECT 1
      FROM public.restaurant_branches AS branch
      JOIN public.users AS company_user
        ON company_user.company_id = branch.company_id
      WHERE branch.id = p_branch_id
        AND company_user.id = p_user_id
        AND company_user.is_active
        AND company_user.role::text IN ('owner', 'admin')
    ) THEN 'admin'
    ELSE (
      SELECT membership.access_role
      FROM public.restaurant_memberships AS membership
      WHERE membership.branch_id = p_branch_id
        AND membership.user_id = p_user_id
        AND membership.is_active
    )
  END;
$$;

-- The commercial rule allows at most one individual add-on before a package
-- expansion is required. Monetary values and package pricing remain editable
-- only through the separately authorized platform terms RPC.
ALTER TABLE public.platform_license_terms
  DROP CONSTRAINT IF EXISTS platform_license_terms_maximum_additional_branches_check;
ALTER TABLE public.platform_license_terms
  ADD CONSTRAINT platform_license_terms_maximum_additional_branches_check
  CHECK (maximum_additional_branches BETWEEN 0 AND 1);

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
     OR p_additional_branch_monthly_price_cents < 0
     OR p_maximum_additional_branches NOT BETWEEN 0 AND 1
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

REVOKE ALL ON FUNCTION public.platform_update_license_terms(uuid, integer, bigint, bigint, smallint, boolean, text, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.platform_update_license_terms(uuid, integer, bigint, bigint, smallint, boolean, text, text)
  TO service_role;
