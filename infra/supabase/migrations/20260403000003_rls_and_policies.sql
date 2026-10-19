-- ========================================================
-- Migration: 20260403000003_rls_and_policies
-- Purpose:   Row Level Security definitions for Multi-Tenant Isolation
-- ========================================================

-- Helper function to fetch the current user's mapped company_id safely
CREATE OR REPLACE FUNCTION public.current_company_id()
RETURNS uuid
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT company_id
  FROM public.users
  WHERE id = auth.uid()
$$;

-- Helper function to fetch the current user's role safely
CREATE OR REPLACE FUNCTION public.current_user_role()
RETURNS text
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT role::text
  FROM public.users
  WHERE id = auth.uid()
$$;

-- ========================================================
-- Enable RLS across all tables
-- ========================================================

ALTER TABLE companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE media_assets ENABLE ROW LEVEL SECURITY;

ALTER TABLE clock_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE photo_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE task_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE note_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE ot_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE ot_approval_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE alert_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE correction_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE shift_report_events ENABLE ROW LEVEL SECURITY;

-- ========================================================
-- Core Tenant Isolation Policies
-- Rule: You can only SELECT rows that belong to your company
-- ========================================================

CREATE POLICY "Tenant isolation for companies" ON companies FOR SELECT USING (id = public.current_company_id());
CREATE POLICY "Tenant isolation for users" ON users FOR SELECT USING (company_id = public.current_company_id());
CREATE POLICY "Tenant isolation for devices" ON devices FOR SELECT USING (company_id = public.current_company_id());
CREATE POLICY "Tenant isolation for projects" ON projects FOR SELECT USING (company_id = public.current_company_id());
CREATE POLICY "Tenant isolation for jobs" ON jobs FOR SELECT USING (company_id = public.current_company_id());
CREATE POLICY "Tenant isolation for tasks" ON tasks FOR SELECT USING (company_id = public.current_company_id());
CREATE POLICY "Tenant isolation for assignments" ON assignments FOR SELECT USING (company_id = public.current_company_id());
CREATE POLICY "Tenant isolation for media_assets" ON media_assets FOR SELECT USING (company_id = public.current_company_id());

CREATE POLICY "Tenant isolation for clock_events" ON clock_events FOR SELECT USING (company_id = public.current_company_id());
CREATE POLICY "Tenant isolation for photo_events" ON photo_events FOR SELECT USING (company_id = public.current_company_id());
CREATE POLICY "Tenant isolation for task_events" ON task_events FOR SELECT USING (company_id = public.current_company_id());
CREATE POLICY "Tenant isolation for note_events" ON note_events FOR SELECT USING (company_id = public.current_company_id());
CREATE POLICY "Tenant isolation for ot_requests" ON ot_requests FOR SELECT USING (company_id = public.current_company_id());
CREATE POLICY "Tenant isolation for ot_approval_events" ON ot_approval_events FOR SELECT USING (company_id = public.current_company_id());
CREATE POLICY "Tenant isolation for alert_events" ON alert_events FOR SELECT USING (company_id = public.current_company_id());
CREATE POLICY "Tenant isolation for correction_events" ON correction_events FOR SELECT USING (company_id = public.current_company_id());
CREATE POLICY "Tenant isolation for shift_report_events" ON shift_report_events FOR SELECT USING (company_id = public.current_company_id());

-- ========================================================
-- Strict Write Patterns (Edge Functions Bypass RLS)
-- ========================================================

-- Users can only INSERT events into their own company scoping (and they must be the auth.uid)
CREATE POLICY "Worker clock event insert" ON clock_events FOR INSERT WITH CHECK (
  company_id = public.current_company_id() AND user_id = auth.uid()
);

CREATE POLICY "Worker photo event insert" ON photo_events FOR INSERT WITH CHECK (
  company_id = public.current_company_id() AND user_id = auth.uid()
);

-- Note: Because standard client access is incredibly locked down, most mutations (like batch offline sync)
-- are processed via Edge Functions utilizing the SUPERBASE_SERVICE_ROLE key which natively bypasses RLS.
