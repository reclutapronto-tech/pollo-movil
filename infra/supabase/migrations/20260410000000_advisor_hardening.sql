-- =========================================================
-- Migration: 20260410000000_advisor_hardening
-- Purpose:
--   Resolve Supabase security advisor findings after initial
--   24-migration bootstrap:
--
--   1. security_definer_view (ERROR) — views created by a
--      superuser role default to SECURITY DEFINER semantics in
--      Supabase, bypassing RLS for the querying user. Set
--      security_invoker = true on every tenant-facing view so
--      they enforce the caller's RLS policies.
--
--   2. function_search_path_mutable (WARN) — trigger / helper
--      functions without SET search_path are exposed to
--      CVE-2018-1058 if the search_path is ever manipulated.
--      Pin search_path = public on every such function.
--
-- Author: production-readiness audit, 2026-04-10
-- =========================================================

-- ─── 1. Enable security_invoker on tenant-facing views ─────

ALTER VIEW public.job_timeline            SET (security_invoker = true);
ALTER VIEW public.company_summary         SET (security_invoker = true);
ALTER VIEW public.job_clock_durations     SET (security_invoker = true);
ALTER VIEW public.job_budget_summary      SET (security_invoker = true);
ALTER VIEW public.time_correction_summary SET (security_invoker = true);

-- ─── 2. Pin search_path on mutable-search_path functions ──

ALTER FUNCTION public.set_updated_at()                             SET search_path = public;
ALTER FUNCTION public.prevent_event_mutation()                     SET search_path = public;
ALTER FUNCTION public.enqueue_job(p_type text, p_payload jsonb, p_delay interval)
  SET search_path = public;
ALTER FUNCTION public.claim_next_job(p_types text[])                SET search_path = public;
ALTER FUNCTION public.complete_job(p_id uuid, p_error text)         SET search_path = public;
