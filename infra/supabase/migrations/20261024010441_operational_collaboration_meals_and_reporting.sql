-- Operational collaboration, work attribution, availability, meals and explainable analysis.
-- Additive only: no existing records are rewritten and no branch defaults are invented.

ALTER TABLE public.restaurant_branches
  ADD COLUMN meal_duration_minutes integer,
  ADD COLUMN collaboration_reservation_seconds integer,
  ADD COLUMN receipt_escalation_seconds_by_priority jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN minimum_area_coverage jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD CONSTRAINT restaurant_branches_meal_duration_valid
    CHECK (meal_duration_minutes IS NULL OR meal_duration_minutes BETWEEN 1 AND 240),
  ADD CONSTRAINT restaurant_branches_minimum_area_coverage_object
    CHECK (pg_catalog.jsonb_typeof(minimum_area_coverage) = 'object'),
  ADD CONSTRAINT restaurant_branches_collaboration_reservation_valid
    CHECK (collaboration_reservation_seconds IS NULL OR collaboration_reservation_seconds BETWEEN 30 AND 3600),
  ADD CONSTRAINT restaurant_branches_receipt_escalation_object
    CHECK (pg_catalog.jsonb_typeof(receipt_escalation_seconds_by_priority) = 'object');

-- Explicit coverage mapping: a work position may serve one physical area.
ALTER TABLE public.restaurant_positions ADD COLUMN area_id uuid;
ALTER TABLE public.restaurant_positions
  ADD CONSTRAINT restaurant_positions_area_same_branch_fk
    FOREIGN KEY (branch_id, area_id)
    REFERENCES public.restaurant_areas(branch_id, id)
    ON DELETE SET NULL (area_id);
CREATE INDEX restaurant_positions_area_idx
  ON public.restaurant_positions(branch_id, area_id) WHERE area_id IS NOT NULL;

ALTER TABLE public.restaurant_activity_templates
  ADD COLUMN evidence_policy text NOT NULL DEFAULT 'none';
UPDATE public.restaurant_activity_templates SET evidence_policy = 'required' WHERE requires_evidence;
ALTER TABLE public.restaurant_activity_templates
  ADD CONSTRAINT restaurant_activity_templates_evidence_policy_check
    CHECK (evidence_policy IN ('none', 'optional', 'required', 'independent_review'));

ALTER TABLE public.restaurant_tasks
  ADD COLUMN evidence_policy text NOT NULL DEFAULT 'none';
UPDATE public.restaurant_tasks SET evidence_policy = 'required' WHERE requires_evidence;
ALTER TABLE public.restaurant_tasks
  ADD CONSTRAINT restaurant_tasks_evidence_policy_check
    CHECK (evidence_policy IN ('none', 'optional', 'required', 'independent_review'));

CREATE OR REPLACE FUNCTION private.sync_restaurant_evidence_policy()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
DECLARE template_policy text;
BEGIN
  IF TG_TABLE_NAME = 'restaurant_activity_templates' THEN
    IF TG_OP = 'INSERT' THEN
      IF NEW.evidence_policy = 'none' AND NEW.requires_evidence THEN
        NEW.evidence_policy := 'required';
      END IF;
      NEW.requires_evidence := NEW.evidence_policy = 'required';
    ELSIF NEW.evidence_policy IS DISTINCT FROM OLD.evidence_policy THEN
      NEW.requires_evidence := NEW.evidence_policy = 'required';
    ELSIF NEW.requires_evidence IS DISTINCT FROM OLD.requires_evidence THEN
      NEW.evidence_policy := CASE WHEN NEW.requires_evidence THEN 'required' ELSE 'none' END;
    END IF;
    RETURN NEW;
  END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.activity_template_id IS NOT NULL THEN
      SELECT t.evidence_policy INTO template_policy FROM public.restaurant_activity_templates t
        WHERE t.branch_id = NEW.branch_id AND t.id = NEW.activity_template_id;
    END IF;
    IF template_policy IS NOT NULL THEN
      NEW.evidence_policy := template_policy;
    ELSIF NEW.requires_evidence THEN
      NEW.evidence_policy := 'required';
    END IF;
    NEW.requires_evidence := NEW.evidence_policy = 'required';
  ELSIF NEW.evidence_policy IS DISTINCT FROM OLD.evidence_policy THEN
    NEW.requires_evidence := NEW.evidence_policy = 'required';
  ELSIF NEW.requires_evidence IS DISTINCT FROM OLD.requires_evidence THEN
    NEW.evidence_policy := CASE WHEN NEW.requires_evidence THEN 'required' ELSE 'none' END;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION private.sync_restaurant_evidence_policy() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER restaurant_activity_template_evidence_policy_sync
  BEFORE INSERT OR UPDATE OF evidence_policy, requires_evidence ON public.restaurant_activity_templates
  FOR EACH ROW EXECUTE FUNCTION private.sync_restaurant_evidence_policy();
CREATE TRIGGER restaurant_task_evidence_policy_sync
  BEFORE INSERT OR UPDATE OF evidence_policy, requires_evidence ON public.restaurant_tasks
  FOR EACH ROW EXECUTE FUNCTION private.sync_restaurant_evidence_policy();

CREATE TABLE public.restaurant_member_operational_states (
  branch_id uuid NOT NULL,
  employee_id uuid NOT NULL,
  state text NOT NULL CHECK (state IN ('available', 'occupied', 'meal', 'rest', 'off_shift')),
  changed_by uuid NOT NULL,
  changed_at timestamptz NOT NULL DEFAULT now(),
  note text CHECK (note IS NULL OR pg_catalog.length(note) <= 500),
  PRIMARY KEY (branch_id, employee_id),
  FOREIGN KEY (branch_id, employee_id)
    REFERENCES public.restaurant_memberships(branch_id, user_id) ON DELETE CASCADE,
  FOREIGN KEY (branch_id, changed_by)
    REFERENCES public.restaurant_memberships(branch_id, user_id) ON DELETE RESTRICT
);
ALTER TABLE public.restaurant_member_operational_states ENABLE ROW LEVEL SECURITY;
CREATE POLICY restaurant_operational_states_branch_read ON public.restaurant_member_operational_states
  FOR SELECT TO authenticated USING (private.restaurant_has_access(branch_id));
REVOKE ALL ON public.restaurant_member_operational_states FROM anon, authenticated;
GRANT SELECT ON public.restaurant_member_operational_states TO authenticated;
GRANT ALL ON public.restaurant_member_operational_states TO service_role;

CREATE TABLE public.restaurant_operational_state_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid NOT NULL,
  employee_id uuid NOT NULL,
  state text NOT NULL CHECK (state IN ('available', 'occupied', 'meal', 'rest', 'off_shift')),
  changed_by uuid NOT NULL,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  note text CHECK (note IS NULL OR pg_catalog.length(note) <= 500),
  FOREIGN KEY (branch_id, employee_id)
    REFERENCES public.restaurant_memberships(branch_id, user_id) ON DELETE RESTRICT,
  FOREIGN KEY (branch_id, changed_by)
    REFERENCES public.restaurant_memberships(branch_id, user_id) ON DELETE RESTRICT
);
CREATE INDEX restaurant_operational_state_events_history_idx
  ON public.restaurant_operational_state_events(branch_id, employee_id, occurred_at DESC);
ALTER TABLE public.restaurant_operational_state_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY restaurant_operational_state_events_participant_read
  ON public.restaurant_operational_state_events FOR SELECT TO authenticated
  USING (private.restaurant_has_access(branch_id)
    AND (employee_id = auth.uid() OR private.restaurant_can_manage(branch_id)));
REVOKE ALL ON public.restaurant_operational_state_events FROM anon, authenticated;
GRANT SELECT ON public.restaurant_operational_state_events TO authenticated;
GRANT ALL ON public.restaurant_operational_state_events TO service_role;

