# Scheduler Enhancement: Audit, Fix & UI/UX Polish
**Date:** 2026-04-05
**Scope:** Full (C) — Bugs + Incomplete Features + UI/UX Polish
**Files in scope:**
- `apps/fieldops_web/src/app/schedule/page.tsx`
- `apps/fieldops_web/src/lib/i18n.tsx`
- `infra/supabase/functions/schedule_ai/index.ts`

---

## Background

Dev claimed Sprint 6 scheduler enhancements complete. Audit found 4 bugs, 3 incomplete features, and 8 UI/UX gaps. This spec covers all of them in surgical, step-verified order.

---

## Section 1: Bug Fixes

### B1 — Missing i18n keys
**File:** `apps/fieldops_web/src/lib/i18n.tsx`
**Problem:** `t("schedulePage.weekCopied")` and `t("schedulePage.failedToCopy")` are called in `handleCopyPreviousWeek` but neither key exists in EN or ES translation blocks. Users see raw key strings.
**Fix:** Add to both `en.schedulePage` and `es.schedulePage`:
- `weekCopied`: "Previous week copied as drafts."
- `failedToCopy`: "Failed to copy previous week."
**Verify:** Both strings appear in the success/error banners when Copy Previous Week is triggered.

---

### B2 — Worker `metadata` not fetched
**File:** `apps/fieldops_web/src/app/schedule/page.tsx` line ~310
**Problem:** `loadReferenceData` selects `"id, full_name, role"` — omits `metadata`. Every `hourly_rate` lookup returns `undefined`, falling back to `$20`. OT cost impact calculations and drag overlay cost estimates are wrong for all workers.
**Fix:** Change select to `"id, full_name, role, metadata"`.
**Verify:** After fix, `worker.metadata?.hourly_rate` is truthy for workers with rates set in DB.

---

### B3 — `events` useMemo stale dependency array
**File:** `apps/fieldops_web/src/app/schedule/page.tsx` line ~277
**Problem:** `useMemo(() => [...entries, ...ghostShifts].map(...), [entries])` — deps array only includes `entries`. Omits `ghostShifts` and `workers`. When AI suggestions arrive, ghost shifts won't trigger a re-render. Worker name fallback lookup also won't update.
**Fix:** Change deps to `[entries, ghostShifts, workers]`.
**Verify:** After `askAiForSuggestions()` resolves, ghost events appear on the calendar immediately without requiring any other state change.

---

### B4 — AI suggestions button missing from UI
**File:** `apps/fieldops_web/src/app/schedule/page.tsx` header button row
**Problem:** `askAiForSuggestions()` function is fully implemented but no button in the JSX calls it. The entire AI feature is unreachable.
**Fix:** Add an "AI Suggestions" button to the header action row, next to "Copy Previous Week". Button shows spinner when `aiLoading === true`. Disabled while `aiLoading` or `busyAction` is set.
**Verify:** Clicking the button triggers the fetch, shows loading state, and ghost shifts appear on the calendar.

---

## Section 2: Incomplete Features

### F1 — Named Templates (save/apply)
**Problem:** Only "copy previous week" exists. No named templates, no save-as-template, no apply to arbitrary future week.
**Approach:** `localStorage`-backed template store. No new DB table.
- `saveWeekAsTemplate(name: string)` — serialises current week's shifts (worker_id, job_id, start_time, end_time, day-of-week offset) into `localStorage["schedule_templates"]`.
- `applyTemplate(templateName: string)` — reads template, maps day offsets to current `anchorDate` week, POSTs each shift as `action: "create"` draft.
- State: `templates: ScheduleTemplate[]`, `showTemplatePanel: boolean`.
- UI: "Save as Template" button (next to Copy Week) → inline prompt for template name. "Apply Template" dropdown lists saved templates.
**Constraints:** Templates are company-scoped in name only (localStorage is per-browser); no cross-device sync. Acceptable for MVP.
**Verify:** Save a week → switch to next week → apply template → shifts appear as drafts.

