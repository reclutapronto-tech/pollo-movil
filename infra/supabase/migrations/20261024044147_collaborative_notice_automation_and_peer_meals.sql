-- Automate receipt follow-up with the branch-configured deadlines already
-- exposed in the operational settings UI. A blank policy means no automation.
ALTER TABLE public.restaurant_branches
  ADD COLUMN collaboration_manager_escalation_seconds integer,
  ADD CONSTRAINT restaurant_branches_manager_escalation_seconds_valid
    CHECK (collaboration_manager_escalation_seconds IS NULL
      OR collaboration_manager_escalation_seconds BETWEEN 30 AND 604800);

ALTER TABLE public.restaurant_task_receipts
  ADD COLUMN IF NOT EXISTS escalation_processed_at timestamptz;

CREATE INDEX restaurant_task_receipts_due_idx
  ON public.restaurant_task_receipts(assignment_recorded_at, branch_id, task_id)
  WHERE receipt_state = 'awaiting';

CREATE OR REPLACE FUNCTION private.reset_receipt_escalation_on_reassignment()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
  IF NEW.assignment_recorded_at IS DISTINCT FROM OLD.assignment_recorded_at THEN
    NEW.escalation_processed_at := NULL;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION private.reset_receipt_escalation_on_reassignment() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER restaurant_receipt_reset_escalation_on_reassignment
  BEFORE UPDATE OF assignment_recorded_at ON public.restaurant_task_receipts
  FOR EACH ROW EXECUTE FUNCTION private.reset_receipt_escalation_on_reassignment();

ALTER TABLE public.restaurant_collaboration_requests
  ALTER COLUMN created_by DROP NOT NULL,
  ADD COLUMN request_source text NOT NULL DEFAULT 'manager_manual'
    CHECK (request_source IN ('manager_manual', 'receipt_timeout')),
  ADD COLUMN manager_escalated_at timestamptz,
  ADD CONSTRAINT restaurant_collaboration_request_source_actor_check
    CHECK ((request_source = 'receipt_timeout') = (created_by IS NULL));

ALTER TABLE public.restaurant_collaboration_events
  ALTER COLUMN actor_id DROP NOT NULL,
  DROP CONSTRAINT restaurant_collaboration_events_event_type_check,
  ADD CONSTRAINT restaurant_collaboration_events_event_type_check CHECK (
    event_type IN ('requested', 'receipt_deadline_triggered', 'claimed', 'claim_released',
      'peer_notified', 'not_located', 'cancelled', 'manager_escalated')
  );

ALTER TABLE public.restaurant_notifications
  DROP CONSTRAINT restaurant_notifications_notification_type_check,
  ADD CONSTRAINT restaurant_notifications_notification_type_check CHECK (
    notification_type IN (
      'task_assigned', 'task_part_assigned', 'incident_assigned', 'incident_reported',
      'shift_handoff_received', 'shift_handoff_acknowledged',
      'shift_published', 'shift_updated', 'shift_removed',
      'absence_requested', 'absence_reviewed', 'inspection_attention',
      'shift_cover_requested', 'shift_cover_reviewed', 'collaboration_requested',
      'collaboration_escalated'
    )
  );
ALTER TABLE public.restaurant_notifications
  DROP CONSTRAINT restaurant_notifications_entity_type_check,
  ADD CONSTRAINT restaurant_notifications_entity_type_check
    CHECK (entity_type IN ('task', 'incident', 'handoff', 'shift', 'absence', 'inspection',
      'shift_cover_request', 'collaboration_request', 'collaboration_escalation'));

