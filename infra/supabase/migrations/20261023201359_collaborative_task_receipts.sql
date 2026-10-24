-- Task receipt and coworker communication are separate from task completion.
CREATE TABLE public.restaurant_task_receipts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid NOT NULL,
  task_id uuid NOT NULL,
  employee_id uuid NOT NULL,
  assignment_recorded_at timestamptz NOT NULL DEFAULT now(),
  receipt_state text NOT NULL DEFAULT 'awaiting'
    CHECK (receipt_state IN ('awaiting', 'employee_confirmed', 'peer_notified', 'unassigned')),
  confirmed_at timestamptz,
  confirmed_by uuid,
  confirmation_channel text CHECK (confirmation_channel IN ('employee', 'peer')),
  updated_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (branch_id, task_id)
    REFERENCES public.restaurant_tasks(branch_id, id) ON DELETE CASCADE,
  FOREIGN KEY (branch_id, employee_id)
    REFERENCES public.restaurant_memberships(branch_id, user_id) ON DELETE CASCADE,
  FOREIGN KEY (branch_id, confirmed_by)
    REFERENCES public.restaurant_memberships(branch_id, user_id) ON DELETE SET NULL (confirmed_by),
  UNIQUE (branch_id, task_id)
);
CREATE INDEX restaurant_task_receipts_employee_idx
  ON public.restaurant_task_receipts(branch_id, employee_id, receipt_state, assignment_recorded_at DESC);
ALTER TABLE public.restaurant_task_receipts ENABLE ROW LEVEL SECURITY;
CREATE POLICY restaurant_task_receipts_member_read ON public.restaurant_task_receipts
  FOR SELECT TO authenticated USING (private.restaurant_has_access(branch_id));
REVOKE ALL ON public.restaurant_task_receipts FROM anon, authenticated;
GRANT SELECT ON public.restaurant_task_receipts TO authenticated;
GRANT ALL ON public.restaurant_task_receipts TO service_role;

CREATE TABLE public.restaurant_task_receipt_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid NOT NULL,
  receipt_id uuid NOT NULL REFERENCES public.restaurant_task_receipts(id) ON DELETE CASCADE,
  actor_id uuid,
  event_type text NOT NULL CHECK (event_type IN ('assigned', 'employee_confirmed', 'peer_notified', 'unassigned')),
  occurred_at timestamptz NOT NULL DEFAULT now(),
  details jsonb NOT NULL DEFAULT '{}'::jsonb,
  FOREIGN KEY (branch_id, actor_id)
    REFERENCES public.restaurant_memberships(branch_id, user_id) ON DELETE RESTRICT
);
ALTER TABLE public.restaurant_task_receipt_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY restaurant_task_receipt_events_member_read ON public.restaurant_task_receipt_events
  FOR SELECT TO authenticated USING (private.restaurant_has_access(branch_id));
REVOKE ALL ON public.restaurant_task_receipt_events FROM anon, authenticated;
GRANT SELECT ON public.restaurant_task_receipt_events TO authenticated;
GRANT ALL ON public.restaurant_task_receipt_events TO service_role;

CREATE TABLE public.restaurant_collaboration_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid NOT NULL,
  task_id uuid NOT NULL,
  target_employee_id uuid NOT NULL,
  created_by uuid NOT NULL,
  client_event_id uuid NOT NULL,
  status text NOT NULL DEFAULT 'open'
    CHECK (status IN ('open', 'claimed', 'resolved', 'cancelled')),
  claimed_by uuid,
  claimed_until timestamptz,
  resolution text CHECK (resolution IN ('peer_notified', 'not_located')),
  resolved_by uuid,
  resolved_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (branch_id, task_id)
    REFERENCES public.restaurant_tasks(branch_id, id) ON DELETE CASCADE,
  FOREIGN KEY (branch_id, target_employee_id)
    REFERENCES public.restaurant_memberships(branch_id, user_id) ON DELETE CASCADE,
  FOREIGN KEY (branch_id, created_by)
    REFERENCES public.restaurant_memberships(branch_id, user_id) ON DELETE CASCADE,
  FOREIGN KEY (branch_id, claimed_by)
    REFERENCES public.restaurant_memberships(branch_id, user_id) ON DELETE SET NULL (claimed_by),
  FOREIGN KEY (branch_id, resolved_by)
    REFERENCES public.restaurant_memberships(branch_id, user_id) ON DELETE SET NULL (resolved_by),
  UNIQUE (branch_id, id),
  UNIQUE (branch_id, client_event_id),
  CHECK ((status = 'claimed') = (claimed_by IS NOT NULL AND claimed_until IS NOT NULL)),
  CHECK ((status = 'resolved') = (resolution IS NOT NULL AND resolved_by IS NOT NULL AND resolved_at IS NOT NULL))
);
CREATE UNIQUE INDEX restaurant_collaboration_one_active_request
  ON public.restaurant_collaboration_requests(branch_id, task_id)
  WHERE status IN ('open', 'claimed');
