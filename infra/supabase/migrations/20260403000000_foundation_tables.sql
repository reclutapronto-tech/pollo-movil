-- ========================================================
-- Migration: 20260403000000_foundation_tables
-- Purpose:   Create extensions, enums, triggers, and core business tables (soft-deletes included)
-- ========================================================

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
-- Note: uuidv7 is supported natively in newer Postgres. We will use gen_random_uuid() as a fallback for v4 if v7 function is missing, or rely on application-supplied UUIDs. For this schema, we assume standard uuid defaults.

-- 1. Enums
CREATE TYPE user_role AS ENUM ('owner', 'admin', 'supervisor', 'foreman', 'worker');
CREATE TYPE project_status AS ENUM ('draft', 'active', 'on_hold', 'completed', 'archived');
CREATE TYPE job_status AS ENUM ('draft', 'active', 'in_progress', 'review', 'completed', 'archived');
CREATE TYPE task_status AS ENUM ('not_started', 'in_progress', 'blocked', 'completed', 'skipped');
CREATE TYPE clock_event_type AS ENUM ('clock_in', 'clock_out', 'break_start', 'break_end');
CREATE TYPE event_type AS ENUM (
  'clock_event', 'photo_event', 'task_event', 'note_event', 
  'ot_request_event', 'ot_approval_event', 'alert_event', 
  'correction_event', 'shift_report_event', 'assignment_event', 'job_status_event'
);
CREATE TYPE media_kind AS ENUM ('raw_photo', 'stamped_photo', 'thumbnail', 'report_pdf', 'video');
CREATE TYPE approval_decision AS ENUM ('pending', 'approved', 'denied');
CREATE TYPE visibility_scope AS ENUM ('internal', 'client');
CREATE TYPE sync_status AS ENUM ('pending', 'uploaded', 'processed', 'failed');
CREATE TYPE alert_status AS ENUM ('open', 'resolved', 'dismissed');
CREATE TYPE device_platform AS ENUM ('android', 'ios', 'web');
CREATE TYPE employment_type AS ENUM ('employee', 'contractor', 'temp');
CREATE TYPE export_kind AS ENUM (
  'timesheet_pdf', 'timesheet_csv', 'job_report_pdf', 
  'daily_shift_report_pdf', 'client_report_pdf', 'payroll_csv', 'kmz_export'
);

-- 2. Trigger Functions
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION prevent_event_mutation()
RETURNS TRIGGER AS $$
BEGIN
  RAISE EXCEPTION 'Event tables are append-only. Use correction_events for updates.';
END;
$$ LANGUAGE plpgsql;

-- 3. Core Tables

CREATE TABLE companies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  slug text UNIQUE NOT NULL,
  logo_url text,
  timezone text NOT NULL DEFAULT 'UTC',
  default_locale text NOT NULL DEFAULT 'en',
  status text NOT NULL DEFAULT 'active',
  settings jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  updated_at timestamptz NOT NULL DEFAULT NOW(),
  deleted_at timestamptz -- Soft delete support
);
CREATE TRIGGER trg_companies_updated_at BEFORE UPDATE ON companies FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE users (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
  role user_role NOT NULL,
  full_name text NOT NULL,
  email text,
  phone text,
  employment_type employment_type,
  language_code text NOT NULL DEFAULT 'en',
  timezone text,
  is_active boolean NOT NULL DEFAULT true,
  avatar_url text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  updated_at timestamptz NOT NULL DEFAULT NOW(),
  deleted_at timestamptz -- Soft delete support
);
CREATE TRIGGER trg_users_updated_at BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE devices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_platform device_platform NOT NULL,
  device_identifier text NOT NULL,
  app_version text,
  os_version text,
  model text,
  push_token text,
  last_seen_at timestamptz,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  updated_at timestamptz NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, device_identifier)
);
CREATE TRIGGER trg_devices_updated_at BEFORE UPDATE ON devices FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE projects (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
  name text NOT NULL,
  code text,
  status project_status NOT NULL DEFAULT 'draft',
  start_date date,
  end_date date,
  client_name text,
  client_reference text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_by uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT NOW(),
  updated_at timestamptz NOT NULL DEFAULT NOW(),
  deleted_at timestamptz -- Soft delete support
);
CREATE TRIGGER trg_projects_updated_at BEFORE UPDATE ON projects FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
  project_id uuid REFERENCES projects(id) ON DELETE SET NULL,
  name text NOT NULL,
  code text NOT NULL,
  status job_status NOT NULL DEFAULT 'draft',
  site_name text,
  address_line_1 text,
  address_line_2 text,
  city text,
  region text,
  postal_code text,
  country_code text,
  site_lat double precision,
  site_lng double precision,
  geofence_radius_m integer NOT NULL DEFAULT 100,
  scheduled_start_at timestamptz,
  scheduled_end_at timestamptz,
  actual_started_at timestamptz,
  actual_completed_at timestamptz,
  client_visible boolean NOT NULL DEFAULT false,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_by uuid NOT NULL REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT NOW(),
  updated_at timestamptz NOT NULL DEFAULT NOW(),
  deleted_at timestamptz, -- Soft delete support
  UNIQUE (company_id, code)
);
CREATE TRIGGER trg_jobs_updated_at BEFORE UPDATE ON jobs FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
  job_id uuid NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
  parent_task_id uuid REFERENCES tasks(id) ON DELETE CASCADE,
  name text NOT NULL,
  description text,
  status task_status NOT NULL DEFAULT 'not_started',
  sort_order integer NOT NULL DEFAULT 0,
  requires_photo boolean NOT NULL DEFAULT false,
  requires_before_after boolean NOT NULL DEFAULT false,
  checkpoint_code text,
  assigned_to uuid REFERENCES users(id),
  due_at timestamptz,
  completed_at timestamptz,
  completed_by uuid REFERENCES users(id),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  updated_at timestamptz NOT NULL DEFAULT NOW(),
  deleted_at timestamptz -- Soft delete support
);
CREATE TRIGGER trg_tasks_updated_at BEFORE UPDATE ON tasks FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
  job_id uuid NOT NULL REFERENCES jobs(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  assigned_role user_role NOT NULL,
  assigned_by uuid NOT NULL REFERENCES users(id),
  starts_at timestamptz,
  ends_at timestamptz,
  is_active boolean NOT NULL DEFAULT true,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  UNIQUE (job_id, user_id)
);

CREATE TABLE media_assets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES companies(id) ON DELETE RESTRICT,
  job_id uuid REFERENCES jobs(id) ON DELETE CASCADE,
  task_id uuid REFERENCES tasks(id) ON DELETE SET NULL,
  uploaded_by uuid NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
  kind media_kind NOT NULL DEFAULT 'raw_photo',
  bucket_name text NOT NULL,
  storage_path text NOT NULL,
  mime_type text,
  file_size_bytes bigint,
  width_px integer,
  height_px integer,
  sha256_hash text,
  perceptual_hash text,
  verification_code text,
  original_media_id uuid REFERENCES media_assets(id) ON DELETE SET NULL,
  stamped_media_id uuid REFERENCES media_assets(id) ON DELETE SET NULL,
  thumbnail_media_id uuid REFERENCES media_assets(id) ON DELETE SET NULL,
  sync_status sync_status NOT NULL DEFAULT 'pending',
  captured_at timestamptz,
  gps_lat double precision,
  gps_lng double precision,
  gps_accuracy_m double precision,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT NOW(),
  processed_at timestamptz,
  deleted_at timestamptz
);
