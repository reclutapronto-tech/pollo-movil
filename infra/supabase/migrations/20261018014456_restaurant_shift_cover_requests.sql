CREATE TABLE public.restaurant_shift_cover_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid NOT NULL REFERENCES public.restaurant_branches(id) ON DELETE CASCADE,
  shift_id uuid NOT NULL,
  requester_id uuid NOT NULL,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'denied', 'cancelled')),
  note text CHECK (note IS NULL OR length(note) <= 1000),
  decision_note text CHECK (decision_note IS NULL OR length(decision_note) <= 500),
  replacement_employee_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
  replacement_shift_id uuid REFERENCES public.restaurant_shifts(id) ON DELETE SET NULL,
  client_event_id uuid NOT NULL UNIQUE,
  reviewed_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
  reviewed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (branch_id, shift_id)
    REFERENCES public.restaurant_shifts(branch_id, id) ON DELETE CASCADE,
  FOREIGN KEY (branch_id, requester_id)
    REFERENCES public.restaurant_memberships(branch_id, user_id) ON DELETE CASCADE
);

CREATE UNIQUE INDEX restaurant_shift_cover_one_pending_per_shift
  ON public.restaurant_shift_cover_requests(branch_id, shift_id)
  WHERE status = 'pending';
CREATE INDEX restaurant_shift_cover_requester_idx
  ON public.restaurant_shift_cover_requests(branch_id, requester_id, created_at DESC);
CREATE INDEX restaurant_shift_cover_review_queue_idx
  ON public.restaurant_shift_cover_requests(branch_id, created_at)
  WHERE status = 'pending';
CREATE INDEX restaurant_shift_cover_replacement_employee_idx
  ON public.restaurant_shift_cover_requests(replacement_employee_id);
CREATE INDEX restaurant_shift_cover_replacement_shift_idx
  ON public.restaurant_shift_cover_requests(replacement_shift_id);
CREATE INDEX restaurant_shift_cover_reviewer_idx
  ON public.restaurant_shift_cover_requests(reviewed_by);

ALTER TABLE public.restaurant_shift_cover_requests ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.restaurant_shift_cover_requests FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON public.restaurant_shift_cover_requests TO service_role;

ALTER TABLE public.restaurant_notifications
  DROP CONSTRAINT restaurant_notifications_notification_type_check;
ALTER TABLE public.restaurant_notifications
  ADD CONSTRAINT restaurant_notifications_notification_type_check CHECK (
    notification_type IN (
      'task_assigned', 'task_part_assigned', 'incident_assigned', 'incident_reported',
      'shift_handoff_received', 'shift_handoff_acknowledged',
      'shift_published', 'shift_updated', 'shift_removed',
      'absence_requested', 'absence_reviewed', 'inspection_attention',
      'shift_cover_requested', 'shift_cover_reviewed'
    )
  );
ALTER TABLE public.restaurant_notifications
  DROP CONSTRAINT restaurant_notifications_entity_type_check;
ALTER TABLE public.restaurant_notifications
  ADD CONSTRAINT restaurant_notifications_entity_type_check
  CHECK (entity_type IN ('task', 'incident', 'handoff', 'shift', 'absence', 'inspection', 'shift_cover_request'));