CREATE INDEX restaurant_collaboration_inbox_idx
  ON public.restaurant_collaboration_requests(branch_id, status, created_at DESC);
ALTER TABLE public.restaurant_collaboration_requests ENABLE ROW LEVEL SECURITY;
CREATE POLICY restaurant_collaboration_requests_member_read ON public.restaurant_collaboration_requests
  FOR SELECT TO authenticated USING (private.restaurant_has_access(branch_id));
REVOKE ALL ON public.restaurant_collaboration_requests FROM anon, authenticated;
GRANT SELECT ON public.restaurant_collaboration_requests TO authenticated;
GRANT ALL ON public.restaurant_collaboration_requests TO service_role;

CREATE TABLE public.restaurant_collaboration_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid NOT NULL,
  request_id uuid NOT NULL,
  actor_id uuid NOT NULL,
  event_type text NOT NULL CHECK (event_type IN ('requested', 'claimed', 'claim_released', 'peer_notified', 'not_located', 'cancelled')),
  occurred_at timestamptz NOT NULL DEFAULT now(),
  details jsonb NOT NULL DEFAULT '{}'::jsonb,
  FOREIGN KEY (branch_id, request_id)
    REFERENCES public.restaurant_collaboration_requests(branch_id, id) ON DELETE CASCADE,
  FOREIGN KEY (branch_id, actor_id)
    REFERENCES public.restaurant_memberships(branch_id, user_id) ON DELETE RESTRICT
);
ALTER TABLE public.restaurant_collaboration_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY restaurant_collaboration_events_member_read ON public.restaurant_collaboration_events
  FOR SELECT TO authenticated USING (private.restaurant_has_access(branch_id));
REVOKE ALL ON public.restaurant_collaboration_events FROM anon, authenticated;
GRANT SELECT ON public.restaurant_collaboration_events TO authenticated;
GRANT ALL ON public.restaurant_collaboration_events TO service_role;

CREATE OR REPLACE FUNCTION private.reject_collaboration_event_mutation()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
  IF TG_OP = 'DELETE' AND pg_catalog.pg_trigger_depth() > 1 THEN
    RETURN OLD;
  END IF;
  RAISE EXCEPTION 'COLLABORATION_EVENTS_APPEND_ONLY';
END;
$$;
REVOKE ALL ON FUNCTION private.reject_collaboration_event_mutation() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER restaurant_collaboration_events_append_only
  BEFORE UPDATE OR DELETE ON public.restaurant_collaboration_events
  FOR EACH ROW EXECUTE FUNCTION private.reject_collaboration_event_mutation();
CREATE TRIGGER restaurant_task_receipt_events_append_only
  BEFORE UPDATE OR DELETE ON public.restaurant_task_receipt_events
  FOR EACH ROW EXECUTE FUNCTION private.reject_collaboration_event_mutation();