---

### F2 — AI endpoint: historical pattern logic (replace mock)
**File:** `infra/supabase/functions/schedule_ai/index.ts`
**Problem:** Returns hardcoded first-3-workers-on-first-job. No auth check.
**Fix:**
1. Add JWT validation (same pattern as `schedule/index.ts`).
2. Query `schedule_shifts` for the same week in previous 4 weeks.
3. Build a frequency map: for each job, which workers appeared most?
4. Return top-N workers per job as ghost shifts for the current `anchorDate` week.
5. Include `worker_name` in ghost shift payload (join with `users` table).
**Verify:** AI response references workers who actually appeared in recent history. Ghost shifts show correct worker names in the review dialog.

---

### F3 — Cost code shown in DragOverlay
**Problem:** Overlay shows flat `hourly_rate × 8`. Job cost code not surfaced.
**Fix:** Pass the `jobs` array into the drag overlay logic. When `activeWorker` is set, if `formJobId` is also set (pre-filled from hover), show `job.code`. Since we can't know the target job until drop, show "Drop on a job row to see cost code" as placeholder text, replacing the flat estimate. The flat estimate moves to the conflict check dialog where we have the full context.
**Note:** True real-time "cost preview on hover" requires FullCalendar's `eventReceive` or a custom drop target — out of scope for this sprint. This fix is honest: remove misleading flat estimate, add informative placeholder.
**Verify:** Drag overlay no longer shows `$160 / 8h` as if it's accurate. Shows worker name, role, and "Assign to a job row" guidance.

---

## Section 3: UI/UX Polish

### U1 — Sidebar header with worker count
Add a header row above the search box: `"Workers"` label left, `"(n)"` count badge right using a subtle `bg-slate-100` pill. Count reflects filtered workers when search is active.

### U2 — Event color legend
Add a 3-chip legend row above the FullCalendar grid:
- `●` amber: Draft
- `●` green: Published
- `●` purple: AI Suggestion

### U3 — Override reason required indicator
- Add `*` to the label.
- On submit attempt with empty reason: flash red border on input + shake animation.
- Add helper text: "Reason is logged with the shift for audit trail."

### U4 — "Copy Previous Week" → contextual label
Compute the previous week's Monday. Show: `"Copy Week of Apr 1"` instead of generic label. Updates dynamically with `anchorDate`.

### U5 — Calendar empty state
When `entries.length === 0 && ghostShifts.length === 0 && !loading`: render a centered overlay inside the calendar container:
> "No shifts scheduled — drag a worker from the left panel to get started."
With a small drag-arrow icon.

### U6 — AI dialog date formatting
Replace raw `reviewGhostShift?.date` with `parseDate(reviewGhostShift.date).toLocaleDateString(undefined, { weekday: "short", month: "short", day: "numeric" })`.

### U7 — DragOverlay redesign
Remove misleading cost estimate. Show:
- Worker name (large, bold)
- Role (pill badge)
- Status dot (PTO/OT/available)
- "Drop onto a job row" guidance text

### U8 — Worker card hours bar
Replace the plain `{currentHours}h` text with a small progress bar (0–40h range) that fills proportionally. Color: green → amber at 32h → red at 40h+. Hours text stays. Makes OT risk scannable without reading numbers.

---

## Execution Order

Run in this sequence — verify each before proceeding:

1. B1 (i18n) → B2 (metadata) → B3 (useMemo deps) → B4 (AI button)
2. F1 (templates) → F2 (AI logic) → F3 (drag overlay)
3. U1→U8 (UI/UX polish via `ui-ux-pro-max`)

---

## Definition of Done

- [ ] All 4 bugs fixed and verified individually
- [ ] Templates: save + apply round-trip works
- [ ] AI endpoint returns real historical data with worker names
- [ ] Drag overlay no longer shows misleading flat cost
- [ ] All 8 UI/UX items applied
- [ ] No TypeScript errors (`npm run build` clean)
- [ ] No new i18n keys missing (EN + ES both complete)
