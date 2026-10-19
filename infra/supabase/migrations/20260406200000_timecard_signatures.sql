-- Timecard signature tracking (Sprint 6 — Payroll & Compliance)
CREATE TABLE IF NOT EXISTS timecard_signatures (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL REFERENCES companies(id),
  worker_id UUID NOT NULL REFERENCES auth.users(id),
  supervisor_id UUID REFERENCES auth.users(id),
  week_start DATE NOT NULL,
  week_end DATE NOT NULL,
  worker_signature TEXT, -- base64 PNG data from canvas
  worker_signed_at TIMESTAMPTZ,
  supervisor_signature TEXT,
  supervisor_signed_at TIMESTAMPTZ,
  total_regular_hours NUMERIC(6,2),
  total_ot_hours NUMERIC(6,2),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'worker_signed', 'approved', 'disputed')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(worker_id, week_start)
);

ALTER TABLE timecard_signatures ENABLE ROW LEVEL SECURITY;

-- Workers can see and sign their own timecards
CREATE POLICY "Workers see own timecards"
  ON timecard_signatures FOR SELECT
  USING (worker_id = auth.uid());

CREATE POLICY "Workers sign own timecards"
  ON timecard_signatures FOR UPDATE
  USING (worker_id = auth.uid())
  WITH CHECK (worker_id = auth.uid());

-- Supervisors/admins can see and countersign for their company
CREATE POLICY "Supervisors see company timecards"
  ON timecard_signatures FOR SELECT
  USING (company_id IN (SELECT company_id FROM users WHERE id = auth.uid()));

CREATE POLICY "Supervisors countersign"
  ON timecard_signatures FOR UPDATE
  USING (company_id IN (SELECT company_id FROM users WHERE id = auth.uid()));

-- Insert policy for system
CREATE POLICY "System inserts timecards"
  ON timecard_signatures FOR INSERT
  WITH CHECK (company_id IN (SELECT company_id FROM users WHERE id = auth.uid()));

-- Add cost_code column to clock_events if not present
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'clock_events' AND column_name = 'cost_code'
  ) THEN
    ALTER TABLE clock_events ADD COLUMN cost_code TEXT;
  END IF;
END $$;