CREATE OR REPLACE FUNCTION private.track_restaurant_task_assignment()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF TG_OP = 'INSERT' OR NEW.assigned_to IS DISTINCT FROM OLD.assigned_to THEN
    INSERT INTO public.restaurant_task_receipts(branch_id, task_id, employee_id, receipt_state,
      assignment_recorded_at, confirmed_at, confirmed_by, confirmation_channel, updated_at)
    SELECT NEW.branch_id, NEW.id, NEW.assigned_to,
      CASE WHEN NEW.assigned_to IS NULL THEN 'unassigned' ELSE 'awaiting' END,
      now(), NULL, NULL, NULL, now()
    WHERE NEW.assigned_to IS NOT NULL
    ON CONFLICT (branch_id, task_id) DO UPDATE SET employee_id = EXCLUDED.employee_id,
      receipt_state = EXCLUDED.receipt_state, assignment_recorded_at = now(),
      confirmed_at = NULL, confirmed_by = NULL, confirmation_channel = NULL, updated_at = now();
    INSERT INTO public.restaurant_task_receipt_events(branch_id, receipt_id, actor_id, event_type, details)
    SELECT NEW.branch_id, r.id, NULL, 'assigned',
      pg_catalog.jsonb_build_object('employee_id', NEW.assigned_to)
    FROM public.restaurant_task_receipts r
    WHERE NEW.assigned_to IS NOT NULL AND r.branch_id = NEW.branch_id AND r.task_id = NEW.id;
    IF TG_OP = 'UPDATE' AND NEW.assigned_to IS NULL THEN
      UPDATE public.restaurant_task_receipts SET employee_id = OLD.assigned_to,
        receipt_state = 'unassigned', updated_at = now()
      WHERE branch_id = NEW.branch_id AND task_id = NEW.id;
      INSERT INTO public.restaurant_task_receipt_events(branch_id, receipt_id, actor_id, event_type, details)
      SELECT NEW.branch_id, r.id, NULL, 'unassigned',
        pg_catalog.jsonb_build_object('employee_id', OLD.assigned_to)
      FROM public.restaurant_task_receipts r
      WHERE r.branch_id = NEW.branch_id AND r.task_id = NEW.id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION private.track_restaurant_task_assignment() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER restaurant_task_assignment_receipt
  AFTER INSERT OR UPDATE OF assigned_to ON public.restaurant_tasks
  FOR EACH ROW EXECUTE FUNCTION private.track_restaurant_task_assignment();

CREATE OR REPLACE FUNCTION private.confirm_task_receipt_on_start()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE receipt_id uuid;
BEGIN
  IF NEW.event_type <> 'start' OR NEW.part_id IS NOT NULL THEN RETURN NEW; END IF;
  UPDATE public.restaurant_task_receipts SET receipt_state = 'employee_confirmed', confirmed_at = NEW.occurred_at,
    confirmed_by = NEW.actor_id, confirmation_channel = 'employee', updated_at = now()
    WHERE branch_id = NEW.branch_id AND task_id = NEW.task_id AND employee_id = NEW.actor_id
      AND receipt_state = 'awaiting'
    RETURNING id INTO receipt_id;
  IF receipt_id IS NOT NULL THEN
    INSERT INTO public.restaurant_task_receipt_events(branch_id, receipt_id, actor_id, event_type, details)
      VALUES (NEW.branch_id, receipt_id, NEW.actor_id, 'employee_confirmed',
        pg_catalog.jsonb_build_object('source', 'task_start', 'task_event_id', NEW.id));
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION private.confirm_task_receipt_on_start() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER restaurant_task_started_confirms_receipt
  AFTER INSERT ON public.restaurant_task_events
  FOR EACH ROW EXECUTE FUNCTION private.confirm_task_receipt_on_start();

ALTER TABLE public.restaurant_notifications
  DROP CONSTRAINT restaurant_notifications_notification_type_check;
ALTER TABLE public.restaurant_notifications
  ADD CONSTRAINT restaurant_notifications_notification_type_check CHECK (
    notification_type IN (
      'task_assigned', 'task_part_assigned', 'incident_assigned', 'incident_reported',
      'shift_handoff_received', 'shift_handoff_acknowledged',
      'shift_published', 'shift_updated', 'shift_removed',
      'absence_requested', 'absence_reviewed', 'inspection_attention',
      'shift_cover_requested', 'shift_cover_reviewed', 'collaboration_requested'
    )
  );
ALTER TABLE public.restaurant_notifications
  DROP CONSTRAINT restaurant_notifications_entity_type_check;
ALTER TABLE public.restaurant_notifications
  ADD CONSTRAINT restaurant_notifications_entity_type_check
  CHECK (entity_type IN ('task', 'incident', 'handoff', 'shift', 'absence', 'inspection',
    'shift_cover_request', 'collaboration_request'));

