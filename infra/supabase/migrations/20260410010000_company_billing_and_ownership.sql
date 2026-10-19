-- =========================================================
-- Migration: 20260410010000_company_billing_and_ownership
-- Purpose:
--   1. Add Stripe subscription metadata to companies.
--   2. Add explicit tenant billing contact and plan state.
-- =========================================================

ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS stripe_subscription_id text;

ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS billing_email text;

ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS billing_plan text NOT NULL DEFAULT 'starter';

ALTER TABLE public.companies
  DROP CONSTRAINT IF EXISTS chk_billing_plan;

ALTER TABLE public.companies
  ADD CONSTRAINT chk_billing_plan
  CHECK (billing_plan IN ('starter', 'pro', 'business', 'enterprise'));

UPDATE public.companies
SET billing_email = COALESCE(billing_email, email)
WHERE billing_email IS NULL;
