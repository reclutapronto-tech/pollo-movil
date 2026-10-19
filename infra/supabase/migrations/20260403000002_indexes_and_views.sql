-- ========================================================
-- Migration: 20260403000002_indexes_and_views
-- Purpose:   Explicit Foreign Key indexes, Unique source constraints, and Timeline Views
-- ========================================================

-- Unique constraints on source_event_uuid to strictly drop duplicates natively
CREATE UNIQUE INDEX idx_clock_events_source_uuid ON clock_events(source_event_uuid, occurred_at) WHERE source_event_uuid IS NOT NULL;
CREATE UNIQUE INDEX idx_photo_events_source_uuid ON photo_events(source_event_uuid, occurred_at) WHERE source_event_uuid IS NOT NULL;
CREATE UNIQUE INDEX idx_task_events_source_uuid ON task_events(source_event_uuid, occurred_at) WHERE source_event_uuid IS NOT NULL;
CREATE UNIQUE INDEX idx_note_events_source_uuid ON note_events(source_event_uuid, occurred_at) WHERE source_event_uuid IS NOT NULL;
CREATE UNIQUE INDEX idx_ot_requests_source_uuid ON ot_requests(source_event_uuid, requested_at) WHERE source_event_uuid IS NOT NULL;
CREATE UNIQUE INDEX idx_ot_approval_source_uuid ON ot_approval_events(source_event_uuid, occurred_at) WHERE source_event_uuid IS NOT NULL;
CREATE UNIQUE INDEX idx_alert_events_source_uuid ON alert_events(source_event_uuid, triggered_at) WHERE source_event_uuid IS NOT NULL;
CREATE INDEX idx_shift_report_daily ON shift_report_events(job_id, report_date, foreman_id);

-- Explicitly index all Foreign Keys and critical multi-fields for Projection acceleration
-- Users
CREATE INDEX idx_users_company_id ON users(company_id);
CREATE INDEX idx_users_role ON users(role);
-- Devices
CREATE INDEX idx_devices_company_user ON devices(company_id, user_id);
-- Projects/Jobs
CREATE INDEX idx_projects_company_id ON projects(company_id);
CREATE INDEX idx_jobs_company_id ON jobs(company_id);
CREATE INDEX idx_jobs_project_id ON jobs(project_id);
CREATE INDEX idx_jobs_created_by ON jobs(created_by);
-- Tasks
CREATE INDEX idx_tasks_company_id ON tasks(company_id);
CREATE INDEX idx_tasks_job_id ON tasks(job_id);
CREATE INDEX idx_tasks_assigned_to ON tasks(assigned_to);
-- Assignments
CREATE INDEX idx_assignments_job_id ON assignments(job_id);
CREATE INDEX idx_assignments_user_id ON assignments(user_id);
-- Media
CREATE INDEX idx_media_company_id ON media_assets(company_id);
CREATE INDEX idx_media_job_id ON media_assets(job_id);
CREATE INDEX idx_media_task_id ON media_assets(task_id);
CREATE INDEX idx_media_uploaded_by ON media_assets(uploaded_by);
-- Events
CREATE INDEX idx_clock_events_job_id ON clock_events(job_id);
CREATE INDEX idx_clock_events_user_id ON clock_events(user_id);
CREATE INDEX idx_photo_events_job_id ON photo_events(job_id);
CREATE INDEX idx_photo_events_task_id ON photo_events(task_id);
CREATE INDEX idx_photo_events_user_id ON photo_events(user_id);
CREATE INDEX idx_task_events_job_id ON task_events(job_id);
CREATE INDEX idx_task_events_task_id ON task_events(task_id);
CREATE INDEX idx_note_events_job_id ON note_events(job_id);
CREATE INDEX idx_ot_requests_job_id ON ot_requests(job_id);
CREATE INDEX idx_ot_approval_job_id ON ot_approval_events(job_id);
CREATE INDEX idx_shift_report_job_id ON shift_report_events(job_id);

-- JSONB GIN Indexes (for high-yield payloads)
CREATE INDEX idx_clock_events_metadata_gin ON clock_events USING gin (metadata);
CREATE INDEX idx_jobs_metadata_gin ON jobs USING gin (metadata);

-- ========================================================
-- Job Timeline Unified Feed
-- ========================================================

CREATE VIEW job_timeline AS
SELECT
  id,
  company_id,
  job_id,
  user_id,
  'clock_event'::text as event_type,
  occurred_at,
  jsonb_build_object(
    'subtype', event_subtype,
    'gps_lat', gps_lat,
    'gps_lng', gps_lng,
    'gps_accuracy_m', gps_accuracy_m,
    'task_classification', task_classification,
    'notes', notes
  ) as payload
FROM clock_events

UNION ALL

SELECT
  id,
  company_id,
  job_id,
  user_id,
  'photo_event'::text as event_type,
  occurred_at,
  jsonb_build_object(
    'task_id', task_id,
    'media_asset_id', media_asset_id,
    'photo_role', photo_role,
    'is_checkpoint', is_checkpoint,
    'gps_lat', gps_lat,
    'gps_lng', gps_lng
  ) as payload
FROM photo_events

UNION ALL

SELECT
  id,
  company_id,
  job_id,
  user_id,
  'task_event'::text as event_type,
  occurred_at,
  jsonb_build_object(
    'task_id', task_id,
    'from_status', from_status,
    'to_status', to_status,
    'note', note
  ) as payload
FROM task_events

UNION ALL

SELECT
  id,
  company_id,
  job_id,
  author_id as user_id,
  'note_event'::text as event_type,
  occurred_at,
  jsonb_build_object(
    'visibility', visibility,
    'content', content
  ) as payload
FROM note_events

UNION ALL

SELECT
  id,
  company_id,
  job_id,
  approver_id as user_id,
  'ot_approval_event'::text as event_type,
  occurred_at,
  jsonb_build_object(
    'ot_request_id', ot_request_id,
    'worker_id', worker_id,
    'decision', decision,
    'reason', reason
  ) as payload
FROM ot_approval_events

UNION ALL

SELECT
  id,
  company_id,
  job_id,
  corrected_by as user_id,
  'correction_event'::text as event_type,
  occurred_at,
  jsonb_build_object(
    'corrected_table', corrected_table,
    'corrected_record_id', corrected_record_id,
    'corrected_field', corrected_field,
    'reason', reason
  ) as payload
FROM correction_events;
