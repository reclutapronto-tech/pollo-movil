CREATE OR REPLACE FUNCTION public.update_restaurant_incident(
  p_branch_id uuid,
  p_incident_id uuid,
  p_actor_id uuid,
  p_status text,
  p_assigned_to uuid,
  p_is_blocking boolean,
  p_note text
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  PERFORM 1 FROM public.restaurant_incidents
  WHERE id = p_incident_id AND branch_id = p_branch_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'INCIDENT_NOT_FOUND'; END IF;
  IF p_status NOT IN ('open', 'in_progress', 'resolved') THEN RAISE EXCEPTION 'INVALID_INCIDENT_STATUS'; END IF;
  UPDATE public.restaurant_incidents SET
    status = p_status,
    assigned_to = p_assigned_to,
    is_blocking = p_is_blocking,
    resolved_at = CASE WHEN p_status = 'resolved' THEN now() ELSE NULL END
  WHERE id = p_incident_id AND branch_id = p_branch_id;
  INSERT INTO public.restaurant_incident_events(branch_id, incident_id, actor_id, event_type, note)
  VALUES (p_branch_id, p_incident_id, p_actor_id, 'updated', nullif(trim(p_note), ''));
  RETURN jsonb_build_object('id', p_incident_id, 'status', p_status);
END;
$$;