CREATE OR REPLACE FUNCTION public.create_restaurant_collaboration_request(
  p_branch_id uuid, p_task_id uuid, p_actor_id uuid, p_client_event_id uuid
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE task_row public.restaurant_tasks%ROWTYPE; request_id uuid; existing public.restaurant_collaboration_requests%ROWTYPE;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.restaurant_memberships m
    WHERE m.branch_id = p_branch_id AND m.user_id = p_actor_id AND m.is_active) THEN
    RAISE EXCEPTION 'BRANCH_ACCESS_REQUIRED';
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(p_branch_id::text || p_task_id::text, 0));
  SELECT * INTO existing FROM public.restaurant_collaboration_requests
    WHERE branch_id = p_branch_id AND client_event_id = p_client_event_id;
  IF FOUND THEN
    IF existing.task_id <> p_task_id OR existing.created_by <> p_actor_id THEN RAISE EXCEPTION 'IDEMPOTENCY_KEY_REUSED'; END IF;
    RETURN existing.id;
  END IF;
  SELECT * INTO task_row FROM public.restaurant_tasks
    WHERE branch_id = p_branch_id AND id = p_task_id FOR UPDATE;
  IF NOT FOUND OR task_row.assigned_to IS NULL THEN RAISE EXCEPTION 'TASK_NOT_ASSIGNED'; END IF;
  IF task_row.status = 'completed' THEN RAISE EXCEPTION 'TASK_ALREADY_COMPLETED'; END IF;
  WITH stale AS (
    UPDATE public.restaurant_collaboration_requests SET status = 'cancelled',
      claimed_by = NULL, claimed_until = NULL, resolution = NULL, resolved_by = NULL, resolved_at = NULL
    WHERE branch_id = p_branch_id AND task_id = p_task_id AND status IN ('open', 'claimed')
      AND target_employee_id <> task_row.assigned_to
    RETURNING id
  )
  INSERT INTO public.restaurant_collaboration_events(branch_id, request_id, actor_id, event_type, details)
  SELECT p_branch_id, stale.id, p_actor_id, 'cancelled',
    pg_catalog.jsonb_build_object('reason', 'task_reassigned') FROM stale;
  IF NOT EXISTS (SELECT 1 FROM public.restaurant_task_receipts r
    WHERE r.branch_id = p_branch_id AND r.task_id = p_task_id AND r.employee_id = task_row.assigned_to
      AND r.receipt_state = 'awaiting') THEN RAISE EXCEPTION 'TASK_RECEIPT_NOT_AWAITING'; END IF;
  INSERT INTO public.restaurant_collaboration_requests(branch_id, task_id, target_employee_id, created_by, client_event_id)
    VALUES (p_branch_id, p_task_id, task_row.assigned_to, p_actor_id, p_client_event_id)
    ON CONFLICT (branch_id, task_id) WHERE status IN ('open', 'claimed') DO NOTHING
    RETURNING id INTO request_id;
  IF request_id IS NULL THEN
    SELECT id INTO request_id FROM public.restaurant_collaboration_requests
      WHERE branch_id = p_branch_id AND task_id = p_task_id AND status IN ('open', 'claimed');
    RETURN request_id;
  END IF;
  INSERT INTO public.restaurant_collaboration_events(branch_id, request_id, actor_id, event_type)
    VALUES (p_branch_id, request_id, p_actor_id, 'requested');
  INSERT INTO public.restaurant_notifications(branch_id, recipient_id, notification_type, title, body,
    entity_type, entity_id, data)
  SELECT p_branch_id, m.user_id, 'collaboration_requested', 'Aviso colaborativo',
    '¿Puedes avisarle personalmente a un compañero sobre una tarea pendiente?',
    'collaboration_request', request_id,
    pg_catalog.jsonb_build_object('request_id', request_id, 'task_id', p_task_id)
  FROM public.restaurant_memberships m
  JOIN public.restaurant_branches b ON b.id = m.branch_id
  WHERE m.branch_id = p_branch_id AND m.is_active AND m.user_id <> task_row.assigned_to
    AND m.user_id <> p_actor_id
    AND EXISTS (
      SELECT 1 FROM public.restaurant_shifts s
      WHERE s.branch_id = m.branch_id AND s.employee_id = m.user_id AND s.status = 'published'
        AND (
          (s.shift_date = (now() AT TIME ZONE b.timezone)::date AND s.start_time < s.end_time
            AND (now() AT TIME ZONE b.timezone)::time >= s.start_time AND (now() AT TIME ZONE b.timezone)::time < s.end_time)
          OR (s.shift_date = (now() AT TIME ZONE b.timezone)::date AND s.start_time > s.end_time
            AND (now() AT TIME ZONE b.timezone)::time >= s.start_time)
          OR (s.shift_date = (now() AT TIME ZONE b.timezone)::date - 1 AND s.start_time > s.end_time
            AND (now() AT TIME ZONE b.timezone)::time < s.end_time)
        )
        AND NOT EXISTS (
          SELECT 1 FROM public.restaurant_shift_breaks br
          WHERE br.branch_id = s.branch_id AND br.shift_id = s.id
            AND ((br.start_time < br.end_time AND (now() AT TIME ZONE b.timezone)::time >= br.start_time AND (now() AT TIME ZONE b.timezone)::time < br.end_time)
              OR (br.start_time > br.end_time AND ((now() AT TIME ZONE b.timezone)::time >= br.start_time OR (now() AT TIME ZONE b.timezone)::time < br.end_time)))
        )
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.restaurant_absences a
      WHERE a.branch_id = m.branch_id AND a.employee_id = m.user_id AND a.status = 'approved'
        AND a.start_date <= (now() AT TIME ZONE b.timezone)::date
        AND a.end_date >= (now() AT TIME ZONE b.timezone)::date
    );
  RETURN request_id;
