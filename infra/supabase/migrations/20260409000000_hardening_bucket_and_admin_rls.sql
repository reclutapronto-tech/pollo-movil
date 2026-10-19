-- =========================================================
-- Migration: 20260409000000_hardening_bucket_and_admin_rls
-- Purpose:
--   1. Create the `fieldops-media` storage bucket in hosted
--      environments. Previously only created in seed.sql,
--      which is not applied to hosted Supabase projects.
--   2. Enable RLS (default-deny) on admin tables so they
--      cannot be enumerated via PostgREST by authenticated
--      users. Service role still bypasses RLS automatically.
-- Author:   production-readiness audit, 2026-04-10
-- =========================================================

-- ─── 1. fieldops-media bucket (idempotent) ──────────────────
-- Matches seed.sql defaults: private, 20MB limit, jpg/png only.
-- Upload/read is gated by the storage RLS policies defined in
-- migration 20260404000100_storage_media_policies.sql which
-- scope access by company_id via foldername()[1].

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'fieldops-media',
  'fieldops-media',
  false,
  20971520,
  ARRAY['image/jpeg', 'image/png']::text[]
)
ON CONFLICT (id) DO UPDATE
SET
  public            = EXCLUDED.public,
  file_size_limit   = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types,
  updated_at        = NOW();

-- ─── 2. Admin table RLS (default-deny) ──────────────────────
-- These tables are intended for service-role-only access from
-- the platform_admin edge function. Without RLS enabled, they
-- are exposed to authenticated users via PostgREST. Enabling
-- RLS with zero policies = default deny for everyone except
-- service_role (which bypasses RLS).

ALTER TABLE public.platform_admins        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_admin_invites ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.admin_audit_log        ENABLE ROW LEVEL SECURITY;

-- Explicitly revoke from PostgREST-exposed roles as belt-and-suspenders.
REVOKE ALL ON public.platform_admins        FROM anon, authenticated;
REVOKE ALL ON public.platform_admin_invites FROM anon, authenticated;
REVOKE ALL ON public.admin_audit_log        FROM anon, authenticated;
