-- ========================================================
-- Migration: 20260419110000_pto_allocations
-- Purpose:
--   Create public.pto_allocations — per-company, per-user, per-year,
--   per-pto_type total-day allocations. Backs the pto edge function's
--   `balance` action (replacing the hardcoded DEFAULT_ALLOCATIONS fallback)
--   and the new `allocations_list` / `allocations_upsert` admin actions.
--
-- Conventions:
--   - RLS helpers public.current_company_id() / public.current_user_role()
--     are defined in 20260403000003_rls_and_policies.sql.
--   - Trigger function set_updated_at() is defined in 20260403000000_foundation_tables.sql.
--   - user_role enum values: 'owner','admin','supervisor','foreman','worker'
--     (20260403000000_foundation_tables.sql).
--   - users.id === auth.uid() (FK to auth.users), so RLS uses auth.uid() directly.
--   - Idempotent: CREATE TABLE IF NOT EXISTS, CREATE INDEX IF NOT EXISTS.
--     No destructive DDL. Safe to re-run.
-- ========================================================

-- ──────────────────────────────────────────────────────────────
-- pto_allocations — per-worker PTO day totals by year & type
-- ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.pto_allocations (
  id          uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  uuid          NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  user_id     uuid          NOT NULL REFERENCES public.users(id)     ON DELETE CASCADE,
  pto_type    text          NOT NULL CHECK (pto_type IN ('vacation', 'sick', 'personal')),
  year        int           NOT NULL,
  total_days  numeric(6, 2) NOT NULL CHECK (total_days >= 0),
  created_at  timestamptz   NOT NULL DEFAULT now(),
  updated_at  timestamptz   NOT NULL DEFAULT now(),
  UNIQUE (company_id, user_id, pto_type, year)
);

CREATE TRIGGER trg_pto_allocations_updated_at
BEFORE UPDATE ON public.pto_allocations
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Admin roll-ups: all allocations for a company in a given year.
CREATE INDEX IF NOT EXISTS pto_allocations_company_year_idx
  ON public.pto_allocations (company_id, year);

-- Worker balance lookup: all of a user's allocations for a given year.
CREATE INDEX IF NOT EXISTS pto_allocations_user_year_idx
  ON public.pto_allocations (user_id, year);

ALTER TABLE public.pto_allocations ENABLE ROW LEVEL SECURITY;

-- Workers see their own allocation rows.
CREATE POLICY "Worker sees own pto allocations"
  ON public.pto_allocations
  FOR SELECT
  TO authenticated
  USING (
    company_id = public.current_company_id()
    AND user_id = auth.uid()
  );

-- Supervisors / foremen / admins / owners see every allocation in their company.
CREATE POLICY "Supervisors+ see company pto allocations"
  ON public.pto_allocations
  FOR SELECT
  TO authenticated
  USING (
    company_id = public.current_company_id()
    AND public.current_user_role() IN ('owner', 'admin', 'supervisor', 'foreman')
  );

-- Admins / owners insert allocations (company-scoped).
CREATE POLICY "Admins insert pto allocations"
  ON public.pto_allocations
  FOR INSERT
  TO authenticated
  WITH CHECK (
    company_id = public.current_company_id()
    AND public.current_user_role() IN ('owner', 'admin')
  );

-- Admins / owners update allocations (company-scoped).
CREATE POLICY "Admins update pto allocations"
  ON public.pto_allocations
  FOR UPDATE
  TO authenticated
  USING (
    company_id = public.current_company_id()
    AND public.current_user_role() IN ('owner', 'admin')
  )
  WITH CHECK (
    company_id = public.current_company_id()
    AND public.current_user_role() IN ('owner', 'admin')
  );

-- Admins / owners delete allocations (company-scoped).
CREATE POLICY "Admins delete pto allocations"
  ON public.pto_allocations
  FOR DELETE
  TO authenticated
  USING (
    company_id = public.current_company_id()
    AND public.current_user_role() IN ('owner', 'admin')
  );

GRANT SELECT, INSERT, UPDATE, DELETE ON public.pto_allocations TO authenticated;

-- ========================================================
-- Summary of changes (2026-04-19):
--   1. Created public.pto_allocations
--        - columns: id, company_id, user_id, pto_type (vacation/sick/personal),
--          year, total_days numeric(6,2) >= 0, created_at, updated_at
--        - unique: (company_id, user_id, pto_type, year)
--        - indexes: (company_id, year), (user_id, year)
--        - trigger: set_updated_at() on UPDATE
--        - RLS: worker-SELECT-own, supervisor+-SELECT-all,
--               admin/owner-INSERT/UPDATE/DELETE (company-scoped)
--        - GRANT SELECT, INSERT, UPDATE, DELETE to authenticated
-- ========================================================
