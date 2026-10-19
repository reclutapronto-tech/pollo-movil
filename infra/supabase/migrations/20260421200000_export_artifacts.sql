-- Create export_artifacts: audit trail of generated reports/exports.
--
-- The reports edge function (functions/reports/index.ts) inserts a row here for
-- every job report, timesheet CSV, and photo packet it generates, and returns
-- the artifact_id to the client. The table was never created, so those inserts
-- silently failed (they are not error-checked) and artifact_id pointed at
-- nothing. Schema derived from the three insert sites (lines ~199, 251, 495).

CREATE TABLE IF NOT EXISTS public.export_artifacts (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id   uuid        NOT NULL REFERENCES public.companies(id) ON DELETE RESTRICT,
  job_id       uuid        REFERENCES public.jobs(id)  ON DELETE CASCADE,   -- nullable: timesheets aren't job-scoped
  generated_by uuid        REFERENCES public.users(id) ON DELETE SET NULL,
  export_kind  text        NOT NULL,   -- e.g. job_report_pdf, timesheet_csv, photo_insurance_claim
  status       text        NOT NULL DEFAULT 'completed',
  generated_at timestamptz NOT NULL DEFAULT NOW(),
  metadata     jsonb       NOT NULL DEFAULT '{}'::jsonb,
  created_at   timestamptz NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.export_artifacts IS
  'Audit trail of generated exports (reports, timesheets, photo packets). Written by the reports edge function via the service role.';

CREATE INDEX IF NOT EXISTS idx_export_artifacts_company
  ON public.export_artifacts(company_id, generated_at DESC);
CREATE INDEX IF NOT EXISTS idx_export_artifacts_job
  ON public.export_artifacts(job_id) WHERE job_id IS NOT NULL;

-- RLS: tenant-scoped reads for company members. Inserts happen via the service
-- role (reports function), which bypasses RLS, so no INSERT policy is needed.
ALTER TABLE public.export_artifacts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Tenant read export_artifacts" ON public.export_artifacts
  FOR SELECT USING (company_id = public.current_company_id());

GRANT SELECT ON public.export_artifacts TO authenticated;
