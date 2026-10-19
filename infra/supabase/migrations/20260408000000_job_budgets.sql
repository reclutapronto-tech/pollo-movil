-- ========================================================-- Migration: 20260408000000_job_budgets-- Purpose:   Add job budgeting for budget vs actual tracking-- =========================================================

CREATE TABLE job_budgets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
  job_id uuid NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
  budgeted_hours numeric(10, 2) NOT NULL DEFAULT 0 CHECK (budgeted_hours >= 0),
  budgeted_cost numeric(12, 2) NOT NULL DEFAULT 0 CHECK (budgeted_cost >= 0),
  hourly_rate numeric(10, 2) NOT NULL DEFAULT 0 CHECK (hourly_rate >= 0),
  warning_threshold_percent numeric(5, 2) NOT NULL DEFAULT 80.0 CHECK (warning_threshold_percent BETWEEN 0 AND 100),
  created_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  updated_at timestamptz NOT NULL DEFAULT NOW(),
  UNIQUE(job_id)
);

CREATE TRIGGER trg_job_budgets_updated_at
BEFORE UPDATE ON job_budgets
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE INDEX idx_job_budgets_company_job ON job_budgets(company_id, job_id);

ALTER TABLE job_budgets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Tenant isolation for job_budgets"
ON job_budgets
FOR SELECT
USING (company_id = public.current_company_id());

CREATE POLICY "Supervisor/admin can manage job_budgets"
ON job_budgets
FOR ALL
USING (
  company_id = public.current_company_id()
  AND EXISTS (
    SELECT 1 FROM users
    WHERE users.id = auth.uid()
    AND users.role IN ('supervisor', 'admin', 'owner')
  )
)
WITH CHECK (
  company_id = public.current_company_id()
  AND EXISTS (
    SELECT 1 FROM users
    WHERE users.id = auth.uid()
    AND users.role IN ('supervisor', 'admin', 'owner')
  )
);

-- Helper: compute per-(job, user) clock_in -> clock_out durations in minutes.
-- clock_events is append-only event-sourced with no duration column; we pair
-- each clock_out with the immediately preceding clock_in for the same user
-- on the same job (matches the pairing logic in the timecards edge function).
CREATE OR REPLACE VIEW job_clock_durations AS
WITH clock_pairs AS (
  SELECT
    ce.job_id,
    ce.user_id,
    ce.event_subtype,
    ce.occurred_at,
    LAG(ce.occurred_at) OVER (
      PARTITION BY ce.job_id, ce.user_id
      ORDER BY ce.occurred_at
    ) AS prev_occurred_at,
    LAG(ce.event_subtype) OVER (
      PARTITION BY ce.job_id, ce.user_id
      ORDER BY ce.occurred_at
    ) AS prev_subtype
  FROM clock_events ce
)
SELECT
  job_id,
  user_id,
  EXTRACT(EPOCH FROM (occurred_at - prev_occurred_at)) / 60.0 AS minutes
FROM clock_pairs
WHERE event_subtype = 'clock_out'
  AND prev_subtype   = 'clock_in'
  AND prev_occurred_at IS NOT NULL;

-- View for budget vs actual reporting
CREATE VIEW job_budget_summary AS
SELECT
  jb.id,
  jb.company_id,
  jb.job_id,
  j.name AS job_name,
  j.code AS job_code,
  j.status AS job_status,
  jb.budgeted_hours,
  jb.budgeted_cost,
  jb.hourly_rate,
  jb.warning_threshold_percent,
  COALESCE(agg.actual_hours, 0) AS actual_hours,
  COALESCE(agg.actual_hours, 0) * jb.hourly_rate AS actual_cost,
  jb.created_by,
  jb.created_at,
  jb.updated_at
FROM job_budgets jb
JOIN jobs j ON j.id = jb.job_id
LEFT JOIN LATERAL (
  SELECT COALESCE(SUM(d.minutes), 0) / 60.0 AS actual_hours
  FROM job_clock_durations d
  WHERE d.job_id = jb.job_id
) agg ON true;

-- Function to calculate job labor costs
CREATE OR REPLACE FUNCTION calculate_job_labor_cost(p_job_id uuid)
RETURNS TABLE (
  actual_hours numeric,
  actual_cost numeric,
  worker_count bigint
) AS $$
DECLARE
  v_hourly_rate numeric;
BEGIN
  SELECT jb.hourly_rate INTO v_hourly_rate
  FROM job_budgets jb
  WHERE jb.job_id = p_job_id;

  v_hourly_rate := COALESCE(v_hourly_rate, 0);

  RETURN QUERY
  SELECT
    COALESCE(SUM(d.minutes) / 60.0, 0)::numeric           AS actual_hours,
    (COALESCE(SUM(d.minutes) / 60.0, 0) * v_hourly_rate)::numeric AS actual_cost,
    COUNT(DISTINCT d.user_id)                              AS worker_count
  FROM job_clock_durations d
  WHERE d.job_id = p_job_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;
