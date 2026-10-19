-- =========================================================
-- Migration: 20260410000001_jobs_write_policy
-- Purpose:
--   Add INSERT / UPDATE / DELETE policies for the jobs table
--   so that company admins and supervisors can manage jobs
--   directly from the client (e.g. the onboarding wizard and
--   the jobs management UI).
--
--   Without these policies the table is default-deny for
--   authenticated users — all writes from the web/mobile
--   client silently fail.
-- =========================================================

-- Owners, admins, and supervisors can create jobs for their company.
CREATE POLICY "Admin/supervisor can insert jobs"
ON jobs
FOR INSERT
WITH CHECK (
  company_id = public.current_company_id()
  AND public.current_user_role() IN ('owner', 'admin', 'supervisor')
);

-- Owners, admins, and supervisors can update jobs for their company.
CREATE POLICY "Admin/supervisor can update jobs"
ON jobs
FOR UPDATE
USING (company_id = public.current_company_id() AND public.current_user_role() IN ('owner', 'admin', 'supervisor'))
WITH CHECK (company_id = public.current_company_id());

-- Only owners/admins can delete (soft-delete via deleted_at) jobs.
CREATE POLICY "Admin can delete jobs"
ON jobs
FOR DELETE
USING (company_id = public.current_company_id() AND public.current_user_role() IN ('owner', 'admin'));
