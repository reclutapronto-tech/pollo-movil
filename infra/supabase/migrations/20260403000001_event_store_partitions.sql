-- ========================================================
-- Migration: 20260403000001_event_store_partitions
-- Purpose:   Create event store tables mapped to RANGE partitions to ensure scale.
-- ========================================================

-- A core rule of range partitioning in Postgres: 
-- The partition key (occurred_at) MUST be part of the primary key.

CREATE TABLE clock_events (
  id uuid DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
  job_id uuid NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  device_id uuid REFERENCES devices(id) ON DELETE SET NULL,
  event_subtype clock_event_type NOT NULL,
  occurred_at timestamptz NOT NULL,
  received_at timestamptz NOT NULL DEFAULT NOW(),
  gps_lat double precision,
  gps_lng double precision,
  gps_accuracy_m double precision,
  geofence_passed boolean,
  task_classification text,
  rate_code text,
  shift_label text,
  notes text,
  source_event_uuid uuid,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  PRIMARY KEY (id, occurred_at)
) PARTITION BY RANGE (occurred_at);

CREATE TABLE photo_events (
  id uuid DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
  job_id uuid NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
  task_id uuid REFERENCES tasks(id) ON DELETE SET NULL,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  device_id uuid REFERENCES devices(id) ON DELETE SET NULL,
  media_asset_id uuid NOT NULL REFERENCES media_assets(id) ON DELETE RESTRICT,
  occurred_at timestamptz NOT NULL,
  received_at timestamptz NOT NULL DEFAULT NOW(),
  photo_role text,
  is_checkpoint boolean NOT NULL DEFAULT false,
  before_after_group_id uuid,
  gps_lat double precision,
  gps_lng double precision,
  gps_accuracy_m double precision,
  source_event_uuid uuid,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  PRIMARY KEY (id, occurred_at)
) PARTITION BY RANGE (occurred_at);

CREATE TABLE task_events (
  id uuid DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
  job_id uuid NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
  task_id uuid NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  occurred_at timestamptz NOT NULL,
  received_at timestamptz NOT NULL DEFAULT NOW(),
  from_status task_status,
  to_status task_status,
  note text,
  source_event_uuid uuid,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  PRIMARY KEY (id, occurred_at)
) PARTITION BY RANGE (occurred_at);

CREATE TABLE note_events (
  id uuid DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
  job_id uuid NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
  task_id uuid REFERENCES tasks(id) ON DELETE SET NULL,
  author_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  visibility visibility_scope NOT NULL DEFAULT 'internal',
  content text NOT NULL,
  occurred_at timestamptz NOT NULL,
  received_at timestamptz NOT NULL DEFAULT NOW(),
  source_event_uuid uuid,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  PRIMARY KEY (id, occurred_at)
) PARTITION BY RANGE (occurred_at);

CREATE TABLE ot_requests (
  id uuid DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
  job_id uuid NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
  worker_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  request_photo_event_id uuid,
  requested_at timestamptz NOT NULL,
  total_hours_at_request numeric(8,2),
  notes text,
  status approval_decision NOT NULL DEFAULT 'pending',
  source_event_uuid uuid,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  PRIMARY KEY (id, requested_at)
) PARTITION BY RANGE (requested_at);

CREATE TABLE ot_approval_events (
  id uuid DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
  job_id uuid NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
  ot_request_id uuid NOT NULL,
  worker_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  approver_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  decision approval_decision NOT NULL,
  reason text,
  occurred_at timestamptz NOT NULL,
  received_at timestamptz NOT NULL DEFAULT NOW(),
  source_event_uuid uuid,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  PRIMARY KEY (id, occurred_at)
) PARTITION BY RANGE (occurred_at);

CREATE TABLE alert_events (
  id uuid DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
  job_id uuid REFERENCES jobs(id) ON DELETE CASCADE,
  user_id uuid REFERENCES users(id) ON DELETE SET NULL,
  alert_type text NOT NULL,
  severity text NOT NULL,
  status alert_status NOT NULL DEFAULT 'open',
  message text NOT NULL,
  triggered_at timestamptz NOT NULL,
  resolved_at timestamptz,
  resolved_by uuid REFERENCES users(id),
  source_event_uuid uuid,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  PRIMARY KEY (id, triggered_at)
) PARTITION BY RANGE (triggered_at);

CREATE TABLE correction_events (
  id uuid DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
  job_id uuid REFERENCES jobs(id) ON DELETE CASCADE,
  corrected_table text NOT NULL,
  corrected_record_id uuid NOT NULL,
  corrected_field text,
  old_value jsonb,
  new_value jsonb,
  reason text NOT NULL,
  corrected_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  occurred_at timestamptz NOT NULL,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  PRIMARY KEY (id, occurred_at)
) PARTITION BY RANGE (occurred_at);