CREATE TABLE public.restaurant_meal_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid NOT NULL,
  employee_id uuid NOT NULL,
  scheduled_start timestamptz,
  scheduled_end timestamptz,
  started_at timestamptz NOT NULL DEFAULT now(),
  started_by uuid NOT NULL,
  return_confirmed_at timestamptz,
  return_confirmed_by uuid,
  state_after_return text NOT NULL DEFAULT 'available'
    CHECK (state_after_return IN ('available', 'busy')),
  note text CHECK (note IS NULL OR pg_catalog.length(note) <= 500),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (branch_id, employee_id)
    REFERENCES public.restaurant_memberships(branch_id, user_id) ON DELETE CASCADE,
  FOREIGN KEY (branch_id, started_by)
    REFERENCES public.restaurant_memberships(branch_id, user_id) ON DELETE RESTRICT,
  FOREIGN KEY (branch_id, return_confirmed_by)
    REFERENCES public.restaurant_memberships(branch_id, user_id) ON DELETE RESTRICT,
  CHECK ((scheduled_start IS NULL) = (scheduled_end IS NULL)),
  CHECK (scheduled_end IS NULL OR scheduled_end > scheduled_start),
  CHECK ((return_confirmed_at IS NULL) = (return_confirmed_by IS NULL)),
  UNIQUE (branch_id, id)
);
CREATE UNIQUE INDEX restaurant_meal_one_open_per_employee
  ON public.restaurant_meal_sessions(branch_id, employee_id)
  WHERE return_confirmed_at IS NULL;
CREATE INDEX restaurant_meal_sessions_branch_started_idx
  ON public.restaurant_meal_sessions(branch_id, started_at DESC);
ALTER TABLE public.restaurant_meal_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY restaurant_meal_sessions_branch_read ON public.restaurant_meal_sessions
  FOR SELECT TO authenticated USING (private.restaurant_has_access(branch_id));
REVOKE ALL ON public.restaurant_meal_sessions FROM anon, authenticated;
GRANT SELECT ON public.restaurant_meal_sessions TO authenticated;
GRANT ALL ON public.restaurant_meal_sessions TO service_role;

CREATE TABLE public.restaurant_meal_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid NOT NULL,
  meal_session_id uuid NOT NULL,
  actor_id uuid NOT NULL,
  event_type text NOT NULL CHECK (event_type IN ('started', 'return_confirmed')),
  occurred_at timestamptz NOT NULL DEFAULT now(),
  details jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (pg_catalog.jsonb_typeof(details) = 'object'),
  FOREIGN KEY (branch_id, meal_session_id)
    REFERENCES public.restaurant_meal_sessions(branch_id, id) ON DELETE CASCADE,
  FOREIGN KEY (branch_id, actor_id)
    REFERENCES public.restaurant_memberships(branch_id, user_id) ON DELETE RESTRICT
);
ALTER TABLE public.restaurant_meal_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY restaurant_meal_events_branch_read ON public.restaurant_meal_events
  FOR SELECT TO authenticated USING (private.restaurant_has_access(branch_id));
REVOKE ALL ON public.restaurant_meal_events FROM anon, authenticated;
GRANT SELECT ON public.restaurant_meal_events TO authenticated;
GRANT ALL ON public.restaurant_meal_events TO service_role;

CREATE TABLE public.restaurant_task_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid NOT NULL,
  task_id uuid NOT NULL,
  part_id uuid,
  responsible_employee_id uuid NOT NULL,
  recorded_by uuid NOT NULL,
  declared_completed_at timestamptz NOT NULL,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  evidence_path text,
  evidence_required boolean NOT NULL,
  independent_review_required boolean NOT NULL DEFAULT false,
  note text CHECK (note IS NULL OR pg_catalog.length(note) <= 1000),
  client_event_id uuid NOT NULL,
  FOREIGN KEY (branch_id, task_id)
    REFERENCES public.restaurant_tasks(branch_id, id) ON DELETE CASCADE,
  FOREIGN KEY (branch_id, part_id)
    REFERENCES public.restaurant_task_parts(branch_id, id) ON DELETE CASCADE,
  FOREIGN KEY (branch_id, responsible_employee_id)
    REFERENCES public.restaurant_memberships(branch_id, user_id) ON DELETE RESTRICT,
  FOREIGN KEY (branch_id, recorded_by)
    REFERENCES public.restaurant_memberships(branch_id, user_id) ON DELETE RESTRICT,
  UNIQUE (branch_id, recorded_by, client_event_id),
  UNIQUE (branch_id, id)
);
CREATE INDEX restaurant_task_reports_branch_task_recorded_idx
  ON public.restaurant_task_reports(branch_id, task_id, recorded_at DESC);
ALTER TABLE public.restaurant_task_reports ENABLE ROW LEVEL SECURITY;
CREATE POLICY restaurant_task_reports_branch_read ON public.restaurant_task_reports
  FOR SELECT TO authenticated USING (private.restaurant_has_access(branch_id));
REVOKE ALL ON public.restaurant_task_reports FROM anon, authenticated;
GRANT SELECT ON public.restaurant_task_reports TO authenticated;
GRANT ALL ON public.restaurant_task_reports TO service_role;

CREATE TABLE public.restaurant_task_report_reviews (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid NOT NULL,
  report_id uuid NOT NULL,
  reviewer_id uuid NOT NULL,
  decision text NOT NULL CHECK (decision IN ('accepted', 'rejected')),
  note text CHECK (note IS NULL OR pg_catalog.length(note) <= 1000),
  reviewed_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (branch_id, report_id)
    REFERENCES public.restaurant_task_reports(branch_id, id) ON DELETE CASCADE,
  FOREIGN KEY (branch_id, reviewer_id)
    REFERENCES public.restaurant_memberships(branch_id, user_id) ON DELETE RESTRICT
);
CREATE INDEX restaurant_task_report_reviews_latest_idx
  ON public.restaurant_task_report_reviews(branch_id, report_id, reviewed_at DESC);
ALTER TABLE public.restaurant_task_report_reviews ENABLE ROW LEVEL SECURITY;
CREATE POLICY restaurant_task_report_reviews_branch_read ON public.restaurant_task_report_reviews
  FOR SELECT TO authenticated USING (private.restaurant_has_access(branch_id));
REVOKE ALL ON public.restaurant_task_report_reviews FROM anon, authenticated;
GRANT SELECT ON public.restaurant_task_report_reviews TO authenticated;
GRANT ALL ON public.restaurant_task_report_reviews TO service_role;

CREATE TABLE public.restaurant_meal_plan_proposals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid NOT NULL REFERENCES public.restaurant_branches(id) ON DELETE CASCADE,
  shift_date date NOT NULL,
  planner text NOT NULL CHECK (planner IN ('timefold', 'local')),
  proposed_schedule jsonb NOT NULL CHECK (pg_catalog.jsonb_typeof(proposed_schedule) = 'array'),
  planning_inputs jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (pg_catalog.jsonb_typeof(planning_inputs) = 'object'),
  approved_schedule jsonb CHECK (approved_schedule IS NULL OR pg_catalog.jsonb_typeof(approved_schedule) = 'array'),
  status text NOT NULL DEFAULT 'proposed'
    CHECK (status IN ('proposed', 'approved', 'modified', 'rejected')),
  generated_at timestamptz NOT NULL DEFAULT now(),
  decided_by uuid,
  decided_at timestamptz,
  decision_note text CHECK (decision_note IS NULL OR pg_catalog.length(decision_note) <= 1000),
  FOREIGN KEY (branch_id, decided_by)
    REFERENCES public.restaurant_memberships(branch_id, user_id) ON DELETE RESTRICT,
  CHECK ((status IN ('approved', 'modified')) = (approved_schedule IS NOT NULL)),
  CHECK ((decided_by IS NULL) = (decided_at IS NULL)),
  UNIQUE (branch_id, id)
);
ALTER TABLE public.restaurant_meal_plan_proposals ENABLE ROW LEVEL SECURITY;
CREATE POLICY restaurant_meal_plan_branch_read ON public.restaurant_meal_plan_proposals
  FOR SELECT TO authenticated USING (private.restaurant_can_manage(branch_id));
