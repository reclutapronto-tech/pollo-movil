# Scheduler Audit Fix & UI/UX Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 4 bugs, complete 3 incomplete features, and apply 8 UI/UX polish items in the FieldsOps scheduler — surgical, step-verified, one task at a time.

**Architecture:** All changes are contained to the schedule page (`apps/fieldops_web/src/app/schedule/page.tsx`), i18n (`apps/fieldops_web/src/lib/i18n.tsx`), and the schedule_ai edge function (`infra/supabase/functions/schedule_ai/index.ts`). No new files needed except the template types (inline in page.tsx). localStorage backs the template store — no DB migration.

**Tech Stack:** Next.js 15, React 19, TypeScript 5, @dnd-kit/core, @fullcalendar/resource-timeline, Tailwind CSS 4, Supabase Edge Functions (Deno), shadcn/ui (Dialog, Label, Input)

---

## File Map

| File | Changes |
|---|---|
| `apps/fieldops_web/src/lib/i18n.tsx` | Add `weekCopied`, `failedToCopy` to EN (line ~294) and ES (line ~779) |
| `apps/fieldops_web/src/app/schedule/page.tsx` | B2 metadata, B3 deps, B4 AI button, F1 templates, F3 overlay, U1–U8 |
| `infra/supabase/functions/schedule_ai/index.ts` | F2 real historical logic + auth check |

---

## Task 1 (B1): Add missing i18n keys — `weekCopied` + `failedToCopy`

**Files:**
- Modify: `apps/fieldops_web/src/lib/i18n.tsx` line ~294 (EN) and ~779 (ES)

- [ ] **Step 1: Add EN keys after `failedToPublish` (line 294)**

In `apps/fieldops_web/src/lib/i18n.tsx`, find:
```ts
      failedToPublish: "Failed to publish schedule",
```
Add immediately after:
```ts
      weekCopied: "Previous week copied as drafts.",
      failedToCopy: "Failed to copy previous week.",
```

- [ ] **Step 2: Add ES keys after `failedToPublish` (line 779)**

Find:
```ts
      failedToPublish: "No se pudo publicar el horario",
```
Add immediately after:
```ts
      weekCopied: "Semana anterior copiada como borradores.",
      failedToCopy: "No se pudo copiar la semana anterior.",
```

- [ ] **Step 3: Verify TypeScript compiles**

```bash
cd apps/fieldops_web && npm run build 2>&1 | grep -E "error|Error|✓" | head -20
```
Expected: build completes with no TS errors referencing `weekCopied` or `failedToCopy`.

- [ ] **Step 4: Commit**

```bash
git add apps/fieldops_web/src/lib/i18n.tsx
git commit -m "fix: add missing weekCopied and failedToCopy i18n keys (EN + ES)"
```

---

## Task 2 (B2): Fix worker `metadata` not fetched

**Files:**
- Modify: `apps/fieldops_web/src/app/schedule/page.tsx` line ~310

- [ ] **Step 1: Update the Supabase select query**

Find (around line 309):
```ts
    const { data: workersData } = await supabase
      .from("users")
      .select("id, full_name, role")
      .eq("is_active", true)
```
Replace with:
```ts
    const { data: workersData } = await supabase
      .from("users")
      .select("id, full_name, role, metadata")
      .eq("is_active", true)
```

- [ ] **Step 2: Verify TypeScript compiles**

```bash
cd apps/fieldops_web && npm run build 2>&1 | grep -E "error|Error|✓" | head -20
```
Expected: no TS errors.

- [ ] **Step 3: Commit**

```bash
git add apps/fieldops_web/src/app/schedule/page.tsx
git commit -m "fix: fetch worker metadata so hourly_rate is used in OT and cost calculations"
```

---

## Task 3 (B3): Fix `events` useMemo stale dependency array

**Files:**
- Modify: `apps/fieldops_web/src/app/schedule/page.tsx` line ~277

- [ ] **Step 1: Fix the dependency array**

Find (around line 296):
```ts
    [entries],
```
That closing bracket is the deps array of the `events` useMemo. Replace with:
```ts
    [entries, ghostShifts, workers],
```