-- The peer roster excludes every worker who cannot take a collaborative
-- request: occupied, meal/rest, off shift, absent, on a scheduled break, or
-- without an active published shift.
CREATE OR REPLACE FUNCTION private.restaurant_member_scheduled_available_now(
  p_branch_id uuid, p_employee_id uuid
) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.restaurant_memberships m
    JOIN public.restaurant_branches b ON b.id = m.branch_id
    JOIN public.restaurant_shifts s ON s.branch_id = m.branch_id AND s.employee_id = m.user_id
    WHERE m.branch_id = p_branch_id AND m.user_id = p_employee_id AND m.is_active
      AND s.status = 'published'
      AND (
        (s.shift_date = (now() AT TIME ZONE b.timezone)::date AND s.start_time < s.end_time
          AND (now() AT TIME ZONE b.timezone)::time >= s.start_time AND (now() AT TIME ZONE b.timezone)::time < s.end_time)
        OR (s.shift_date = (now() AT TIME ZONE b.timezone)::date AND s.start_time > s.end_time
          AND (now() AT TIME ZONE b.timezone)::time >= s.start_time)
        OR (s.shift_date = (now() AT TIME ZONE b.timezone)::date - 1 AND s.start_time > s.end_time
          AND (now() AT TIME ZONE b.timezone)::time < s.end_time)
      )
      AND NOT EXISTS (SELECT 1 FROM public.restaurant_shift_breaks br
        WHERE br.branch_id = s.branch_id AND br.shift_id = s.id
          AND ((br.start_time < br.end_time AND (now() AT TIME ZONE b.timezone)::time >= br.start_time AND (now() AT TIME ZONE b.timezone)::time < br.end_time)
            OR (br.start_time > br.end_time AND ((now() AT TIME ZONE b.timezone)::time >= br.start_time OR (now() AT TIME ZONE b.timezone)::time < br.end_time))))
      AND NOT EXISTS (SELECT 1 FROM public.restaurant_absences a
        WHERE a.branch_id = m.branch_id AND a.employee_id = m.user_id AND a.status = 'approved'
          AND a.start_date <= (now() AT TIME ZONE b.timezone)::date
          AND a.end_date >= (now() AT TIME ZONE b.timezone)::date)
      AND NOT EXISTS (SELECT 1 FROM public.restaurant_member_operational_states os
        WHERE os.branch_id = m.branch_id AND os.employee_id = m.user_id
          AND os.state IN ('occupied', 'meal', 'rest', 'off_shift'))
      AND NOT EXISTS (SELECT 1 FROM public.restaurant_meal_sessions ms
        WHERE ms.branch_id = m.branch_id AND ms.employee_id = m.user_id
          AND ms.return_confirmed_at IS NULL)
  );
$$;
REVOKE ALL ON FUNCTION private.restaurant_member_scheduled_available_now(uuid, uuid)
  FROM PUBLIC, anon, authenticated;

-- Realtime meal changes are visible only to the employee, branch management,
-- or a currently available coworker on a published shift at that branch.
CREATE OR REPLACE FUNCTION private.restaurant_current_user_can_view_peer_meal(
  p_branch_id uuid, p_employee_id uuid
) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT private.restaurant_has_access(p_branch_id)
    AND (auth.uid() = p_employee_id
      OR private.restaurant_current_user_is_branch_manager(p_branch_id)
      OR (private.restaurant_current_user_scheduled_available_now(p_branch_id)
        AND private.restaurant_member_on_shift_now(p_branch_id, p_employee_id)));