END;
$$;

CREATE OR REPLACE FUNCTION private.restaurant_member_scheduled_available_now(
  p_branch_id uuid, p_employee_id uuid
) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.restaurant_memberships m
    JOIN public.restaurant_branches b ON b.id = m.branch_id
    JOIN public.restaurant_shifts s ON s.branch_id = m.branch_id AND s.employee_id = m.user_id
    WHERE m.branch_id = p_branch_id AND m.user_id = p_employee_id AND m.is_active AND s.status = 'published'
      AND (
        (s.shift_date = (now() AT TIME ZONE b.timezone)::date AND s.start_time < s.end_time
          AND (now() AT TIME ZONE b.timezone)::time >= s.start_time AND (now() AT TIME ZONE b.timezone)::time < s.end_time)
        OR (s.shift_date = (now() AT TIME ZONE b.timezone)::date AND s.start_time > s.end_time
          AND (now() AT TIME ZONE b.timezone)::time >= s.start_time)
        OR (s.shift_date = (now() AT TIME ZONE b.timezone)::date - 1 AND s.start_time > s.end_time
          AND (now() AT TIME ZONE b.timezone)::time < s.end_time)
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.restaurant_shift_breaks br
        WHERE br.branch_id = s.branch_id AND br.shift_id = s.id
          AND ((br.start_time < br.end_time AND (now() AT TIME ZONE b.timezone)::time >= br.start_time AND (now() AT TIME ZONE b.timezone)::time < br.end_time)
            OR (br.start_time > br.end_time AND ((now() AT TIME ZONE b.timezone)::time >= br.start_time OR (now() AT TIME ZONE b.timezone)::time < br.end_time)))
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.restaurant_absences a WHERE a.branch_id = m.branch_id
          AND a.employee_id = m.user_id AND a.status = 'approved'
          AND a.start_date <= (now() AT TIME ZONE b.timezone)::date
          AND a.end_date >= (now() AT TIME ZONE b.timezone)::date
      )
  );
