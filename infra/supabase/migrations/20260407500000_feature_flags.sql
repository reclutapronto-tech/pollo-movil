-- ========================================================
-- Migration: 20260407500000_feature_flags
-- Purpose:   Company-level and global feature flags for safe rollouts.
--            Provides a feature_flags table (global defaults),
--            a company_feature_overrides table (per-company toggles),
--            and a helper function is_feature_enabled().
-- ========================================================

-- 1. feature_flags (global registry)

CREATE TABLE IF NOT EXISTS feature_flags (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  flag_key        text        NOT NULL UNIQUE,
  description     text,
  default_enabled boolean     NOT NULL DEFAULT false,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_feature_flags_key ON feature_flags(flag_key);

-- 2. company_feature_overrides (per-company toggles)

CREATE TABLE IF NOT EXISTS company_feature_overrides (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id      uuid        NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  flag_key        text        NOT NULL REFERENCES feature_flags(flag_key) ON DELETE CASCADE,
  enabled         boolean     NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (company_id, flag_key)
);

CREATE INDEX IF NOT EXISTS idx_company_feature_overrides_company
  ON company_feature_overrides(company_id);

-- 3. RLS

ALTER TABLE feature_flags ENABLE ROW LEVEL SECURITY;
ALTER TABLE company_feature_overrides ENABLE ROW LEVEL SECURITY;

-- feature_flags: everyone can read, only platform admins can manage
CREATE POLICY "Anyone can read feature flags"
  ON feature_flags FOR SELECT
  USING (true);

CREATE POLICY "Platform admins manage feature flags"
  ON feature_flags FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM platform_admins
      WHERE auth_user_id = auth.uid() AND is_active = true
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM platform_admins
      WHERE auth_user_id = auth.uid() AND is_active = true
    )
  );

-- company_feature_overrides: company users can read their own, owners/admins can manage
CREATE POLICY "Company users read their overrides"
  ON company_feature_overrides FOR SELECT
  USING (company_id = public.current_company_id());

CREATE POLICY "Company admins manage overrides"
  ON company_feature_overrides FOR ALL
  USING (
    company_id = public.current_company_id()
    AND public.current_user_role() IN ('owner', 'admin')
  )
  WITH CHECK (
    company_id = public.current_company_id()
    AND public.current_user_role() IN ('owner', 'admin')
  );

-- 4. Helper function

CREATE OR REPLACE FUNCTION is_feature_enabled(p_company_id uuid, p_flag_key text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT enabled FROM company_feature_overrides
     WHERE company_id = p_company_id AND flag_key = p_flag_key),
    (SELECT default_enabled FROM feature_flags
     WHERE flag_key = p_flag_key),
    false
  )
$$;

-- 5. Seed initial flags

INSERT INTO feature_flags (flag_key, description, default_enabled) VALUES
  ('ai_schedule_suggestions', 'AI-powered schedule recommendations',     true),
  ('expense_capture',         'Photo-based expense capture',             true),
  ('gps_breadcrumbs',         'GPS breadcrumb trail tracking',           true),
  ('photo_optimization',      'Automatic photo compression and WebP',    true),
  ('equipment_tracking',      'Equipment assignment and tracking',       false)
ON CONFLICT (flag_key) DO NOTHING;