$$;
REVOKE ALL ON FUNCTION private.restaurant_current_user_can_view_peer_meal(uuid, uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.restaurant_current_user_can_view_peer_meal(uuid, uuid)
  TO authenticated;

DROP POLICY restaurant_meal_sessions_branch_read ON public.restaurant_meal_sessions;
CREATE POLICY restaurant_meal_sessions_branch_read ON public.restaurant_meal_sessions
  FOR SELECT TO authenticated USING (
    private.restaurant_current_user_can_view_peer_meal(branch_id, employee_id));
DROP POLICY restaurant_meal_events_branch_read ON public.restaurant_meal_events;
CREATE POLICY restaurant_meal_events_branch_read ON public.restaurant_meal_events
  FOR SELECT TO authenticated USING (
    EXISTS (SELECT 1 FROM public.restaurant_meal_sessions ms
      WHERE ms.branch_id = restaurant_meal_events.branch_id
        AND ms.id = restaurant_meal_events.meal_session_id
        AND private.restaurant_current_user_can_view_peer_meal(ms.branch_id, ms.employee_id)));

DROP POLICY restaurant_collaboration_requests_member_read ON public.restaurant_collaboration_requests;
CREATE POLICY restaurant_collaboration_requests_member_read ON public.restaurant_collaboration_requests
  FOR SELECT TO authenticated USING (private.restaurant_has_access(branch_id)
    AND (status IN ('resolved', 'cancelled')
      OR private.restaurant_current_user_is_branch_manager(branch_id)
      OR private.restaurant_current_user_scheduled_available_now(branch_id)));

CREATE OR REPLACE FUNCTION private.open_restaurant_collaboration_request(
  p_branch_id uuid, p_task_id uuid, p_actor_id uuid,
  p_client_event_id uuid, p_request_source text
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  task_row public.restaurant_tasks%ROWTYPE;
  existing public.restaurant_collaboration_requests%ROWTYPE;
  request_id uuid;
  event_type text;
BEGIN
  IF p_request_source NOT IN ('manager_manual', 'receipt_timeout')
      OR (p_request_source = 'receipt_timeout' AND p_actor_id IS NOT NULL)
      OR (p_request_source = 'manager_manual' AND p_actor_id IS NULL) THEN
    RAISE EXCEPTION 'INVALID_COLLABORATION_REQUEST_SOURCE';
  END IF;
  IF p_actor_id IS NOT NULL AND NOT private.restaurant_is_branch_manager(p_branch_id, p_actor_id) THEN
    RAISE EXCEPTION 'MANAGER_REQUIRED';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_branch_id::text || p_task_id::text, 0));
  SELECT * INTO existing FROM public.restaurant_collaboration_requests
    WHERE branch_id = p_branch_id AND client_event_id = p_client_event_id;
  IF FOUND THEN
    IF existing.task_id <> p_task_id
       OR existing.created_by IS DISTINCT FROM p_actor_id
       OR existing.request_source <> p_request_source THEN
      RAISE EXCEPTION 'IDEMPOTENCY_KEY_REUSED';
    END IF;
    RETURN existing.id;
  END IF;

  SELECT * INTO task_row FROM public.restaurant_tasks
    WHERE branch_id = p_branch_id AND id = p_task_id FOR UPDATE;
  IF NOT FOUND OR task_row.assigned_to IS NULL THEN RAISE EXCEPTION 'TASK_NOT_ASSIGNED'; END IF;
  IF task_row.status = 'completed' THEN RAISE EXCEPTION 'TASK_ALREADY_COMPLETED'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.restaurant_task_receipts r
    WHERE r.branch_id = p_branch_id AND r.task_id = p_task_id
      AND r.employee_id = task_row.assigned_to AND r.receipt_state = 'awaiting') THEN
    RAISE EXCEPTION 'TASK_RECEIPT_NOT_AWAITING';
  END IF;

  -- A prior manual request satisfies the automatic trigger too; the partial
  -- unique index remains the final concurrency guard for all callers.
  SELECT id INTO request_id FROM public.restaurant_collaboration_requests
    WHERE branch_id = p_branch_id AND task_id = p_task_id AND status IN ('open', 'claimed');
  IF request_id IS NOT NULL THEN RETURN request_id; END IF;

  INSERT INTO public.restaurant_collaboration_requests(
    branch_id, task_id, target_employee_id, created_by, client_event_id, request_source
  ) VALUES (
    p_branch_id, p_task_id, task_row.assigned_to, p_actor_id, p_client_event_id, p_request_source
  ) ON CONFLICT (branch_id, task_id) WHERE status IN ('open', 'claimed') DO NOTHING
  RETURNING id INTO request_id;
  IF request_id IS NULL THEN
    SELECT id INTO request_id FROM public.restaurant_collaboration_requests
      WHERE branch_id = p_branch_id AND task_id = p_task_id AND status IN ('open', 'claimed');
    RETURN request_id;
  END IF;

  event_type := CASE WHEN p_request_source = 'receipt_timeout'
    THEN 'receipt_deadline_triggered' ELSE 'requested' END;
  INSERT INTO public.restaurant_collaboration_events(branch_id, request_id, actor_id, event_type, details)
    VALUES (p_branch_id, request_id, p_actor_id, event_type,
      pg_catalog.jsonb_build_object('source', p_request_source,
        'target_employee_id', task_row.assigned_to));

  INSERT INTO public.restaurant_notifications(branch_id, recipient_id, notification_type, title, body,
    entity_type, entity_id, data)
  SELECT p_branch_id, m.user_id, 'collaboration_requested', 'Aviso colaborativo',
    '¿Puedes avisarle personalmente a un compañero sobre una tarea pendiente?',
    'collaboration_request', request_id,
    pg_catalog.jsonb_build_object('request_id', request_id, 'task_id', p_task_id,
      'request_source', p_request_source)
  FROM public.restaurant_memberships m
  WHERE m.branch_id = p_branch_id AND m.is_active
    AND m.user_id <> task_row.assigned_to
    AND (p_actor_id IS NULL OR m.user_id <> p_actor_id)
    AND private.restaurant_member_scheduled_available_now(p_branch_id, m.user_id);
  RETURN request_id;
