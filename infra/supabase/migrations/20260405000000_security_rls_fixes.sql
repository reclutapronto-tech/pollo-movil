-- ========================================================
-- Migration: 20260405000000_security_rls_fixes
-- Purpose:   Code review P0/P2 security hardening
--            - Enable RLS on api_guard tables (were fully unprotected)
--            - Add write policies for schedule_shifts (INSERT/UPDATE/DELETE)
--            - Add UPDATE policy for expense_events (approval workflow)
--            - Add INSERT policies for task_events and note_events
--            - Add missing indexes on ot_requests
-- ========================================================

-- ========================================================
-- 1. Enable RLS on api_guard tables
--    These tables hold sensitive per-user request history.
-- ========================================================

ALTER TABLE api_idempotency_keys ENABLE ROW LEVEL SECURITY;
ALTER TABLE api_request_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE ingest_event_keys ENABLE ROW LEVEL SECURITY;

-- api_idempotency_keys: users can only see their own records
CREATE POLICY "User isolation for api_idempotency_keys"
ON api_idempotency_keys
FOR SELECT
USING (user_id = auth.uid());

-- api_request_logs: users can only see their own records
CREATE POLICY "User isolation for api_request_logs"
ON api_request_logs
FOR SELECT
USING (user_id = auth.uid());

-- ingest_event_keys: restricted to service role only (edge functions bypass RLS).
-- No client-facing SELECT policy — these are internal dedup records.

-- ========================================================
-- 2. schedule_shifts write policies
--    Supervisors, admins, and owners can INSERT/UPDATE/DELETE.
--    Workers can only SELECT (already covered by tenant isolation policy).
-- ========================================================

CREATE POLICY "Supervisor schedule insert"
ON schedule_shifts
FOR INSERT
WITH CHECK (
  company_id = public.current_company_id()
  AND public.current_user_role() IN ('supervisor', 'admin', 'owner')
  AND created_by = auth.uid()
);

CREATE POLICY "Supervisor schedule update"
ON schedule_shifts
FOR UPDATE
USING (
  company_id = public.current_company_id()
  AND public.current_user_role() IN ('supervisor', 'admin', 'owner')
)
WITH CHECK (
  company_id = public.current_company_id()
  AND public.current_user_role() IN ('supervisor', 'admin', 'owner')
);

CREATE POLICY "Supervisor schedule delete"
ON schedule_shifts
FOR DELETE
USING (
  company_id = public.current_company_id()
  AND public.current_user_role() IN ('supervisor', 'admin', 'owner')
  AND status = 'draft'  -- cannot delete published shifts
);

-- ========================================================
-- 3. expense_events UPDATE policy (approval workflow)
--    Only supervisors/admins/owners for the same company can update
--    (approve/deny/reimburse). Workers cannot modify their own decisions.
-- ========================================================

CREATE POLICY "Supervisor expense approval update"
ON expense_events
FOR UPDATE
USING (
  company_id = public.current_company_id()
  AND public.current_user_role() IN ('supervisor', 'admin', 'owner')
  AND submitted_by != auth.uid()  -- cannot approve own expense
)
WITH CHECK (
  company_id = public.current_company_id()
  AND public.current_user_role() IN ('supervisor', 'admin', 'owner')
  AND submitted_by != auth.uid()
);

-- ========================================================
-- 4. task_events and note_events INSERT policies
--    Edge functions (service role) handle most writes, but
--    adding client-side policies prevents unintentional gaps.
-- ========================================================

CREATE POLICY "Worker task event insert"
ON task_events
FOR INSERT
WITH CHECK (
  company_id = public.current_company_id()
  AND user_id = auth.uid()
);

CREATE POLICY "Worker note event insert"
ON note_events
FOR INSERT
WITH CHECK (
  company_id = public.current_company_id()
  AND author_id = auth.uid()
);

-- ========================================================
-- 5. Missing indexes on ot_requests
--    worker_id and company_id are used in every OT query.
-- ========================================================

CREATE INDEX IF NOT EXISTS idx_ot_requests_worker_id
  ON ot_requests(worker_id);

CREATE INDEX IF NOT EXISTS idx_ot_requests_company_status
  ON ot_requests(company_id, status, requested_at DESC);
