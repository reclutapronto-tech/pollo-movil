# Photos And Ops Stabilization Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stabilize failed-fetch operations pages, convert overtime listing to the scoped edge-function path, redesign `/photos` into a project browser with in-page tabs, and add Thai to the language selector.

**Architecture:** Standardize client-side function fetching behind one authenticated helper, then migrate the affected operations pages onto that helper. Rework the photo page into focused sections so project browsing and in-page `Feed`/`Timeline`/`Map` views live on one route without reusing the unrelated standalone pages.

**Tech Stack:** Next.js App Router, React client components, Supabase JS, Supabase Edge Functions, TypeScript, Tailwind CSS.

---

### Task 1: Add A Shared Authenticated Function Fetch Helper

**Files:**
- Create: `/Users/seancheick/FieldsOps_ai/apps/fieldops_web/src/lib/function-client.ts`
- Test: `/Users/seancheick/FieldsOps_ai/execution/test_web_function_client.py`

- [ ] **Step 1: Write the failing test**

Create a small regression test that verifies the helper file exists, centralizes token lookup, and throws normalized errors when a response is not OK.

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 execution/test_web_function_client.py`
Expected: FAIL because the helper file does not exist yet.

- [ ] **Step 3: Write minimal implementation**

Implement a helper that:
- gets the current session from Supabase
- throws a clear missing-session error
- builds the `functions/v1/...` URL from `NEXT_PUBLIC_SUPABASE_URL`
- parses JSON safely
- throws the backend message on non-OK responses

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 execution/test_web_function_client.py`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add execution/test_web_function_client.py apps/fieldops_web/src/lib/function-client.ts
git commit -m "refactor(web): add shared function client"
```

### Task 2: Move Overtime Listing Onto The OT Edge Function

**Files:**
- Modify: `/Users/seancheick/FieldsOps_ai/apps/fieldops_web/src/app/overtime/page.tsx`
- Test: `/Users/seancheick/FieldsOps_ai/execution/test_overtime_page_contract.py`

- [ ] **Step 1: Write the failing test**

Add a regression test that checks the OT page uses the shared function client and consumes `ot_requests` from the edge-function payload rather than querying `ot_requests` directly.

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 execution/test_overtime_page_contract.py`
Expected: FAIL because the page still queries Supabase tables directly.

- [ ] **Step 3: Write minimal implementation**

Update the OT page to:
- request `GET /functions/v1/ot?status=...`
- read `payload.ot_requests`
- reuse the shared retry/error path for initial load and pagination

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 execution/test_overtime_page_contract.py`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add execution/test_overtime_page_contract.py apps/fieldops_web/src/app/overtime/page.tsx
git commit -m "fix(web): align overtime listing with edge function"
```

### Task 3: Harden Expenses, PTO, And Cost Codes Fetching

**Files:**
- Modify: `/Users/seancheick/FieldsOps_ai/apps/fieldops_web/src/app/expenses/page.tsx`
- Modify: `/Users/seancheick/FieldsOps_ai/apps/fieldops_web/src/app/pto/page.tsx`
- Modify: `/Users/seancheick/FieldsOps_ai/apps/fieldops_web/src/app/cost-codes/page.tsx`
- Test: `/Users/seancheick/FieldsOps_ai/execution/test_ops_pages_use_function_client.py`

- [ ] **Step 1: Write the failing test**

