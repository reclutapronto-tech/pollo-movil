ALTER TABLE public.restaurant_branches
  ALTER COLUMN timezone DROP DEFAULT;

CREATE OR REPLACE FUNCTION public.create_restaurant_branch(
  p_company_id uuid,
  p_creator_id uuid,
  p_name text,
  p_timezone text
)
RETURNS uuid
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  branch_row public.restaurant_branches%ROWTYPE;
BEGIN
  IF length(trim(p_name)) < 2 OR length(trim(p_name)) > 120 THEN
    RAISE EXCEPTION 'INVALID_BRANCH_NAME';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.users AS u
    WHERE u.id = p_creator_id AND u.company_id = p_company_id
      AND u.is_active AND u.role::text IN ('owner', 'admin')
  ) THEN
    RAISE EXCEPTION 'BRANCH_ADMIN_REQUIRED';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name = p_timezone
  ) THEN
    RAISE EXCEPTION 'INVALID_TIMEZONE';
  END IF;

  INSERT INTO public.restaurant_branches(company_id, name, timezone, created_by)
  VALUES (p_company_id, trim(p_name), p_timezone, p_creator_id)
  RETURNING * INTO branch_row;

  INSERT INTO public.restaurant_memberships(
    branch_id, company_id, user_id, access_role, created_by
  ) VALUES (
    branch_row.id, p_company_id, p_creator_id, 'admin', p_creator_id
  );

  RETURN branch_row.id;
END;
$$;
