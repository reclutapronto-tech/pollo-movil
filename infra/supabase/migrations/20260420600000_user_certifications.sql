-- User certifications registry (Phase 1 of FUX-016).
--
-- Why: safety/compliance alerts (e.g., HV electrical, OSHA-30, first-aid)
-- expire. Today FieldOps has no way to surface "worker X's cert expires in
-- 7 days" — the PRD calls for this but nothing in the schema tracks it.
--
-- Scope (this migration):
--   - user_certifications table with expires_at
--   - RLS: any company user SELECT; admin-only INSERT/UPDATE/DELETE
--   - Indexes for the upcoming alert scan (company + expires_at, user)
--
-- Out of scope (tracked as FUX-016b):
--   - Admin /settings/certifications CRUD page
--   - Document storage for attached cert PDFs
--   - "Expire" sweeper cron (certs don't need flip-to-expired like permits;
--     the alert scan computes "expiring within N days" in SQL against the
--     live expires_at value).

CREATE TABLE IF NOT EXISTS public.user_certifications (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id    uuid        NOT NULL REFERENCES public.companies(id) ON DELETE RESTRICT,
  user_id       uuid        NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  cert_type     text        NOT NULL,    -- free-form label for Phase 1: "OSHA-30", "HV Electrical", etc.
  cert_number   text        NULL,        -- optional issuer-issued identifier
  issuer        text        NULL,
  issued_at     date        NULL,
  expires_at    date        NULL,        -- NULL = non-expiring
  document_path text        NULL,        -- Storage bucket path, populated by FUX-016b
  notes         text        NULL,
  created_at    timestamptz NOT NULL DEFAULT NOW(),
  updated_at    timestamptz NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.user_certifications IS
  'Worker certifications with optional expiration. expires_at NULL means non-expiring. Alert scan surfaces rows expiring within 14 days.';

-- updated_at auto-bump via shared helper
DROP TRIGGER IF EXISTS set_user_certifications_updated_at ON public.user_certifications;
CREATE TRIGGER set_user_certifications_updated_at
  BEFORE UPDATE ON public.user_certifications
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Indexes: scan-by-expiry + lookup-by-user
CREATE INDEX IF NOT EXISTS user_certifications_company_expires_idx
  ON public.user_certifications (company_id, expires_at)
  WHERE expires_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS user_certifications_user_idx
  ON public.user_certifications (user_id);

-- RLS
ALTER TABLE public.user_certifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Tenant read user_certifications" ON public.user_certifications
  FOR SELECT USING (company_id = public.current_company_id());

CREATE POLICY "Admin insert user_certifications" ON public.user_certifications
  FOR INSERT WITH CHECK (
    company_id = public.current_company_id()
    AND public.current_user_role() IN ('admin', 'owner')
  );

CREATE POLICY "Admin update user_certifications" ON public.user_certifications
  FOR UPDATE USING (
    company_id = public.current_company_id()
    AND public.current_user_role() IN ('admin', 'owner')
  );

CREATE POLICY "Admin delete user_certifications" ON public.user_certifications
  FOR DELETE USING (
    company_id = public.current_company_id()
    AND public.current_user_role() IN ('admin', 'owner')
  );

GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_certifications TO authenticated;
