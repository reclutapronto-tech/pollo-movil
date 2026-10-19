-- ========================================================
-- Migration: 20260404000400_expense_events
-- Purpose:   Add receipt/expense persistence with tenant isolation
-- ========================================================

CREATE TABLE expense_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
  job_id uuid NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
  submitted_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  category text NOT NULL CHECK (category IN ('materials', 'fuel', 'tools', 'meals', 'other')),
  amount numeric(12, 2) NOT NULL CHECK (amount > 0),
  vendor text,
  notes text,
  media_asset_id uuid REFERENCES media_assets(id) ON DELETE SET NULL,
  status approval_decision NOT NULL DEFAULT 'pending',
  submitted_at timestamptz NOT NULL DEFAULT NOW(),
  decided_by uuid REFERENCES users(id) ON DELETE SET NULL,
  decided_at timestamptz,
  decision_reason text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  updated_at timestamptz NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_expense_events_updated_at
BEFORE UPDATE ON expense_events
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE INDEX idx_expense_events_company_status_submitted
ON expense_events(company_id, status, submitted_at DESC);

CREATE INDEX idx_expense_events_job_submitted
ON expense_events(job_id, submitted_at DESC);

CREATE INDEX idx_expense_events_submitted_by
ON expense_events(submitted_by, submitted_at DESC);

ALTER TABLE expense_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Tenant isolation for expense_events"
ON expense_events
FOR SELECT
USING (company_id = public.current_company_id());

CREATE POLICY "Worker expense insert"
ON expense_events
FOR INSERT
WITH CHECK (
  company_id = public.current_company_id()
  AND submitted_by = auth.uid()
);
