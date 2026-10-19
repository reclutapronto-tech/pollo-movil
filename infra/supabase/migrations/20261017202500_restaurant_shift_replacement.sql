CREATE OR REPLACE FUNCTION public.replace_restaurant_shift(
  p_branch_id uuid,
  p_actor_id uuid,
  p_shift_id uuid,
  p_employee_id uuid,
  p_shift_date date,
  p_start_time time,
  p_end_time time,
  p_status text,
  p_breaks jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  old_shift public.restaurant_shifts%ROWTYPE;
BEGIN
  IF private.restaurant_user_role(p_branch_id, p_actor_id) NOT IN ('admin', 'supervisor') THEN
    RAISE EXCEPTION 'MANAGER_REQUIRED';
  END IF;

  SELECT * INTO old_shift
  FROM public.restaurant_shifts
  WHERE branch_id = p_branch_id AND id = p_shift_id
  FOR UPDATE;
  IF old_shift.id IS NULL OR old_shift.status = 'cancelled' THEN
    RAISE EXCEPTION 'SHIFT_NOT_FOUND';
  END IF;

  IF old_shift.employee_id IS DISTINCT FROM p_employee_id
    OR old_shift.shift_date IS DISTINCT FROM p_shift_date
    OR old_shift.start_time IS DISTINCT FROM p_start_time
    OR old_shift.end_time IS DISTINCT FROM p_end_time THEN
    UPDATE public.restaurant_shifts SET status = 'cancelled'
    WHERE branch_id = p_branch_id AND id = p_shift_id;
  END IF;

  RETURN public.save_restaurant_shift(
    p_branch_id, p_actor_id, p_employee_id, p_shift_date,
    p_start_time, p_end_time, p_status, p_breaks
  );
END;
$$;

REVOKE ALL ON FUNCTION public.replace_restaurant_shift(uuid, uuid, uuid, uuid, date, time, time, text, jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.replace_restaurant_shift(uuid, uuid, uuid, uuid, date, time, time, text, jsonb)
  TO service_role;
