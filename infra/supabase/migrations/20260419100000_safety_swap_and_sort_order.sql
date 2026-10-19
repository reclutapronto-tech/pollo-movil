-- ========================================================
-- Migration: 20260419100000_safety_swap_and_sort_order
-- Purpose:
--   1. Create public.safety_checklists      (immutable audit of pre-shift safety Q&A)
--   2. Create public.shift_swap_requests    (worker-initiated shift swap workflow)
--   3. Add schedule_shifts.sort_order       (foreman crew-view ordering)
--
-- Conventions:
--   - RLS helpers public.current_company_id() / public.current_user_role()
--     are defined in 20260403000003_rls_and_policies.sql.
--   - Trigger function set_updated_at() is defined in 20260403000000_foundation_tables.sql.
--   - user_role enum values: 'owner','admin','supervisor','foreman','worker'
--     (20260403000000_foundation_tables.sql).
--   - users.id === auth.uid() (FK to auth.users), so RLS uses auth.uid() directly.
--   - Idempotent: CREATE TABLE IF NOT EXISTS, ADD COLUMN IF NOT EXISTS,
--     CREATE INDEX IF NOT EXISTS. No destructive DDL. Safe to re-run.
-- ========================================================

-- ──────────────────────────────────────────────────────────────
-- 1. safety_checklists — immutable pre-shift safety audit trail
-- ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.safety_checklists (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id    uuid        NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  user_id       uuid        NOT NULL REFERENCES public.users(id)     ON DELETE CASCADE,
  job_id        uuid        NOT NULL REFERENCES public.jobs(id)      ON DELETE CASCADE,
  -- JSONB array of { question_id: uuid|text, answer: bool, answered_at: timestamptz }.
  responses     jsonb       NOT NULL,
  completed_at  timestamptz NOT NULL DEFAULT now(),
  created_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT safety_checklists_responses_is_array CHECK (jsonb_typeof(responses) = 'array')
);

-- Company-wide supervisor/admin roll-ups ordered by recency.
CREATE INDEX IF NOT EXISTS safety_checklists_company_completed_idx
  ON public.safety_checklists (company_id, completed_at DESC);

-- "Has this worker completed the checklist for this job today?" lookup.
CREATE INDEX IF NOT EXISTS safety_checklists_user_job_completed_idx
  ON public.safety_checklists (user_id, job_id, completed_at DESC);

ALTER TABLE public.safety_checklists ENABLE ROW LEVEL SECURITY;

-- Workers see their own completed checklists.
CREATE POLICY "Worker sees own safety checklists"
  ON public.safety_checklists
  FOR SELECT
  TO authenticated
  USING (
    company_id = public.current_company_id()
    AND user_id = auth.uid()
  );

-- Supervisors / foremen / admins / owners see every checklist in their company.
CREATE POLICY "Supervisors+ see company safety checklists"
  ON public.safety_checklists
  FOR SELECT
  TO authenticated
  USING (
    company_id = public.current_company_id()
    AND public.current_user_role() IN ('owner', 'admin', 'supervisor', 'foreman')
  );

-- Workers insert their own checklist — must match their auth.uid() and company.
CREATE POLICY "Worker inserts own safety checklist"
  ON public.safety_checklists
  FOR INSERT
  TO authenticated
  WITH CHECK (
    company_id = public.current_company_id()
    AND user_id = auth.uid()
  );

-- No UPDATE / DELETE policies are defined → RLS denies by default.
-- Safety checklists are an immutable audit trail.

GRANT SELECT, INSERT ON public.safety_checklists TO authenticated;

