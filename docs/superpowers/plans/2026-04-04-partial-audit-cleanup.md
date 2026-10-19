# Partial Audit Cleanup Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert the remaining "real but partial" audit items into either fully working vertical slices or explicitly verified backlog with corrected scope.

**Architecture:** Work from proofed backend outward. Finish persistence and API contracts first, then wire mobile/web consumers, then close docs/tracker status based only on passing verification. Avoid broad rewrites; complete one vertical path at a time.

**Tech Stack:** Supabase Edge Functions, Postgres migrations/RLS, Next.js App Router, Flutter/Riverpod, Python regression scripts.

---

### Task 1: Baseline verification
- [x] Run `python3 execution/run_backend_regression_suite.py`
- [x] Confirm current backend proof path is green before edits

### Task 2: Re-audit remaining partial items
- [ ] Map current code for expenses, i18n, cost codes, schedule, logging, CA OT, worker hours, PTO, timecard signatures
- [ ] Separate "working but partial" from "domain-only scaffolding"

### Task 3: Finish expenses vertical slice
- [ ] Add failing coverage for receipt photo linkage and supervisor review if missing
- [ ] Wire mobile receipt capture to carry real media asset/photo identifiers, not only a local boolean
- [ ] Add/verify supervisor-facing review surface if still missing
- [ ] Re-run targeted and full regression tests

### Task 4: Finish Spanish support on remaining web surfaces
- [ ] Identify untranslated supervisor pages outside the main operational flow
- [ ] Add locale wiring and translations
- [ ] Run `npm run lint` and `npm run build` in `apps/fieldops_web`

### Task 5: Close cost codes and schedule remaining gaps
- [ ] Decide smallest shippable completion scope for each
- [ ] Implement missing worker/supervisor consumer paths
- [ ] Verify with targeted tests and builds

### Task 6: Wire real worker-hours data
- [ ] Add failing mobile test or focused verification for hour summary data
- [ ] Compute today/week/month hours from real state/events
- [ ] Verify UI uses live values

### Task 7: Promote PTO and timecard signatures from domain-only to real slices
- [ ] Add minimal persistence/API support
- [ ] Add minimal mobile/web entry surfaces
- [ ] Verify end-to-end behavior

### Task 8: Close logging and California OT scope
- [ ] Decide completion criteria that is actually shippable
- [ ] Wire structured logging consistently across remaining critical functions
- [ ] Apply CA OT calculation to the actual payroll/reporting path
- [ ] Verify with regression coverage

### Task 9: Update status docs
- [ ] Update `SPRINT_TRACKER.md` and `LESSONS_LEARNED.md` only after fresh verification
