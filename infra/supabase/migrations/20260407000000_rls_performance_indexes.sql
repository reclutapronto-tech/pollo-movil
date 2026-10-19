-- ========================================================
-- Migration: 20260407000000_rls_performance_indexes
-- Purpose:   Ensure every company_id, job_id, user_id/worker_id
--            column used in RLS policies has a B-tree index.
--
--            Many of these already exist (from 20260403000002 and
--            later migrations). We use CREATE INDEX IF NOT EXISTS
--            so this migration is idempotent and only fills gaps.
-- ========================================================

-- ─── Core tables ────────────────────────────────────────────

-- users
CREATE INDEX IF NOT EXISTS idx_users_company_id ON users(company_id);

-- jobs
CREATE INDEX IF NOT EXISTS idx_jobs_company_id ON jobs(company_id);

-- tasks
CREATE INDEX IF NOT EXISTS idx_tasks_job_id ON tasks(job_id);
CREATE INDEX IF NOT EXISTS idx_tasks_company_id ON tasks(company_id);

-- assignments
CREATE INDEX IF NOT EXISTS idx_assignments_job_id ON assignments(job_id);
CREATE INDEX IF NOT EXISTS idx_assignments_user_id ON assignments(user_id);
CREATE INDEX IF NOT EXISTS idx_assignments_company_id ON assignments(company_id);

-- ─── Event tables (partitioned) ─────────────────────────────

-- clock_events
CREATE INDEX IF NOT EXISTS idx_clock_events_user_id ON clock_events(user_id);
CREATE INDEX IF NOT EXISTS idx_clock_events_job_id ON clock_events(job_id);
CREATE INDEX IF NOT EXISTS idx_clock_events_company_id ON clock_events(company_id);

-- photo_events
CREATE INDEX IF NOT EXISTS idx_photo_events_user_id ON photo_events(user_id);
CREATE INDEX IF NOT EXISTS idx_photo_events_job_id ON photo_events(job_id);
CREATE INDEX IF NOT EXISTS idx_photo_events_company_id ON photo_events(company_id);

-- task_events
CREATE INDEX IF NOT EXISTS idx_task_events_user_id ON task_events(user_id);
CREATE INDEX IF NOT EXISTS idx_task_events_company_id ON task_events(company_id);

-- note_events (author_id is the user column)
CREATE INDEX IF NOT EXISTS idx_note_events_author_id ON note_events(author_id);
CREATE INDEX IF NOT EXISTS idx_note_events_company_id ON note_events(company_id);

-- ot_requests (worker_id is the user column)
CREATE INDEX IF NOT EXISTS idx_ot_requests_worker_id ON ot_requests(worker_id);
CREATE INDEX IF NOT EXISTS idx_ot_requests_job_id ON ot_requests(job_id);
CREATE INDEX IF NOT EXISTS idx_ot_requests_company_id ON ot_requests(company_id);

-- ot_approval_events
CREATE INDEX IF NOT EXISTS idx_ot_approval_events_company_id ON ot_approval_events(company_id);

-- alert_events
CREATE INDEX IF NOT EXISTS idx_alert_events_company_id ON alert_events(company_id);

-- correction_events
CREATE INDEX IF NOT EXISTS idx_correction_events_company_id ON correction_events(company_id);

-- shift_report_events
CREATE INDEX IF NOT EXISTS idx_shift_report_events_company_id ON shift_report_events(company_id);

-- ─── Later tables ───────────────────────────────────────────

-- expense_events
CREATE INDEX IF NOT EXISTS idx_expense_events_user_id ON expense_events(submitted_by);
CREATE INDEX IF NOT EXISTS idx_expense_events_job_id ON expense_events(job_id);
CREATE INDEX IF NOT EXISTS idx_expense_events_company_id ON expense_events(company_id);

-- schedule_shifts
CREATE INDEX IF NOT EXISTS idx_schedule_shifts_worker_id ON schedule_shifts(worker_id);
CREATE INDEX IF NOT EXISTS idx_schedule_shifts_job_id ON schedule_shifts(job_id);
CREATE INDEX IF NOT EXISTS idx_schedule_shifts_company_id ON schedule_shifts(company_id);

-- pto_requests
CREATE INDEX IF NOT EXISTS idx_pto_requests_worker_id ON pto_requests(user_id);
CREATE INDEX IF NOT EXISTS idx_pto_requests_company_id ON pto_requests(company_id);

-- timecard_signatures
CREATE INDEX IF NOT EXISTS idx_timecard_signatures_worker_id ON timecard_signatures(worker_id);
CREATE INDEX IF NOT EXISTS idx_timecard_signatures_company_id ON timecard_signatures(company_id);

-- media_assets
CREATE INDEX IF NOT EXISTS idx_media_assets_user_id ON media_assets(uploaded_by);
CREATE INDEX IF NOT EXISTS idx_media_assets_company_id ON media_assets(company_id);

-- devices
CREATE INDEX IF NOT EXISTS idx_devices_company_id ON devices(company_id);

-- projects
CREATE INDEX IF NOT EXISTS idx_projects_company_id ON projects(company_id);
