-- Pollo Móvil operational domain. This is additive to the FieldOps base schema.
CREATE SCHEMA IF NOT EXISTS private;

CREATE TABLE public.restaurant_branches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE RESTRICT,
  name text NOT NULL,
  timezone text NOT NULL,
  enable_time_clock boolean NOT NULL DEFAULT false,
  require_gps_for_time_clock boolean NOT NULL DEFAULT false,
  is_active boolean NOT NULL DEFAULT true,
  created_by uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (company_id, name),
  UNIQUE (company_id, id),
  CHECK (NOT require_gps_for_time_clock OR enable_time_clock)
);

CREATE TABLE public.restaurant_areas (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid NOT NULL REFERENCES public.restaurant_branches(id) ON DELETE CASCADE,
  name text NOT NULL,
  sort_order integer NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (branch_id, name),
  UNIQUE (branch_id, id)
);

CREATE TABLE public.restaurant_positions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid NOT NULL REFERENCES public.restaurant_branches(id) ON DELETE CASCADE,
  name text NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (branch_id, name),
  UNIQUE (branch_id, id)
);

CREATE TABLE public.restaurant_memberships (
  branch_id uuid NOT NULL REFERENCES public.restaurant_branches(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE RESTRICT,
  user_id uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  access_role text NOT NULL CHECK (access_role IN ('admin', 'supervisor', 'employee')),
  is_active boolean NOT NULL DEFAULT true,
  customer_service_active boolean NOT NULL DEFAULT false,
  created_by uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (branch_id, user_id),
  FOREIGN KEY (company_id, branch_id)
    REFERENCES public.restaurant_branches(company_id, id) ON DELETE CASCADE
);

CREATE TABLE public.restaurant_member_positions (
  branch_id uuid NOT NULL,
  user_id uuid NOT NULL,
  position_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (branch_id, user_id, position_id),
  FOREIGN KEY (branch_id, user_id)
    REFERENCES public.restaurant_memberships(branch_id, user_id) ON DELETE CASCADE,
  FOREIGN KEY (branch_id, position_id)
    REFERENCES public.restaurant_positions(branch_id, id) ON DELETE CASCADE
);

-- Optional attendance records. GPS is event-only; this model has no background tracking.
CREATE TABLE public.restaurant_time_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid NOT NULL REFERENCES public.restaurant_branches(id) ON DELETE CASCADE,
  employee_id uuid NOT NULL,
  clock_in_at timestamptz NOT NULL,
  clock_out_at timestamptz,
  clock_in_latitude numeric(9,6),
  clock_in_longitude numeric(9,6),
  clock_in_accuracy_m numeric(8,2),
  clock_out_latitude numeric(9,6),
  clock_out_longitude numeric(9,6),
  clock_out_accuracy_m numeric(8,2),
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (clock_out_at IS NULL OR clock_out_at >= clock_in_at),
  CHECK (clock_in_latitude IS NULL OR clock_in_latitude BETWEEN -90 AND 90),
  CHECK (clock_in_longitude IS NULL OR clock_in_longitude BETWEEN -180 AND 180),
  CHECK (clock_out_latitude IS NULL OR clock_out_latitude BETWEEN -90 AND 90),
  CHECK (clock_out_longitude IS NULL OR clock_out_longitude BETWEEN -180 AND 180),
  FOREIGN KEY (branch_id, employee_id)
    REFERENCES public.restaurant_memberships(branch_id, user_id) ON DELETE CASCADE,
  UNIQUE (branch_id, id)
);
CREATE UNIQUE INDEX restaurant_one_active_time_session
  ON public.restaurant_time_sessions(branch_id, employee_id) WHERE clock_out_at IS NULL;

CREATE TABLE public.restaurant_time_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid NOT NULL,
  session_id uuid NOT NULL,
  actor_id uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  client_event_id uuid NOT NULL UNIQUE,
  event_type text NOT NULL CHECK (event_type IN ('clock_in', 'clock_out')),
  occurred_at timestamptz NOT NULL,
  received_at timestamptz NOT NULL DEFAULT now(),
  latitude numeric(9,6),
  longitude numeric(9,6),
  accuracy_m numeric(8,2),
  CHECK (latitude IS NULL OR latitude BETWEEN -90 AND 90),
  CHECK (longitude IS NULL OR longitude BETWEEN -180 AND 180),
  FOREIGN KEY (branch_id, session_id)
    REFERENCES public.restaurant_time_sessions(branch_id, id) ON DELETE CASCADE
);

CREATE TABLE public.restaurant_shifts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid NOT NULL REFERENCES public.restaurant_branches(id) ON DELETE CASCADE,
  employee_id uuid NOT NULL,
  shift_date date NOT NULL,
  start_time time NOT NULL,
  end_time time NOT NULL,
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'published')),
  created_by uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (start_time <> end_time),
  FOREIGN KEY (branch_id, employee_id)
    REFERENCES public.restaurant_memberships(branch_id, user_id) ON DELETE CASCADE,
  UNIQUE (branch_id, employee_id, shift_date, start_time, end_time),
  UNIQUE (branch_id, id)
);

CREATE TABLE public.restaurant_shift_breaks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid NOT NULL,
  shift_id uuid NOT NULL,
  start_time time NOT NULL,
  end_time time NOT NULL,
  CHECK (start_time <> end_time),
  FOREIGN KEY (branch_id, shift_id)
    REFERENCES public.restaurant_shifts(branch_id, id) ON DELETE CASCADE
);

CREATE TABLE public.restaurant_absences (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid NOT NULL REFERENCES public.restaurant_branches(id) ON DELETE CASCADE,
  employee_id uuid NOT NULL,
  start_date date NOT NULL,
  end_date date NOT NULL,
  status text NOT NULL CHECK (status IN ('pending', 'approved', 'denied')),
  note text,
  created_by uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (end_date >= start_date),
  FOREIGN KEY (branch_id, employee_id)
    REFERENCES public.restaurant_memberships(branch_id, user_id) ON DELETE CASCADE
);

CREATE TABLE public.restaurant_waste_bins (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid NOT NULL REFERENCES public.restaurant_branches(id) ON DELETE CASCADE,
  name text NOT NULL,
  sort_order integer NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true,
  inspection_interval_minutes integer CHECK (inspection_interval_minutes IS NULL OR inspection_interval_minutes > 0),
  bag_change_activity_name text,
  bag_change_minutes integer,
  bag_change_difficulty smallint,
  bag_change_priority smallint,
  last_state text CHECK (last_state IS NULL OR last_state IN ('low', 'half', 'full')),
  last_inspected_at timestamptz,
  last_bag_changed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (branch_id, name),
  UNIQUE (branch_id, id)
);

CREATE TABLE public.restaurant_activity_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid NOT NULL REFERENCES public.restaurant_branches(id) ON DELETE CASCADE,
  area_id uuid,
  name text NOT NULL,
  description text,
  activity_type text NOT NULL CHECK (activity_type IN ('scheduled', 'conditional', 'corrective')),
  schedule_days smallint[] NOT NULL DEFAULT '{}',
  estimated_minutes integer NOT NULL CHECK (estimated_minutes > 0),
  difficulty smallint NOT NULL CHECK (difficulty BETWEEN 1 AND 5),
  priority smallint NOT NULL CHECK (priority BETWEEN 1 AND 5),
  is_divisible boolean NOT NULL DEFAULT false,
  interruptible boolean NOT NULL DEFAULT true,
  requires_evidence boolean NOT NULL DEFAULT false,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (activity_type <> 'scheduled' OR cardinality(schedule_days) > 0),
  CHECK (schedule_days <@ ARRAY[1,2,3,4,5,6,7]::smallint[]),
  FOREIGN KEY (branch_id, area_id)
    REFERENCES public.restaurant_areas(branch_id, id) ON DELETE SET NULL (area_id),
  UNIQUE (branch_id, id),
  UNIQUE (branch_id, name)
);

CREATE TABLE public.restaurant_activity_positions (
  branch_id uuid NOT NULL,
  activity_template_id uuid NOT NULL,
  position_id uuid NOT NULL,
  PRIMARY KEY (activity_template_id, position_id),
  FOREIGN KEY (branch_id, activity_template_id)
    REFERENCES public.restaurant_activity_templates(branch_id, id) ON DELETE CASCADE,
  FOREIGN KEY (branch_id, position_id)
    REFERENCES public.restaurant_positions(branch_id, id) ON DELETE CASCADE
);

CREATE TABLE public.restaurant_waste_positions (
  branch_id uuid NOT NULL,
  position_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (branch_id, position_id),
  FOREIGN KEY (branch_id, position_id)
    REFERENCES public.restaurant_positions(branch_id, id) ON DELETE CASCADE
);