The full useMemo now looks like:
```ts
  const events = useMemo(
    () =>
      [...entries, ...ghostShifts].map((entry) => ({
        id: entry.id,
        resourceId: entry.job_id,
        title: entry.worker_name || workers.find((w) => w.id === entry.worker_id)?.full_name || "Unknown",
        start: buildEventDateTime(entry.date, formatTime(entry.start_time)),
        end: buildEventDateTime(entry.date, formatTime(entry.end_time)),
        backgroundColor: entry.status === "draft" ? "#f8e2b4" : entry.status === "ghost" ? "#e0e7ff" : "#dcfce7",
        borderColor: entry.status === "draft" ? "#f59e0b" : entry.status === "ghost" ? "#8b5cf6" : "#4ade80",
        textColor: entry.status === "draft" ? "#92400e" : entry.status === "ghost" ? "#4c1d95" : "#166534",
        extendedProps: {
          isGhost: entry.status === "ghost",
          status: entry.status,
          worker_name: entry.worker_name,
          job_id: entry.job_id,
          worker_id: entry.worker_id,
          notes: entry.notes,
        },
      })),
    [entries, ghostShifts, workers],
  );
```

- [ ] **Step 2: Verify TypeScript compiles**

```bash
cd apps/fieldops_web && npm run build 2>&1 | grep -E "error|Error|✓" | head -20
```
Expected: no TS errors.

- [ ] **Step 3: Commit**

```bash
git add apps/fieldops_web/src/app/schedule/page.tsx
git commit -m "fix: add ghostShifts and workers to events useMemo deps so AI suggestions render immediately"
```

---

## Task 4 (B4): Add AI Suggestions button to header

**Files:**
- Modify: `apps/fieldops_web/src/app/schedule/page.tsx` header button row (~line 880)

- [ ] **Step 1: Add button next to "Copy Previous Week"**

Find this block (around line 880):
```tsx
              <button
                onClick={handleCopyPreviousWeek}
                disabled={busyAction === "copy"}
                className="rounded-xl border border-stone-300 bg-white px-5 py-2 text-sm font-semibold text-slate-700 hover:bg-stone-50 disabled:opacity-50"
              >
                {busyAction === "copy" ? "Copying..." : "Copy Previous Week"}
              </button>
```
Add immediately BEFORE that block:
```tsx
              <button
                onClick={askAiForSuggestions}
                disabled={aiLoading || Boolean(busyAction)}
                className="rounded-xl border border-indigo-200 bg-indigo-50 px-5 py-2 text-sm font-semibold text-indigo-700 hover:bg-indigo-100 disabled:opacity-50"
              >
                {aiLoading ? (
                  <span className="flex items-center gap-2">
                    <span className="h-3.5 w-3.5 animate-spin rounded-full border-2 border-indigo-300 border-t-indigo-700" />
                    Thinking...
                  </span>
                ) : (
                  "✦ AI Suggestions"
                )}
              </button>
```

- [ ] **Step 2: Verify TypeScript compiles**

```bash
cd apps/fieldops_web && npm run build 2>&1 | grep -E "error|Error|✓" | head -20
```
Expected: no TS errors.

- [ ] **Step 3: Commit**

```bash
git add apps/fieldops_web/src/app/schedule/page.tsx
git commit -m "fix: add AI Suggestions button to header — askAiForSuggestions was unreachable"
```

---

## Task 5 (F1): Named templates (save + apply)

**Files:**
- Modify: `apps/fieldops_web/src/app/schedule/page.tsx`

- [ ] **Step 1: Add ScheduleTemplate type and state after existing interfaces (around line 116)**

After the `type ViewMode` line, add:
```ts
interface ScheduleTemplate {
  name: string;
  createdAt: string;
  shifts: Array<{
    worker_id: string;
    job_id: string;
    day_offset: number; // 0=Mon, 1=Tue, ... 6=Sun relative to week start
    start_time: string;
    end_time: string;
    notes: string;
  }>;
}

function loadTemplates(): ScheduleTemplate[] {
  try {
    return JSON.parse(localStorage.getItem("schedule_templates") ?? "[]");
  } catch {
    return [];
  }
}

function persistTemplates(templates: ScheduleTemplate[]) {
  localStorage.setItem("schedule_templates", JSON.stringify(templates));
}
```