Add a regression test that asserts the three pages import the shared helper and stop duplicating session-token fetch boilerplate.

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 execution/test_ops_pages_use_function_client.py`
Expected: FAIL

- [ ] **Step 3: Write minimal implementation**

Refactor each page to use the shared helper, preserve current page-specific enrichment where needed, and normalize retry/error states.

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 execution/test_ops_pages_use_function_client.py`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add execution/test_ops_pages_use_function_client.py apps/fieldops_web/src/app/expenses/page.tsx apps/fieldops_web/src/app/pto/page.tsx apps/fieldops_web/src/app/cost-codes/page.tsx
git commit -m "refactor(web): stabilize ops page fetching"
```

### Task 4: Rebuild Photos Into A Project Browser And In-Page Workspace

**Files:**
- Modify: `/Users/seancheick/FieldsOps_ai/apps/fieldops_web/src/app/photos/page.tsx`
- Create: `/Users/seancheick/FieldsOps_ai/apps/fieldops_web/src/components/photos/project-browser.tsx`
- Create: `/Users/seancheick/FieldsOps_ai/apps/fieldops_web/src/components/photos/project-workspace-tabs.tsx`
- Create: `/Users/seancheick/FieldsOps_ai/apps/fieldops_web/src/components/photos/photo-timeline-panel.tsx`
- Create: `/Users/seancheick/FieldsOps_ai/apps/fieldops_web/src/components/photos/photo-map-panel.tsx`
- Test: `/Users/seancheick/FieldsOps_ai/execution/test_photos_page_structure.py`

- [ ] **Step 1: Write the failing test**

Add a regression test that checks:
- the page no longer renders the old “select project” dropdown-only flow as the primary entry
- timeline/map are represented as in-page tabs
- the new photo components exist

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 execution/test_photos_page_structure.py`
Expected: FAIL

- [ ] **Step 3: Write minimal implementation**

Refactor the page to:
- show folder-like project browser states when `job_id` is absent
- switch between icon/list view
- keep `Feed`, `Timeline`, and `Map` in the same route
- render selected project breadcrumb/header state
- reuse existing feed behavior where possible

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 execution/test_photos_page_structure.py`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add execution/test_photos_page_structure.py apps/fieldops_web/src/app/photos/page.tsx apps/fieldops_web/src/components/photos/project-browser.tsx apps/fieldops_web/src/components/photos/project-workspace-tabs.tsx apps/fieldops_web/src/components/photos/photo-timeline-panel.tsx apps/fieldops_web/src/components/photos/photo-map-panel.tsx
git commit -m "feat(web): redesign photos workspace"
```

### Task 5: Add Thai Locale Support

**Files:**
- Modify: `/Users/seancheick/FieldsOps_ai/apps/fieldops_web/src/lib/i18n.tsx`
- Modify: `/Users/seancheick/FieldsOps_ai/apps/fieldops_web/src/components/sidebar.tsx`
- Test: `/Users/seancheick/FieldsOps_ai/execution/test_web_i18n_thai.py`

- [ ] **Step 1: Write the failing test**

Add a regression test asserting the locale union includes `th`, the translations object contains a Thai root, and the sidebar exposes Thai in the language picker.

- [ ] **Step 2: Run test to verify it fails**

Run: `python3 execution/test_web_i18n_thai.py`
Expected: FAIL

- [ ] **Step 3: Write minimal implementation**

Add Thai shell/common translations and wire the picker to show `Thai`.

- [ ] **Step 4: Run test to verify it passes**

Run: `python3 execution/test_web_i18n_thai.py`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add execution/test_web_i18n_thai.py apps/fieldops_web/src/lib/i18n.tsx apps/fieldops_web/src/components/sidebar.tsx
git commit -m "feat(web): add thai locale support"
```

### Task 6: Verify The Full Slice

**Files:**
- Modify: `/Users/seancheick/FieldsOps_ai/SPRINT_TRACKER.md`

- [ ] **Step 1: Run focused regression tests**

Run:
- `python3 execution/test_web_function_client.py`
- `python3 execution/test_overtime_page_contract.py`
- `python3 execution/test_ops_pages_use_function_client.py`
- `python3 execution/test_photos_page_structure.py`
- `python3 execution/test_web_i18n_thai.py`

Expected: all PASS

- [ ] **Step 2: Run app verification**

Run:
- `npm run lint` in `/Users/seancheick/FieldsOps_ai/apps/fieldops_web`
- `npm run build` in `/Users/seancheick/FieldsOps_ai/apps/fieldops_web`

Expected: PASS, or if build is blocked by known external font fetch in the sandbox, document that exact blocker.

- [ ] **Step 3: Update tracker notes**

Add concise notes in [`/Users/seancheick/FieldsOps_ai/SPRINT_TRACKER.md`](/Users/seancheick/FieldsOps_ai/SPRINT_TRACKER.md) reflecting the completed stabilization and photo UX work.

- [ ] **Step 4: Commit**

```bash
git add SPRINT_TRACKER.md
git commit -m "docs: update tracker for photos and ops stabilization"
```