CREATE TABLE public.restaurant_activity_zones (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid NOT NULL,
  activity_template_id uuid NOT NULL,
  name text NOT NULL,
  estimated_minutes integer NOT NULL CHECK (estimated_minutes > 0),
  difficulty smallint NOT NULL CHECK (difficulty BETWEEN 1 AND 5),
  sort_order integer NOT NULL DEFAULT 0,
  FOREIGN KEY (branch_id, activity_template_id)
    REFERENCES public.restaurant_activity_templates(branch_id, id) ON DELETE CASCADE,
  UNIQUE (activity_template_id, name),
  UNIQUE (branch_id, id)
);

CREATE TABLE public.restaurant_tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid NOT NULL REFERENCES public.restaurant_branches(id) ON DELETE CASCADE,
  activity_template_id uuid,
  area_id uuid,
  waste_bin_id uuid,
  source_event_id uuid,
  scheduled_for date NOT NULL,
  task_source text NOT NULL DEFAULT 'scheduled' CHECK (task_source IN ('scheduled', 'conditional', 'corrective', 'waste')),
  name text NOT NULL,
  description text,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'in_progress', 'paused', 'blocked', 'completed')),
  assigned_to uuid,
  estimated_minutes integer NOT NULL CHECK (estimated_minutes > 0),
  difficulty smallint NOT NULL CHECK (difficulty BETWEEN 1 AND 5),
  priority smallint NOT NULL CHECK (priority BETWEEN 1 AND 5),
  requires_evidence boolean NOT NULL DEFAULT false,
  started_at timestamptz,
  paused_at timestamptz,
  completed_at timestamptz,
  completed_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
  created_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (branch_id, activity_template_id)
    REFERENCES public.restaurant_activity_templates(branch_id, id) ON DELETE SET NULL (activity_template_id),
  FOREIGN KEY (branch_id, area_id)
    REFERENCES public.restaurant_areas(branch_id, id) ON DELETE SET NULL (area_id),
  FOREIGN KEY (branch_id, waste_bin_id)
    REFERENCES public.restaurant_waste_bins(branch_id, id) ON DELETE SET NULL (waste_bin_id),
  FOREIGN KEY (branch_id, assigned_to)
    REFERENCES public.restaurant_memberships(branch_id, user_id) ON DELETE SET NULL (assigned_to),
  UNIQUE (branch_id, id),
  CHECK (source_event_id IS NULL OR task_source <> 'scheduled')
);

CREATE TABLE public.restaurant_task_parts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid NOT NULL,
  task_id uuid NOT NULL,
  zone_id uuid NOT NULL,
  assigned_to uuid,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'in_progress', 'paused', 'blocked', 'completed')),
  estimated_minutes integer NOT NULL CHECK (estimated_minutes > 0),
  difficulty smallint NOT NULL CHECK (difficulty BETWEEN 1 AND 5),
  started_at timestamptz,
  paused_at timestamptz,
  completed_at timestamptz,
  completed_by uuid REFERENCES public.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (branch_id, task_id)
    REFERENCES public.restaurant_tasks(branch_id, id) ON DELETE CASCADE,
  FOREIGN KEY (branch_id, zone_id)
    REFERENCES public.restaurant_activity_zones(branch_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (branch_id, assigned_to)
    REFERENCES public.restaurant_memberships(branch_id, user_id) ON DELETE SET NULL (assigned_to),
  UNIQUE (task_id, zone_id),
  UNIQUE (branch_id, id)
);

CREATE TABLE public.restaurant_task_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid NOT NULL,
  task_id uuid NOT NULL,
  part_id uuid,
  actor_id uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  client_event_id uuid NOT NULL,
  event_type text NOT NULL,
  from_status text,
  to_status text,
  note text,
  evidence_path text,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (branch_id, task_id)
    REFERENCES public.restaurant_tasks(branch_id, id) ON DELETE CASCADE,
  FOREIGN KEY (branch_id, part_id)
    REFERENCES public.restaurant_task_parts(branch_id, id) ON DELETE CASCADE,
  UNIQUE (branch_id, actor_id, client_event_id)
);

CREATE TABLE public.restaurant_waste_inspections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid NOT NULL REFERENCES public.restaurant_branches(id) ON DELETE CASCADE,
  inspector_id uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  client_event_id uuid NOT NULL,
  inspected_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (branch_id, client_event_id),
  UNIQUE (branch_id, id)
);

CREATE TABLE public.restaurant_waste_inspection_results (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid NOT NULL,
  inspection_id uuid NOT NULL,
  bin_id uuid NOT NULL,
  declared_state text NOT NULL CHECK (declared_state IN ('low', 'half', 'full')),
  FOREIGN KEY (branch_id, inspection_id)
    REFERENCES public.restaurant_waste_inspections(branch_id, id) ON DELETE CASCADE,
  FOREIGN KEY (branch_id, bin_id)
    REFERENCES public.restaurant_waste_bins(branch_id, id) ON DELETE RESTRICT,
  UNIQUE (inspection_id, bin_id)
);

CREATE TABLE public.restaurant_incidents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid NOT NULL REFERENCES public.restaurant_branches(id) ON DELETE CASCADE,
  area_id uuid,
  description text NOT NULL CHECK (length(trim(description)) BETWEEN 3 AND 1000),
  urgency text NOT NULL DEFAULT 'normal' CHECK (urgency IN ('low', 'normal', 'high', 'urgent')),
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'in_progress', 'resolved')),
  is_blocking boolean NOT NULL DEFAULT false,
  assigned_to uuid,
  reported_by uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  client_event_id uuid,
  resolved_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (branch_id, area_id)
    REFERENCES public.restaurant_areas(branch_id, id) ON DELETE SET NULL (area_id),
  FOREIGN KEY (branch_id, assigned_to)
    REFERENCES public.restaurant_memberships(branch_id, user_id) ON DELETE SET NULL (assigned_to),
  UNIQUE (branch_id, id)
);

CREATE TABLE public.restaurant_incident_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid NOT NULL,
  incident_id uuid NOT NULL,
  actor_id uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  event_type text NOT NULL,
  note text,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (branch_id, incident_id)
    REFERENCES public.restaurant_incidents(branch_id, id) ON DELETE CASCADE
);

CREATE TABLE public.restaurant_evidence (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  branch_id uuid NOT NULL,
  task_id uuid NOT NULL,
  part_id uuid,
  uploaded_by uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  object_path text NOT NULL UNIQUE,
  mime_type text NOT NULL CHECK (mime_type IN ('image/jpeg', 'image/png', 'image/webp')),
  file_size_bytes bigint NOT NULL CHECK (file_size_bytes BETWEEN 1 AND 10485760),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (branch_id, task_id)
    REFERENCES public.restaurant_tasks(branch_id, id) ON DELETE CASCADE,
  FOREIGN KEY (branch_id, part_id)
    REFERENCES public.restaurant_task_parts(branch_id, id) ON DELETE CASCADE
);

CREATE INDEX restaurant_memberships_user_idx ON public.restaurant_memberships(user_id, branch_id) WHERE is_active;
CREATE INDEX restaurant_member_positions_user_idx ON public.restaurant_member_positions(branch_id, user_id);
CREATE INDEX restaurant_shifts_window_idx ON public.restaurant_shifts(branch_id, shift_date, status);
CREATE INDEX restaurant_absences_window_idx ON public.restaurant_absences(branch_id, employee_id, start_date, end_date) WHERE status = 'approved';
CREATE INDEX restaurant_tasks_daily_idx ON public.restaurant_tasks(branch_id, scheduled_for, status, priority DESC);
CREATE UNIQUE INDEX restaurant_tasks_schedule_once
  ON public.restaurant_tasks(branch_id, activity_template_id, scheduled_for)
  WHERE task_source = 'scheduled' AND activity_template_id IS NOT NULL;
CREATE UNIQUE INDEX restaurant_tasks_source_event_once
  ON public.restaurant_tasks(branch_id, source_event_id) WHERE source_event_id IS NOT NULL;
CREATE INDEX restaurant_time_sessions_employee_idx ON public.restaurant_time_sessions(branch_id, employee_id, clock_in_at DESC);
CREATE INDEX restaurant_task_parts_assignee_idx ON public.restaurant_task_parts(branch_id, assigned_to, status);
CREATE INDEX restaurant_incidents_open_idx ON public.restaurant_incidents(branch_id, status, urgency DESC) WHERE status <> 'resolved';
CREATE UNIQUE INDEX restaurant_incidents_client_event_unique
  ON public.restaurant_incidents(branch_id, reported_by, client_event_id) WHERE client_event_id IS NOT NULL;
CREATE UNIQUE INDEX restaurant_one_open_waste_task_per_bin
  ON public.restaurant_tasks(branch_id, waste_bin_id)
  WHERE task_source = 'waste' AND waste_bin_id IS NOT NULL AND status <> 'completed';