- [ ] **Step 2: Add template state inside `SchedulePage` component (after `ghostShifts` state, around line 258)**

```ts
  const [templates, setTemplates] = useState<ScheduleTemplate[]>(() => loadTemplates());
  const [showTemplateInput, setShowTemplateInput] = useState(false);
  const [templateNameInput, setTemplateNameInput] = useState("");
  const [showApplyDropdown, setShowApplyDropdown] = useState(false);
```

- [ ] **Step 3: Add `saveAsTemplate` and `applyTemplate` functions (after `resolveGhostShift`, around line 810)**

```ts
  function saveAsTemplate() {
    const name = templateNameInput.trim();
    if (!name) return;

    const weekStart = parseDate(rangeStart);
    const weekStartMs = weekStart.getTime();

    const templateShifts = entries
      .filter((e) => e.date >= rangeStart && e.date <= rangeEnd)
      .map((e) => {
        const shiftDate = parseDate(e.date);
        const dayOffset = Math.round((shiftDate.getTime() - weekStartMs) / 86400000);
        return {
          worker_id: e.worker_id,
          job_id: e.job_id,
          day_offset: dayOffset,
          start_time: e.start_time,
          end_time: e.end_time,
          notes: e.notes ?? "",
        };
      });

    const newTemplate: ScheduleTemplate = {
      name,
      createdAt: new Date().toISOString(),
      shifts: templateShifts,
    };

    const updated = [...templates.filter((t) => t.name !== name), newTemplate];
    persistTemplates(updated);
    setTemplates(updated);
    setTemplateNameInput("");
    setShowTemplateInput(false);
    setSuccessMessage(`Template "${name}" saved (${templateShifts.length} shifts).`);
  }

  async function applyTemplate(template: ScheduleTemplate) {
    setShowApplyDropdown(false);
    if (template.shifts.length === 0) return;

    setBusyAction("copy");
    setError(null);
    setSuccessMessage(null);
    const weekStart = parseDate(rangeStart);

    try {
      await Promise.all(
        template.shifts.map((shift) => {
          const targetDate = new Date(weekStart);
          targetDate.setUTCDate(weekStart.getUTCDate() + shift.day_offset);
          return postSchedule({
            action: "create",
            worker_id: shift.worker_id,
            job_id: shift.job_id,
            shift_date: asDateKey(targetDate),
            start_time: shift.start_time,
            end_time: shift.end_time,
            notes: shift.notes,
          });
        }),
      );
      await loadSchedule();
      setSuccessMessage(`Template "${template.name}" applied — ${template.shifts.length} draft shifts created.`);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to apply template.");
    } finally {
      setBusyAction(null);
    }
  }
```

- [ ] **Step 4: Add template UI buttons in the header (after the AI Suggestions button)**

Find the "Copy Previous Week" button block. After it, add:
```tsx
              {/* Save as Template */}
              {showTemplateInput ? (
                <div className="flex items-center gap-2">
                  <input
                    autoFocus
                    type="text"
                    value={templateNameInput}
                    onChange={(e) => setTemplateNameInput(e.target.value)}
                    onKeyDown={(e) => { if (e.key === "Enter") saveAsTemplate(); if (e.key === "Escape") setShowTemplateInput(false); }}
                    placeholder="Template name..."
                    className="rounded-xl border border-stone-300 px-3 py-2 text-sm w-40"
                  />
                  <button
                    onClick={saveAsTemplate}
                    disabled={!templateNameInput.trim()}
                    className="rounded-xl bg-slate-900 px-4 py-2 text-sm font-semibold text-white hover:bg-slate-700 disabled:opacity-40"
                  >
                    Save
                  </button>
                  <button
                    onClick={() => { setShowTemplateInput(false); setTemplateNameInput(""); }}
                    className="rounded-xl bg-stone-100 px-3 py-2 text-sm font-semibold text-slate-600 hover:bg-stone-200"
                  >
                    ✕
                  </button>
                </div>
              ) : (
                <button
                  onClick={() => setShowTemplateInput(true)}
                  className="rounded-xl border border-stone-300 bg-white px-5 py-2 text-sm font-semibold text-slate-700 hover:bg-stone-50"
                >
                  Save as Template
                </button>
              )}

              {/* Apply Template */}
              {templates.length > 0 && (
                <div className="relative">
                  <button
                    onClick={() => setShowApplyDropdown((v) => !v)}
                    className="rounded-xl border border-stone-300 bg-white px-5 py-2 text-sm font-semibold text-slate-700 hover:bg-stone-50"
                  >
                    Apply Template ▾
                  </button>
                  {showApplyDropdown && (
                    <div className="absolute right-0 top-full z-50 mt-1 min-w-[180px] rounded-xl border border-stone-200 bg-white py-1 shadow-lg">
                      {templates.map((t) => (
                        <button
                          key={t.name}
                          onClick={() => applyTemplate(t)}
                          className="flex w-full items-center justify-between px-4 py-2 text-sm text-slate-700 hover:bg-stone-50"
                        >
                          <span>{t.name}</span>
                          <span className="text-xs text-slate-400">{t.shifts.length}sh</span>
                        </button>
                      ))}
                    </div>
                  )}
                </div>
              )}
```