CREATE OR REPLACE FUNCTION public.create_restaurant_shift_cover_request(
  p_branch_id uuid,
  p_actor_id uuid,
  p_shift_id uuid,
  p_client_event_id uuid,
  p_note text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  actor_role text;
  branch_timezone text;
  shift_row public.restaurant_shifts%ROWTYPE;
  existing_request public.restaurant_shift_cover_requests%ROWTYPE;
  request_id uuid;
BEGIN
  actor_role := private.restaurant_user_role(p_branch_id, p_actor_id);
  IF actor_role IS NULL THEN RAISE EXCEPTION 'BRANCH_ACCESS_REQUIRED'; END IF;
  IF p_note IS NOT NULL AND length(trim(p_note)) > 1000 THEN
    RAISE EXCEPTION 'INVALID_SHIFT_COVER_NOTE';
  END IF;

  SELECT branch.timezone INTO branch_timezone
  FROM public.restaurant_branches AS branch
  WHERE branch.id = p_branch_id AND branch.is_active;
  IF branch_timezone IS NULL THEN RAISE EXCEPTION 'BRANCH_ACCESS_REQUIRED'; END IF;

  SELECT * INTO existing_request
  FROM public.restaurant_shift_cover_requests
  WHERE client_event_id = p_client_event_id;
  IF existing_request.id IS NOT NULL THEN
    IF existing_request.branch_id IS DISTINCT FROM p_branch_id
      OR existing_request.shift_id IS DISTINCT FROM p_shift_id
      OR existing_request.requester_id IS DISTINCT FROM p_actor_id
      OR existing_request.note IS DISTINCT FROM nullif(trim(p_note), '') THEN
      RAISE EXCEPTION 'IDEMPOTENCY_KEY_REUSED';
    END IF;
    RETURN existing_request.id;
  END IF;

  SELECT * INTO shift_row
  FROM public.restaurant_shifts
  WHERE branch_id = p_branch_id AND id = p_shift_id
  FOR UPDATE;
  IF shift_row.id IS NULL OR shift_row.status <> 'published' THEN
    RAISE EXCEPTION 'SHIFT_NOT_AVAILABLE';
  END IF;
  IF shift_row.employee_id IS DISTINCT FROM p_actor_id THEN
    RAISE EXCEPTION 'SHIFT_NOT_OWNED_BY_REQUESTER';
  END IF;
  IF shift_row.shift_date + shift_row.start_time <= (now() AT TIME ZONE branch_timezone) THEN
    RAISE EXCEPTION 'SHIFT_ALREADY_STARTED';
  END IF;

  INSERT INTO public.restaurant_shift_cover_requests(
    branch_id, shift_id, requester_id, note, client_event_id
  ) VALUES (
    p_branch_id, p_shift_id, p_actor_id, nullif(trim(p_note), ''), p_client_event_id
  )
  ON CONFLICT DO NOTHING
  RETURNING id INTO request_id;

  IF request_id IS NULL THEN
    SELECT * INTO existing_request
    FROM public.restaurant_shift_cover_requests
    WHERE client_event_id = p_client_event_id;
    IF existing_request.id IS NOT NULL THEN
      IF existing_request.branch_id IS DISTINCT FROM p_branch_id
        OR existing_request.shift_id IS DISTINCT FROM p_shift_id
        OR existing_request.requester_id IS DISTINCT FROM p_actor_id
        OR existing_request.note IS DISTINCT FROM nullif(trim(p_note), '') THEN
        RAISE EXCEPTION 'IDEMPOTENCY_KEY_REUSED';
      END IF;
      RETURN existing_request.id;
    END IF;
    RAISE EXCEPTION 'SHIFT_COVER_ALREADY_PENDING';
  END IF;

  INSERT INTO public.restaurant_notifications(
    branch_id, recipient_id, notification_type, title, body, entity_type, entity_id, data
  )
  SELECT p_branch_id, member.user_id, 'shift_cover_requested', 'Solicitud para cubrir un turno',
    pg_catalog.concat(
      shift_row.shift_date, ' · ', pg_catalog.to_char(shift_row.start_time, 'HH24:MI'),
      '–', pg_catalog.to_char(shift_row.end_time, 'HH24:MI')
    ), 'shift_cover_request', request_id,
    pg_catalog.jsonb_build_object(
      'request_id', request_id, 'shift_id', p_shift_id, 'shift_date', shift_row.shift_date
    )
  FROM public.restaurant_memberships AS member
  WHERE member.branch_id = p_branch_id AND member.is_active
    AND member.access_role IN ('admin', 'supervisor');

  RETURN request_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.review_restaurant_shift_cover_request(
  p_branch_id uuid,
  p_actor_id uuid,
  p_request_id uuid,
  p_decision text,
  p_replacement_employee_id uuid DEFAULT NULL,
  p_decision_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  actor_role text;
  request_row public.restaurant_shift_cover_requests%ROWTYPE;
  old_shift public.restaurant_shifts%ROWTYPE;
  replacement_role text;
  replacement_is_active boolean;
  breaks_payload jsonb;
  new_shift_id uuid;
BEGIN
  actor_role := private.restaurant_user_role(p_branch_id, p_actor_id);
  IF actor_role IS NULL OR actor_role NOT IN ('admin', 'supervisor') THEN
    RAISE EXCEPTION 'MANAGER_REQUIRED';
  END IF;
  IF p_decision IS NULL OR p_decision NOT IN ('approved', 'denied') THEN
    RAISE EXCEPTION 'INVALID_SHIFT_COVER_DECISION';
  END IF;
  IF p_decision_note IS NOT NULL AND length(trim(p_decision_note)) > 500 THEN
    RAISE EXCEPTION 'INVALID_SHIFT_COVER_NOTE';
  END IF;

  SELECT * INTO request_row
  FROM public.restaurant_shift_cover_requests
  WHERE branch_id = p_branch_id AND id = p_request_id
  FOR UPDATE;
  IF request_row.id IS NULL THEN RAISE EXCEPTION 'SHIFT_COVER_REQUEST_NOT_FOUND'; END IF;
  IF request_row.status <> 'pending' THEN RAISE EXCEPTION 'SHIFT_COVER_REQUEST_NOT_PENDING'; END IF;

  SELECT * INTO old_shift
  FROM public.restaurant_shifts
  WHERE branch_id = p_branch_id AND id = request_row.shift_id
  FOR UPDATE;
  IF old_shift.id IS NULL OR old_shift.status <> 'published'
    OR old_shift.employee_id IS DISTINCT FROM request_row.requester_id THEN
    RAISE EXCEPTION 'SHIFT_NOT_AVAILABLE';
  END IF;

  IF p_decision = 'approved' THEN
    IF p_replacement_employee_id IS NULL
      OR p_replacement_employee_id = request_row.requester_id THEN
      RAISE EXCEPTION 'INVALID_SHIFT_COVER_REPLACEMENT';
    END IF;

    SELECT member.access_role, account.is_active INTO replacement_role, replacement_is_active
    FROM public.restaurant_memberships AS member
    JOIN public.users AS account ON account.id = member.user_id
    WHERE member.branch_id = p_branch_id AND member.user_id = p_replacement_employee_id
      AND member.is_active
    FOR SHARE OF member, account;
    IF NOT FOUND OR replacement_role <> 'employee' OR NOT replacement_is_active THEN
      RAISE EXCEPTION 'EMPLOYEE_NOT_ACTIVE';
    END IF;

    IF EXISTS (
      SELECT 1 FROM public.restaurant_absences AS absence
      WHERE absence.branch_id = p_branch_id
        AND absence.employee_id = p_replacement_employee_id
        AND absence.status = 'approved'
        AND old_shift.shift_date BETWEEN absence.start_date AND absence.end_date
    ) THEN
      RAISE EXCEPTION 'EMPLOYEE_ABSENT';
    END IF;

    SELECT coalesce(
      pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object('start_time', item.start_time, 'end_time', item.end_time)
        ORDER BY item.start_time
      ), '[]'::jsonb
    ) INTO breaks_payload
    FROM public.restaurant_shift_breaks AS item
    WHERE item.branch_id = p_branch_id AND item.shift_id = old_shift.id;

    new_shift_id := public.replace_restaurant_shift(
      p_branch_id, p_actor_id, old_shift.id, p_replacement_employee_id,
      old_shift.shift_date, old_shift.start_time, old_shift.end_time,
      'published', breaks_payload
    );
  END IF;

  UPDATE public.restaurant_shift_cover_requests
  SET status = p_decision,
      decision_note = nullif(trim(p_decision_note), ''),
      replacement_employee_id = CASE WHEN p_decision = 'approved' THEN p_replacement_employee_id ELSE NULL END,
      replacement_shift_id = new_shift_id,
      reviewed_by = p_actor_id,
      reviewed_at = now()
  WHERE id = request_row.id;

  INSERT INTO public.restaurant_notifications(
    branch_id, recipient_id, notification_type, title, body, entity_type, entity_id, data
  ) VALUES (
    p_branch_id, request_row.requester_id, 'shift_cover_reviewed',
    CASE WHEN p_decision = 'approved' THEN 'Cobertura confirmada' ELSE 'Solicitud de cobertura no aprobada' END,
    CASE WHEN p_decision = 'approved'
      THEN pg_catalog.concat(
        'Tu turno del ', pg_catalog.to_char(old_shift.shift_date, 'DD/MM/YYYY'), ' · ',
        pg_catalog.to_char(old_shift.start_time, 'HH24:MI'), '–',
        pg_catalog.to_char(old_shift.end_time, 'HH24:MI'), ' fue cubierto.'
      )
      ELSE coalesce(nullif(trim(p_decision_note), ''), 'El gerente revisó tu solicitud.')
    END,
    'shift_cover_request', request_row.id,
    pg_catalog.jsonb_build_object(
      'request_id', request_row.id,
      'shift_id', request_row.shift_id,
      'replacement_shift_id', new_shift_id,
      'shift_date', old_shift.shift_date,
      'status', p_decision
    )
  );

  RETURN pg_catalog.jsonb_build_object(
    'request_id', request_row.id,
    'status', p_decision,
    'replacement_shift_id', new_shift_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.create_restaurant_shift_cover_request(uuid, uuid, uuid, uuid, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_restaurant_shift_cover_request(uuid, uuid, uuid, uuid, text)
  TO service_role;
REVOKE ALL ON FUNCTION public.review_restaurant_shift_cover_request(uuid, uuid, uuid, text, uuid, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.review_restaurant_shift_cover_request(uuid, uuid, uuid, text, uuid, text)
  TO service_role;