REVOKE ALL ON public.restaurant_meal_plan_proposals FROM anon, authenticated;
GRANT SELECT ON public.restaurant_meal_plan_proposals TO authenticated;
GRANT ALL ON public.restaurant_meal_plan_proposals TO service_role;

-- One row per employee keeps approved meal times available to that employee
-- over Realtime without exposing coworkers' full proposal JSON.
CREATE TABLE public.restaurant_meal_plan_slots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid NOT NULL,
  plan_id uuid NOT NULL,
  employee_id uuid NOT NULL,
  starts_at timestamptz NOT NULL,
  scheduled_end_at timestamptz NOT NULL,
  meal_duration_minutes integer NOT NULL CHECK (meal_duration_minutes BETWEEN 1 AND 240),
  decision text NOT NULL CHECK (decision IN ('approved', 'modified')),
  approved_by uuid NOT NULL,
  approved_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (branch_id, plan_id) REFERENCES public.restaurant_meal_plan_proposals(branch_id, id) ON DELETE CASCADE,
  FOREIGN KEY (branch_id, employee_id) REFERENCES public.restaurant_memberships(branch_id, user_id) ON DELETE RESTRICT,
  FOREIGN KEY (branch_id, approved_by) REFERENCES public.restaurant_memberships(branch_id, user_id) ON DELETE RESTRICT,
  CHECK (scheduled_end_at > starts_at),
  CHECK (scheduled_end_at - starts_at = pg_catalog.make_interval(mins => meal_duration_minutes)),
  UNIQUE (branch_id, plan_id, employee_id)
);
CREATE INDEX restaurant_meal_plan_slots_employee_start_idx
  ON public.restaurant_meal_plan_slots(branch_id, employee_id, starts_at DESC);
ALTER TABLE public.restaurant_meal_plan_slots ENABLE ROW LEVEL SECURITY;
CREATE POLICY restaurant_meal_plan_slots_member_read ON public.restaurant_meal_plan_slots
  FOR SELECT TO authenticated USING (private.restaurant_has_access(branch_id)
    AND (employee_id = auth.uid() OR private.restaurant_can_manage(branch_id)));
REVOKE ALL ON public.restaurant_meal_plan_slots FROM anon, authenticated;
GRANT SELECT ON public.restaurant_meal_plan_slots TO authenticated;
GRANT ALL ON public.restaurant_meal_plan_slots TO service_role;

CREATE TABLE public.restaurant_operational_recommendations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid NOT NULL REFERENCES public.restaurant_branches(id) ON DELETE CASCADE,
  category text NOT NULL CHECK (category IN ('workload', 'coverage', 'delay', 'inspection', 'schedule')),
  source_period_start timestamptz NOT NULL,
  source_period_end timestamptz NOT NULL,
  source_data jsonb NOT NULL CHECK (pg_catalog.jsonb_typeof(source_data) = 'object'),
  explanation text NOT NULL CHECK (pg_catalog.length(explanation) BETWEEN 1 AND 2000),
  suggested_action text NOT NULL CHECK (pg_catalog.length(suggested_action) BETWEEN 1 AND 1000),
  confidence numeric(4,3) CHECK (confidence IS NULL OR confidence BETWEEN 0 AND 1),
  decision text NOT NULL DEFAULT 'pending'
    CHECK (decision IN ('pending', 'approved', 'modified', 'rejected')),
  decided_by uuid,
  decided_at timestamptz,
  outcome_note text CHECK (outcome_note IS NULL OR pg_catalog.length(outcome_note) <= 1000),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (branch_id, decided_by)
    REFERENCES public.restaurant_memberships(branch_id, user_id) ON DELETE RESTRICT,
  CHECK (source_period_end > source_period_start),
  CHECK ((decided_by IS NULL) = (decided_at IS NULL)),
  UNIQUE (branch_id, id)
);
CREATE INDEX restaurant_recommendations_branch_pending_idx
  ON public.restaurant_operational_recommendations(branch_id, created_at DESC)
  WHERE decision = 'pending';
CREATE UNIQUE INDEX restaurant_coverage_recommendation_interval_uidx
  ON public.restaurant_operational_recommendations(
    branch_id, source_period_start, source_period_end, (source_data ->> 'area_id')
  ) WHERE category = 'coverage' AND source_data ->> 'analysis' = 'published_shift_qualified_coverage';
CREATE UNIQUE INDEX restaurant_recommendation_source_uidx
  ON public.restaurant_operational_recommendations(
    branch_id, category, source_period_start, source_period_end, (source_data ->> 'fingerprint')
  ) WHERE source_data ->> 'fingerprint' IS NOT NULL;
ALTER TABLE public.restaurant_operational_recommendations ENABLE ROW LEVEL SECURITY;
CREATE POLICY restaurant_recommendations_branch_read ON public.restaurant_operational_recommendations
  FOR SELECT TO authenticated USING (private.restaurant_can_manage(branch_id));
REVOKE ALL ON public.restaurant_operational_recommendations FROM anon, authenticated;
GRANT SELECT ON public.restaurant_operational_recommendations TO authenticated;
GRANT ALL ON public.restaurant_operational_recommendations TO service_role;

CREATE OR REPLACE FUNCTION private.reject_operational_event_mutation()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
  IF TG_OP = 'DELETE' AND pg_catalog.pg_trigger_depth() > 1 THEN RETURN OLD; END IF;
  RAISE EXCEPTION 'OPERATIONAL_EVENTS_APPEND_ONLY';