CREATE TABLE shift_report_events (
  id uuid DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
  job_id uuid NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
  foreman_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  report_date date NOT NULL,
  headcount integer,
  summary text,
  blocked_items text,
  next_steps text,
  occurred_at timestamptz NOT NULL,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  PRIMARY KEY (id, occurred_at)
) PARTITION BY RANGE (occurred_at);

-- Apply Immutable Triggers
CREATE TRIGGER trg_no_update_clock_events BEFORE UPDATE OR DELETE ON clock_events FOR EACH ROW EXECUTE FUNCTION prevent_event_mutation();
CREATE TRIGGER trg_no_update_photo_events BEFORE UPDATE OR DELETE ON photo_events FOR EACH ROW EXECUTE FUNCTION prevent_event_mutation();
CREATE TRIGGER trg_no_update_task_events BEFORE UPDATE OR DELETE ON task_events FOR EACH ROW EXECUTE FUNCTION prevent_event_mutation();
CREATE TRIGGER trg_no_update_note_events BEFORE UPDATE OR DELETE ON note_events FOR EACH ROW EXECUTE FUNCTION prevent_event_mutation();
CREATE TRIGGER trg_no_update_ot_approval_events BEFORE UPDATE OR DELETE ON ot_approval_events FOR EACH ROW EXECUTE FUNCTION prevent_event_mutation();
CREATE TRIGGER trg_no_update_correction_events BEFORE UPDATE OR DELETE ON correction_events FOR EACH ROW EXECUTE FUNCTION prevent_event_mutation();

-- Initial monthly partitions for early production phases (April -> July 2026)
-- Clock Events
CREATE TABLE clock_events_2026_04 PARTITION OF clock_events FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');
CREATE TABLE clock_events_2026_05 PARTITION OF clock_events FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');
CREATE TABLE clock_events_2026_06 PARTITION OF clock_events FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
-- Photo Events
CREATE TABLE photo_events_2026_04 PARTITION OF photo_events FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');
CREATE TABLE photo_events_2026_05 PARTITION OF photo_events FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');
CREATE TABLE photo_events_2026_06 PARTITION OF photo_events FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
-- Task Events
CREATE TABLE task_events_2026_04 PARTITION OF task_events FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');
CREATE TABLE task_events_2026_05 PARTITION OF task_events FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');
CREATE TABLE task_events_2026_06 PARTITION OF task_events FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
-- Note Events
CREATE TABLE note_events_2026_04 PARTITION OF note_events FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');
CREATE TABLE note_events_2026_05 PARTITION OF note_events FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');
CREATE TABLE note_events_2026_06 PARTITION OF note_events FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
-- OT Requests
CREATE TABLE ot_requests_2026_04 PARTITION OF ot_requests FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');
CREATE TABLE ot_requests_2026_05 PARTITION OF ot_requests FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');
CREATE TABLE ot_requests_2026_06 PARTITION OF ot_requests FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
-- OT Approval Events
CREATE TABLE ot_approval_events_2026_04 PARTITION OF ot_approval_events FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');
CREATE TABLE ot_approval_events_2026_05 PARTITION OF ot_approval_events FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');
CREATE TABLE ot_approval_events_2026_06 PARTITION OF ot_approval_events FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
-- Alert Events
CREATE TABLE alert_events_2026_04 PARTITION OF alert_events FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');
CREATE TABLE alert_events_2026_05 PARTITION OF alert_events FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');
CREATE TABLE alert_events_2026_06 PARTITION OF alert_events FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
-- Correction Events
CREATE TABLE correction_events_2026_04 PARTITION OF correction_events FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');
CREATE TABLE correction_events_2026_05 PARTITION OF correction_events FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');
CREATE TABLE correction_events_2026_06 PARTITION OF correction_events FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
-- Shift Report Events
CREATE TABLE shift_report_events_2026_04 PARTITION OF shift_report_events FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');
CREATE TABLE shift_report_events_2026_05 PARTITION OF shift_report_events FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');
CREATE TABLE shift_report_events_2026_06 PARTITION OF shift_report_events FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');

-- Catch-all defaults to prevent catastrophic failure if pg_cron misses a monthly instantiation
CREATE TABLE clock_events_default PARTITION OF clock_events DEFAULT;
CREATE TABLE photo_events_default PARTITION OF photo_events DEFAULT;
CREATE TABLE task_events_default PARTITION OF task_events DEFAULT;
CREATE TABLE note_events_default PARTITION OF note_events DEFAULT;
CREATE TABLE ot_requests_default PARTITION OF ot_requests DEFAULT;
CREATE TABLE ot_approval_events_default PARTITION OF ot_approval_events DEFAULT;
CREATE TABLE alert_events_default PARTITION OF alert_events DEFAULT;
CREATE TABLE correction_events_default PARTITION OF correction_events DEFAULT;
CREATE TABLE shift_report_events_default PARTITION OF shift_report_events DEFAULT;
