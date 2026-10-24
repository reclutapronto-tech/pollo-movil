ALTER TABLE public.restaurant_incident_events
  ADD COLUMN client_event_id uuid,
  ADD COLUMN client_event_payload jsonb;

CREATE UNIQUE INDEX restaurant_incident_events_client_event_unique
  ON public.restaurant_incident_events(branch_id, client_event_id)
  WHERE client_event_id IS NOT NULL;

DROP FUNCTION IF EXISTS public.update_restaurant_incident(
  uuid, uuid, uuid, text, uuid, boolean, text
);

CREATE FUNCTION public.update_restaurant_incident(
  p_branch_id uuid,
  p_incident_id uuid,
  p_actor_id uuid,
  p_status text,
  p_assigned_to uuid,
  p_is_blocking boolean,
  p_note text,
  p_client_event_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  incident_row public.restaurant_incidents%ROWTYPE;
  existing_event public.restaurant_incident_events%ROWTYPE;
  event_payload jsonb := pg_catalog.jsonb_build_object(
    'status', p_status,
    'assigned_to', p_assigned_to,
    'is_blocking', p_is_blocking,
    'note', nullif(pg_catalog.btrim(p_note), '')
  );
BEGIN
  IF p_client_event_id IS NULL THEN
    RAISE EXCEPTION 'CLIENT_EVENT_ID_REQUIRED';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_branch_id::text || ':' || p_client_event_id::text, 0)
  );

  SELECT * INTO existing_event
  FROM public.restaurant_incident_events
  WHERE branch_id = p_branch_id AND client_event_id = p_client_event_id;

  IF FOUND THEN
    IF existing_event.incident_id <> p_incident_id
      OR existing_event.actor_id <> p_actor_id
      OR existing_event.event_type <> 'updated'
      OR existing_event.client_event_payload IS DISTINCT FROM event_payload THEN
      RAISE EXCEPTION 'IDEMPOTENCY_KEY_REUSED';
    END IF;
    RETURN pg_catalog.jsonb_build_object(
      'id', p_incident_id,
      'status', existing_event.client_event_payload ->> 'status',
      'duplicate', true
    );
  END IF;

  SELECT * INTO incident_row
  FROM public.restaurant_incidents
  WHERE id = p_incident_id AND branch_id = p_branch_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'INCIDENT_NOT_FOUND'; END IF;
  IF p_status NOT IN ('open', 'in_progress', 'resolved') THEN
    RAISE EXCEPTION 'INVALID_INCIDENT_STATUS';
  END IF;

  UPDATE public.restaurant_incidents SET
    status = p_status,
    assigned_to = p_assigned_to,
    is_blocking = p_is_blocking,
    resolved_at = CASE WHEN p_status = 'resolved' THEN now() ELSE NULL END
  WHERE id = p_incident_id AND branch_id = p_branch_id;

  INSERT INTO public.restaurant_incident_events(
    branch_id, incident_id, actor_id, event_type, note,
    client_event_id, client_event_payload
  ) VALUES (
    p_branch_id, p_incident_id, p_actor_id, 'updated',
    nullif(pg_catalog.btrim(p_note), ''), p_client_event_id, event_payload
  );

  RETURN pg_catalog.jsonb_build_object(
    'id', p_incident_id,
    'status', p_status,
    'duplicate', false
  );
END;
$$;

REVOKE ALL ON FUNCTION public.update_restaurant_incident(
  uuid, uuid, uuid, text, uuid, boolean, text, uuid
) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.update_restaurant_incident(
  uuid, uuid, uuid, text, uuid, boolean, text, uuid
) TO service_role;