CREATE TRIGGER restaurant_branches_updated_at BEFORE UPDATE ON public.restaurant_branches
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER restaurant_templates_updated_at BEFORE UPDATE ON public.restaurant_activity_templates
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER restaurant_tasks_updated_at BEFORE UPDATE ON public.restaurant_tasks
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER restaurant_incidents_updated_at BEFORE UPDATE ON public.restaurant_incidents
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE OR REPLACE FUNCTION private.restaurant_user_role(p_branch_id uuid, p_user_id uuid DEFAULT auth.uid())
RETURNS text
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
  SELECT m.access_role
  FROM public.restaurant_memberships AS m
  WHERE m.branch_id = p_branch_id
    AND m.user_id = p_user_id
    AND m.is_active
$$;

CREATE OR REPLACE FUNCTION private.restaurant_has_access(p_branch_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
  SELECT private.restaurant_user_role(p_branch_id, (SELECT auth.uid())) IS NOT NULL
$$;

CREATE OR REPLACE FUNCTION private.restaurant_can_manage(p_branch_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
STABLE
AS $$
  SELECT private.restaurant_user_role(p_branch_id, (SELECT auth.uid())) IN ('admin', 'supervisor')
$$;

CREATE OR REPLACE FUNCTION private.restaurant_can_access_evidence(p_branch_id uuid, p_task_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT private.restaurant_can_manage(p_branch_id)
    OR EXISTS (
      SELECT 1 FROM public.restaurant_tasks task
      WHERE task.branch_id = p_branch_id AND task.id = p_task_id
        AND task.requires_evidence AND task.assigned_to = (SELECT auth.uid())
    )
    OR EXISTS (
      SELECT 1 FROM public.restaurant_task_parts part
      JOIN public.restaurant_tasks task ON task.branch_id = part.branch_id AND task.id = part.task_id
      WHERE part.branch_id = p_branch_id AND part.task_id = p_task_id
        AND task.requires_evidence AND part.assigned_to = (SELECT auth.uid())
    );
$$;

REVOKE ALL ON FUNCTION private.restaurant_user_role(uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION private.restaurant_has_access(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION private.restaurant_can_manage(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION private.restaurant_can_access_evidence(uuid, uuid) FROM PUBLIC, anon;
GRANT USAGE ON SCHEMA private TO authenticated;
GRANT EXECUTE ON FUNCTION private.restaurant_has_access(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.restaurant_can_manage(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION private.restaurant_can_access_evidence(uuid, uuid) TO authenticated;
GRANT USAGE ON SCHEMA private TO service_role;
GRANT EXECUTE ON FUNCTION private.restaurant_user_role(uuid, uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.record_restaurant_time_event(
  p_branch_id uuid,
  p_actor_id uuid,
  p_client_event_id uuid,
  p_event_type text,
  p_occurred_at timestamptz,
  p_latitude numeric DEFAULT NULL,
  p_longitude numeric DEFAULT NULL,
  p_accuracy_m numeric DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  branch_row public.restaurant_branches%ROWTYPE;
  session_row public.restaurant_time_sessions%ROWTYPE;
  existing_event public.restaurant_time_events%ROWTYPE;
  gps_latitude numeric;
  gps_longitude numeric;
  gps_accuracy numeric;
BEGIN
  IF private.restaurant_user_role(p_branch_id, p_actor_id) IS NULL THEN
    RAISE EXCEPTION 'BRANCH_ACCESS_REQUIRED';
  END IF;
  SELECT * INTO branch_row FROM public.restaurant_branches WHERE id = p_branch_id AND is_active;
  IF branch_row.id IS NULL THEN RAISE EXCEPTION 'BRANCH_NOT_FOUND'; END IF;
  IF NOT branch_row.enable_time_clock THEN RAISE EXCEPTION 'TIME_CLOCK_DISABLED'; END IF;
  IF p_event_type NOT IN ('clock_in', 'clock_out') OR p_occurred_at IS NULL THEN
    RAISE EXCEPTION 'INVALID_TIME_EVENT';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_branch_id::text || p_actor_id::text, 0)
  );
  SELECT * INTO existing_event FROM public.restaurant_time_events
  WHERE client_event_id = p_client_event_id;
  IF existing_event.id IS NOT NULL THEN
    IF existing_event.branch_id <> p_branch_id OR existing_event.actor_id <> p_actor_id
      OR existing_event.event_type <> p_event_type THEN RAISE EXCEPTION 'IDEMPOTENCY_KEY_REUSED'; END IF;
    RETURN jsonb_build_object('session_id', existing_event.session_id, 'event_type', existing_event.event_type, 'duplicate', true);
  END IF;

  IF branch_row.require_gps_for_time_clock THEN
    IF p_latitude IS NULL OR p_longitude IS NULL
      OR p_latitude NOT BETWEEN -90 AND 90 OR p_longitude NOT BETWEEN -180 AND 180
      OR p_accuracy_m IS NULL OR p_accuracy_m < 0 THEN RAISE EXCEPTION 'GPS_REQUIRED'; END IF;
    gps_latitude := p_latitude;
    gps_longitude := p_longitude;
    gps_accuracy := p_accuracy_m;
  END IF;

  IF p_event_type = 'clock_in' THEN
    IF EXISTS (SELECT 1 FROM public.restaurant_time_sessions
      WHERE branch_id = p_branch_id AND employee_id = p_actor_id AND clock_out_at IS NULL) THEN
      RAISE EXCEPTION 'ACTIVE_TIME_SESSION';
    END IF;
    INSERT INTO public.restaurant_time_sessions(
      branch_id, employee_id, clock_in_at, clock_in_latitude, clock_in_longitude, clock_in_accuracy_m
    ) VALUES (
      p_branch_id, p_actor_id, p_occurred_at, gps_latitude, gps_longitude, gps_accuracy
    ) RETURNING * INTO session_row;
  ELSE
    SELECT * INTO session_row FROM public.restaurant_time_sessions
    WHERE branch_id = p_branch_id AND employee_id = p_actor_id AND clock_out_at IS NULL
    FOR UPDATE;
    IF session_row.id IS NULL THEN RAISE EXCEPTION 'NO_ACTIVE_TIME_SESSION'; END IF;
    IF p_occurred_at < session_row.clock_in_at THEN RAISE EXCEPTION 'INVALID_TIME_EVENT'; END IF;
    UPDATE public.restaurant_time_sessions SET
      clock_out_at = p_occurred_at, clock_out_latitude = gps_latitude,
      clock_out_longitude = gps_longitude, clock_out_accuracy_m = gps_accuracy
    WHERE id = session_row.id RETURNING * INTO session_row;
  END IF;

  INSERT INTO public.restaurant_time_events(
    branch_id, session_id, actor_id, client_event_id, event_type,
    occurred_at, latitude, longitude, accuracy_m
  ) VALUES (
    p_branch_id, session_row.id, p_actor_id, p_client_event_id, p_event_type,
    p_occurred_at, gps_latitude, gps_longitude, gps_accuracy
  );
  RETURN jsonb_build_object(
    'session_id', session_row.id, 'event_type', p_event_type,
    'clock_in_at', session_row.clock_in_at, 'clock_out_at', session_row.clock_out_at,
    'duplicate', false
  );
END;
$$;

REVOKE ALL ON FUNCTION public.record_restaurant_time_event(uuid, uuid, uuid, text, timestamptz, numeric, numeric, numeric) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_restaurant_time_event(uuid, uuid, uuid, text, timestamptz, numeric, numeric, numeric) TO service_role;

DO $$
DECLARE
  table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'restaurant_branches', 'restaurant_areas', 'restaurant_positions',
    'restaurant_memberships', 'restaurant_member_positions', 'restaurant_shifts',
    'restaurant_time_sessions', 'restaurant_time_events',
    'restaurant_shift_breaks', 'restaurant_absences', 'restaurant_waste_bins',
    'restaurant_activity_templates', 'restaurant_activity_positions',
    'restaurant_activity_zones', 'restaurant_waste_positions', 'restaurant_tasks', 'restaurant_task_parts',
    'restaurant_task_events', 'restaurant_waste_inspections',
    'restaurant_waste_inspection_results', 'restaurant_incidents',
    'restaurant_incident_events', 'restaurant_evidence'
  ] LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', table_name);
    EXECUTE format('REVOKE ALL ON TABLE public.%I FROM anon, authenticated', table_name);
    EXECUTE format('GRANT SELECT ON TABLE public.%I TO authenticated', table_name);
    EXECUTE format('GRANT ALL ON TABLE public.%I TO service_role', table_name);
  END LOOP;
END $$;

CREATE POLICY restaurant_branches_member_read ON public.restaurant_branches
  FOR SELECT TO authenticated USING (private.restaurant_has_access(id));
CREATE POLICY restaurant_areas_member_read ON public.restaurant_areas
  FOR SELECT TO authenticated USING (private.restaurant_has_access(branch_id));
CREATE POLICY restaurant_positions_member_read ON public.restaurant_positions
  FOR SELECT TO authenticated USING (private.restaurant_has_access(branch_id));
CREATE POLICY restaurant_memberships_member_read ON public.restaurant_memberships
  FOR SELECT TO authenticated USING (private.restaurant_has_access(branch_id));
CREATE POLICY restaurant_member_positions_member_read ON public.restaurant_member_positions
  FOR SELECT TO authenticated USING (private.restaurant_has_access(branch_id));
CREATE POLICY restaurant_time_sessions_member_read ON public.restaurant_time_sessions
  FOR SELECT TO authenticated USING (
    employee_id = (SELECT auth.uid()) OR private.restaurant_can_manage(branch_id)
  );
CREATE POLICY restaurant_time_events_member_read ON public.restaurant_time_events
  FOR SELECT TO authenticated USING (
    actor_id = (SELECT auth.uid()) OR private.restaurant_can_manage(branch_id)
  );
CREATE POLICY restaurant_shifts_member_read ON public.restaurant_shifts
  FOR SELECT TO authenticated USING (private.restaurant_has_access(branch_id));
CREATE POLICY restaurant_shift_breaks_member_read ON public.restaurant_shift_breaks
  FOR SELECT TO authenticated USING (private.restaurant_has_access(branch_id));
CREATE POLICY restaurant_absences_manager_read ON public.restaurant_absences
  FOR SELECT TO authenticated USING (private.restaurant_can_manage(branch_id));
CREATE POLICY restaurant_waste_bins_member_read ON public.restaurant_waste_bins
  FOR SELECT TO authenticated USING (private.restaurant_has_access(branch_id));
CREATE POLICY restaurant_activity_templates_member_read ON public.restaurant_activity_templates
  FOR SELECT TO authenticated USING (private.restaurant_has_access(branch_id));
CREATE POLICY restaurant_activity_positions_member_read ON public.restaurant_activity_positions
  FOR SELECT TO authenticated USING (private.restaurant_has_access(branch_id));
CREATE POLICY restaurant_activity_zones_member_read ON public.restaurant_activity_zones
  FOR SELECT TO authenticated USING (private.restaurant_has_access(branch_id));
CREATE POLICY restaurant_waste_positions_manager_read ON public.restaurant_waste_positions
  FOR SELECT TO authenticated USING (private.restaurant_can_manage(branch_id));
CREATE POLICY restaurant_tasks_member_read ON public.restaurant_tasks
  FOR SELECT TO authenticated USING (private.restaurant_has_access(branch_id));
CREATE POLICY restaurant_task_parts_member_read ON public.restaurant_task_parts
  FOR SELECT TO authenticated USING (private.restaurant_has_access(branch_id));
CREATE POLICY restaurant_task_events_member_read ON public.restaurant_task_events
  FOR SELECT TO authenticated USING (private.restaurant_has_access(branch_id));
CREATE POLICY restaurant_waste_inspections_member_read ON public.restaurant_waste_inspections
  FOR SELECT TO authenticated USING (private.restaurant_has_access(branch_id));
CREATE POLICY restaurant_waste_results_member_read ON public.restaurant_waste_inspection_results
  FOR SELECT TO authenticated USING (private.restaurant_has_access(branch_id));
CREATE POLICY restaurant_incidents_member_read ON public.restaurant_incidents
  FOR SELECT TO authenticated USING (private.restaurant_has_access(branch_id));
CREATE POLICY restaurant_incident_events_member_read ON public.restaurant_incident_events
  FOR SELECT TO authenticated USING (private.restaurant_has_access(branch_id));
CREATE POLICY restaurant_evidence_member_read ON public.restaurant_evidence
  FOR SELECT TO authenticated USING (private.restaurant_has_access(branch_id));

CREATE OR REPLACE FUNCTION public.materialize_restaurant_tasks(p_branch_id uuid, p_for_date date)
RETURNS integer
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  inserted_count integer;
BEGIN
  WITH created_tasks AS (
    INSERT INTO public.restaurant_tasks (
      branch_id, activity_template_id, area_id, scheduled_for, task_source,
      name, description, estimated_minutes, difficulty, priority, requires_evidence
    )
    SELECT t.branch_id, t.id, t.area_id, p_for_date, t.activity_type,
      t.name, t.description, t.estimated_minutes, t.difficulty, t.priority, t.requires_evidence
    FROM public.restaurant_activity_templates AS t
    WHERE t.branch_id = p_branch_id
      AND t.activity_type = 'scheduled'
      AND t.is_active
      AND extract(isodow FROM p_for_date)::smallint = ANY(t.schedule_days)
    ON CONFLICT (branch_id, activity_template_id, scheduled_for)
      WHERE task_source = 'scheduled' AND activity_template_id IS NOT NULL DO NOTHING
    RETURNING id, branch_id, activity_template_id
  ), created_parts AS (
    INSERT INTO public.restaurant_task_parts (
      branch_id, task_id, zone_id, estimated_minutes, difficulty
    )
    SELECT c.branch_id, c.id, z.id, z.estimated_minutes, z.difficulty
    FROM created_tasks AS c
    JOIN public.restaurant_activity_templates AS t ON t.id = c.activity_template_id
    JOIN public.restaurant_activity_zones AS z ON z.activity_template_id = t.id
    WHERE t.is_divisible
    RETURNING id
  )
  SELECT count(*)::integer INTO inserted_count FROM created_tasks;
  RETURN inserted_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_restaurant_task_instance(
  p_branch_id uuid,
  p_actor_id uuid,
  p_template_id uuid,
  p_scheduled_for date,
  p_source_event_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  template_row public.restaurant_activity_templates%ROWTYPE;
  task_id uuid;
BEGIN
  IF private.restaurant_user_role(p_branch_id, p_actor_id) NOT IN ('admin', 'supervisor') THEN
    RAISE EXCEPTION 'MANAGER_REQUIRED';
  END IF;
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_branch_id::text || p_source_event_id::text, 0)
  );
  SELECT id INTO task_id FROM public.restaurant_tasks
  WHERE branch_id = p_branch_id AND source_event_id = p_source_event_id;
  IF task_id IS NOT NULL THEN RETURN task_id; END IF;

  SELECT * INTO template_row FROM public.restaurant_activity_templates
  WHERE branch_id = p_branch_id AND id = p_template_id AND is_active
    AND activity_type IN ('conditional', 'corrective');
  IF NOT FOUND THEN RAISE EXCEPTION 'INVALID_ACTIVITY_TEMPLATE'; END IF;

  INSERT INTO public.restaurant_tasks(
    branch_id, activity_template_id, area_id, source_event_id, scheduled_for,
    task_source, name, description, estimated_minutes, difficulty, priority, requires_evidence, created_by
  ) VALUES (
    p_branch_id, template_row.id, template_row.area_id, p_source_event_id, p_scheduled_for,
    template_row.activity_type, template_row.name, template_row.description,
    template_row.estimated_minutes, template_row.difficulty, template_row.priority,
    template_row.requires_evidence, p_actor_id
  ) RETURNING id INTO task_id;

  IF template_row.is_divisible THEN
    INSERT INTO public.restaurant_task_parts(branch_id, task_id, zone_id, estimated_minutes, difficulty)
    SELECT p_branch_id, task_id, zone.id, zone.estimated_minutes, zone.difficulty
    FROM public.restaurant_activity_zones zone
    WHERE zone.branch_id = p_branch_id AND zone.activity_template_id = template_row.id;
  END IF;
  RETURN task_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.apply_restaurant_task_action(
  p_branch_id uuid,
  p_task_id uuid,
  p_part_id uuid,
  p_actor_id uuid,
  p_action text,
  p_client_event_id uuid,
  p_note text DEFAULT NULL,
  p_evidence_path text DEFAULT NULL,
  p_occurred_at timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  task_row public.restaurant_tasks%ROWTYPE;
  part_row public.restaurant_task_parts%ROWTYPE;
  previous_status text;
  next_status text;
  event_row public.restaurant_task_events%ROWTYPE;
  now_at timestamptz := coalesce(p_occurred_at, now());
  eligible boolean;
  active_shift boolean;
  local_now timestamp without time zone;
  local_date date;
  local_time time without time zone;
  branch_timezone text;
BEGIN
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_branch_id::text || p_actor_id::text || p_client_event_id::text, 0)
  );
  SELECT * INTO event_row
  FROM public.restaurant_task_events
  WHERE branch_id = p_branch_id AND actor_id = p_actor_id AND client_event_id = p_client_event_id;
  IF FOUND THEN
    RETURN jsonb_build_object('replayed', true, 'task_id', event_row.task_id,
      'part_id', event_row.part_id, 'status', event_row.to_status);
  END IF;

  SELECT * INTO task_row FROM public.restaurant_tasks
  WHERE id = p_task_id AND branch_id = p_branch_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'TASK_NOT_FOUND'; END IF;
  SELECT * INTO event_row
  FROM public.restaurant_task_events
  WHERE branch_id = p_branch_id AND actor_id = p_actor_id AND client_event_id = p_client_event_id;
  IF FOUND THEN
    RETURN jsonb_build_object('replayed', true, 'task_id', event_row.task_id,
      'part_id', event_row.part_id, 'status', event_row.to_status);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.restaurant_memberships
    WHERE branch_id = p_branch_id AND user_id = p_actor_id AND is_active) THEN
    RAISE EXCEPTION 'BRANCH_ACCESS_REQUIRED';
  END IF;

  SELECT timezone INTO branch_timezone FROM public.restaurant_branches WHERE id = p_branch_id;
  IF branch_timezone IS NULL THEN RAISE EXCEPTION 'BRANCH_NOT_FOUND'; END IF;
  local_now := now_at AT TIME ZONE branch_timezone;
  local_date := local_now::date;
  local_time := local_now::time;

  SELECT EXISTS (
    SELECT 1 FROM public.restaurant_shifts s
    WHERE s.branch_id = p_branch_id AND s.employee_id = p_actor_id
      AND s.status = 'published'
      AND (
        (s.shift_date = local_date AND s.start_time < s.end_time
          AND local_time >= s.start_time AND local_time < s.end_time)
        OR (s.shift_date = local_date AND s.start_time > s.end_time AND local_time >= s.start_time)
        OR (s.shift_date = local_date - 1 AND s.start_time > s.end_time AND local_time < s.end_time)
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.restaurant_shift_breaks b
        WHERE b.branch_id = s.branch_id AND b.shift_id = s.id
          AND (
            (b.start_time < b.end_time AND local_time >= b.start_time AND local_time < b.end_time)
            OR (b.start_time > b.end_time AND (local_time >= b.start_time OR local_time < b.end_time))
          )
      )
  ) AND NOT EXISTS (
    SELECT 1 FROM public.restaurant_absences a
    WHERE a.branch_id = p_branch_id AND a.employee_id = p_actor_id
      AND a.status = 'approved' AND a.start_date <= local_date AND a.end_date >= local_date
  ) INTO active_shift;
  IF NOT active_shift THEN RAISE EXCEPTION 'NOT_ON_SHIFT_OR_ON_BREAK'; END IF;

  IF p_part_id IS NULL THEN
    previous_status := task_row.status;
    IF task_row.assigned_to IS DISTINCT FROM p_actor_id THEN
      IF p_action <> 'claim' OR task_row.assigned_to IS NOT NULL OR task_row.status <> 'pending' THEN
        RAISE EXCEPTION 'TASK_NOT_ASSIGNED_TO_USER';
      END IF;
      SELECT EXISTS (
        SELECT 1 FROM public.restaurant_member_positions mp
        WHERE mp.branch_id = p_branch_id AND mp.user_id = p_actor_id
          AND (
            (task_row.task_source = 'waste' AND EXISTS (
              SELECT 1 FROM public.restaurant_waste_positions wp
              WHERE wp.branch_id = p_branch_id AND wp.position_id = mp.position_id
            ))
            OR (task_row.task_source <> 'waste' AND task_row.activity_template_id IS NOT NULL AND EXISTS (
              SELECT 1 FROM public.restaurant_activity_positions ap
              WHERE ap.branch_id = p_branch_id AND ap.position_id = mp.position_id
                AND ap.activity_template_id = task_row.activity_template_id
            ))
          )
      ) INTO eligible;
      IF NOT eligible THEN
        RAISE EXCEPTION 'NO_ELIGIBLE_POSITION';
      END IF;
      UPDATE public.restaurant_tasks SET assigned_to = p_actor_id WHERE id = p_task_id;
      next_status := 'pending';
    ELSE
      next_status := CASE p_action
        WHEN 'start' THEN 'in_progress'
        WHEN 'resume' THEN 'in_progress'
        WHEN 'pause' THEN 'paused'
        WHEN 'complete' THEN 'completed'
        WHEN 'bag_changed' THEN 'completed'
        WHEN 'block' THEN 'blocked'
        ELSE NULL
      END;
      IF next_status IS NULL OR NOT (
        (previous_status = 'pending' AND next_status = 'in_progress') OR
        (previous_status = 'in_progress' AND next_status IN ('paused', 'completed', 'blocked')) OR
        (previous_status = 'paused' AND next_status = 'in_progress') OR
        (previous_status = 'blocked' AND next_status IN ('in_progress', 'completed'))
      ) THEN RAISE EXCEPTION 'INVALID_TASK_TRANSITION'; END IF;
      IF next_status = 'completed' AND task_row.requires_evidence AND p_evidence_path IS NULL THEN
        RAISE EXCEPTION 'EVIDENCE_REQUIRED';
      END IF;
      IF p_action = 'bag_changed' AND task_row.task_source <> 'waste' THEN
        RAISE EXCEPTION 'NOT_A_WASTE_TASK';
      END IF;
      IF p_action IN ('start', 'resume') AND task_row.activity_template_id IS NOT NULL
        AND (SELECT customer_service_active FROM public.restaurant_memberships
          WHERE branch_id = p_branch_id AND user_id = p_actor_id)
        AND (SELECT interruptible FROM public.restaurant_activity_templates WHERE id = task_row.activity_template_id) THEN
        RAISE EXCEPTION 'CUSTOMER_SERVICE_PRIORITY';
      END IF;
      UPDATE public.restaurant_tasks SET
        status = next_status,
        started_at = CASE WHEN p_action IN ('start', 'resume') THEN coalesce(started_at, now_at) ELSE started_at END,
        paused_at = CASE WHEN next_status = 'paused' THEN now_at ELSE NULL END,
        completed_at = CASE WHEN next_status = 'completed' THEN now_at ELSE completed_at END,
        completed_by = CASE WHEN next_status = 'completed' THEN p_actor_id ELSE completed_by END
      WHERE id = p_task_id;
      IF p_action = 'bag_changed' THEN
        UPDATE public.restaurant_waste_bins SET last_state = 'low', last_bag_changed_at = now_at
        WHERE id = task_row.waste_bin_id AND branch_id = p_branch_id;
      END IF;
    END IF;
  ELSE
    SELECT * INTO part_row FROM public.restaurant_task_parts
    WHERE id = p_part_id AND task_id = p_task_id AND branch_id = p_branch_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'TASK_PART_NOT_FOUND'; END IF;
    previous_status := part_row.status;
    IF part_row.assigned_to IS DISTINCT FROM p_actor_id THEN
      IF p_action <> 'claim' OR part_row.assigned_to IS NOT NULL OR part_row.status <> 'pending' THEN
        RAISE EXCEPTION 'TASK_NOT_ASSIGNED_TO_USER';
      END IF;
      SELECT EXISTS (
        SELECT 1 FROM public.restaurant_member_positions mp
        JOIN public.restaurant_activity_positions ap
          ON ap.branch_id = mp.branch_id AND ap.position_id = mp.position_id
        WHERE mp.branch_id = p_branch_id AND mp.user_id = p_actor_id
          AND ap.activity_template_id = task_row.activity_template_id
      ) INTO eligible;
      IF NOT eligible THEN RAISE EXCEPTION 'NO_ELIGIBLE_POSITION'; END IF;
      UPDATE public.restaurant_task_parts SET assigned_to = p_actor_id WHERE id = p_part_id;
      next_status := 'pending';
    ELSE
      next_status := CASE p_action
        WHEN 'start' THEN 'in_progress'
        WHEN 'resume' THEN 'in_progress'
        WHEN 'pause' THEN 'paused'
        WHEN 'complete' THEN 'completed'
        WHEN 'block' THEN 'blocked'
        ELSE NULL
      END;
      IF next_status IS NULL OR NOT (
        (previous_status = 'pending' AND next_status = 'in_progress') OR
        (previous_status = 'in_progress' AND next_status IN ('paused', 'completed', 'blocked')) OR
        (previous_status = 'paused' AND next_status = 'in_progress') OR
        (previous_status = 'blocked' AND next_status IN ('in_progress', 'completed'))
      ) THEN RAISE EXCEPTION 'INVALID_TASK_TRANSITION'; END IF;
      IF next_status = 'completed' AND task_row.requires_evidence AND p_evidence_path IS NULL THEN
        RAISE EXCEPTION 'EVIDENCE_REQUIRED';
      END IF;
      IF p_action IN ('start', 'resume')
        AND (SELECT customer_service_active FROM public.restaurant_memberships
          WHERE branch_id = p_branch_id AND user_id = p_actor_id)
        AND (SELECT interruptible FROM public.restaurant_activity_templates WHERE id = task_row.activity_template_id) THEN
        RAISE EXCEPTION 'CUSTOMER_SERVICE_PRIORITY';
      END IF;
      UPDATE public.restaurant_task_parts SET
        status = next_status,
        started_at = CASE WHEN p_action IN ('start', 'resume') THEN coalesce(started_at, now_at) ELSE started_at END,
        paused_at = CASE WHEN next_status = 'paused' THEN now_at ELSE NULL END,
        completed_at = CASE WHEN next_status = 'completed' THEN now_at ELSE completed_at END,
        completed_by = CASE WHEN next_status = 'completed' THEN p_actor_id ELSE completed_by END
      WHERE id = p_part_id;
      IF NOT EXISTS (
        SELECT 1 FROM public.restaurant_task_parts WHERE task_id = p_task_id AND status <> 'completed'
      ) THEN
        UPDATE public.restaurant_tasks SET status = 'completed', completed_at = now_at, completed_by = p_actor_id
        WHERE id = p_task_id;
      ELSE
        UPDATE public.restaurant_tasks SET status = 'in_progress', started_at = coalesce(started_at, now_at)
        WHERE id = p_task_id AND status = 'pending';
      END IF;
    END IF;
  END IF;

  INSERT INTO public.restaurant_task_events (
    branch_id, task_id, part_id, actor_id, client_event_id, event_type,
    from_status, to_status, note, evidence_path, occurred_at
  ) VALUES (
    p_branch_id, p_task_id, p_part_id, p_actor_id, p_client_event_id, p_action,
    previous_status, next_status, nullif(trim(p_note), ''), p_evidence_path, now_at
  );

  RETURN jsonb_build_object('replayed', false, 'task_id', p_task_id,
    'part_id', p_part_id, 'from_status', previous_status, 'status', next_status);
END;
$$;

CREATE OR REPLACE FUNCTION public.record_restaurant_waste_inspection(
  p_branch_id uuid,
  p_inspector_id uuid,
  p_client_event_id uuid,
  p_results jsonb,
  p_occurred_at timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  inspection_id uuid;
  expected_count integer;
  supplied_count integer;
  result_item jsonb;
  bin_row public.restaurant_waste_bins%ROWTYPE;
  active_task_id uuid;
  inspection_at timestamptz := coalesce(p_occurred_at, now());
  branch_timezone text;
  inspection_is_latest boolean;
BEGIN
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_branch_id::text || p_client_event_id::text, 0)
  );
  SELECT id INTO inspection_id FROM public.restaurant_waste_inspections
  WHERE branch_id = p_branch_id AND client_event_id = p_client_event_id;
  IF inspection_id IS NOT NULL THEN
    RETURN jsonb_build_object('replayed', true, 'inspection_id', inspection_id);
  END IF;

  SELECT timezone INTO branch_timezone FROM public.restaurant_branches
  WHERE id = p_branch_id AND is_active;
  IF branch_timezone IS NULL THEN RAISE EXCEPTION 'BRANCH_NOT_FOUND'; END IF;

  SELECT count(*) INTO expected_count FROM public.restaurant_waste_bins
  WHERE branch_id = p_branch_id AND is_active;
  IF jsonb_typeof(p_results) <> 'array' THEN RAISE EXCEPTION 'INVALID_INSPECTION_RESULTS'; END IF;
  SELECT count(DISTINCT item->>'bin_id') INTO supplied_count
  FROM jsonb_array_elements(p_results) AS results(item);
  IF expected_count = 0 OR supplied_count <> expected_count OR jsonb_array_length(p_results) <> expected_count THEN
    RAISE EXCEPTION 'INSPECTION_MUST_INCLUDE_EVERY_ACTIVE_BIN';
  END IF;

  INSERT INTO public.restaurant_waste_inspections(branch_id, inspector_id, client_event_id, inspected_at)
  VALUES (p_branch_id, p_inspector_id, p_client_event_id, inspection_at) RETURNING id INTO inspection_id;

  FOR result_item IN SELECT value FROM jsonb_array_elements(p_results)
  LOOP
    SELECT * INTO bin_row FROM public.restaurant_waste_bins
    WHERE id = (result_item->>'bin_id')::uuid AND branch_id = p_branch_id AND is_active FOR UPDATE;
    IF NOT FOUND OR result_item->>'state' NOT IN ('low', 'half', 'full') THEN
      RAISE EXCEPTION 'INVALID_BIN_OR_STATE';
    END IF;
    inspection_is_latest := bin_row.last_inspected_at IS NULL OR inspection_at >= bin_row.last_inspected_at;
    INSERT INTO public.restaurant_waste_inspection_results(branch_id, inspection_id, bin_id, declared_state)
    VALUES (p_branch_id, inspection_id, bin_row.id, result_item->>'state');
    UPDATE public.restaurant_waste_bins SET
      last_state = CASE WHEN inspection_is_latest THEN result_item->>'state' ELSE last_state END,
      last_inspected_at = GREATEST(COALESCE(last_inspected_at, inspection_at), inspection_at)
    WHERE id = bin_row.id;

    IF result_item->>'state' = 'full' AND inspection_is_latest THEN
      IF bin_row.bag_change_activity_name IS NULL
        OR bin_row.bag_change_minutes IS NULL
        OR bin_row.bag_change_difficulty IS NULL
        OR bin_row.bag_change_priority IS NULL THEN
        RAISE EXCEPTION 'WASTE_TASK_POLICY_REQUIRED';
      END IF;
      INSERT INTO public.restaurant_tasks(
        branch_id, waste_bin_id, scheduled_for, task_source, name, description,
        estimated_minutes, difficulty, priority
      ) VALUES (
        p_branch_id, bin_row.id, (now() AT TIME ZONE branch_timezone)::date,
        'waste', bin_row.bag_change_activity_name, 'Resultado de inspección que requiere cambio del contenedor.',
        bin_row.bag_change_minutes, bin_row.bag_change_difficulty, bin_row.bag_change_priority
      ) ON CONFLICT (branch_id, waste_bin_id)
        WHERE task_source = 'waste' AND waste_bin_id IS NOT NULL AND status <> 'completed'
        DO NOTHING;
      SELECT id INTO active_task_id FROM public.restaurant_tasks
      WHERE branch_id = p_branch_id AND waste_bin_id = bin_row.id AND task_source = 'waste' AND status <> 'completed';
    END IF;
  END LOOP;

  RETURN jsonb_build_object('replayed', false, 'inspection_id', inspection_id,
    'active_waste_task_id', active_task_id);
END;
$$;

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
DECLARE
  incident_row public.restaurant_incidents%ROWTYPE;
BEGIN
  SELECT * INTO incident_row FROM public.restaurant_incidents
  WHERE id = p_incident_id AND branch_id = p_branch_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'INCIDENT_NOT_FOUND'; END IF;
  IF p_status NOT IN ('open', 'in_progress', 'resolved') THEN RAISE EXCEPTION 'INVALID_INCIDENT_STATUS'; END IF;
  UPDATE public.restaurant_incidents SET
    status = p_status,
    assigned_to = p_assigned_to,
    is_blocking = p_is_blocking,
    resolved_at = CASE WHEN p_status = 'resolved' THEN now() ELSE NULL END
  WHERE id = p_incident_id;
  INSERT INTO public.restaurant_incident_events(branch_id, incident_id, actor_id, event_type, note)
  VALUES (p_branch_id, p_incident_id, p_actor_id, 'updated', nullif(trim(p_note), ''));
  RETURN jsonb_build_object('id', p_incident_id, 'status', p_status);
END;
$$;

CREATE OR REPLACE FUNCTION public.create_restaurant_incident(
  p_branch_id uuid,
  p_actor_id uuid,
  p_area_id uuid,
  p_description text,
  p_urgency text,
  p_is_blocking boolean,
  p_assigned_to uuid,
  p_client_event_id uuid,
  p_occurred_at timestamptz DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  incident_id uuid;
  incident_at timestamptz := coalesce(p_occurred_at, now());
BEGIN
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_branch_id::text || p_actor_id::text || p_client_event_id::text, 0)
  );
  SELECT id INTO incident_id FROM public.restaurant_incidents
  WHERE branch_id = p_branch_id AND reported_by = p_actor_id AND client_event_id = p_client_event_id;
  IF incident_id IS NOT NULL THEN RETURN incident_id; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.restaurant_memberships
    WHERE branch_id = p_branch_id AND user_id = p_actor_id AND is_active) THEN
    RAISE EXCEPTION 'BRANCH_ACCESS_REQUIRED';
  END IF;
  IF p_urgency NOT IN ('low', 'normal', 'high', 'urgent') THEN RAISE EXCEPTION 'INVALID_URGENCY'; END IF;
  IF p_area_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.restaurant_areas WHERE id = p_area_id AND branch_id = p_branch_id
  ) THEN RAISE EXCEPTION 'INVALID_AREA'; END IF;
  IF p_assigned_to IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.restaurant_memberships
    WHERE branch_id = p_branch_id AND user_id = p_assigned_to AND is_active
  ) THEN RAISE EXCEPTION 'INVALID_ASSIGNEE'; END IF;
  INSERT INTO public.restaurant_incidents(
    branch_id, area_id, description, urgency, is_blocking, assigned_to, reported_by, client_event_id, created_at
  ) VALUES (
    p_branch_id, p_area_id, trim(p_description), p_urgency, p_is_blocking, p_assigned_to,
    p_actor_id, p_client_event_id, incident_at
  ) RETURNING id INTO incident_id;
  INSERT INTO public.restaurant_incident_events(branch_id, incident_id, actor_id, event_type, occurred_at)
  VALUES (p_branch_id, incident_id, p_actor_id, 'reported', incident_at);
  RETURN incident_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.save_restaurant_activity_template(
  p_branch_id uuid,
  p_actor_id uuid,
  p_template_id uuid,
  p_area_id uuid,
  p_name text,
  p_description text,
  p_activity_type text,
  p_schedule_days smallint[],
  p_estimated_minutes integer,
  p_difficulty smallint,
  p_priority smallint,
  p_is_divisible boolean,
  p_interruptible boolean,
  p_requires_evidence boolean,
  p_is_active boolean,
  p_position_ids uuid[],
  p_zones jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SET search_path = ''
AS $$
DECLARE
  template_id uuid;
  zone_item jsonb;
BEGIN
  IF private.restaurant_user_role(p_branch_id, p_actor_id) NOT IN ('admin', 'supervisor') THEN
    RAISE EXCEPTION 'MANAGER_REQUIRED';
  END IF;
  IF p_activity_type NOT IN ('scheduled', 'conditional', 'corrective')
    OR (p_activity_type = 'scheduled' AND cardinality(p_schedule_days) = 0)
    OR p_estimated_minutes NOT BETWEEN 1 AND 1440
    OR p_difficulty NOT BETWEEN 1 AND 5
    OR p_priority NOT BETWEEN 1 AND 5 THEN
    RAISE EXCEPTION 'INVALID_ACTIVITY_CONFIGURATION';
  END IF;
  IF p_area_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.restaurant_areas WHERE id = p_area_id AND branch_id = p_branch_id
  ) THEN RAISE EXCEPTION 'INVALID_AREA'; END IF;
  IF coalesce(cardinality(p_position_ids), 0) > 0 AND (
    SELECT count(DISTINCT id) FROM public.restaurant_positions
    WHERE branch_id = p_branch_id AND id = ANY(p_position_ids)
  ) <> cardinality(p_position_ids) THEN RAISE EXCEPTION 'INVALID_POSITION'; END IF;
  IF jsonb_typeof(coalesce(p_zones, '[]'::jsonb)) <> 'array' THEN RAISE EXCEPTION 'INVALID_ZONES'; END IF;

  IF p_template_id IS NULL THEN
    INSERT INTO public.restaurant_activity_templates(
      branch_id, area_id, name, description, activity_type, schedule_days,
      estimated_minutes, difficulty, priority, is_divisible, interruptible,
      requires_evidence, is_active
    ) VALUES (
      p_branch_id, p_area_id, trim(p_name), nullif(trim(p_description), ''), p_activity_type, p_schedule_days,
      p_estimated_minutes, p_difficulty, p_priority, p_is_divisible, p_interruptible,
      p_requires_evidence, p_is_active
    ) RETURNING id INTO template_id;
  ELSE
    UPDATE public.restaurant_activity_templates SET
      area_id = p_area_id, name = trim(p_name), description = nullif(trim(p_description), ''),
      activity_type = p_activity_type, schedule_days = p_schedule_days,
      estimated_minutes = p_estimated_minutes, difficulty = p_difficulty, priority = p_priority,
      is_divisible = p_is_divisible, interruptible = p_interruptible,
      requires_evidence = p_requires_evidence, is_active = p_is_active
    WHERE id = p_template_id AND branch_id = p_branch_id
    RETURNING id INTO template_id;
    IF template_id IS NULL THEN RAISE EXCEPTION 'TEMPLATE_NOT_FOUND'; END IF;
  END IF;

  DELETE FROM public.restaurant_activity_positions
  WHERE branch_id = p_branch_id AND activity_template_id = template_id;
  INSERT INTO public.restaurant_activity_positions(branch_id, activity_template_id, position_id)
  SELECT p_branch_id, template_id, position_id
  FROM unnest(coalesce(p_position_ids, ARRAY[]::uuid[])) AS positions(position_id);
  DELETE FROM public.restaurant_activity_zones
  WHERE branch_id = p_branch_id AND activity_template_id = template_id;
  FOR zone_item IN SELECT value FROM jsonb_array_elements(coalesce(p_zones, '[]'::jsonb))
  LOOP
    INSERT INTO public.restaurant_activity_zones(
      branch_id, activity_template_id, name, estimated_minutes, difficulty, sort_order
    ) VALUES (
      p_branch_id, template_id, trim(zone_item->>'name'),
      coalesce((zone_item->>'estimated_minutes')::integer, p_estimated_minutes),
      coalesce((zone_item->>'difficulty')::smallint, p_difficulty),
      coalesce((zone_item->>'sort_order')::integer, 0)
    );
  END LOOP;
  RETURN template_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.save_restaurant_member_positions(
  p_branch_id uuid,
  p_actor_id uuid,
  p_employee_id uuid,
  p_position_ids uuid[]
)
RETURNS boolean
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF private.restaurant_user_role(p_branch_id, p_actor_id) NOT IN ('admin', 'supervisor') THEN
    RAISE EXCEPTION 'MANAGER_REQUIRED';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.restaurant_memberships
    WHERE branch_id = p_branch_id AND user_id = p_employee_id AND is_active) THEN
    RAISE EXCEPTION 'EMPLOYEE_NOT_IN_BRANCH';
  END IF;
  IF coalesce(cardinality(p_position_ids), 0) > 0 AND (
    SELECT count(DISTINCT id) FROM public.restaurant_positions
    WHERE branch_id = p_branch_id AND id = ANY(p_position_ids)
  ) <> cardinality(p_position_ids) THEN RAISE EXCEPTION 'INVALID_POSITION'; END IF;
  DELETE FROM public.restaurant_member_positions
  WHERE branch_id = p_branch_id AND user_id = p_employee_id;
  INSERT INTO public.restaurant_member_positions(branch_id, user_id, position_id)
  SELECT p_branch_id, p_employee_id, position_id
  FROM unnest(coalesce(p_position_ids, ARRAY[]::uuid[])) AS positions(position_id);
  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.save_restaurant_waste_positions(
  p_branch_id uuid,
  p_actor_id uuid,
  p_position_ids uuid[]
)
RETURNS boolean
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF private.restaurant_user_role(p_branch_id, p_actor_id) NOT IN ('admin', 'supervisor') THEN
    RAISE EXCEPTION 'MANAGER_REQUIRED';
  END IF;
  IF coalesce(cardinality(p_position_ids), 0) > 0 AND (
    SELECT count(DISTINCT id) FROM public.restaurant_positions
    WHERE branch_id = p_branch_id AND id = ANY(p_position_ids)
  ) <> cardinality(p_position_ids) THEN RAISE EXCEPTION 'INVALID_POSITION'; END IF;
  DELETE FROM public.restaurant_waste_positions WHERE branch_id = p_branch_id;
  INSERT INTO public.restaurant_waste_positions(branch_id, position_id)
  SELECT p_branch_id, position_id
  FROM unnest(coalesce(p_position_ids, ARRAY[]::uuid[])) AS positions(position_id);
  RETURN true;
