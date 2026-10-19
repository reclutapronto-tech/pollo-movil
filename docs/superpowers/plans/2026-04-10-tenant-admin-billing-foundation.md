# Tenant Admin And Billing Foundation Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish the multi-tenant admin slice so company admins can safely manage only their own company, platform admins can accurately manage all companies, and the codebase is ready for Stripe-backed billing and entitlements.

**Architecture:** Keep the current shared-infra multi-tenant model and harden the management plane before adding monetization. First fix correctness gaps in the existing platform-admin flow, then add tenant-facing billing surfaces and Stripe sync, then add a clearer ownership/permissions model on top of the stable foundation.

**Tech Stack:** Supabase Auth + Postgres RLS + Edge Functions, Next.js App Router, Stripe Billing, repo-local regression tests in `execution/`

---

## File Map

- Modify: `infra/supabase/functions/platform_admin/index.ts`
- Modify: `apps/fieldops_admin/src/app/page.tsx`
- Modify: `apps/fieldops_admin/src/app/companies/page.tsx`
- Modify: `apps/fieldops_admin/src/app/companies/[id]/page.tsx`
- Modify: `apps/fieldops_admin/src/lib/types.ts`
- Create: `execution/test_platform_admin.py`
- Modify: `SPRINT_TRACKER.md`
- Modify: `apps/fieldops_web/src/app/settings/page.tsx`
- Modify: `apps/fieldops_web/src/app/settings/staff/page.tsx`
- Create: `apps/fieldops_web/src/app/settings/billing/page.tsx`
- Create: `infra/supabase/migrations/20260410010000_company_billing_and_ownership.sql`
- Create: `infra/supabase/functions/billing_portal/index.ts`
- Create: `infra/supabase/functions/stripe_webhook/index.ts`
- Create: `execution/test_billing_foundation.py`

## Scope Notes

- This plan intentionally covers one execution slice with three phases:
  1. Correct the existing admin plane.
  2. Add tenant billing foundations.
  3. Tighten ownership and permissions.
- Do **not** start custom role builder, white-label, QuickBooks, or AI work in this slice.
- Do **not** switch to tenant-per-database or tenant-per-project architecture in this slice.

### Task 1: Finish The Existing Platform-Admin Contract

**Files:**
- Modify: `infra/supabase/functions/platform_admin/index.ts`
- Modify: `apps/fieldops_admin/src/app/page.tsx`
- Modify: `apps/fieldops_admin/src/app/companies/page.tsx`
- Modify: `apps/fieldops_admin/src/app/companies/[id]/page.tsx`
- Modify: `apps/fieldops_admin/src/lib/types.ts`
- Create: `execution/test_platform_admin.py`
- Modify: `SPRINT_TRACKER.md`

- [ ] **Step 1: Write the failing regression test for the platform-admin list/detail contract**

```python
def test_list_companies_returns_summary_counts():
    payload = get_platform_admin("list_companies")
    company = payload["companies"][0]
    assert "active_user_count" in company
    assert "total_user_count" in company

def test_toggle_company_action_matches_ui_flow():
    result = post_platform_admin({"action": "toggle_company", "company_id": COMPANY_ID, "status": "suspended"})
    assert result["new_status"] == "suspended"
```

- [ ] **Step 2: Run test to verify current behavior fails or is incomplete**

Run: `python3 execution/test_platform_admin.py -v`
Expected: FAIL because `list_companies` reads from `companies` instead of `company_summary`, and the company detail page posts `update_company` while the edge function expects `toggle_company`.

- [ ] **Step 3: Fix the edge-function contract**

```ts
let query = supabaseAdmin
  .from("company_summary")
  .select("*")
  .order("created_at", { ascending: false })
  .limit(100)
```

```ts
body: JSON.stringify({
  action: "toggle_company",
  company_id: companyId,
  status: newStatus,
})
```

- [ ] **Step 4: Normalize admin payload shapes**

```ts
return jsonResponse({
  status: "success",
  company,
  users: users || [],
  audit_logs: logs || [],
  request_id: requestId,
}, 200, requestId)
```

- [ ] **Step 5: Run regression test and basic app lint/build**

Run: `python3 execution/test_platform_admin.py -v`
Expected: PASS

Run: `npm run lint`
Workdir: `apps/fieldops_admin`
Expected: PASS

- [ ] **Step 6: Update the sprint tracker to stop overstating completion**

Add explicit notes in `SPRINT_TRACKER.md` that Sprint 6 admin system required post-completion hardening for:
- summary counts
- toggle contract mismatch
- regression coverage

- [ ] **Step 7: Commit**

```bash
git add execution/test_platform_admin.py infra/supabase/functions/platform_admin/index.ts apps/fieldops_admin/src/app/page.tsx apps/fieldops_admin/src/app/companies/page.tsx apps/fieldops_admin/src/app/companies/[id]/page.tsx apps/fieldops_admin/src/lib/types.ts SPRINT_TRACKER.md
git commit -m "fix(admin): harden platform admin contract and summary data"
```

### Task 2: Add Tenant Billing Foundations

**Files:**
- Create: `infra/supabase/migrations/20260410010000_company_billing_and_ownership.sql`
- Create: `infra/supabase/functions/billing_portal/index.ts`
- Create: `infra/supabase/functions/stripe_webhook/index.ts`
- Modify: `apps/fieldops_web/src/app/settings/page.tsx`
- Create: `apps/fieldops_web/src/app/settings/billing/page.tsx`
- Create: `execution/test_billing_foundation.py`

- [ ] **Step 1: Write the failing billing-foundation regression test**