END;
$$;
REVOKE ALL ON FUNCTION private.open_restaurant_collaboration_request(uuid, uuid, uuid, uuid, text)
  FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.create_restaurant_collaboration_request(
  p_branch_id uuid, p_task_id uuid, p_actor_id uuid, p_client_event_id uuid
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  RETURN private.open_restaurant_collaboration_request(
    p_branch_id, p_task_id, p_actor_id, p_client_event_id, 'manager_manual');
END;
$$;
REVOKE ALL ON FUNCTION public.create_restaurant_collaboration_request(uuid, uuid, uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_restaurant_collaboration_request(uuid, uuid, uuid, uuid)
  TO service_role;

-- Release expired reservations and escalate only if the configured policy
-- says so. Every update and append-only event is committed atomically.
CREATE OR REPLACE FUNCTION private.process_restaurant_collaboration_deadlines()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  due_row record;
  request_row record;
  active_request_id uuid;
  client_event_id uuid;
  processed integer := 0;
BEGIN
  FOR due_row IN
    SELECT r.branch_id, r.task_id, r.id AS receipt_id, r.employee_id,
      r.assignment_recorded_at, t.priority
    FROM public.restaurant_task_receipts r
    JOIN public.restaurant_tasks t ON t.branch_id = r.branch_id AND t.id = r.task_id
    JOIN public.restaurant_branches b ON b.id = r.branch_id AND b.is_active
    CROSS JOIN LATERAL (
      SELECT CASE
        WHEN pg_catalog.length(b.receipt_escalation_seconds_by_priority ->> t.priority::text) BETWEEN 2 AND 5
          AND (b.receipt_escalation_seconds_by_priority ->> t.priority::text) ~ '^[0-9]+$'
        THEN CASE
          WHEN (b.receipt_escalation_seconds_by_priority ->> t.priority::text)::integer BETWEEN 30 AND 86400
          THEN (b.receipt_escalation_seconds_by_priority ->> t.priority::text)::integer
          ELSE NULL END
        ELSE NULL END AS escalation_seconds
    ) configured_policy
    WHERE r.receipt_state = 'awaiting' AND t.assigned_to = r.employee_id
      AND t.status <> 'completed'
      AND configured_policy.escalation_seconds IS NOT NULL
      AND r.assignment_recorded_at + pg_catalog.make_interval(secs => configured_policy.escalation_seconds) <= now()
      AND r.escalation_processed_at IS NULL
    ORDER BY r.assignment_recorded_at
    FOR UPDATE OF r SKIP LOCKED
  LOOP
    client_event_id := (pg_catalog.substr(pg_catalog.md5('receipt-deadline:' || due_row.receipt_id::text), 1, 8)
      || '-' || pg_catalog.substr(pg_catalog.md5('receipt-deadline:' || due_row.receipt_id::text), 9, 4)
      || '-' || pg_catalog.substr(pg_catalog.md5('receipt-deadline:' || due_row.receipt_id::text), 13, 4)
      || '-' || pg_catalog.substr(pg_catalog.md5('receipt-deadline:' || due_row.receipt_id::text), 17, 4)
      || '-' || pg_catalog.substr(pg_catalog.md5('receipt-deadline:' || due_row.receipt_id::text), 21, 12))::uuid;
    active_request_id := private.open_restaurant_collaboration_request(
      due_row.branch_id, due_row.task_id, NULL, client_event_id, 'receipt_timeout');
    UPDATE public.restaurant_task_receipts SET escalation_processed_at = now()
      WHERE id = due_row.receipt_id AND escalation_processed_at IS NULL;
    processed := processed + CASE WHEN active_request_id IS NULL THEN 0 ELSE 1 END;
  END LOOP;

  FOR request_row IN
    SELECT r.id, r.branch_id, r.task_id
    FROM public.restaurant_collaboration_requests r
    WHERE r.status = 'claimed' AND r.claimed_until <= now()
    ORDER BY r.claimed_until
    FOR UPDATE OF r SKIP LOCKED
  LOOP
    UPDATE public.restaurant_collaboration_requests SET status = 'open',
      claimed_by = NULL, claimed_until = NULL, resolution = NULL,
      resolved_by = NULL, resolved_at = NULL
      WHERE id = request_row.id;
    INSERT INTO public.restaurant_collaboration_events(branch_id, request_id, actor_id, event_type, details)
      VALUES (request_row.branch_id, request_row.id, NULL, 'claim_released',
        pg_catalog.jsonb_build_object('reason', 'reservation_expired', 'source', 'scheduler'));
    processed := processed + 1;
  END LOOP;

  FOR request_row IN
    SELECT r.id, r.branch_id, r.task_id, r.target_employee_id, r.created_at,
      b.collaboration_manager_escalation_seconds
    FROM public.restaurant_collaboration_requests r
    JOIN public.restaurant_branches b ON b.id = r.branch_id AND b.is_active
    WHERE r.status = 'open' AND r.manager_escalated_at IS NULL
      AND b.collaboration_manager_escalation_seconds IS NOT NULL
      AND r.created_at + pg_catalog.make_interval(secs => b.collaboration_manager_escalation_seconds) <= now()
    ORDER BY r.created_at
    FOR UPDATE OF r SKIP LOCKED
  LOOP
    UPDATE public.restaurant_collaboration_requests SET manager_escalated_at = now()
      WHERE id = request_row.id AND manager_escalated_at IS NULL;
    IF NOT FOUND THEN CONTINUE; END IF;
    INSERT INTO public.restaurant_collaboration_events(branch_id, request_id, actor_id, event_type, details)
      VALUES (request_row.branch_id, request_row.id, NULL, 'manager_escalated',
        pg_catalog.jsonb_build_object('source', 'scheduler', 'escalated_at', now()));
    INSERT INTO public.restaurant_notifications(branch_id, recipient_id, notification_type, title, body,
      entity_type, entity_id, data)
    SELECT request_row.branch_id, m.user_id, 'collaboration_escalated', 'Aviso colaborativo sin atender',
      'La solicitud de apoyo sigue sin ser atendida y requiere seguimiento de gerencia.',
      'collaboration_escalation', request_row.id,
      pg_catalog.jsonb_build_object('request_id', request_row.id, 'task_id', request_row.task_id,
        'target_employee_id', request_row.target_employee_id, 'request_source', 'manager_escalation')
    FROM public.restaurant_memberships m
    WHERE m.branch_id = request_row.branch_id AND m.is_active
      AND m.access_role IN ('admin', 'supervisor');
    processed := processed + 1;
  END LOOP;
  RETURN processed;
END;
$$;
REVOKE ALL ON FUNCTION private.process_restaurant_collaboration_deadlines()
  FROM PUBLIC, anon, authenticated, service_role;

DO $$
DECLARE existing_job record;
BEGIN
  FOR existing_job IN SELECT jobid FROM cron.job
    WHERE jobname = 'restaurant-collaboration-deadlines'
  LOOP
    PERFORM cron.unschedule(existing_job.jobid);
  END LOOP;
  PERFORM cron.schedule('restaurant-collaboration-deadlines', '* * * * *',
    'SELECT private.process_restaurant_collaboration_deadlines();');
END;
$$;

-- Once the assigned employee confirms receipt, old peer requests become
-- inactive immediately; the assignment itself is still not marked complete.
CREATE OR REPLACE FUNCTION private.cancel_collaboration_after_receipt_confirmed()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE closed_request record;
BEGIN
  IF NEW.receipt_state <> 'employee_confirmed'
     OR OLD.receipt_state = 'employee_confirmed' THEN RETURN NEW; END IF;
  FOR closed_request IN
    UPDATE public.restaurant_collaboration_requests SET status = 'cancelled',
      claimed_by = NULL, claimed_until = NULL, resolution = NULL,
      resolved_by = NULL, resolved_at = NULL
    WHERE branch_id = NEW.branch_id AND task_id = NEW.task_id
      AND status IN ('open', 'claimed')
    RETURNING id
  LOOP
    INSERT INTO public.restaurant_collaboration_events(branch_id, request_id, actor_id, event_type, details)
      VALUES (NEW.branch_id, closed_request.id, NEW.confirmed_by, 'cancelled',
        pg_catalog.jsonb_build_object('reason', 'receipt_confirmed', 'source', 'employee'));
  END LOOP;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION private.cancel_collaboration_after_receipt_confirmed() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER restaurant_cancel_collaboration_after_receipt
  AFTER UPDATE OF receipt_state ON public.restaurant_task_receipts
  FOR EACH ROW EXECUTE FUNCTION private.cancel_collaboration_after_receipt_confirmed();

-- A failed-to-locate response returns the request to the active inbox. Its
-- outcome is kept in the immutable event ledger, not in the open row's state.
CREATE OR REPLACE FUNCTION public.resolve_restaurant_collaboration_request(
  p_branch_id uuid, p_request_id uuid, p_actor_id uuid, p_resolution text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE request_row public.restaurant_collaboration_requests%ROWTYPE; receipt_id uuid;
BEGIN
  IF p_resolution NOT IN ('peer_notified', 'not_located') THEN
    RAISE EXCEPTION 'INVALID_COLLABORATION_RESOLUTION';
  END IF;
  SELECT * INTO request_row FROM public.restaurant_collaboration_requests
    WHERE branch_id = p_branch_id AND id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'COLLABORATION_REQUEST_NOT_FOUND'; END IF;
  IF request_row.status <> 'claimed' OR request_row.claimed_by <> p_actor_id
      OR request_row.claimed_until <= now() THEN
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
  ELSE
    UPDATE public.restaurant_collaboration_requests SET status = 'open', resolution = NULL,
      resolved_by = NULL, resolved_at = NULL, claimed_by = NULL, claimed_until = NULL
      WHERE id = p_request_id;
  END IF;
  INSERT INTO public.restaurant_collaboration_events(branch_id, request_id, actor_id, event_type, details)
    VALUES (p_branch_id, p_request_id, p_actor_id, p_resolution,
      pg_catalog.jsonb_build_object('request_source', request_row.request_source));
  IF p_resolution = 'peer_notified' THEN
    INSERT INTO public.restaurant_task_receipt_events(branch_id, receipt_id, actor_id, event_type, details)
      VALUES (p_branch_id, receipt_id, p_actor_id, 'peer_notified',
        pg_catalog.jsonb_build_object('request_id', p_request_id,
          'target_employee_id', request_row.target_employee_id));
  END IF;
  RETURN pg_catalog.jsonb_build_object('resolution', p_resolution,
    'task_completed', false, 'request_status', CASE WHEN p_resolution = 'peer_notified' THEN 'resolved' ELSE 'open' END);
END;
$$;
REVOKE ALL ON FUNCTION public.resolve_restaurant_collaboration_request(uuid, uuid, uuid, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_restaurant_collaboration_request(uuid, uuid, uuid, text)
  TO service_role;

-- Keep the actual DB recording time and the reported movement time separate.
-- Existing sessions remain null in the newly added fields rather than being
-- backfilled with a fabricated historical declaration.
ALTER TABLE public.restaurant_meal_sessions
  ADD COLUMN declared_started_at timestamptz,
  ADD COLUMN start_origin text CHECK (start_origin IN ('self', 'peer', 'manager')),
  ADD COLUMN declared_return_at timestamptz,
  ADD COLUMN return_origin text CHECK (return_origin IN ('self', 'peer', 'manager'));

CREATE OR REPLACE FUNCTION public.restaurant_start_meal(
  p_branch_id uuid, p_employee_id uuid, p_actor_id uuid, p_note text,
  p_declared_started_at timestamptz
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE actor_role text; active_session uuid; meal_minutes integer; origin text;
BEGIN
  SELECT b.meal_duration_minutes INTO meal_minutes FROM public.restaurant_branches b
    WHERE b.id = p_branch_id AND b.is_active;
  IF meal_minutes IS NULL THEN RAISE EXCEPTION 'MEAL_DURATION_NOT_CONFIGURED'; END IF;
  SELECT m.access_role INTO actor_role FROM public.restaurant_memberships m
    WHERE m.branch_id = p_branch_id AND m.user_id = p_actor_id AND m.is_active;
  IF actor_role IS NULL THEN RAISE EXCEPTION 'BRANCH_ACCESS_REQUIRED'; END IF;
  origin := CASE WHEN p_actor_id = p_employee_id THEN 'self'
    WHEN actor_role IN ('admin', 'supervisor') THEN 'manager' ELSE 'peer' END;
  IF origin = 'peer' AND NOT private.restaurant_member_scheduled_available_now(p_branch_id, p_actor_id) THEN
    RAISE EXCEPTION 'COLLABORATOR_NOT_AVAILABLE';
  END IF;
  PERFORM 1 FROM public.restaurant_memberships m
    WHERE m.branch_id = p_branch_id AND m.user_id = p_employee_id AND m.is_active FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'EMPLOYEE_NOT_ACTIVE'; END IF;
  IF NOT private.restaurant_member_on_shift_now(p_branch_id, p_employee_id) THEN
    RAISE EXCEPTION 'EMPLOYEE_NOT_ON_SHIFT';
  END IF;
  IF EXISTS (SELECT 1 FROM public.restaurant_member_operational_states os
      WHERE os.branch_id = p_branch_id AND os.employee_id = p_employee_id
        AND os.state IN ('meal', 'rest', 'off_shift')) THEN
    RAISE EXCEPTION 'EMPLOYEE_NOT_AVAILABLE_FOR_MEAL';
  END IF;
  IF EXISTS (SELECT 1 FROM public.restaurant_tasks t WHERE t.branch_id = p_branch_id
      AND t.assigned_to = p_employee_id AND t.status = 'in_progress')
    OR EXISTS (SELECT 1 FROM public.restaurant_task_parts p WHERE p.branch_id = p_branch_id
      AND p.assigned_to = p_employee_id AND p.status = 'in_progress') THEN
    RAISE EXCEPTION 'ACTIVE_TASK_REQUIRES_HANDOFF';
  END IF;
  IF EXISTS (SELECT 1 FROM public.restaurant_meal_sessions s WHERE s.branch_id = p_branch_id
      AND s.employee_id = p_employee_id AND s.return_confirmed_at IS NULL) THEN
    RAISE EXCEPTION 'MEAL_ALREADY_ACTIVE';
  END IF;
  INSERT INTO public.restaurant_meal_sessions(branch_id, employee_id, scheduled_start, scheduled_end,
    started_by, note, declared_started_at, start_origin)
    VALUES (p_branch_id, p_employee_id, now(), now() + pg_catalog.make_interval(mins => meal_minutes),
      p_actor_id, nullif(pg_catalog.btrim(p_note), ''), p_declared_started_at, origin)
    RETURNING id INTO active_session;
  INSERT INTO public.restaurant_member_operational_states(branch_id, employee_id, state, changed_by, note)
    VALUES (p_branch_id, p_employee_id, 'meal', p_actor_id, 'Comida iniciada')
    ON CONFLICT (branch_id, employee_id) DO UPDATE SET state = 'meal', changed_by = EXCLUDED.changed_by,
      changed_at = now(), note = EXCLUDED.note;
  INSERT INTO public.restaurant_operational_state_events(branch_id, employee_id, state, changed_by, note)
    VALUES (p_branch_id, p_employee_id, 'meal', p_actor_id, 'Comida iniciada');
  INSERT INTO public.restaurant_meal_events(branch_id, meal_session_id, actor_id, event_type, details)
    VALUES (p_branch_id, active_session, p_actor_id, 'started',
      pg_catalog.jsonb_build_object('employee_id', p_employee_id, 'recorded_by', p_actor_id,
        'recorded_at', now(), 'declared_at', p_declared_started_at, 'origin', origin));
  RETURN active_session;
END;
$$;
REVOKE ALL ON FUNCTION public.restaurant_start_meal(uuid, uuid, uuid, text, timestamptz)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.restaurant_start_meal(uuid, uuid, uuid, text, timestamptz)
  TO service_role;

CREATE OR REPLACE FUNCTION public.restaurant_start_meal(
  p_branch_id uuid, p_employee_id uuid, p_actor_id uuid, p_note text
) RETURNS uuid LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  SELECT public.restaurant_start_meal(p_branch_id, p_employee_id, p_actor_id, p_note, NULL);
$$;
REVOKE ALL ON FUNCTION public.restaurant_start_meal(uuid, uuid, uuid, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.restaurant_start_meal(uuid, uuid, uuid, text) TO service_role;

CREATE OR REPLACE FUNCTION public.restaurant_confirm_meal_return(
  p_branch_id uuid, p_session_id uuid, p_actor_id uuid, p_state text,
  p_declared_return_at timestamptz
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE meal_row public.restaurant_meal_sessions%ROWTYPE; actor_role text; final_state text; origin text;
BEGIN
  IF p_state NOT IN ('available', 'busy') THEN RAISE EXCEPTION 'INVALID_RETURN_STATE'; END IF;
  SELECT * INTO meal_row FROM public.restaurant_meal_sessions s
    WHERE s.branch_id = p_branch_id AND s.id = p_session_id FOR UPDATE;
  IF NOT FOUND OR meal_row.return_confirmed_at IS NOT NULL THEN RAISE EXCEPTION 'MEAL_NOT_ACTIVE'; END IF;
  SELECT m.access_role INTO actor_role FROM public.restaurant_memberships m
    WHERE m.branch_id = p_branch_id AND m.user_id = p_actor_id AND m.is_active;
  IF actor_role IS NULL THEN RAISE EXCEPTION 'BRANCH_ACCESS_REQUIRED'; END IF;
  origin := CASE WHEN p_actor_id = meal_row.employee_id THEN 'self'
    WHEN actor_role IN ('admin', 'supervisor') THEN 'manager' ELSE 'peer' END;
  IF origin = 'peer' AND NOT private.restaurant_member_scheduled_available_now(p_branch_id, p_actor_id) THEN
    RAISE EXCEPTION 'COLLABORATOR_NOT_AVAILABLE';
  END IF;
  final_state := CASE WHEN private.restaurant_member_on_shift_now(p_branch_id, meal_row.employee_id)
    THEN p_state ELSE 'off_shift' END;
  UPDATE public.restaurant_meal_sessions SET return_confirmed_at = now(), return_confirmed_by = p_actor_id,
    declared_return_at = p_declared_return_at, return_origin = origin
    WHERE id = meal_row.id;
  UPDATE public.restaurant_member_operational_states SET state = final_state, changed_by = p_actor_id,
    changed_at = now(), note = CASE WHEN final_state = 'off_shift'
      THEN 'Regreso confirmado fuera del turno publicado' ELSE 'Regreso de comida confirmado' END
    WHERE branch_id = p_branch_id AND employee_id = meal_row.employee_id;
  INSERT INTO public.restaurant_operational_state_events(branch_id, employee_id, state, changed_by, note)
    VALUES (p_branch_id, meal_row.employee_id, final_state, p_actor_id,
      CASE WHEN final_state = 'off_shift' THEN 'Regreso confirmado fuera del turno publicado'
        ELSE 'Regreso de comida confirmado' END);
  INSERT INTO public.restaurant_meal_events(branch_id, meal_session_id, actor_id, event_type, details)
    VALUES (p_branch_id, meal_row.id, p_actor_id, 'return_confirmed',
      pg_catalog.jsonb_build_object('employee_id', meal_row.employee_id, 'recorded_by', p_actor_id,
        'recorded_at', now(), 'declared_at', p_declared_return_at,
        'origin', origin, 'state_after_return', final_state));
  RETURN pg_catalog.jsonb_build_object('returned', true, 'state', final_state,
    'employee_id', meal_row.employee_id, 'recorded_by', p_actor_id,
    'recorded_at', now(), 'declared_at', p_declared_return_at, 'origin', origin);
END;
$$;
REVOKE ALL ON FUNCTION public.restaurant_confirm_meal_return(uuid, uuid, uuid, text, timestamptz)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.restaurant_confirm_meal_return(uuid, uuid, uuid, text, timestamptz)
  TO service_role;

CREATE OR REPLACE FUNCTION public.restaurant_confirm_meal_return(
  p_branch_id uuid, p_session_id uuid, p_actor_id uuid, p_state text
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$
  SELECT public.restaurant_confirm_meal_return(p_branch_id, p_session_id, p_actor_id, p_state, NULL);
$$;
REVOKE ALL ON FUNCTION public.restaurant_confirm_meal_return(uuid, uuid, uuid, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.restaurant_confirm_meal_return(uuid, uuid, uuid, text)
  TO service_role;
