CREATE OR REPLACE FUNCTION public.save_restaurant_member(
  p_branch_id uuid,
  p_actor_id uuid,
  p_employee_id uuid,
  p_access_role text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  actor_role text;
  target_role text;
  target_is_active boolean;
  branch_company_id uuid;
BEGIN
  actor_role := private.restaurant_user_role(p_branch_id, p_actor_id);
  IF actor_role IS NULL OR actor_role NOT IN ('admin', 'supervisor') THEN
    RAISE EXCEPTION 'MANAGER_REQUIRED';
  END IF;
  IF p_access_role IS NULL OR p_access_role NOT IN ('admin', 'supervisor', 'employee') THEN
    RAISE EXCEPTION 'INVALID_MEMBER_ROLE';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_branch_id::text || ':member-lifecycle', 0)
  );

  SELECT branch.company_id INTO branch_company_id
  FROM public.restaurant_branches AS branch WHERE branch.id = p_branch_id;
  IF NOT FOUND OR NOT EXISTS (
    SELECT 1 FROM public.users AS employee
    WHERE employee.id = p_employee_id
      AND employee.company_id = branch_company_id
      AND employee.is_active
  ) THEN
    RAISE EXCEPTION 'INVALID_EMPLOYEE';
  END IF;

  SELECT membership.access_role, membership.is_active
    INTO target_role, target_is_active
  FROM public.restaurant_memberships AS membership
  WHERE membership.branch_id = p_branch_id AND membership.user_id = p_employee_id
  FOR UPDATE;

  IF actor_role = 'supervisor' AND (p_access_role = 'admin' OR target_role = 'admin') THEN
    RAISE EXCEPTION 'BRANCH_ADMIN_REQUIRED';
  END IF;

  IF target_is_active AND target_role = 'admin' AND p_access_role <> 'admin' AND (
    SELECT count(*) FROM public.restaurant_memberships AS admins
    WHERE admins.branch_id = p_branch_id AND admins.is_active AND admins.access_role = 'admin'
  ) <= 1 THEN
    RAISE EXCEPTION 'LAST_BRANCH_ADMIN';
  END IF;

  INSERT INTO public.restaurant_memberships(
    branch_id, company_id, user_id, access_role, is_active, created_by
  ) VALUES (
    p_branch_id, branch_company_id, p_employee_id, p_access_role, true, p_actor_id
  )
  ON CONFLICT (branch_id, user_id) DO UPDATE
    SET access_role = EXCLUDED.access_role, is_active = true;

  RETURN pg_catalog.jsonb_build_object('user_id', p_employee_id, 'access_role', p_access_role);
END;
$$;

CREATE OR REPLACE FUNCTION public.set_restaurant_member_active(
  p_branch_id uuid,
  p_actor_id uuid,
  p_employee_id uuid,
  p_is_active boolean
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  actor_role text;
  target_role text;
BEGIN
  actor_role := private.restaurant_user_role(p_branch_id, p_actor_id);
  IF actor_role IS NULL OR actor_role NOT IN ('admin', 'supervisor') THEN
    RAISE EXCEPTION 'MANAGER_REQUIRED';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_branch_id::text || ':member-lifecycle', 0)
  );

  SELECT membership.access_role INTO target_role
  FROM public.restaurant_memberships AS membership
  WHERE membership.branch_id = p_branch_id
    AND membership.user_id = p_employee_id
  FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'EMPLOYEE_NOT_IN_BRANCH'; END IF;

  IF actor_role = 'supervisor' AND target_role = 'admin' THEN
    RAISE EXCEPTION 'BRANCH_ADMIN_REQUIRED';
  END IF;

  IF NOT p_is_active AND EXISTS (
    SELECT 1 FROM public.restaurant_time_sessions AS session
    WHERE session.branch_id = p_branch_id
      AND session.employee_id = p_employee_id
      AND session.clock_out_at IS NULL
  ) THEN
    RAISE EXCEPTION 'EMPLOYEE_HAS_ACTIVE_TIME_SESSION';
  END IF;

  IF NOT p_is_active AND target_role = 'admin' AND (
    SELECT count(*) FROM public.restaurant_memberships AS admins
    WHERE admins.branch_id = p_branch_id
      AND admins.is_active
      AND admins.access_role = 'admin'
  ) <= 1 THEN
    RAISE EXCEPTION 'LAST_BRANCH_ADMIN';
  END IF;

  UPDATE public.restaurant_memberships
  SET is_active = p_is_active,
      customer_service_active = CASE WHEN p_is_active THEN customer_service_active ELSE false END
  WHERE branch_id = p_branch_id AND user_id = p_employee_id;

  IF NOT p_is_active THEN
    UPDATE public.restaurant_task_parts
    SET assigned_to = NULL
    WHERE branch_id = p_branch_id
      AND assigned_to = p_employee_id
      AND status = 'pending';

    UPDATE public.restaurant_tasks
    SET assigned_to = NULL
    WHERE branch_id = p_branch_id
      AND assigned_to = p_employee_id
      AND status = 'pending';
  END IF;

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.set_restaurant_member_active(uuid, uuid, uuid, boolean)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.set_restaurant_member_active(uuid, uuid, uuid, boolean)
  TO service_role;
REVOKE ALL ON FUNCTION public.save_restaurant_member(uuid, uuid, uuid, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.save_restaurant_member(uuid, uuid, uuid, text)
  TO service_role;