```python
def test_company_admin_can_request_billing_portal_session():
    result = post_function("billing_portal", admin_token, {"return_url": APP_URL + "/settings/billing"})
    assert result["url"].startswith("https://billing.stripe.com/")

def test_stripe_webhook_updates_company_payment_status():
    event = fake_checkout_or_subscription_event(customer_id=STRIPE_CUSTOMER_ID, status="active")
    result = post_stripe_webhook(event)
    assert fetch_company()["payment_status"] == "active"
```

- [ ] **Step 2: Run test to verify the billing slice does not exist yet**

Run: `python3 execution/test_billing_foundation.py -v`
Expected: FAIL because the webhook and billing portal functions do not exist.

- [ ] **Step 3: Extend the schema for billing ownership**

```sql
alter table public.companies
  add column if not exists stripe_subscription_id text,
  add column if not exists billing_email text,
  add column if not exists billing_plan text default 'starter';
```

```sql
create table if not exists public.company_membership_audit (...)
```

- [ ] **Step 4: Implement tenant billing portal access**

```ts
if (userRecord.role !== "admin") {
  return errorResponse(requestId, 403, "FORBIDDEN", "Only admins can manage billing")
}
```

```ts
const session = await stripe.billingPortal.sessions.create({
  customer: company.stripe_customer_id,
  return_url,
})
```

- [ ] **Step 5: Implement Stripe webhook sync**

```ts
switch (event.type) {
  case "customer.subscription.updated":
  case "customer.subscription.deleted":
  case "checkout.session.completed":
    // map Stripe state -> companies.payment_status / billing_plan
}
```

- [ ] **Step 6: Add a tenant-facing billing page**

Show:
- current plan
- payment status
- billing email
- active user count
- manage billing button

- [ ] **Step 7: Run regression test plus web lint/build**

Run: `python3 execution/test_billing_foundation.py -v`
Expected: PASS

Run: `npm run lint`
Workdir: `apps/fieldops_web`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add infra/supabase/migrations/20260410010000_company_billing_and_ownership.sql infra/supabase/functions/billing_portal/index.ts infra/supabase/functions/stripe_webhook/index.ts apps/fieldops_web/src/app/settings/page.tsx apps/fieldops_web/src/app/settings/billing/page.tsx execution/test_billing_foundation.py
git commit -m "feat(billing): add tenant billing portal and Stripe sync foundation"
```

### Task 3: Clarify Ownership And Permission Boundaries

**Files:**
- Modify: `infra/supabase/migrations/20260410010000_company_billing_and_ownership.sql`
- Modify: `apps/fieldops_web/src/app/settings/staff/page.tsx`
- Modify: `apps/fieldops_web/src/app/settings/page.tsx`
- Modify: `infra/supabase/functions/invites/index.ts`
- Modify: `SPRINT_TRACKER.md`

- [ ] **Step 1: Write the failing permission-boundary regression test**

```python
def test_supervisor_cannot_promote_other_users_to_admin():
    result = invite_as_supervisor(role="admin")
    assert result["error_code"] == "INVALID_PAYLOAD"

def test_company_owner_cannot_access_other_company_members():
    users = list_staff_as_company_admin()
    assert all(user["company_id"] == OWN_COMPANY_ID for user in users)
```

- [ ] **Step 2: Decide the smallest ownership model**

Implement one of these, not both:
- `users.is_company_owner boolean default false`
- or `companies.owner_user_id uuid`

Recommended: `users.is_company_owner boolean` for lower migration friction with existing `admin` role.

- [ ] **Step 3: Tighten tenant management rules**

```ts
const allowedRoles = userRecord.role === "admin"
  ? ["worker", "foreman", "supervisor"]
  : ["worker", "foreman"]
```

Extend this so only the company owner can:
- change billing contacts
- transfer ownership
- deactivate the last active admin

- [ ] **Step 4: Expose ownership safely in the tenant UI**

Show:
- owner badge on staff list
- prevent self-lockout
- explicit warning before deactivating an admin

- [ ] **Step 5: Run regression tests**

Run: `python3 execution/test_platform_admin.py -v`
Expected: PASS

Run: `python3 execution/test_billing_foundation.py -v`
Expected: PASS

- [ ] **Step 6: Update tracker status**

Move these items from vague future state into concrete status notes in `SPRINT_TRACKER.md`:
- Stripe billing
- feature entitlements tied to billing
- admin granular permissions / custom role builder

- [ ] **Step 7: Commit**

```bash
git add infra/supabase/migrations/20260410010000_company_billing_and_ownership.sql apps/fieldops_web/src/app/settings/staff/page.tsx apps/fieldops_web/src/app/settings/page.tsx infra/supabase/functions/invites/index.ts SPRINT_TRACKER.md
git commit -m "feat(admin): add company ownership guardrails"
```

## Recommended Execution Order

1. Task 1 first. The admin system is already partially built, but currently has correctness drift.
2. Task 2 second. Billing should not be layered onto a misreporting admin plane.
3. Task 3 third. Ownership guardrails are easier to implement once billing and admin surfaces exist.

## Out Of Scope For This Slice

- custom role builder / permission matrix UI
- white-label or custom domains
- QuickBooks, payroll, Procore, Zapier
- SOC 2 process work
- AI anomaly detection

## Verification Checklist

- Platform admin company list shows real user counts from `company_summary`
- Company suspend/reactivate works from UI and via edge function
- Company admin can manage only tenant users
- Company admin can open Stripe billing portal for their own company only
- Stripe webhook updates `companies.payment_status` correctly
- Tracker notes reflect actual verified status

Plan complete and saved to `docs/superpowers/plans/2026-04-10-tenant-admin-billing-foundation.md`. Ready to execute?