- [ ] **Step 5: Verify TypeScript compiles**

```bash
cd apps/fieldops_web && npm run build 2>&1 | grep -E "error|Error|✓" | head -20
```
Expected: no TS errors.

- [ ] **Step 6: Commit**

```bash
git add apps/fieldops_web/src/app/schedule/page.tsx
git commit -m "feat: add named schedule templates — save current week, apply to any future week"
```

---

## Task 6 (F2): Replace mock AI with historical pattern logic

**Files:**
- Modify: `infra/supabase/functions/schedule_ai/index.ts`

- [ ] **Step 1: Replace entire file contents**

```ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import { corsHeaders } from "../_shared/api.ts";

interface AiRequest {
  workers: string[];
  jobs: string[];
  anchorDate: string;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders(req) });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing Authorization header" }), {
        status: 401,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey);

    const jwt = authHeader.replace("Bearer ", "");
    const { data: { user }, error: authError } = await supabase.auth.getUser(jwt);
    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Invalid auth token" }), {
        status: 401,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const body: AiRequest = await req.json();
    const { anchorDate, jobs } = body;

    if (!anchorDate || !jobs?.length) {
      return new Response(JSON.stringify({ error: "anchorDate and jobs are required" }), {
        status: 400,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    // Build 4-week lookback range
    const anchor = new Date(`${anchorDate}T12:00:00Z`);
    const lookbackEnd = new Date(anchor);
    lookbackEnd.setUTCDate(lookbackEnd.getUTCDate() - 1);
    const lookbackStart = new Date(lookbackEnd);
    lookbackStart.setUTCDate(lookbackStart.getUTCDate() - 27); // 4 weeks back

    // Fetch historical shifts with worker names
    const { data: historicalShifts, error: histError } = await supabaseAdmin
      .from("schedule_shifts")
      .select("worker_id, job_id, start_time, end_time, users!inner(id, full_name)")
      .in("job_id", jobs)
      .gte("shift_date", lookbackStart.toISOString().slice(0, 10))
      .lte("shift_date", lookbackEnd.toISOString().slice(0, 10))
      .eq("status", "published");

    if (histError) throw histError;

    // Build frequency map: job_id → { worker_id: count }
    const freq: Record<string, Record<string, { count: number; full_name: string; start_time: string; end_time: string }>> = {};

    for (const shift of (historicalShifts ?? [])) {
      const workerRecord = Array.isArray(shift.users) ? shift.users[0] : shift.users;
      const workerName = workerRecord?.full_name ?? "Unknown";
      if (!freq[shift.job_id]) freq[shift.job_id] = {};
      if (!freq[shift.job_id][shift.worker_id]) {
        freq[shift.job_id][shift.worker_id] = { count: 0, full_name: workerName, start_time: shift.start_time, end_time: shift.end_time };
      }
      freq[shift.job_id][shift.worker_id].count += 1;
    }

    // For each job, pick top 3 workers by frequency
    const ghost_shifts = [];
    for (const jobId of jobs) {
      const jobWorkers = freq[jobId];
      if (!jobWorkers) continue;
      const sorted = Object.entries(jobWorkers)
        .sort(([, a], [, b]) => b.count - a.count)
        .slice(0, 3);

      for (const [workerId, info] of sorted) {
        ghost_shifts.push({
          id: `ghost-${crypto.randomUUID()}`,
          worker_id: workerId,
          worker_name: info.full_name,
          job_id: jobId,
          date: anchorDate,
          start_time: info.start_time,
          end_time: info.end_time,
          status: "ghost",
          notes: `[AI] Based on ${info.count} historical shift${info.count !== 1 ? "s" : ""} on this job.`,
        });
      }
    }

    return new Response(
      JSON.stringify({
        message: `AI recommendations based on ${(historicalShifts ?? []).length} historical shifts.`,
        ghost_shifts,
      }),
      {
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        status: 200,
      },
    );
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : "Unknown error";
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...corsHeaders(req), "Content-Type": "application/json" },
    });
  }
});
```

