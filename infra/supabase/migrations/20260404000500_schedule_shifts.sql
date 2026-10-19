-- ========================================================
-- Migration: 20260404000500_schedule_shifts
-- Purpose:   Persist supervisor schedule drafts and published shifts
-- ========================================================

CREATE TABLE schedule_shifts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
  worker_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  job_id uuid NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
  shift_date date NOT NULL,
  start_time time NOT NULL,
  end_time time NOT NULL,
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'published')),
  notes text,
  published_at timestamptz,
  published_by uuid REFERENCES users(id) ON DELETE SET NULL,
  created_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  updated_at timestamptz NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_schedule_shifts_updated_at
BEFORE UPDATE ON schedule_shifts
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE INDEX idx_schedule_shifts_company_week
ON schedule_shifts(company_id, shift_date, status);

CREATE INDEX idx_schedule_shifts_worker_date
ON schedule_shifts(worker_id, shift_date);

CREATE INDEX idx_schedule_shifts_job_date
ON schedule_shifts(job_id, shift_date);

ALTER TABLE schedule_shifts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Tenant isolation for schedule_shifts"
ON schedule_shifts
FOR SELECT
USING (company_id = public.current_company_id());