$$;
REVOKE ALL ON FUNCTION private.restaurant_member_scheduled_available_now(uuid, uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.claim_restaurant_collaboration_request(
  p_branch_id uuid, p_request_id uuid, p_actor_id uuid, p_reservation_seconds integer
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE request_row public.restaurant_collaboration_requests%ROWTYPE;
  task_assignee uuid; task_status text;
BEGIN
  IF p_reservation_seconds < 30 OR p_reservation_seconds > 3600 THEN RAISE EXCEPTION 'INVALID_RESERVATION'; END IF;
  IF NOT private.restaurant_member_scheduled_available_now(p_branch_id, p_actor_id) THEN
    RAISE EXCEPTION 'COLLABORATOR_NOT_AVAILABLE';
  END IF;
  SELECT * INTO request_row FROM public.restaurant_collaboration_requests
    WHERE branch_id = p_branch_id AND id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'COLLABORATION_REQUEST_NOT_FOUND'; END IF;
  SELECT assigned_to, status INTO task_assignee, task_status FROM public.restaurant_tasks
    WHERE branch_id = p_branch_id AND id = request_row.task_id;
  IF task_assignee IS DISTINCT FROM request_row.target_employee_id OR task_status = 'completed' THEN
    UPDATE public.restaurant_collaboration_requests SET status = 'cancelled', claimed_by = NULL,
      claimed_until = NULL, resolution = NULL, resolved_by = NULL, resolved_at = NULL
      WHERE id = p_request_id;
    INSERT INTO public.restaurant_collaboration_events(branch_id, request_id, actor_id, event_type,
      details) VALUES (p_branch_id, p_request_id, p_actor_id, 'cancelled',
        pg_catalog.jsonb_build_object('reason', 'task_no_longer_matches_request'));
    RETURN pg_catalog.jsonb_build_object('claimed', false, 'cancelled', true);
  END IF;
  IF request_row.target_employee_id = p_actor_id THEN RAISE EXCEPTION 'TARGET_CANNOT_CLAIM_NOTICE'; END IF;
  IF request_row.status = 'claimed' AND request_row.claimed_until <= now() THEN
    INSERT INTO public.restaurant_collaboration_events(branch_id, request_id, actor_id, event_type)
      VALUES (p_branch_id, p_request_id, p_actor_id, 'claim_released');
    UPDATE public.restaurant_collaboration_requests SET status = 'open', claimed_by = NULL, claimed_until = NULL
      WHERE id = p_request_id;
    request_row.status := 'open';
  END IF;
  IF request_row.status = 'claimed' AND request_row.claimed_by = p_actor_id THEN
    RETURN pg_catalog.jsonb_build_object('claimed', true, 'duplicate', true, 'claimed_until', request_row.claimed_until);
  END IF;
  IF request_row.status <> 'open' THEN RAISE EXCEPTION 'COLLABORATION_REQUEST_NOT_OPEN'; END IF;
  UPDATE public.restaurant_collaboration_requests SET status = 'claimed', claimed_by = p_actor_id,
    claimed_until = now() + pg_catalog.make_interval(secs => p_reservation_seconds)
    WHERE id = p_request_id RETURNING * INTO request_row;
  INSERT INTO public.restaurant_collaboration_events(branch_id, request_id, actor_id, event_type, details)
    VALUES (p_branch_id, p_request_id, p_actor_id, 'claimed',
      pg_catalog.jsonb_build_object('claimed_until', request_row.claimed_until));
  RETURN pg_catalog.jsonb_build_object('claimed', true, 'duplicate', false, 'claimed_until', request_row.claimed_until);
END;
$$;

CREATE OR REPLACE FUNCTION public.confirm_restaurant_task_receipt(
  p_branch_id uuid, p_task_id uuid, p_actor_id uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE receipt_row public.restaurant_task_receipts%ROWTYPE;
BEGIN
  SELECT * INTO receipt_row FROM public.restaurant_task_receipts
    WHERE branch_id = p_branch_id AND task_id = p_task_id AND employee_id = p_actor_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'TASK_RECEIPT_NOT_FOUND'; END IF;
  IF receipt_row.receipt_state = 'employee_confirmed' THEN
    RETURN pg_catalog.jsonb_build_object('confirmed', true, 'duplicate', true, 'task_completed', false);
  END IF;
  IF receipt_row.receipt_state <> 'awaiting' THEN RAISE EXCEPTION 'TASK_RECEIPT_NOT_AWAITING'; END IF;
  UPDATE public.restaurant_task_receipts SET receipt_state = 'employee_confirmed', confirmed_at = now(),
    confirmed_by = p_actor_id, confirmation_channel = 'employee', updated_at = now()
    WHERE id = receipt_row.id;
  INSERT INTO public.restaurant_task_receipt_events(branch_id, receipt_id, actor_id, event_type)
    VALUES (p_branch_id, receipt_row.id, p_actor_id, 'employee_confirmed');
  RETURN pg_catalog.jsonb_build_object('confirmed', true, 'duplicate', false, 'task_completed', false);
END;
$$;

CREATE OR REPLACE FUNCTION public.resolve_restaurant_collaboration_request(
  p_branch_id uuid, p_request_id uuid, p_actor_id uuid, p_resolution text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE request_row public.restaurant_collaboration_requests%ROWTYPE; receipt_id uuid;
BEGIN
  IF p_resolution NOT IN ('peer_notified', 'not_located') THEN RAISE EXCEPTION 'INVALID_COLLABORATION_RESOLUTION'; END IF;
  SELECT * INTO request_row FROM public.restaurant_collaboration_requests
    WHERE branch_id = p_branch_id AND id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'COLLABORATION_REQUEST_NOT_FOUND'; END IF;
  IF request_row.status <> 'claimed' OR request_row.claimed_by <> p_actor_id OR request_row.claimed_until <= now() THEN
    RAISE EXCEPTION 'COLLABORATION_CLAIM_EXPIRED';
  END IF;
  IF p_resolution = 'peer_notified' THEN
    UPDATE public.restaurant_collaboration_requests SET status = 'resolved', resolution = p_resolution,
      resolved_by = p_actor_id, resolved_at = now(), claimed_by = NULL, claimed_until = NULL
      WHERE id = p_request_id;
    UPDATE public.restaurant_task_receipts SET receipt_state = 'peer_notified', confirmed_at = now(),
      confirmed_by = p_actor_id, confirmation_channel = 'peer', updated_at = now()
      WHERE branch_id = p_branch_id AND task_id = request_row.task_id
        AND employee_id = request_row.target_employee_id AND receipt_state = 'awaiting'
      RETURNING id INTO receipt_id;
    IF receipt_id IS NULL THEN RAISE EXCEPTION 'TASK_RECEIPT_NOT_AWAITING'; END IF;
    INSERT INTO public.restaurant_task_receipt_events(branch_id, receipt_id, actor_id, event_type, details)
      VALUES (p_branch_id, receipt_id, p_actor_id, 'peer_notified',
        pg_catalog.jsonb_build_object('request_id', p_request_id,
          'target_employee_id', request_row.target_employee_id));
  ELSE
    UPDATE public.restaurant_collaboration_requests SET status = 'open', resolution = p_resolution,
      resolved_by = NULL, resolved_at = NULL, claimed_by = NULL, claimed_until = NULL
      WHERE id = p_request_id;
  END IF;
  INSERT INTO public.restaurant_collaboration_events(branch_id, request_id, actor_id, event_type)
    VALUES (p_branch_id, p_request_id, p_actor_id, p_resolution);
  RETURN pg_catalog.jsonb_build_object('resolution', p_resolution,
    'task_completed', false, 'request_status', CASE WHEN p_resolution = 'peer_notified' THEN 'resolved' ELSE 'open' END);
END;
$$;

REVOKE ALL ON FUNCTION public.create_restaurant_collaboration_request(uuid, uuid, uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.claim_restaurant_collaboration_request(uuid, uuid, uuid, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.resolve_restaurant_collaboration_request(uuid, uuid, uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.confirm_restaurant_task_receipt(uuid, uuid, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_restaurant_collaboration_request(uuid, uuid, uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.claim_restaurant_collaboration_request(uuid, uuid, uuid, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.resolve_restaurant_collaboration_request(uuid, uuid, uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.confirm_restaurant_task_receipt(uuid, uuid, uuid) TO service_role;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_publication WHERE pubname = 'supabase_realtime') THEN
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'restaurant_task_receipts') THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.restaurant_task_receipts;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'restaurant_task_receipt_events') THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.restaurant_task_receipt_events;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_publication_tables WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'restaurant_collaboration_requests') THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.restaurant_collaboration_requests;
    END IF;
  END IF;
END;
$$;