-- ──────────────────────────────────────────────────────────────
-- 2. shift_swap_requests — worker-initiated swap workflow
-- ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.shift_swap_requests (
  id                 uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id         uuid        NOT NULL REFERENCES public.companies(id)        ON DELETE CASCADE,
  shift_id           uuid        NOT NULL REFERENCES public.schedule_shifts(id)  ON DELETE CASCADE,
  requester_id       uuid        NOT NULL REFERENCES public.users(id)            ON DELETE CASCADE,
  swap_with_user_id  uuid        NULL     REFERENCES public.users(id)            ON DELETE SET NULL,
  notes              text        NULL,
  status             text        NOT NULL DEFAULT 'pending'
                                 CHECK (status IN ('pending', 'approved', 'denied', 'cancelled')),
  decided_by         uuid        NULL     REFERENCES public.users(id),
  decided_at         timestamptz NULL,
  decision_reason    text        NULL,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_shift_swap_requests_updated_at
BEFORE UPDATE ON public.shift_swap_requests
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Supervisor inbox: company pending queue ordered by age.
CREATE INDEX IF NOT EXISTS shift_swap_requests_company_status_created_idx
  ON public.shift_swap_requests (company_id, status, created_at DESC);

-- Worker's own requests grouped by state.
CREATE INDEX IF NOT EXISTS shift_swap_requests_requester_status_idx
  ON public.shift_swap_requests (requester_id, status);

ALTER TABLE public.shift_swap_requests ENABLE ROW LEVEL SECURITY;

-- Requester sees their own swap requests.
CREATE POLICY "Requester sees own swap requests"
  ON public.shift_swap_requests
  FOR SELECT
  TO authenticated
  USING (
    company_id = public.current_company_id()
    AND requester_id = auth.uid()
  );

-- Supervisors / foremen / admins / owners see all swap requests in their company.
CREATE POLICY "Supervisors+ see company swap requests"
  ON public.shift_swap_requests
  FOR SELECT
  TO authenticated
  USING (
    company_id = public.current_company_id()
    AND public.current_user_role() IN ('owner', 'admin', 'supervisor', 'foreman')
  );

-- Requester inserts own swap request. Guard: the referenced shift must belong
-- to this worker — prevents submitting swaps for someone else's shift.
CREATE POLICY "Requester inserts own swap request"
  ON public.shift_swap_requests
  FOR INSERT
  TO authenticated
  WITH CHECK (
    company_id = public.current_company_id()
    AND requester_id = auth.uid()
    AND status = 'pending'
    AND EXISTS (
      SELECT 1
      FROM public.schedule_shifts s
      WHERE s.id = shift_swap_requests.shift_id
        AND s.worker_id = auth.uid()
        AND s.company_id = public.current_company_id()
    )
  );

-- Supervisors+ decide (approve / deny) or cancel within their company.
CREATE POLICY "Supervisors+ decide swap requests"
  ON public.shift_swap_requests
  FOR UPDATE
  TO authenticated
  USING (
    company_id = public.current_company_id()
    AND public.current_user_role() IN ('owner', 'admin', 'supervisor', 'foreman')
  )
  WITH CHECK (
    company_id = public.current_company_id()
    AND public.current_user_role() IN ('owner', 'admin', 'supervisor', 'foreman')
  );

GRANT SELECT, INSERT, UPDATE ON public.shift_swap_requests TO authenticated;

-- ──────────────────────────────────────────────────────────────
-- 3. schedule_shifts.sort_order — foreman crew-view ordering
-- ──────────────────────────────────────────────────────────────
ALTER TABLE public.schedule_shifts
  ADD COLUMN IF NOT EXISTS sort_order integer NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS schedule_shifts_crew_order_idx
  ON public.schedule_shifts (company_id, shift_date, sort_order);

-- ========================================================
-- Summary of changes (2026-04-19):
--   1. Created public.safety_checklists
--        - columns: id, company_id, user_id, job_id, responses (jsonb),
--          completed_at, created_at
--        - indexes: (company_id, completed_at DESC),
--                   (user_id, job_id, completed_at DESC)
--        - RLS: worker-SELECT-own, supervisor+-SELECT-all, worker-INSERT-own
--        - immutable: no UPDATE / DELETE policies (denied by default)
--        - GRANT SELECT, INSERT to authenticated
--   2. Created public.shift_swap_requests
--        - columns: id, company_id, shift_id, requester_id, swap_with_user_id,
--          notes, status (pending/approved/denied/cancelled), decided_by,
--          decided_at, decision_reason, created_at, updated_at
--        - indexes: (company_id, status, created_at DESC),
--                   (requester_id, status)
--        - trigger: set_updated_at() on UPDATE
--        - RLS: requester-SELECT-own, supervisor+-SELECT-all,
--               requester-INSERT-own (shift must belong to them),
--               supervisor+-UPDATE for decide/cancel
--        - GRANT SELECT, INSERT, UPDATE to authenticated
--   3. Added schedule_shifts.sort_order integer NOT NULL DEFAULT 0
--        - new index schedule_shifts_crew_order_idx
--          (company_id, shift_date, sort_order)
-- ========================================================
