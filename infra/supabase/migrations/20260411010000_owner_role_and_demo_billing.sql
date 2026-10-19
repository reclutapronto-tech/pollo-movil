-- =========================================================
-- Migration: 20260411010000_owner_role_and_demo_billing (Part 1 of 2)
-- Purpose:
--   1. Introduce a first-class tenant owner role for existing projects.
--   2. Add demo billing mode so billing pages work before Stripe is live.
-- NOTE: RLS policies that reference the new 'owner' enum value are in
--       20260411020000_owner_role_policies.sql — ALTER TYPE ADD VALUE
--       cannot be used in the same transaction as policies that reference it.
-- =========================================================

ALTER TYPE public.user_role ADD VALUE IF NOT EXISTS 'owner' BEFORE 'admin';

ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS billing_mode text NOT NULL DEFAULT 'demo';

ALTER TABLE public.companies
  DROP CONSTRAINT IF EXISTS chk_billing_mode;

ALTER TABLE public.companies
  ADD CONSTRAINT chk_billing_mode
  CHECK (billing_mode IN ('demo', 'stripe'));

UPDATE public.companies
SET billing_mode = 'demo'
WHERE billing_mode IS NULL;