- [ ] **Step 2: Verify Deno types check (TypeScript)**

```bash
cd infra/supabase/functions && deno check schedule_ai/index.ts 2>&1 | head -20
```
Expected: `Check file:///...schedule_ai/index.ts` with no errors. If `deno` not installed, skip — the runtime validates on deploy.

- [ ] **Step 3: Commit**

```bash
git add infra/supabase/functions/schedule_ai/index.ts
git commit -m "feat: replace mock AI with historical frequency analysis — top workers per job from 4-week lookback"
```

---

## Task 7 (F3): DragOverlay — remove misleading cost, show role + guidance

**Files:**
- Modify: `apps/fieldops_web/src/app/schedule/page.tsx` DragOverlay block (~line 1227)

- [ ] **Step 1: Replace DragOverlay contents**

Find:
```tsx
        <DragOverlay>
          {activeWorker ? (
            <div className="cursor-grabbing rounded-2xl border-2 border-indigo-500 bg-white px-4 py-3 shadow-xl opacity-90">
              <div className="font-semibold text-indigo-900">
                {activeWorker.full_name}
              </div>
              <div className="text-xs text-indigo-600">Assigning shift...</div>
              <div className="mt-1 border-t border-indigo-100 pt-1 text-xs font-medium text-slate-500">
                Est. Cost: ${(activeWorker.metadata?.hourly_rate || 20) * 8} /
                8h
              </div>
            </div>
          ) : null}
        </DragOverlay>
```
Replace with:
```tsx
        <DragOverlay>
          {activeWorker ? (
            <div className="cursor-grabbing rounded-2xl border-2 border-indigo-400 bg-white px-4 py-3 shadow-2xl ring-2 ring-indigo-100">
              <div className="flex items-center gap-2">
                <div className="font-semibold text-slate-900">{activeWorker.full_name}</div>
                <span className="rounded-full bg-slate-100 px-2 py-0.5 text-xs font-medium text-slate-600">
                  {activeWorker.role}
                </span>
              </div>
              <div className="mt-1.5 flex items-center gap-1.5 text-xs text-indigo-600 font-medium">
                <svg className="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M7 16V4m0 0L3 8m4-4l4 4m6 0v12m0 0l4-4m-4 4l-4-4" />
                </svg>
                Drop onto a job row
              </div>
            </div>
          ) : null}
        </DragOverlay>
```

- [ ] **Step 2: Verify TypeScript compiles**

```bash
cd apps/fieldops_web && npm run build 2>&1 | grep -E "error|Error|✓" | head -20
```
Expected: no TS errors.

- [ ] **Step 3: Commit**

```bash
git add apps/fieldops_web/src/app/schedule/page.tsx
git commit -m "fix: remove misleading flat cost estimate from DragOverlay, show role + drop guidance"
```

---

## Task 8 (U1–U8): Full UI/UX polish pass

**Files:**
- Modify: `apps/fieldops_web/src/app/schedule/page.tsx`

Apply all 8 items in one focused pass. Each step is a single targeted edit.

### U1 — Sidebar header with worker count