END;
$$;
REVOKE ALL ON FUNCTION private.reject_operational_event_mutation() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION private.restaurant_can_access_evidence(p_branch_id uuid, p_task_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT private.restaurant_can_manage(p_branch_id)
    OR (private.restaurant_has_access(p_branch_id) AND EXISTS (
      SELECT 1 FROM public.restaurant_tasks t
      WHERE t.branch_id = p_branch_id AND t.id = p_task_id AND t.evidence_policy <> 'none'
    ));
$$;
REVOKE ALL ON FUNCTION private.restaurant_can_access_evidence(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.restaurant_can_access_evidence(uuid, uuid) TO authenticated;
CREATE TRIGGER restaurant_meal_events_append_only
  BEFORE UPDATE OR DELETE ON public.restaurant_meal_events
  FOR EACH ROW EXECUTE FUNCTION private.reject_operational_event_mutation();
CREATE TRIGGER restaurant_operational_state_events_append_only
  BEFORE UPDATE OR DELETE ON public.restaurant_operational_state_events
  FOR EACH ROW EXECUTE FUNCTION private.reject_operational_event_mutation();
CREATE TRIGGER restaurant_task_reports_append_only
  BEFORE UPDATE OR DELETE ON public.restaurant_task_reports
  FOR EACH ROW EXECUTE FUNCTION private.reject_operational_event_mutation();
CREATE TRIGGER restaurant_task_report_reviews_append_only
  BEFORE UPDATE OR DELETE ON public.restaurant_task_report_reviews
  FOR EACH ROW EXECUTE FUNCTION private.reject_operational_event_mutation();

CREATE OR REPLACE FUNCTION private.require_review_for_independently_verified_task()
RETURNS trigger LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
  IF NEW.status = 'completed' AND OLD.status IS DISTINCT FROM 'completed'
    AND NEW.evidence_policy = 'independent_review' THEN
    IF EXISTS (SELECT 1 FROM public.restaurant_task_parts p
        WHERE p.branch_id = NEW.branch_id AND p.task_id = NEW.id
          AND NOT EXISTS (SELECT 1 FROM public.restaurant_task_reports r
            JOIN public.restaurant_task_report_reviews v
              ON v.branch_id = r.branch_id AND v.report_id = r.id AND v.decision = 'accepted'
            WHERE r.branch_id = p.branch_id AND r.task_id = p.task_id AND r.part_id = p.id))
      OR (NOT EXISTS (SELECT 1 FROM public.restaurant_task_parts p
            WHERE p.branch_id = NEW.branch_id AND p.task_id = NEW.id)
        AND NOT EXISTS (SELECT 1 FROM public.restaurant_task_reports r
          JOIN public.restaurant_task_report_reviews v
            ON v.branch_id = r.branch_id AND v.report_id = r.id AND v.decision = 'accepted'
          WHERE r.branch_id = NEW.branch_id AND r.task_id = NEW.id AND r.part_id IS NULL)) THEN
      RAISE EXCEPTION 'INDEPENDENT_REVIEW_REQUIRED';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION private.require_review_for_independently_verified_task() FROM PUBLIC, anon, authenticated;
CREATE TRIGGER restaurant_task_independent_review_guard
  BEFORE UPDATE OF status ON public.restaurant_tasks
  FOR EACH ROW EXECUTE FUNCTION private.require_review_for_independently_verified_task();

CREATE OR REPLACE FUNCTION private.restaurant_member_on_shift_now(
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
      AND NOT EXISTS (
        SELECT 1 FROM public.restaurant_absences a WHERE a.branch_id = m.branch_id
          AND a.employee_id = m.user_id AND a.status = 'approved'
          AND a.start_date <= (now() AT TIME ZONE b.timezone)::date
          AND a.end_date >= (now() AT TIME ZONE b.timezone)::date
      )
  );
$$;
REVOKE ALL ON FUNCTION private.restaurant_member_on_shift_now(uuid, uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.restaurant_record_task_report(
  p_branch_id uuid, p_task_id uuid, p_part_id uuid, p_responsible_employee_id uuid,
  p_recorded_by uuid, p_declared_completed_at timestamptz, p_evidence_path text,
  p_note text, p_client_event_id uuid
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE task_row public.restaurant_tasks%ROWTYPE; report_id uuid; actor_role text; branch_timezone text;
BEGIN
  SELECT m.access_role INTO actor_role FROM public.restaurant_memberships m
    WHERE m.branch_id = p_branch_id AND m.user_id = p_recorded_by AND m.is_active;
  IF actor_role IS NULL THEN RAISE EXCEPTION 'BRANCH_ACCESS_REQUIRED'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.restaurant_memberships m
    WHERE m.branch_id = p_branch_id AND m.user_id = p_responsible_employee_id AND m.is_active) THEN
    RAISE EXCEPTION 'RESPONSIBLE_EMPLOYEE_NOT_IN_BRANCH';
  END IF;
  SELECT * INTO task_row FROM public.restaurant_tasks t
    WHERE t.branch_id = p_branch_id AND t.id = p_task_id FOR UPDATE;
  IF NOT FOUND OR task_row.status = 'completed' THEN RAISE EXCEPTION 'TASK_NOT_REPORTABLE'; END IF;
  SELECT b.timezone INTO branch_timezone FROM public.restaurant_branches b WHERE b.id = p_branch_id;
  IF p_declared_completed_at IS NULL OR p_declared_completed_at > now()
    OR (p_declared_completed_at AT TIME ZONE branch_timezone)::date < task_row.scheduled_for THEN
    RAISE EXCEPTION 'INVALID_DECLARED_COMPLETION_TIME';
  END IF;
  IF p_part_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.restaurant_task_parts p
    WHERE p.branch_id = p_branch_id AND p.task_id = p_task_id AND p.id = p_part_id
      AND p.status <> 'completed') THEN RAISE EXCEPTION 'TASK_PART_NOT_REPORTABLE'; END IF;
  IF actor_role NOT IN ('admin', 'supervisor') THEN
    IF p_part_id IS NULL AND ((task_row.assigned_to IS NULL AND p_responsible_employee_id <> p_recorded_by)
      OR (task_row.assigned_to IS NOT NULL AND task_row.assigned_to <> p_responsible_employee_id)) THEN
      RAISE EXCEPTION 'RESPONSIBLE_EMPLOYEE_MISMATCH';
    END IF;
    IF p_part_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.restaurant_task_parts p
      WHERE p.branch_id = p_branch_id AND p.id = p_part_id AND p.assigned_to = p_responsible_employee_id) THEN
      RAISE EXCEPTION 'RESPONSIBLE_EMPLOYEE_MISMATCH';
    END IF;
  END IF;
  IF task_row.requires_evidence AND p_evidence_path IS NULL THEN RAISE EXCEPTION 'TASK_EVIDENCE_REQUIRED'; END IF;
  IF p_evidence_path IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.restaurant_evidence e
    WHERE e.branch_id = p_branch_id AND e.task_id = p_task_id
      AND e.uploaded_by = p_recorded_by AND e.object_path = p_evidence_path) THEN
    RAISE EXCEPTION 'TASK_EVIDENCE_NOT_REGISTERED';
  END IF;
  INSERT INTO public.restaurant_task_reports(branch_id, task_id, part_id,
    responsible_employee_id, recorded_by, declared_completed_at, evidence_path,
    evidence_required, independent_review_required, note, client_event_id)
  VALUES (p_branch_id, p_task_id, p_part_id, p_responsible_employee_id, p_recorded_by,
    p_declared_completed_at, p_evidence_path, task_row.requires_evidence,
    task_row.evidence_policy = 'independent_review', nullif(pg_catalog.btrim(p_note), ''), p_client_event_id)
  ON CONFLICT (branch_id, recorded_by, client_event_id) DO NOTHING
  RETURNING id INTO report_id;
  IF report_id IS NULL THEN
    SELECT r.id INTO report_id FROM public.restaurant_task_reports r
      WHERE r.branch_id = p_branch_id AND r.recorded_by = p_recorded_by
        AND r.client_event_id = p_client_event_id AND r.task_id = p_task_id
        AND r.responsible_employee_id = p_responsible_employee_id;
    IF report_id IS NULL THEN RAISE EXCEPTION 'IDEMPOTENCY_KEY_REUSED'; END IF;
  END IF;
  RETURN report_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.restaurant_review_task_report(
  p_branch_id uuid, p_report_id uuid, p_reviewer_id uuid, p_decision text, p_note text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE report_row public.restaurant_task_reports%ROWTYPE; reviewer_role text;
  latest_decision text; task_row public.restaurant_tasks%ROWTYPE; task_completed boolean := false;
BEGIN
  IF p_decision NOT IN ('accepted', 'rejected') THEN RAISE EXCEPTION 'INVALID_REPORT_DECISION'; END IF;
  SELECT m.access_role INTO reviewer_role FROM public.restaurant_memberships m
    WHERE m.branch_id = p_branch_id AND m.user_id = p_reviewer_id AND m.is_active;
  IF reviewer_role IS NULL OR reviewer_role NOT IN ('admin', 'supervisor') THEN RAISE EXCEPTION 'MANAGER_REQUIRED'; END IF;
  SELECT * INTO report_row FROM public.restaurant_task_reports r
    WHERE r.branch_id = p_branch_id AND r.id = p_report_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'TASK_REPORT_NOT_FOUND'; END IF;
  IF report_row.independent_review_required AND report_row.recorded_by = p_reviewer_id THEN
    RAISE EXCEPTION 'INDEPENDENT_REVIEW_REQUIRED';
  END IF;
  SELECT r.decision INTO latest_decision FROM public.restaurant_task_report_reviews r
    WHERE r.branch_id = p_branch_id AND r.report_id = p_report_id
    ORDER BY r.reviewed_at DESC, r.id DESC LIMIT 1;
  IF latest_decision IS NOT NULL THEN RAISE EXCEPTION 'TASK_REPORT_ALREADY_REVIEWED'; END IF;
  INSERT INTO public.restaurant_task_report_reviews(branch_id, report_id, reviewer_id, decision, note)
    VALUES (p_branch_id, p_report_id, p_reviewer_id, p_decision, nullif(pg_catalog.btrim(p_note), ''));
  IF p_decision = 'accepted' THEN
    SELECT * INTO task_row FROM public.restaurant_tasks t
      WHERE t.branch_id = p_branch_id AND t.id = report_row.task_id FOR UPDATE;
    IF report_row.part_id IS NULL THEN
      IF task_row.status = 'completed' THEN RAISE EXCEPTION 'TASK_ALREADY_COMPLETED'; END IF;
      UPDATE public.restaurant_tasks SET status = 'completed', completed_at = now(),
        completed_by = report_row.responsible_employee_id, updated_at = now()
        WHERE branch_id = p_branch_id AND id = report_row.task_id;
      task_completed := true;
    ELSE
      UPDATE public.restaurant_task_parts SET status = 'completed'
        WHERE branch_id = p_branch_id AND id = report_row.part_id AND status <> 'completed';
      IF NOT FOUND THEN RAISE EXCEPTION 'TASK_PART_ALREADY_COMPLETED'; END IF;
      IF NOT EXISTS (SELECT 1 FROM public.restaurant_task_parts p
          WHERE p.branch_id = p_branch_id AND p.task_id = report_row.task_id AND p.status <> 'completed') THEN
        UPDATE public.restaurant_tasks SET status = 'completed', completed_at = now(),
          completed_by = NULL, updated_at = now()
          WHERE branch_id = p_branch_id AND id = report_row.task_id;
        task_completed := true;
      END IF;
    END IF;
    INSERT INTO public.restaurant_task_events(branch_id, task_id, part_id, actor_id,
      client_event_id, event_type, from_status, to_status, note, evidence_path, occurred_at)
    VALUES (p_branch_id, report_row.task_id, report_row.part_id, p_reviewer_id,
      pg_catalog.gen_random_uuid(), 'peer_report_verified', task_row.status,
      CASE WHEN task_completed THEN 'completed' ELSE task_row.status END,
      'Reporte de actividad validado; responsable y registrador conservados por separado.',
      report_row.evidence_path, now());
  END IF;
  RETURN pg_catalog.jsonb_build_object('decision', p_decision,
    'task_completed', task_completed, 'responsible_employee_id', report_row.responsible_employee_id,
    'recorded_by', report_row.recorded_by, 'reviewed_by', p_reviewer_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.restaurant_start_meal(
  p_branch_id uuid, p_employee_id uuid, p_actor_id uuid, p_note text
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE actor_role text; active_session uuid; meal_minutes integer;
BEGIN
  SELECT b.meal_duration_minutes INTO meal_minutes FROM public.restaurant_branches b
    WHERE b.id = p_branch_id AND b.is_active;
  IF meal_minutes IS NULL THEN RAISE EXCEPTION 'MEAL_DURATION_NOT_CONFIGURED'; END IF;
  SELECT m.access_role INTO actor_role FROM public.restaurant_memberships m
    WHERE m.branch_id = p_branch_id AND m.user_id = p_actor_id AND m.is_active;
  IF actor_role IS NULL OR (p_actor_id <> p_employee_id AND actor_role NOT IN ('admin', 'supervisor')) THEN
    RAISE EXCEPTION 'BRANCH_ACCESS_REQUIRED';
  END IF;
  PERFORM 1 FROM public.restaurant_memberships m
    WHERE m.branch_id = p_branch_id AND m.user_id = p_employee_id AND m.is_active FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'EMPLOYEE_NOT_ACTIVE'; END IF;
  IF NOT private.restaurant_member_on_shift_now(p_branch_id, p_employee_id) THEN
    RAISE EXCEPTION 'EMPLOYEE_NOT_ON_SHIFT';
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
  INSERT INTO public.restaurant_meal_sessions(branch_id, employee_id, scheduled_start, scheduled_end, started_by, note)
    VALUES (p_branch_id, p_employee_id, now(), now() + pg_catalog.make_interval(mins => meal_minutes),
      p_actor_id, nullif(pg_catalog.btrim(p_note), ''))
    RETURNING id INTO active_session;
  INSERT INTO public.restaurant_member_operational_states(branch_id, employee_id, state, changed_by, note)
    VALUES (p_branch_id, p_employee_id, 'meal', p_actor_id, 'Comida iniciada')
    ON CONFLICT (branch_id, employee_id) DO UPDATE SET state = 'meal', changed_by = EXCLUDED.changed_by,
      changed_at = now(), note = EXCLUDED.note;
  INSERT INTO public.restaurant_operational_state_events(branch_id, employee_id, state, changed_by, note)
    VALUES (p_branch_id, p_employee_id, 'meal', p_actor_id, 'Comida iniciada');
  INSERT INTO public.restaurant_meal_events(branch_id, meal_session_id, actor_id, event_type)
    VALUES (p_branch_id, active_session, p_actor_id, 'started');
  RETURN active_session;
END;
$$;

CREATE OR REPLACE FUNCTION public.restaurant_confirm_meal_return(
  p_branch_id uuid, p_session_id uuid, p_actor_id uuid, p_state text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE meal_row public.restaurant_meal_sessions%ROWTYPE; actor_role text; final_state text;
BEGIN
  IF p_state NOT IN ('available', 'busy') THEN RAISE EXCEPTION 'INVALID_RETURN_STATE'; END IF;
  SELECT * INTO meal_row FROM public.restaurant_meal_sessions s
    WHERE s.branch_id = p_branch_id AND s.id = p_session_id FOR UPDATE;
  IF NOT FOUND OR meal_row.return_confirmed_at IS NOT NULL THEN RAISE EXCEPTION 'MEAL_NOT_ACTIVE'; END IF;
  SELECT m.access_role INTO actor_role FROM public.restaurant_memberships m
    WHERE m.branch_id = p_branch_id AND m.user_id = p_actor_id AND m.is_active;
  IF actor_role IS NULL OR (p_actor_id <> meal_row.employee_id AND actor_role NOT IN ('admin', 'supervisor')) THEN
    RAISE EXCEPTION 'BRANCH_ACCESS_REQUIRED';
  END IF;
  final_state := CASE WHEN private.restaurant_member_on_shift_now(p_branch_id, meal_row.employee_id)
    THEN p_state ELSE 'off_shift' END;
  UPDATE public.restaurant_meal_sessions SET return_confirmed_at = now(), return_confirmed_by = p_actor_id
    WHERE id = meal_row.id;
  UPDATE public.restaurant_member_operational_states SET state = final_state, changed_by = p_actor_id,
    changed_at = now(), note = CASE WHEN final_state = 'off_shift' THEN 'Regreso confirmado fuera del turno publicado' ELSE 'Regreso de comida confirmado' END
    WHERE branch_id = p_branch_id AND employee_id = meal_row.employee_id;
  INSERT INTO public.restaurant_operational_state_events(branch_id, employee_id, state, changed_by, note)
    VALUES (p_branch_id, meal_row.employee_id, final_state,
      p_actor_id, CASE WHEN final_state = 'off_shift' THEN 'Regreso confirmado fuera del turno publicado' ELSE 'Regreso de comida confirmado' END);
  INSERT INTO public.restaurant_meal_events(branch_id, meal_session_id, actor_id, event_type, details)
    VALUES (p_branch_id, meal_row.id, p_actor_id, 'return_confirmed',
      pg_catalog.jsonb_build_object('state_after_return', final_state));
  RETURN pg_catalog.jsonb_build_object('returned', true, 'state', final_state,
    'employee_id', meal_row.employee_id, 'recorded_by', p_actor_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.restaurant_set_operational_state(
  p_branch_id uuid, p_employee_id uuid, p_actor_id uuid, p_state text, p_note text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE actor_role text; final_state text := p_state; affected_rows integer;
BEGIN
  IF p_state NOT IN ('available', 'occupied', 'rest', 'off_shift') THEN
    RAISE EXCEPTION 'INVALID_OPERATIONAL_STATE';
  END IF;
  SELECT m.access_role INTO actor_role FROM public.restaurant_memberships m
    WHERE m.branch_id = p_branch_id AND m.user_id = p_actor_id AND m.is_active;
  IF actor_role IS NULL OR (p_actor_id <> p_employee_id AND actor_role NOT IN ('admin', 'supervisor')) THEN
    RAISE EXCEPTION 'BRANCH_ACCESS_REQUIRED';
  END IF;
  PERFORM 1 FROM public.restaurant_memberships m
    WHERE m.branch_id = p_branch_id AND m.user_id = p_employee_id AND m.is_active FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'EMPLOYEE_NOT_ACTIVE'; END IF;
  IF p_state IN ('available', 'occupied')
      AND NOT private.restaurant_member_on_shift_now(p_branch_id, p_employee_id) THEN
    final_state := 'off_shift';
  END IF;
  IF final_state IN ('rest', 'off_shift') AND (
      EXISTS (SELECT 1 FROM public.restaurant_tasks t WHERE t.branch_id = p_branch_id
        AND t.assigned_to = p_employee_id AND t.status = 'in_progress')
      OR EXISTS (SELECT 1 FROM public.restaurant_task_parts p WHERE p.branch_id = p_branch_id
        AND p.assigned_to = p_employee_id AND p.status = 'in_progress')) THEN
    RAISE EXCEPTION 'ACTIVE_TASK_REQUIRES_HANDOFF';
  END IF;
  IF EXISTS (SELECT 1 FROM public.restaurant_meal_sessions s WHERE s.branch_id = p_branch_id
      AND s.employee_id = p_employee_id AND s.return_confirmed_at IS NULL) THEN
    RAISE EXCEPTION 'MEAL_RETURN_MUST_BE_CONFIRMED';
  END IF;
  INSERT INTO public.restaurant_member_operational_states(branch_id, employee_id, state, changed_by, note)
    VALUES (p_branch_id, p_employee_id, final_state, p_actor_id, nullif(pg_catalog.btrim(p_note), ''))
    ON CONFLICT (branch_id, employee_id) DO UPDATE SET state = EXCLUDED.state,
      changed_by = EXCLUDED.changed_by, changed_at = now(), note = EXCLUDED.note
      WHERE public.restaurant_member_operational_states.state IS DISTINCT FROM EXCLUDED.state;
  GET DIAGNOSTICS affected_rows = ROW_COUNT;
  IF affected_rows > 0 THEN
    INSERT INTO public.restaurant_operational_state_events(branch_id, employee_id, state, changed_by, note)
      VALUES (p_branch_id, p_employee_id, final_state, p_actor_id, nullif(pg_catalog.btrim(p_note), ''));
  END IF;
  RETURN pg_catalog.jsonb_build_object('employee_id', p_employee_id, 'state', final_state,
    'changed_by', p_actor_id, 'event_recorded', affected_rows > 0);
END;
$$;

CREATE OR REPLACE FUNCTION public.restaurant_decide_meal_plan(
  p_branch_id uuid, p_plan_id uuid, p_actor_id uuid, p_decision text,
  p_schedule jsonb, p_note text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE actor_role text; plan_row public.restaurant_meal_plan_proposals%ROWTYPE;
BEGIN
  IF p_decision NOT IN ('approved', 'modified', 'rejected') THEN RAISE EXCEPTION 'INVALID_PLAN_DECISION'; END IF;
  IF p_decision = 'modified' AND (p_schedule IS NULL OR pg_catalog.jsonb_typeof(p_schedule) <> 'array') THEN
    RAISE EXCEPTION 'MODIFIED_SCHEDULE_REQUIRED';
  END IF;
  SELECT m.access_role INTO actor_role FROM public.restaurant_memberships m
    WHERE m.branch_id = p_branch_id AND m.user_id = p_actor_id AND m.is_active;
  IF actor_role IS NULL OR actor_role NOT IN ('admin', 'supervisor') THEN RAISE EXCEPTION 'MANAGER_REQUIRED'; END IF;
  SELECT * INTO plan_row FROM public.restaurant_meal_plan_proposals p
    WHERE p.branch_id = p_branch_id AND p.id = p_plan_id FOR UPDATE;
  IF NOT FOUND OR plan_row.status <> 'proposed' THEN RAISE EXCEPTION 'MEAL_PLAN_NOT_PENDING'; END IF;
  IF p_decision IN ('approved', 'modified') THEN
    -- Serialize approval against a concurrent employee/manager start_meal call.
    PERFORM m.user_id FROM public.restaurant_memberships m
      JOIN pg_catalog.jsonb_to_recordset(coalesce(p_schedule, plan_row.proposed_schedule))
        AS slot(employee_id uuid, starts_at timestamptz, scheduled_end_at timestamptz, duration_minutes integer)
        ON slot.employee_id = m.user_id
      WHERE m.branch_id = p_branch_id AND m.is_active
      ORDER BY m.user_id FOR UPDATE OF m;
  END IF;
  IF p_decision IN ('approved', 'modified') AND EXISTS (
    SELECT 1 FROM pg_catalog.jsonb_to_recordset(coalesce(p_schedule, plan_row.proposed_schedule))
      AS slot(employee_id uuid, starts_at timestamptz, scheduled_end_at timestamptz, duration_minutes integer)
    WHERE slot.starts_at <= now()
  ) THEN RAISE EXCEPTION 'MEAL_PLAN_EXPIRED'; END IF;
  IF p_decision IN ('approved', 'modified') AND EXISTS (
    SELECT 1 FROM pg_catalog.jsonb_to_recordset(coalesce(p_schedule, plan_row.proposed_schedule))
      AS slot(employee_id uuid, starts_at timestamptz, scheduled_end_at timestamptz, duration_minutes integer)
    JOIN public.restaurant_meal_sessions ms ON ms.branch_id = p_branch_id
      AND ms.employee_id = slot.employee_id
    WHERE ms.started_at >= (plan_row.shift_date::timestamp AT TIME ZONE
      (SELECT b.timezone FROM public.restaurant_branches b WHERE b.id = p_branch_id))
      AND ms.started_at < ((plan_row.shift_date + 1)::timestamp AT TIME ZONE
      (SELECT b.timezone FROM public.restaurant_branches b WHERE b.id = p_branch_id))
  ) THEN RAISE EXCEPTION 'MEAL_ALREADY_TAKEN'; END IF;
  UPDATE public.restaurant_meal_plan_proposals SET status = p_decision,
    approved_schedule = CASE WHEN p_decision = 'rejected' THEN NULL ELSE coalesce(p_schedule, proposed_schedule) END,
    decided_by = p_actor_id, decided_at = now(), decision_note = nullif(pg_catalog.btrim(p_note), '')
    WHERE id = p_plan_id;
  IF p_decision IN ('approved', 'modified') THEN
    INSERT INTO public.restaurant_meal_plan_slots(
      branch_id, plan_id, employee_id, starts_at, scheduled_end_at,
      meal_duration_minutes, decision, approved_by
    )
    SELECT p_branch_id, p_plan_id, slot.employee_id, slot.starts_at, slot.scheduled_end_at,
      slot.duration_minutes, p_decision, p_actor_id
    FROM pg_catalog.jsonb_to_recordset(coalesce(p_schedule, plan_row.proposed_schedule))
      AS slot(employee_id uuid, starts_at timestamptz, scheduled_end_at timestamptz, duration_minutes integer);
  END IF;
  RETURN pg_catalog.jsonb_build_object('status', p_decision, 'decided_by', p_actor_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.restaurant_decide_recommendation(
  p_branch_id uuid, p_recommendation_id uuid, p_actor_id uuid, p_decision text, p_note text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE actor_role text;
BEGIN
  IF p_decision NOT IN ('approved', 'modified', 'rejected') THEN RAISE EXCEPTION 'INVALID_RECOMMENDATION_DECISION'; END IF;
  SELECT m.access_role INTO actor_role FROM public.restaurant_memberships m
    WHERE m.branch_id = p_branch_id AND m.user_id = p_actor_id AND m.is_active;
  IF actor_role IS NULL OR actor_role NOT IN ('admin', 'supervisor') THEN RAISE EXCEPTION 'MANAGER_REQUIRED'; END IF;
  UPDATE public.restaurant_operational_recommendations SET decision = p_decision,
    decided_by = p_actor_id, decided_at = now(), outcome_note = nullif(pg_catalog.btrim(p_note), '')
    WHERE branch_id = p_branch_id AND id = p_recommendation_id AND decision = 'pending';
  IF NOT FOUND THEN RAISE EXCEPTION 'RECOMMENDATION_NOT_PENDING'; END IF;
  RETURN pg_catalog.jsonb_build_object('decision', p_decision, 'decided_by', p_actor_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.restaurant_record_coverage_recommendation(
  p_branch_id uuid, p_actor_id uuid, p_period_start timestamptz, p_period_end timestamptz,
  p_source_data jsonb, p_explanation text, p_suggested_action text
)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE result_id uuid;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.restaurant_memberships m
    WHERE m.branch_id = p_branch_id AND m.user_id = p_actor_id AND m.is_active
      AND m.access_role IN ('admin', 'supervisor')
  ) THEN RAISE EXCEPTION 'MANAGER_REQUIRED'; END IF;
  IF p_period_end <= p_period_start OR pg_catalog.jsonb_typeof(p_source_data) <> 'object'
     OR p_source_data ->> 'analysis' <> 'published_shift_qualified_coverage'
     OR p_source_data ->> 'area_id' IS NULL THEN RAISE EXCEPTION 'INVALID_COVERAGE_RECOMMENDATION'; END IF;
  INSERT INTO public.restaurant_operational_recommendations AS existing (
    branch_id, category, source_period_start, source_period_end, source_data,
    explanation, suggested_action, confidence
  ) VALUES (
    p_branch_id, 'coverage', p_period_start, p_period_end, p_source_data,
    p_explanation, p_suggested_action, NULL
  )
  ON CONFLICT (branch_id, source_period_start, source_period_end, (source_data ->> 'area_id'))
    WHERE category = 'coverage' AND source_data ->> 'analysis' = 'published_shift_qualified_coverage'
  DO UPDATE SET source_data = EXCLUDED.source_data, explanation = EXCLUDED.explanation,
    suggested_action = EXCLUDED.suggested_action
  WHERE existing.decision = 'pending'
  RETURNING id INTO result_id;
  RETURN result_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.restaurant_record_operational_recommendation(
  p_branch_id uuid, p_actor_id uuid, p_category text,
  p_period_start timestamptz, p_period_end timestamptz,
  p_source_data jsonb, p_explanation text, p_suggested_action text
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE result_id uuid; existing_id uuid; fingerprint text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.restaurant_memberships m
      WHERE m.branch_id = p_branch_id AND m.user_id = p_actor_id AND m.is_active
        AND m.access_role IN ('admin', 'supervisor')) THEN RAISE EXCEPTION 'MANAGER_REQUIRED'; END IF;
  IF p_category NOT IN ('workload', 'delay', 'inspection', 'schedule')
    OR p_period_end <= p_period_start
    OR pg_catalog.jsonb_typeof(p_source_data) <> 'object'
    OR p_source_data ->> 'fingerprint' IS NULL
    OR p_source_data ->> 'analysis' IS NULL
    OR pg_catalog.length(p_explanation) NOT BETWEEN 1 AND 2000
    OR pg_catalog.length(p_suggested_action) NOT BETWEEN 1 AND 1000 THEN
    RAISE EXCEPTION 'INVALID_OPERATIONAL_RECOMMENDATION';
  END IF;
  fingerprint := p_source_data ->> 'fingerprint';
  INSERT INTO public.restaurant_operational_recommendations AS existing (
    branch_id, category, source_period_start, source_period_end, source_data,
    explanation, suggested_action, confidence
  ) VALUES (p_branch_id, p_category, p_period_start, p_period_end, p_source_data,
    p_explanation, p_suggested_action, NULL)
  ON CONFLICT (branch_id, category, source_period_start, source_period_end, (source_data ->> 'fingerprint'))
    WHERE source_data ->> 'fingerprint' IS NOT NULL
  DO UPDATE SET source_data = EXCLUDED.source_data, explanation = EXCLUDED.explanation,
    suggested_action = EXCLUDED.suggested_action
  WHERE existing.decision = 'pending'
  RETURNING id INTO result_id;
  IF result_id IS NULL THEN
    SELECT r.id INTO existing_id FROM public.restaurant_operational_recommendations r
      WHERE r.branch_id = p_branch_id AND r.category = p_category
        AND r.source_period_start = p_period_start AND r.source_period_end = p_period_end
        AND r.source_data ->> 'fingerprint' = fingerprint;
    result_id := existing_id;
  END IF;
  RETURN result_id;
END;
$$;

REVOKE ALL ON FUNCTION public.restaurant_record_task_report(uuid, uuid, uuid, uuid, uuid, timestamptz, text, text, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.restaurant_review_task_report(uuid, uuid, uuid, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.restaurant_start_meal(uuid, uuid, uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.restaurant_confirm_meal_return(uuid, uuid, uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.restaurant_set_operational_state(uuid, uuid, uuid, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.restaurant_decide_meal_plan(uuid, uuid, uuid, text, jsonb, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.restaurant_decide_recommendation(uuid, uuid, uuid, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.restaurant_record_coverage_recommendation(uuid, uuid, timestamptz, timestamptz, jsonb, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.restaurant_record_operational_recommendation(uuid, uuid, text, timestamptz, timestamptz, jsonb, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.restaurant_record_task_report(uuid, uuid, uuid, uuid, uuid, timestamptz, text, text, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.restaurant_review_task_report(uuid, uuid, uuid, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.restaurant_start_meal(uuid, uuid, uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.restaurant_confirm_meal_return(uuid, uuid, uuid, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.restaurant_set_operational_state(uuid, uuid, uuid, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.restaurant_decide_meal_plan(uuid, uuid, uuid, text, jsonb, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.restaurant_decide_recommendation(uuid, uuid, uuid, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.restaurant_record_coverage_recommendation(uuid, uuid, timestamptz, timestamptz, jsonb, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.restaurant_record_operational_recommendation(uuid, uuid, text, timestamptz, timestamptz, jsonb, text, text) TO service_role;

-- Shared operational availability is distinct from network presence.
CREATE OR REPLACE FUNCTION private.restaurant_is_branch_manager(p_branch_id uuid, p_user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (SELECT 1 FROM public.restaurant_memberships m
    WHERE m.branch_id = p_branch_id AND m.user_id = p_user_id AND m.is_active
      AND m.access_role IN ('admin', 'supervisor'));
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
      AND NOT EXISTS (SELECT 1 FROM public.restaurant_shift_breaks br
        WHERE br.branch_id = s.branch_id AND br.shift_id = s.id
          AND ((br.start_time < br.end_time AND (now() AT TIME ZONE b.timezone)::time >= br.start_time AND (now() AT TIME ZONE b.timezone)::time < br.end_time)
            OR (br.start_time > br.end_time AND ((now() AT TIME ZONE b.timezone)::time >= br.start_time OR (now() AT TIME ZONE b.timezone)::time < br.end_time))))
      AND NOT EXISTS (SELECT 1 FROM public.restaurant_absences a
        WHERE a.branch_id = m.branch_id AND a.employee_id = m.user_id AND a.status = 'approved'
          AND a.start_date <= (now() AT TIME ZONE b.timezone)::date AND a.end_date >= (now() AT TIME ZONE b.timezone)::date)
      AND NOT EXISTS (SELECT 1 FROM public.restaurant_member_operational_states os
        WHERE os.branch_id = m.branch_id AND os.employee_id = m.user_id AND os.state IN ('meal', 'rest', 'off_shift'))
      AND NOT EXISTS (SELECT 1 FROM public.restaurant_meal_sessions ms
        WHERE ms.branch_id = m.branch_id AND ms.employee_id = m.user_id AND ms.return_confirmed_at IS NULL)
  );
$$;
CREATE OR REPLACE FUNCTION private.restaurant_employee_on_meal_or_rest(p_branch_id uuid, p_employee_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (SELECT 1 FROM public.restaurant_member_operational_states s
    WHERE s.branch_id = p_branch_id AND s.employee_id = p_employee_id AND s.state IN ('meal', 'rest'))
    OR EXISTS (SELECT 1 FROM public.restaurant_meal_sessions s
      WHERE s.branch_id = p_branch_id AND s.employee_id = p_employee_id AND s.return_confirmed_at IS NULL);
$$;
REVOKE ALL ON FUNCTION private.restaurant_is_branch_manager(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.restaurant_member_scheduled_available_now(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.restaurant_employee_on_meal_or_rest(uuid, uuid) FROM PUBLIC, anon, authenticated;
CREATE OR REPLACE FUNCTION private.restaurant_current_user_is_branch_manager(p_branch_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT private.restaurant_is_branch_manager(p_branch_id, auth.uid());
$$;
CREATE OR REPLACE FUNCTION private.restaurant_current_user_scheduled_available_now(p_branch_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT private.restaurant_member_scheduled_available_now(p_branch_id, auth.uid());
$$;
REVOKE ALL ON FUNCTION private.restaurant_current_user_is_branch_manager(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION private.restaurant_current_user_scheduled_available_now(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION private.restaurant_current_user_is_branch_manager(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.restaurant_current_user_scheduled_available_now(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.restaurant_get_available_collaborator_ids(p_branch_id uuid)
RETURNS uuid[] LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT coalesce(pg_catalog.array_agg(m.user_id), ARRAY[]::uuid[])
  FROM public.restaurant_memberships m
  WHERE m.branch_id = p_branch_id AND m.is_active
    AND private.restaurant_member_scheduled_available_now(p_branch_id, m.user_id);
$$;
REVOKE ALL ON FUNCTION public.restaurant_get_available_collaborator_ids(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.restaurant_get_available_collaborator_ids(uuid) TO service_role;

CREATE OR REPLACE FUNCTION private.suppress_unavailable_collaboration_notification()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF NEW.notification_type = 'collaboration_requested'
     AND NOT private.restaurant_member_scheduled_available_now(NEW.branch_id, NEW.recipient_id) THEN
    RETURN NULL;
  END IF;
  IF NEW.notification_type IN ('task_assigned', 'task_part_assigned', 'incident_assigned', 'incident_reported')
     AND private.restaurant_employee_on_meal_or_rest(NEW.branch_id, NEW.recipient_id) THEN
    RETURN NULL;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER restaurant_suppress_unavailable_collaboration_notification
  BEFORE INSERT ON public.restaurant_notifications
  FOR EACH ROW EXECUTE FUNCTION private.suppress_unavailable_collaboration_notification();
REVOKE ALL ON FUNCTION private.suppress_unavailable_collaboration_notification() FROM PUBLIC, anon, authenticated;

-- Keep direct Postgres/Realtime reads aligned with the role-specific Edge API.
DROP POLICY restaurant_task_receipts_member_read ON public.restaurant_task_receipts;
CREATE POLICY restaurant_task_receipts_member_read ON public.restaurant_task_receipts
  FOR SELECT TO authenticated USING (private.restaurant_has_access(branch_id)
    AND (employee_id = auth.uid() OR private.restaurant_current_user_is_branch_manager(branch_id)));

DROP POLICY restaurant_collaboration_requests_member_read ON public.restaurant_collaboration_requests;
CREATE POLICY restaurant_collaboration_requests_member_read ON public.restaurant_collaboration_requests
  FOR SELECT TO authenticated USING (private.restaurant_has_access(branch_id)
    AND (status = 'resolved' OR private.restaurant_current_user_is_branch_manager(branch_id)
      OR private.restaurant_current_user_scheduled_available_now(branch_id)));
DROP POLICY restaurant_collaboration_events_member_read ON public.restaurant_collaboration_events;
CREATE POLICY restaurant_collaboration_events_member_read ON public.restaurant_collaboration_events
  FOR SELECT TO authenticated USING (private.restaurant_has_access(branch_id)
    AND (private.restaurant_current_user_is_branch_manager(branch_id)
      OR private.restaurant_current_user_scheduled_available_now(branch_id)));

DROP POLICY restaurant_operational_states_branch_read ON public.restaurant_member_operational_states;
CREATE POLICY restaurant_operational_states_branch_read ON public.restaurant_member_operational_states
  FOR SELECT TO authenticated USING (private.restaurant_has_access(branch_id)
    AND (employee_id = auth.uid() OR private.restaurant_current_user_is_branch_manager(branch_id)));
DROP POLICY restaurant_meal_sessions_branch_read ON public.restaurant_meal_sessions;
CREATE POLICY restaurant_meal_sessions_branch_read ON public.restaurant_meal_sessions
  FOR SELECT TO authenticated USING (private.restaurant_has_access(branch_id)
    AND (employee_id = auth.uid() OR private.restaurant_current_user_is_branch_manager(branch_id)));
DROP POLICY restaurant_meal_events_branch_read ON public.restaurant_meal_events;
CREATE POLICY restaurant_meal_events_branch_read ON public.restaurant_meal_events
  FOR SELECT TO authenticated USING (private.restaurant_has_access(branch_id)
    AND (EXISTS (SELECT 1 FROM public.restaurant_meal_sessions ms
      WHERE ms.branch_id = restaurant_meal_events.branch_id AND ms.id = restaurant_meal_events.meal_session_id
        AND ms.employee_id = auth.uid()) OR private.restaurant_current_user_is_branch_manager(branch_id)));
DROP POLICY restaurant_task_reports_branch_read ON public.restaurant_task_reports;
CREATE POLICY restaurant_task_reports_branch_read ON public.restaurant_task_reports
  FOR SELECT TO authenticated USING (private.restaurant_has_access(branch_id)
    AND (responsible_employee_id = auth.uid() OR recorded_by = auth.uid()
      OR private.restaurant_current_user_is_branch_manager(branch_id)));
DROP POLICY restaurant_task_report_reviews_branch_read ON public.restaurant_task_report_reviews;
CREATE POLICY restaurant_task_report_reviews_branch_read ON public.restaurant_task_report_reviews
  FOR SELECT TO authenticated USING (private.restaurant_has_access(branch_id)
    AND (private.restaurant_current_user_is_branch_manager(branch_id) OR EXISTS (
      SELECT 1 FROM public.restaurant_task_reports r
      WHERE r.branch_id = restaurant_task_report_reviews.branch_id AND r.id = restaurant_task_report_reviews.report_id
        AND (r.responsible_employee_id = auth.uid() OR r.recorded_by = auth.uid()))));
DROP POLICY restaurant_meal_plan_branch_read ON public.restaurant_meal_plan_proposals;
CREATE POLICY restaurant_meal_plan_branch_read ON public.restaurant_meal_plan_proposals
  FOR SELECT TO authenticated USING (private.restaurant_has_access(branch_id)
    AND private.restaurant_current_user_is_branch_manager(branch_id));
DROP POLICY restaurant_recommendations_branch_read ON public.restaurant_operational_recommendations;
CREATE POLICY restaurant_recommendations_branch_read ON public.restaurant_operational_recommendations
  FOR SELECT TO authenticated USING (private.restaurant_has_access(branch_id)
    AND private.restaurant_current_user_is_branch_manager(branch_id));

DO $$
DECLARE table_name text;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_catalog.pg_publication WHERE pubname = 'supabase_realtime') THEN
    FOREACH table_name IN ARRAY ARRAY[
      'restaurant_member_operational_states', 'restaurant_operational_state_events', 'restaurant_meal_sessions', 'restaurant_meal_events',
      'restaurant_task_reports', 'restaurant_task_report_reviews', 'restaurant_meal_plan_proposals',
      'restaurant_meal_plan_slots', 'restaurant_operational_recommendations'
    ] LOOP
      IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_publication_tables
          WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = table_name) THEN
        EXECUTE pg_catalog.format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', table_name);
      END IF;
    END LOOP;
  END IF;
END;
$$;
