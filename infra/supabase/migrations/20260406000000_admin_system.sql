-- ═══════════════════════════════════════════════════════════
-- Admin System: Company Management, Platform Admin, Audit Trail
-- ═══════════════════════════════════════════════════════════

-- ─── 1. Extend companies table ──────────────────────────────

ALTER TABLE companies ADD COLUMN IF NOT EXISTS industry text;
ALTER TABLE companies ADD COLUMN IF NOT EXISTS address text;
ALTER TABLE companies ADD COLUMN IF NOT EXISTS phone text;
ALTER TABLE companies ADD COLUMN IF NOT EXISTS email text;
ALTER TABLE companies ADD COLUMN IF NOT EXISTS stripe_customer_id text;
ALTER TABLE companies ADD COLUMN IF NOT EXISTS payment_status text NOT NULL DEFAULT 'trialing';
ALTER TABLE companies ADD COLUMN IF NOT EXISTS logo_data_uri text;
ALTER TABLE companies ADD COLUMN IF NOT EXISTS settings_version int NOT NULL DEFAULT 1;

-- Constraint: payment_status values
ALTER TABLE companies DROP CONSTRAINT IF EXISTS chk_payment_status;
ALTER TABLE companies ADD CONSTRAINT chk_payment_status
  CHECK (payment_status IN ('trialing', 'active', 'past_due', 'cancelled'));

-- ─── 2. Admin UPDATE policies for companies and users ───────

-- Company owner/admin can update their own company
CREATE POLICY "Admin company update"
  ON companies FOR UPDATE
  USING (id = public.current_company_id() AND public.current_user_role() IN ('owner', 'admin'))
  WITH CHECK (id = public.current_company_id());

-- Company owner/admin can update users within their company.
-- Admins cannot modify owner rows or promote users to owner.
CREATE POLICY "Admin user update"
  ON users FOR UPDATE
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

-- ─── 3. Platform admins table (FieldOps internal staff) ─────

CREATE TABLE IF NOT EXISTS platform_admins (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_user_id uuid        NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  email        text        NOT NULL,
  full_name    text        NOT NULL,
  role         text        NOT NULL DEFAULT 'platform_admin',
  is_active    boolean     NOT NULL DEFAULT true,
  created_at   timestamptz NOT NULL DEFAULT NOW(),
  updated_at   timestamptz NOT NULL DEFAULT NOW()
);

-- No RLS on platform_admins — accessed only via service role key
-- from the super-admin app.

-- ─── 4. Platform admin invites ──────────────────────────────

CREATE TABLE IF NOT EXISTS platform_admin_invites (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  email        text        NOT NULL,
  invite_token text        NOT NULL UNIQUE DEFAULT encode(gen_random_bytes(32), 'hex'),
  expires_at   timestamptz NOT NULL DEFAULT (NOW() + INTERVAL '7 days'),
  claimed_at   timestamptz,
  created_by   uuid        REFERENCES platform_admins(id),
  created_at   timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_platform_admin_invites_token
  ON platform_admin_invites(invite_token) WHERE claimed_at IS NULL;

-- ─── 5. Admin audit log (SOC2/GDPR compliant) ──────────────

CREATE TABLE IF NOT EXISTS admin_audit_log (
  id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id       uuid        REFERENCES companies(id),
  actor_id         uuid,  -- could be company user or platform admin
  action           text        NOT NULL,
  target_type      text,  -- 'user', 'company', 'settings', 'invite', etc.
  target_id        text,  -- UUID or identifier of the target
  before_json      jsonb,
  after_json       jsonb,
  settings_version int,
  ip_address       text,
  user_agent       text,
  created_at       timestamptz NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_log_company
  ON admin_audit_log(company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_actor
  ON admin_audit_log(actor_id, created_at DESC);

-- No RLS — service-role-only access from edge functions.

-- ─── 6. Company summary view (for super-admin dashboard) ────

CREATE OR REPLACE VIEW company_summary AS
SELECT
  c.id,
  c.name,
  c.slug,
  c.status,
  c.payment_status,
  c.industry,
  c.logo_url,
  c.created_at,
  c.updated_at,
  COUNT(u.id) FILTER (WHERE u.is_active AND u.deleted_at IS NULL) AS active_user_count,
  COUNT(u.id) FILTER (WHERE u.deleted_at IS NULL) AS total_user_count
FROM companies c
LEFT JOIN users u ON u.company_id = c.id
WHERE c.deleted_at IS NULL
GROUP BY c.id;

-- ─── 7. Helper: is_platform_admin() ────────────────────────

CREATE OR REPLACE FUNCTION public.is_platform_admin()
RETURNS boolean
LANGUAGE sql SECURITY DEFINER SET search_path = public STABLE AS $$
  SELECT EXISTS (
    SELECT 1 FROM platform_admins
    WHERE auth_user_id = auth.uid() AND is_active = true
  )
$$;

-- ─── 8. Company-logos storage bucket ────────────────────────

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'company-logos',
  'company-logos',
  false,
  2097152,  -- 2MB
  ARRAY['image/jpeg', 'image/png', 'image/webp']::text[]
)
ON CONFLICT (id) DO UPDATE
SET
  name = EXCLUDED.name,
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types,
  updated_at = now();

-- ─── 9. Storage RLS for company logos ───────────────────────

-- Read: any authenticated user in the company can read the logo
CREATE POLICY "Company logo read"
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'company-logos'
    AND (storage.foldername(name))[1]::uuid = public.current_company_id()
  );

-- Write: only owner/admin can upload/overwrite
CREATE POLICY "Admin logo upload"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'company-logos'
    AND (storage.foldername(name))[1]::uuid = public.current_company_id()
    AND public.current_user_role() IN ('owner', 'admin')
  );

-- Delete: only owner/admin
CREATE POLICY "Admin logo delete"
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'company-logos'
    AND (storage.foldername(name))[1]::uuid = public.current_company_id()
    AND public.current_user_role() IN ('owner', 'admin')
  );

-- ─── 10. Set default company settings for existing companies ─

UPDATE companies
SET settings = settings || '{
  "stamp_branding": "name_only",
  "ot_rules": { "weekly_threshold": 40, "daily_threshold": null },
  "time_rounding": "off",
  "gps_required": true,
  "geofence_radius_default_m": 150,
  "break_alerts": true,
  "break_duration_min": 30,
  "pay_period": "weekly",
  "photo_on_clockin": false,
  "notifications": { "ot_approach": true, "missed_clockin": true, "shift_reminder": true },
  "onboarding_steps": { "logo_uploaded": false, "pay_period_set": false, "first_staff_invited": false }
}'::jsonb
WHERE settings = '{}'::jsonb OR settings IS NULL;