- [ ] **Step 1: Add header above the search input in the `<aside>` block (~line 1080)**

Find:
```tsx
          <aside className="rounded-2xl border border-stone-200 bg-stone-50 p-4">
            <div className="mb-4">
              <label className="mb-2 block text-sm font-medium text-slate-700">
                {t("schedulePage.searchWorkers")}
              </label>
```
Replace with:
```tsx
          <aside className="rounded-2xl border border-stone-200 bg-stone-50 p-4">
            <div className="mb-3 flex items-center justify-between">
              <h3 className="text-sm font-bold text-slate-800">Workers</h3>
              <span className="rounded-full bg-slate-100 px-2 py-0.5 text-xs font-semibold text-slate-500">
                {filteredWorkers.length}
              </span>
            </div>
            <div className="mb-4">
              <label className="mb-2 block text-sm font-medium text-slate-700">
                {t("schedulePage.searchWorkers")}
              </label>
```

---

### U2 — Event color legend above calendar

- [ ] **Step 2: Add legend row above the calendar container (~line 1134)**

Find:
```tsx
          <div className="relative min-w-0 overflow-x-auto rounded-2xl border border-stone-200 bg-white">
```
Add immediately BEFORE it:
```tsx
          <div className="flex items-center gap-4 px-1 pb-2 text-xs font-medium text-slate-500">
            <span className="flex items-center gap-1.5">
              <span className="inline-block h-2.5 w-2.5 rounded-full bg-amber-400" />
              Draft
            </span>
            <span className="flex items-center gap-1.5">
              <span className="inline-block h-2.5 w-2.5 rounded-full bg-green-400" />
              Published
            </span>
            <span className="flex items-center gap-1.5">
              <span className="inline-block h-2.5 w-2.5 rounded-full bg-violet-400" />
              AI Suggestion
            </span>
          </div>
```

---

### U3 — Conflict override reason: required indicator + validation

- [ ] **Step 3: Add `*` to label and red-border state on empty submit**

Find the conflict dialog Label:
```tsx
              <Label htmlFor="overrideReason" className="text-slate-700">Override Reason (Required)</Label>
```
Replace with:
```tsx
              <Label htmlFor="overrideReason" className="text-slate-700">
                Override Reason <span className="text-rose-600">*</span>
              </Label>
```

Find the Input below it:
```tsx
                <Input
                  id="overrideReason"
                  type="text"
                  placeholder="e.g. Critical site coverage needed"
                  value={overrideReason}
                  onChange={(e) => setOverrideReason(e.target.value)}
                  className="w-full"
                />
```
Replace with:
```tsx
                <Input
                  id="overrideReason"
                  type="text"
                  placeholder="e.g. Critical site coverage needed"
                  value={overrideReason}
                  onChange={(e) => setOverrideReason(e.target.value)}
                  className={`w-full ${!overrideReason.trim() ? "border-rose-300 focus:ring-rose-300" : ""}`}
                />
                <p className="text-xs text-slate-400 mt-1">Reason is logged with the shift for audit trail.</p>
```

---

### U4 — "Copy Previous Week" contextual label

- [ ] **Step 4: Compute source week label and use it**

After `const rangeLabel = useMemo(...)` block (around line 826), add:
```ts
  const copySourceLabel = useMemo(() => {
    const srcMonday = parseDate(previousAnchor(rangeStart, "week"));
    return srcMonday.toLocaleDateString(undefined, { month: "short", day: "numeric" });
  }, [rangeStart]);
```

Then find the Copy Previous Week button text:
```tsx
                {busyAction === "copy" ? "Copying..." : "Copy Previous Week"}
```
Replace with:
```tsx
                {busyAction === "copy" ? "Copying..." : `Copy Week of ${copySourceLabel}`}
```

---

### U5 — Calendar empty state

- [ ] **Step 5: Add empty state overlay inside the calendar container**

