-- ========================================================-- Migration: 20260408000001_time_corrections-- Purpose:   Add manual time entry corrections with audit trail-- =========================================================

CREATE TABLE time_corrections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
  worker_id uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  job_id uuid NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,

  -- The corrected event (what we're fixing).
  -- Note: clock_events is RANGE-partitioned on occurred_at with composite
  -- PK (id, occurred_at). Postgres does not allow a FOREIGN KEY that
  -- references only `id`, so we store the event identifier as a plain
  -- uuid. Referential integrity is enforced at write time by the
  -- time_corrections edge function which looks up the original event.
  original_event_id uuid,
  original_event_subtype clock_event_type,
  original_occurred_at timestamptz,

  -- The corrected values
  corrected_event_subtype clock_event_type NOT NULL,
  corrected_occurred_at timestamptz NOT NULL,

  -- Audit trail
  reason text NOT NULL,
  evidence_notes text,

  -- Who made the correction
  created_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT NOW(),

  -- Status for approval workflow
  status approval_decision NOT NULL DEFAULT 'pending',
  decided_by uuid REFERENCES users(id) ON DELETE SET NULL,
  decided_at timestamptz,
  decision_reason text,

  -- Correction creates a new clock_event when approved. Same FK limitation
  -- as original_event_id (partitioned table, composite PK).
  resulting_event_id uuid,

  updated_at timestamptz NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_time_corrections_updated_at
BEFORE UPDATE ON time_corrections
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE INDEX idx_time_corrections_company_status ON time_corrections(company_id, status, created_at DESC);
CREATE INDEX idx_time_corrections_worker ON time_corrections(worker_id, created_at DESC);
CREATE INDEX idx_time_corrections_job ON time_corrections(job_id, created_at DESC);
CREATE INDEX idx_time_corrections_original_event ON time_corrections(original_event_id);

ALTER TABLE time_corrections ENABLE ROW LEVEL SECURITY;

-- Workers can view their own corrections
CREATE POLICY "Workers can view own time_corrections"
ON time_corrections
FOR SELECT
USING (
  company_id = public.current_company_id()
  AND (worker_id = auth.uid() OR created_by = auth.uid())
);

-- Supervisors/admins/owners can view all corrections for their company
CREATE POLICY "Supervisors can view company time_corrections"
ON time_corrections
FOR SELECT
USING (
  company_id = public.current_company_id()
  AND EXISTS (
    SELECT 1 FROM users
    WHERE users.id = auth.uid()
    AND users.role IN ('supervisor', 'admin', 'owner', 'foreman')
  )
);

-- Supervisors/admins/owners can create corrections
CREATE POLICY "Supervisors can create time_corrections"
ON time_corrections
FOR INSERT
WITH CHECK (
  company_id = public.current_company_id()
  AND EXISTS (
    SELECT 1 FROM users
    WHERE users.id = auth.uid()
    AND users.role IN ('supervisor', 'admin', 'owner', 'foreman')
  )
);

-- Only supervisors/admins/owners can update (approve/deny)
CREATE POLICY "Supervisors can update time_corrections"
ON time_corrections
FOR UPDATE
USING (
  company_id = public.current_company_id()
  AND EXISTS (
    SELECT 1 FROM users
    WHERE users.id = auth.uid()
    AND users.role IN ('supervisor', 'admin', 'owner')
  )
);

-- View for time correction summary with worker and job details
CREATE VIEW time_correction_summary AS
SELECT
  tc.*,
  w.full_name AS worker_name,
  j.name AS job_name,
  j.code AS job_code,
  cb.full_name AS created_by_name,
  db.full_name AS decided_by_name
FROM time_corrections tc
JOIN users w ON w.id = tc.worker_id
JOIN jobs j ON j.id = tc.job_id
JOIN users cb ON cb.id = tc.created_by
LEFT JOIN users db ON db.id = tc.decided_by;