END;
$$;

CREATE OR REPLACE FUNCTION public.save_restaurant_shift(
  p_branch_id uuid,
  p_actor_id uuid,
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
  saved_shift_id uuid;
  shift_start integer;
  shift_end integer;
  break_start integer;
  break_end integer;
  item jsonb;
  break_ranges int4range[] := ARRAY[]::int4range[];
  new_range int4range;
  old_range int4range;
  old_shift record;
  candidate_start timestamp without time zone;
  candidate_end timestamp without time zone;
  old_end timestamp without time zone;
BEGIN
  IF private.restaurant_user_role(p_branch_id, p_actor_id) NOT IN ('admin', 'supervisor') THEN
    RAISE EXCEPTION 'MANAGER_REQUIRED';
  END IF;
  IF p_status NOT IN ('draft', 'published') OR p_start_time = p_end_time THEN
    RAISE EXCEPTION 'INVALID_SHIFT';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.restaurant_memberships
    WHERE branch_id = p_branch_id AND user_id = p_employee_id AND is_active) THEN
    RAISE EXCEPTION 'EMPLOYEE_NOT_IN_BRANCH';
  END IF;
  IF jsonb_typeof(coalesce(p_breaks, '[]'::jsonb)) <> 'array' THEN
    RAISE EXCEPTION 'INVALID_SHIFT_BREAK';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_branch_id::text || p_employee_id::text, 0)
  );
  shift_start := extract(hour FROM p_start_time)::integer * 60 + extract(minute FROM p_start_time)::integer;
  shift_end := extract(hour FROM p_end_time)::integer * 60 + extract(minute FROM p_end_time)::integer;
  IF shift_end <= shift_start THEN shift_end := shift_end + 1440; END IF;

  INSERT INTO public.restaurant_shifts(
    branch_id, employee_id, shift_date, start_time, end_time, status, created_by
  ) VALUES (p_branch_id, p_employee_id, p_shift_date, p_start_time, p_end_time, p_status, p_actor_id)
  ON CONFLICT (branch_id, employee_id, shift_date, start_time, end_time)
  DO UPDATE SET status = EXCLUDED.status, created_by = EXCLUDED.created_by
  RETURNING id INTO saved_shift_id;

  candidate_start := p_shift_date + p_start_time;
  candidate_end := p_shift_date + p_end_time;
  IF p_end_time <= p_start_time THEN candidate_end := candidate_end + interval '1 day'; END IF;
  FOR old_shift IN SELECT * FROM public.restaurant_shifts
    WHERE branch_id = p_branch_id AND employee_id = p_employee_id AND id <> saved_shift_id
      AND status <> 'cancelled'
      AND shift_date BETWEEN p_shift_date - 1 AND p_shift_date + 1
  LOOP
    old_end := old_shift.shift_date + old_shift.end_time;
    IF old_shift.end_time <= old_shift.start_time THEN old_end := old_end + interval '1 day'; END IF;
    IF candidate_start < old_end
      AND old_shift.shift_date + old_shift.start_time < candidate_end THEN
      RAISE EXCEPTION 'SHIFT_OVERLAP';
    END IF;
  END LOOP;

  FOR item IN SELECT value FROM jsonb_array_elements(coalesce(p_breaks, '[]'::jsonb))
  LOOP
    break_start := extract(hour FROM (item->>'start_time')::time)::integer * 60
      + extract(minute FROM (item->>'start_time')::time)::integer;
    break_end := extract(hour FROM (item->>'end_time')::time)::integer * 60
      + extract(minute FROM (item->>'end_time')::time)::integer;
    IF break_start < shift_start THEN break_start := break_start + 1440; END IF;
    break_end := break_end + (break_start / 1440) * 1440;
    IF break_end <= break_start THEN break_end := break_end + 1440; END IF;
    IF break_start < shift_start OR break_end > shift_end THEN RAISE EXCEPTION 'INVALID_SHIFT_BREAK'; END IF;
    new_range := int4range(break_start, break_end, '[)');
    FOREACH old_range IN ARRAY break_ranges LOOP
      IF new_range && old_range THEN RAISE EXCEPTION 'INVALID_SHIFT_BREAK'; END IF;
    END LOOP;
    break_ranges := array_append(break_ranges, new_range);
  END LOOP;

  DELETE FROM public.restaurant_shift_breaks AS saved_break
  WHERE saved_break.branch_id = p_branch_id AND saved_break.shift_id = saved_shift_id;
  INSERT INTO public.restaurant_shift_breaks(branch_id, shift_id, start_time, end_time)
  SELECT p_branch_id, saved_shift_id, (breaks.item->>'start_time')::time, (breaks.item->>'end_time')::time
  FROM jsonb_array_elements(coalesce(p_breaks, '[]'::jsonb)) AS breaks(item);
  RETURN saved_shift_id;
