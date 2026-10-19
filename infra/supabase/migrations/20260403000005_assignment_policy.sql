-- ========================================================
-- Migration: 20260403000005_assignment_policy
-- Purpose:   Tighten assignment visibility so workers only see their own assignments while supervisors can see team assignments.
-- ========================================================

DROP POLICY IF EXISTS "Tenant isolation for assignments" ON assignments;

CREATE POLICY "Assignment visibility" ON assignments
FOR SELECT
USING (
  company_id = public.current_company_id()
  AND (
    user_id = auth.uid()
    OR public.current_user_role() IN ('admin', 'supervisor', 'foreman')
  )
);
