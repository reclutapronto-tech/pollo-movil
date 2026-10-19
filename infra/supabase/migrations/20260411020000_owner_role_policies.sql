-- =========================================================
-- Migration: 20260411020000_owner_role_policies (Part 2 of 2)
-- Purpose:
--   Rebuild RLS policies so owners inherit admin-level company control.
--   Must run in a separate transaction from 20260411010000 because
--   PostgreSQL forbids using a newly-added enum value in the same
--   transaction as the ALTER TYPE ADD VALUE statement.
-- =========================================================

DROP POLICY IF EXISTS "Admin company update" ON public.companies;
CREATE POLICY "Admin company update"
  ON public.companies FOR UPDATE
  USING (id = public.current_company_id() AND public.current_user_role() IN ('owner', 'admin'))
  WITH CHECK (id = public.current_company_id());

DROP POLICY IF EXISTS "Admin user update" ON public.users;
CREATE POLICY "Admin user update"
  ON public.users FOR UPDATE
  USING (
    company_id = public.current_company_id()
    AND (
      public.current_user_role() = 'owner'
      OR (public.current_user_role() = 'admin' AND role <> 'owner')
    )
  )
  WITH CHECK (
    company_id = public.current_company_id()
    AND (
      public.current_user_role() = 'owner'
      OR (public.current_user_role() = 'admin' AND role <> 'owner')
    )
  );

DROP POLICY IF EXISTS "Company admins manage overrides" ON public.company_feature_overrides;
CREATE POLICY "Company admins manage overrides"
  ON public.company_feature_overrides FOR ALL
  USING (
    company_id = public.current_company_id()
    AND public.current_user_role() IN ('owner', 'admin')
  )
  WITH CHECK (
    company_id = public.current_company_id()
    AND public.current_user_role() IN ('owner', 'admin')
  );

DROP POLICY IF EXISTS "Admin/supervisor can insert jobs" ON public.jobs;
CREATE POLICY "Admin/supervisor can insert jobs"
  ON public.jobs FOR INSERT
  WITH CHECK (
    company_id = public.current_company_id()
    AND public.current_user_role() IN ('owner', 'admin', 'supervisor')
  );

DROP POLICY IF EXISTS "Admin/supervisor can update jobs" ON public.jobs;
CREATE POLICY "Admin/supervisor can update jobs"
  ON public.jobs FOR UPDATE
  USING (company_id = public.current_company_id() AND public.current_user_role() IN ('owner', 'admin', 'supervisor'))
  WITH CHECK (company_id = public.current_company_id());

DROP POLICY IF EXISTS "Admin can delete jobs" ON public.jobs;
CREATE POLICY "Admin can delete jobs"
  ON public.jobs FOR DELETE
  USING (company_id = public.current_company_id() AND public.current_user_role() IN ('owner', 'admin'));

DROP POLICY IF EXISTS "Supervisor schedule insert" ON public.schedule_shifts;
CREATE POLICY "Supervisor schedule insert"
  ON public.schedule_shifts FOR INSERT
  WITH CHECK (
    company_id = public.current_company_id()
    AND public.current_user_role() IN ('supervisor', 'admin', 'owner')
    AND created_by = auth.uid()
  );

DROP POLICY IF EXISTS "Supervisor schedule update" ON public.schedule_shifts;
CREATE POLICY "Supervisor schedule update"
  ON public.schedule_shifts FOR UPDATE
  USING (
    company_id = public.current_company_id()
    AND public.current_user_role() IN ('supervisor', 'admin', 'owner')
  )
  WITH CHECK (
    company_id = public.current_company_id()
    AND public.current_user_role() IN ('supervisor', 'admin', 'owner')
  );

DROP POLICY IF EXISTS "Supervisor schedule delete" ON public.schedule_shifts;
CREATE POLICY "Supervisor schedule delete"
  ON public.schedule_shifts FOR DELETE
  USING (
    company_id = public.current_company_id()
    AND public.current_user_role() IN ('supervisor', 'admin', 'owner')
    AND status = 'draft'
  );

DROP POLICY IF EXISTS "Supervisor expense approval update" ON public.expense_events;
CREATE POLICY "Supervisor expense approval update"
  ON public.expense_events FOR UPDATE
  USING (
    company_id = public.current_company_id()
    AND public.current_user_role() IN ('supervisor', 'admin', 'owner')
    AND submitted_by != auth.uid()
  )
  WITH CHECK (
    company_id = public.current_company_id()
    AND public.current_user_role() IN ('supervisor', 'admin', 'owner')
    AND submitted_by != auth.uid()
  );

DROP POLICY IF EXISTS "Supervisor PTO decision" ON public.pto_requests;
CREATE POLICY "Supervisor PTO decision"
  ON public.pto_requests FOR UPDATE
  USING (
    company_id = public.current_company_id()
    AND public.current_user_role() IN ('supervisor', 'admin', 'owner')
    AND status = 'pending'
  )
  WITH CHECK (
    status IN ('approved', 'denied')
    AND decided_by = auth.uid()
  );

DROP POLICY IF EXISTS "Supervisor/admin can manage job_budgets" ON public.job_budgets;
CREATE POLICY "Supervisor/admin can manage job_budgets"
  ON public.job_budgets FOR ALL
  USING (
    company_id = public.current_company_id()
    AND EXISTS (
      SELECT 1 FROM public.users
      WHERE users.id = auth.uid()
      AND users.role IN ('supervisor', 'admin', 'owner')
    )
  )
  WITH CHECK (
    company_id = public.current_company_id()
    AND EXISTS (
      SELECT 1 FROM public.users
      WHERE users.id = auth.uid()
      AND users.role IN ('supervisor', 'admin', 'owner')
    )
  );

DROP POLICY IF EXISTS "Supervisors can view company time_corrections" ON public.time_corrections;
CREATE POLICY "Supervisors can view company time_corrections"
  ON public.time_corrections FOR SELECT
  USING (
    company_id = public.current_company_id()
    AND EXISTS (
      SELECT 1 FROM public.users
      WHERE users.id = auth.uid()
      AND users.role IN ('supervisor', 'admin', 'owner', 'foreman')
    )
  );

DROP POLICY IF EXISTS "Supervisors can create time_corrections" ON public.time_corrections;
CREATE POLICY "Supervisors can create time_corrections"
  ON public.time_corrections FOR INSERT
  WITH CHECK (
    company_id = public.current_company_id()
    AND EXISTS (
      SELECT 1 FROM public.users
      WHERE users.id = auth.uid()
      AND users.role IN ('supervisor', 'admin', 'owner', 'foreman')
    )
  );

DROP POLICY IF EXISTS "Supervisors can update time_corrections" ON public.time_corrections;
CREATE POLICY "Supervisors can update time_corrections"
  ON public.time_corrections FOR UPDATE
  USING (
    company_id = public.current_company_id()
    AND EXISTS (
      SELECT 1 FROM public.users
      WHERE users.id = auth.uid()
      AND users.role IN ('supervisor', 'admin', 'owner')
    )
  );

DROP POLICY IF EXISTS "Admin logo upload" ON storage.objects;
CREATE POLICY "Admin logo upload"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'company-logos'
    AND (storage.foldername(name))[1]::uuid = public.current_company_id()
    AND public.current_user_role() IN ('owner', 'admin')
  );

DROP POLICY IF EXISTS "Admin logo delete" ON storage.objects;
CREATE POLICY "Admin logo delete"
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'company-logos'
    AND (storage.foldername(name))[1]::uuid = public.current_company_id()
    AND public.current_user_role() IN ('owner', 'admin')
  );