Find (around line 1163):
```tsx
            {loading && (
```
Add immediately BEFORE that `loading` check:
```tsx
            {!loading && entries.length === 0 && ghostShifts.length === 0 && (
              <div className="absolute inset-0 z-10 flex flex-col items-center justify-center gap-3 text-slate-400 pointer-events-none">
                <svg className="h-10 w-10 opacity-40" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M8 7h12m0 0l-4-4m4 4l-4 4m0 6H4m0 0l4 4m-4-4l4-4" />
                </svg>
                <p className="text-sm font-medium">No shifts scheduled</p>
                <p className="text-xs">Drag a worker from the left panel to get started</p>
              </div>
            )}
```

---

### U6 — AI suggestion dialog: format raw date string

- [ ] **Step 6: Format date in ghost shift review dialog (~line 1255)**

Find:
```tsx
                <span className="block">{reviewGhostShift?.date} - {reviewGhostShift?.start_time} to {reviewGhostShift?.end_time}</span>
```
Replace with:
```tsx
                <span className="block">
                  {reviewGhostShift?.date
                    ? parseDate(reviewGhostShift.date).toLocaleDateString(undefined, {
                        weekday: "short",
                        month: "short",
                        day: "numeric",
                      })
                    : ""}{" "}
                  · {reviewGhostShift?.start_time} – {reviewGhostShift?.end_time}
                </span>
```

---

### U7 — DragOverlay already done in Task 7 (F3). ✓

---

### U8 — Worker card hours progress bar

- [ ] **Step 7: Replace hours text with a progress bar in `DraggableWorker`**

Find in the `DraggableWorker` component (~line 88):
```tsx
        <span className="font-medium">{currentHours}h</span>
```
The parent `<div>` containing this is:
```tsx
      <div className="flex items-center justify-between mt-1 text-xs text-slate-500">
        <span>{worker.role}</span>
        <span className="font-medium">{currentHours}h</span>
      </div>
```
Replace entirely with:
```tsx
      <div className="mt-2 space-y-1">
        <div className="flex items-center justify-between text-xs text-slate-500">
          <span>{worker.role}</span>
          <span className={`font-semibold tabular-nums ${currentHours >= 40 ? "text-red-600" : currentHours >= 32 ? "text-amber-600" : "text-slate-600"}`}>
            {currentHours}h / 40h
          </span>
        </div>
        <div className="h-1.5 w-full overflow-hidden rounded-full bg-slate-100">
          <div
            className={`h-full rounded-full transition-all ${currentHours >= 40 ? "bg-red-500" : currentHours >= 32 ? "bg-amber-400" : "bg-green-400"}`}
            style={{ width: `${Math.min((currentHours / 40) * 100, 100)}%` }}
          />
        </div>
      </div>
```

Note: `currentHours` is a prop passed into `DraggableWorker`. Update the component signature to match what's already being passed — it already receives `currentHours: number`. ✓

- [ ] **Step 8: Verify TypeScript compiles and lint passes**

```bash
cd apps/fieldops_web && npm run build 2>&1 | grep -E "error|Error|✓" | head -30
```
Expected: clean build, no TS errors.

```bash
cd apps/fieldops_web && npm run lint 2>&1 | tail -10
```
Expected: no lint errors (or only pre-existing ones, if any).

- [ ] **Step 9: Commit all UI/UX polish**

```bash
git add apps/fieldops_web/src/app/schedule/page.tsx
git commit -m "feat: UI/UX polish — sidebar header, event legend, conflict dialog, contextual copy label, empty state, AI date format, worker hours bar"
```

---

## Self-Review Against Spec

- **B1 i18n** → Task 1 ✓
- **B2 metadata** → Task 2 ✓
- **B3 useMemo deps** → Task 3 ✓
- **B4 AI button** → Task 4 ✓
- **F1 templates save + apply** → Task 5 ✓
- **F2 AI historical logic + auth** → Task 6 ✓
- **F3 drag overlay** → Task 7 ✓
- **U1 sidebar header** → Task 8 step 1 ✓
- **U2 legend** → Task 8 step 2 ✓
- **U3 required indicator** → Task 8 step 3 ✓
- **U4 copy label** → Task 8 step 4 ✓
- **U5 empty state** → Task 8 step 5 ✓
- **U6 date format** → Task 8 step 6 ✓
- **U7 overlay** → Task 7 ✓
- **U8 hours bar** → Task 8 step 7 ✓

All 15 spec items covered. No gaps. No TODOs.
