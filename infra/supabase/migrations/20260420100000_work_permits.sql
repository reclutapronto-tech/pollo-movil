-- ========================================================
-- Migration: 20260420100000_work_permits
-- Purpose:
--   1. Create public.work_permits        (full-lifecycle work permit
--                                         issued by supervisor — required
--                                         before clock-in on regulated jobs:
--                                         HV electrical, confined space,
--                                         hot work, etc.)
--   2. Add jobs.requires_permit          (per-job toggle that drives the
--                                         mobile clock-in gate)
--   3. Add jobs.required_permit_type     (which permit type is required for
--                                         the gate to pass)
--
-- Conventions:
--   - RLS helpers public.current_company_id() / public.current_user_role()
--     are defined in 20260403000003_rls_and_policies.sql.
--   - Trigger function set_updated_at() is defined in 20260403000000_foundation_tables.sql.
--   - user_role enum values: 'owner','admin','supervisor','foreman','worker'
--     (20260403000000_foundation_tables.sql).
--   - users.id === auth.uid() (FK to auth.users), so RLS uses auth.uid() directly.
--   - Lifecycle: draft → issued → (active|expired|revoked).
--     'active' is a server-side projection (status='issued' AND expires_at > now()),
--     not a stored value — see edge function check_active. A future sweeper will
--     flip 'issued' rows whose expires_at has passed to 'expired'.
--   - Idempotent: CREATE TABLE IF NOT EXISTS, ADD COLUMN IF NOT EXISTS,
--     CREATE INDEX IF NOT EXISTS. No destructive DDL. Safe to re-run.
-- ========================================================

-- ──────────────────────────────────────────────────────────────
-- 1. work_permits — full-lifecycle work permit
-- ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.work_permits (
  id                 uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id         uuid        NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  job_id             uuid        NOT NULL REFERENCES public.jobs(id)      ON DELETE CASCADE,
  permit_number      text        NOT NULL,
  permit_type        text        NOT NULL
                                 CHECK (permit_type IN (
                                   'hv_electrical',
                                   'confined_space',
                                   'hot_work',
                                   'working_at_heights',
                                   'lockout_tagout',
                                   'excavation',
                                   'general',
                                   'other'
                                 )),
  description        text        NULL,
  status             text        NOT NULL DEFAULT 'draft'
                                 CHECK (status IN ('draft', 'issued', 'active', 'expired', 'revoked')),
  issued_by          uuid        NULL     REFERENCES public.users(id),
  issued_at          timestamptz NULL,
  -- expires_at NULL means "never expires" — open-ended permit valid for the
  -- duration of the job. Active = status='issued' AND (expires_at IS NULL OR expires_at > now()).
  expires_at         timestamptz NULL,
  revoked_by         uuid        NULL     REFERENCES public.users(id),
  revoked_at         timestamptz NULL,
  revocation_reason  text        NULL,
  pdf_path           text        NULL,
  created_by         uuid        NOT NULL REFERENCES public.users(id),
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  -- Permit numbers are issued by an external regulator and should not be
  -- duplicated within a company.
  UNIQUE (company_id, permit_number)
);

CREATE TRIGGER trg_work_permits_updated_at
BEFORE UPDATE ON public.work_permits
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- "Is there an active permit for this job?" — drives the mobile clock-in gate
-- and the check_active edge action.
CREATE INDEX IF NOT EXISTS work_permits_company_job_status_idx
  ON public.work_permits (company_id, job_id, status);

-- Drives the future expiry-sweeper job (find issued rows past expires_at).
CREATE INDEX IF NOT EXISTS work_permits_company_expires_idx
  ON public.work_permits (company_id, expires_at);

-- Drives the job-detail "permits on this job" panel.
CREATE INDEX IF NOT EXISTS work_permits_job_status_idx
  ON public.work_permits (job_id, status);

ALTER TABLE public.work_permits ENABLE ROW LEVEL SECURITY;

-- SELECT: any authenticated user in the caller's company.
CREATE POLICY "Company sees work permits"
  ON public.work_permits
  FOR SELECT
  TO authenticated
  USING (
    company_id = public.current_company_id()
  );

-- INSERT: owner/admin/supervisor only, scoped to their company.
CREATE POLICY "Supervisors+ insert work permits"
  ON public.work_permits
  FOR INSERT
  TO authenticated
  WITH CHECK (
    company_id = public.current_company_id()
    AND public.current_user_role() IN ('owner', 'admin', 'supervisor')
  );

-- UPDATE: owner/admin/supervisor only, scoped to their company.
CREATE POLICY "Supervisors+ update work permits"
  ON public.work_permits
  FOR UPDATE
  TO authenticated
  USING (
    company_id = public.current_company_id()
    AND public.current_user_role() IN ('owner', 'admin', 'supervisor')
  )
  WITH CHECK (
    company_id = public.current_company_id()
    AND public.current_user_role() IN ('owner', 'admin', 'supervisor')
  );

-- DELETE: owner/admin/supervisor only, scoped to their company.
CREATE POLICY "Supervisors+ delete work permits"
  ON public.work_permits
  FOR DELETE
  TO authenticated
  USING (
    company_id = public.current_company_id()
    AND public.current_user_role() IN ('owner', 'admin', 'supervisor')
  );

GRANT SELECT, INSERT, UPDATE, DELETE ON public.work_permits TO authenticated;

-- ──────────────────────────────────────────────────────────────
-- 2. jobs.requires_permit + jobs.required_permit_type
-- ──────────────────────────────────────────────────────────────
ALTER TABLE public.jobs
  ADD COLUMN IF NOT EXISTS requires_permit boolean NOT NULL DEFAULT false;

ALTER TABLE public.jobs
  ADD COLUMN IF NOT EXISTS required_permit_type text NULL
  CHECK (required_permit_type IN (
    'hv_electrical',
    'confined_space',
    'hot_work',
    'working_at_heights',
    'lockout_tagout',
    'excavation',
    'general',
    'other'
  ));

-- ========================================================
-- Summary of changes (2026-04-20):
--   1. Created public.work_permits
--        - columns: id, company_id, job_id, permit_number, permit_type
--          (hv_electrical / confined_space / hot_work / working_at_heights /
--          lockout_tagout / excavation / general / other), description,
--          status (draft/issued/active/expired/revoked), issued_by, issued_at,
--          expires_at (NULL = never expires), revoked_by, revoked_at,
--          revocation_reason, pdf_path, created_by, created_at, updated_at
--        - UNIQUE (company_id, permit_number)
--        - indexes: (company_id, job_id, status),
--                   (company_id, expires_at),
--                   (job_id, status)
--        - trigger: set_updated_at() on UPDATE
--        - RLS: company-SELECT-all, supervisor+-INSERT/UPDATE/DELETE
--        - GRANT SELECT, INSERT, UPDATE, DELETE to authenticated
--   2. Added jobs.requires_permit boolean NOT NULL DEFAULT false
--        - drives the mobile clock-in permit gate
--   3. Added jobs.required_permit_type text NULL (same enum as work_permits)
--        - nullable; only consulted when requires_permit = true
-- ========================================================
