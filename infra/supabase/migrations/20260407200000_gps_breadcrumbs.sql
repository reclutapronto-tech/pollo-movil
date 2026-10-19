-- GPS Breadcrumb Trail: stores periodic GPS samples during active shifts
-- for route replay and supervisor oversight.

CREATE TABLE IF NOT EXISTS gps_breadcrumbs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id),
  job_id UUID NOT NULL REFERENCES jobs(id),
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  accuracy_m DOUBLE PRECISION,
  recorded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  shift_date DATE NOT NULL
);

ALTER TABLE gps_breadcrumbs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Workers insert own breadcrumbs" ON gps_breadcrumbs FOR INSERT
  WITH CHECK (user_id = auth.uid());
CREATE POLICY "Workers see own breadcrumbs" ON gps_breadcrumbs FOR SELECT
  USING (user_id = auth.uid());
CREATE POLICY "Supervisors see company breadcrumbs" ON gps_breadcrumbs FOR SELECT
  USING (user_id IN (SELECT id FROM users WHERE company_id IN (SELECT company_id FROM users WHERE id = auth.uid())));

CREATE INDEX IF NOT EXISTS idx_gps_breadcrumbs_user_shift ON gps_breadcrumbs(user_id, shift_date);
CREATE INDEX IF NOT EXISTS idx_gps_breadcrumbs_job_date ON gps_breadcrumbs(job_id, shift_date);