END;
$$;

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
    SELECT 1 FROM public.users u
    WHERE u.id = p_creator_id AND u.company_id = p_company_id
      AND u.is_active AND u.role::text IN ('owner', 'admin')
  ) THEN RAISE EXCEPTION 'BRANCH_ADMIN_REQUIRED'; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name = p_timezone) THEN
    RAISE EXCEPTION 'INVALID_TIMEZONE';
  END IF;

  INSERT INTO public.restaurant_branches(company_id, name, timezone, created_by)
  VALUES (p_company_id, trim(p_name), p_timezone, p_creator_id)
  RETURNING * INTO branch_row;
  INSERT INTO public.restaurant_memberships(branch_id, company_id, user_id, access_role, created_by)
  VALUES (branch_row.id, p_company_id, p_creator_id, 'admin', p_creator_id);

  RETURN branch_row.id;
END;
$$;

REVOKE ALL ON FUNCTION public.materialize_restaurant_tasks(uuid, date) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.create_restaurant_task_instance(uuid, uuid, uuid, date, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.apply_restaurant_task_action(uuid, uuid, uuid, uuid, text, uuid, text, text, timestamptz) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_restaurant_waste_inspection(uuid, uuid, uuid, jsonb, timestamptz) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.update_restaurant_incident(uuid, uuid, uuid, text, uuid, boolean, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.create_restaurant_branch(uuid, uuid, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.create_restaurant_incident(uuid, uuid, uuid, text, text, boolean, uuid, uuid, timestamptz) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.save_restaurant_activity_template(uuid, uuid, uuid, uuid, text, text, text, smallint[], integer, smallint, smallint, boolean, boolean, boolean, boolean, uuid[], jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.save_restaurant_member_positions(uuid, uuid, uuid, uuid[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.save_restaurant_waste_positions(uuid, uuid, uuid[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.save_restaurant_shift(uuid, uuid, uuid, date, time, time, text, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.record_restaurant_time_event(uuid, uuid, uuid, text, timestamptz, numeric, numeric, numeric) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.materialize_restaurant_tasks(uuid, date) TO service_role;
GRANT EXECUTE ON FUNCTION public.create_restaurant_task_instance(uuid, uuid, uuid, date, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.apply_restaurant_task_action(uuid, uuid, uuid, uuid, text, uuid, text, text, timestamptz) TO service_role;
GRANT EXECUTE ON FUNCTION public.record_restaurant_waste_inspection(uuid, uuid, uuid, jsonb, timestamptz) TO service_role;
GRANT EXECUTE ON FUNCTION public.update_restaurant_incident(uuid, uuid, uuid, text, uuid, boolean, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.create_restaurant_branch(uuid, uuid, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.create_restaurant_incident(uuid, uuid, uuid, text, text, boolean, uuid, uuid, timestamptz) TO service_role;
GRANT EXECUTE ON FUNCTION public.save_restaurant_activity_template(uuid, uuid, uuid, uuid, text, text, text, smallint[], integer, smallint, smallint, boolean, boolean, boolean, boolean, uuid[], jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.save_restaurant_member_positions(uuid, uuid, uuid, uuid[]) TO service_role;
GRANT EXECUTE ON FUNCTION public.save_restaurant_waste_positions(uuid, uuid, uuid[]) TO service_role;
GRANT EXECUTE ON FUNCTION public.save_restaurant_shift(uuid, uuid, uuid, date, time, time, text, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.record_restaurant_time_event(uuid, uuid, uuid, text, timestamptz, numeric, numeric, numeric) TO service_role;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('restaurant-evidence', 'restaurant-evidence', false, 10485760,
  ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO NOTHING;

CREATE POLICY restaurant_evidence_upload ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'restaurant-evidence'
    AND CASE
      WHEN (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        AND (storage.foldername(name))[2] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      THEN private.restaurant_can_access_evidence(((storage.foldername(name))[1])::uuid, ((storage.foldername(name))[2])::uuid)
      ELSE false
    END
  );
CREATE POLICY restaurant_evidence_read ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'restaurant-evidence'
    AND CASE
      WHEN (storage.foldername(name))[1] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        AND (storage.foldername(name))[2] ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      THEN private.restaurant_can_access_evidence(((storage.foldername(name))[1])::uuid, ((storage.foldername(name))[2])::uuid)
      ELSE false
    END
  );

ALTER PUBLICATION supabase_realtime ADD TABLE
  public.restaurant_branches,
  public.restaurant_tasks,
  public.restaurant_task_parts,
  public.restaurant_incidents,
  public.restaurant_waste_inspections;

CREATE TRIGGER restaurant_task_events_append_only
  BEFORE UPDATE OR DELETE ON public.restaurant_task_events
  FOR EACH ROW EXECUTE FUNCTION public.prevent_event_mutation();
CREATE TRIGGER restaurant_incident_events_append_only
  BEFORE UPDATE OR DELETE ON public.restaurant_incident_events
  FOR EACH ROW EXECUTE FUNCTION public.prevent_event_mutation();
CREATE TRIGGER restaurant_waste_inspections_append_only
  BEFORE UPDATE OR DELETE ON public.restaurant_waste_inspections
  FOR EACH ROW EXECUTE FUNCTION public.prevent_event_mutation();
CREATE TRIGGER restaurant_waste_results_append_only
  BEFORE UPDATE OR DELETE ON public.restaurant_waste_inspection_results
  FOR EACH ROW EXECUTE FUNCTION public.prevent_event_mutation();
CREATE TRIGGER restaurant_time_events_append_only
  BEFORE UPDATE OR DELETE ON public.restaurant_time_events
  FOR EACH ROW EXECUTE FUNCTION public.prevent_event_mutation();
