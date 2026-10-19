---
title: Lessons Learned
tags:
  - lessons
  - retrospective
  - process
aliases:
  - Retro Notes
related:
  - "[[SPRINT_TRACKER]]"
  - "[[ROADMAP]]"
---

# Lessons Learned

This file captures the practical lessons from each sprint so they survive beyond chat history.

> [!tip] Navigation
> - [[SPRINT_TRACKER]] — Current sprint status
> - [[ROADMAP]] — Where we're headed

Use it to improve:
- future prompts
- project setup
- definition of done
- testing discipline
- planning accuracy
- CI and local developer workflows

Update rule:
- Append to this file at the end of each sprint.
- Add only lessons that changed how we build, verify, scope, or communicate.
- Keep lessons concrete and reusable.
- Prefer observed fact over vague opinion.

Recommended format for each sprint:
- What we learned
- What we fixed
- Why it mattered
- What to do earlier next time
- Reusable rule for future projects

---

## Sprint 1 Lessons Learned

### 1. A task is not done because the board says it is done

What we learned:
- Several Sprint 1 tasks in Notion were marked `Done`, but the repo did not contain the matching mobile or web implementation.
- The backend was materially complete.
- The full worker loop was not complete in-repo.

What we fixed:
- Re-verified the backend from the code and tests instead of trusting task status.
- Corrected Notion statuses.
- Moved unfinished mobile and web tasks into Sprint 2.
- Added a repo-local tracker in [SPRINT_TRACKER.md](/Users/seancheick/FieldsOps_ai/SPRINT_TRACKER.md).

Why it mattered:
- False `Done` states distort planning.
- They create bad handoffs, bad sprint reviews, and bad next-step decisions.
- They hide real delivery risk.

What to do earlier next time:
- Tie every `Done` status to fresh verification evidence.
- Separate `backend complete` from `product complete`.
- Move unfinished work forward immediately instead of leaving it in the wrong sprint.

Reusable rule:
- Never let the board become more optimistic than the repo.

### 2. Definition of done must be tied to proof, not effort

What we learned:
- “Built” is not enough.
- The right question is whether there is one command that proves the behavior still works.

What we fixed:
- Kept Sprint 1 backend tasks closed only after fresh verification.
- Added explicit evidence references in the tracker and in Notion notes.

Why it mattered:
- It prevents completion theater.
- It gives the next developer a clear standard.

What to do earlier next time:
- Define the proof command during the sprint, not after the sprint.

Reusable rule:
- A task is only done when its proof path is known, runnable, and recent.

### 3. Notion is useful, but it should not be the only execution tracker

What we learned:
- Notion is good for backlog planning, sprint visibility, and reprioritization.
- It is weaker as the only execution source of truth during implementation.

What we fixed:
- Created [SPRINT_TRACKER.md](/Users/seancheick/FieldsOps_ai/SPRINT_TRACKER.md) inside the repo.
- Mirrored the Notion field style so updates can move between both systems easily.

Why it mattered:
- The local tracker lives next to the code, tests, and docs.
- It can be updated in the same change set as implementation work.
- It reduces drift between project state and planning state.

What to do earlier next time:
- Start every project with both:
  - planning board
  - repo-local execution tracker

Reusable rule:
- Use a hybrid system:
  - Notion for planning
  - repo tracker for execution
  - tests/CI for proof

### 4. Local verification must be deterministic, not dependent on machine luck

What we learned:
- Local Supabase behavior was unstable when the suite depended on ambient Docker state.
- We hit multiple environment issues:
  - stale Supabase project instances holding ports
  - wrong Supabase working directory
  - flaky `supabase db reset`
  - missing seed/auth state after rebuilds
  - hardcoded container-name assumptions

What we fixed:
- Added [run_backend_regression_suite.py](/Users/seancheick/FieldsOps_ai/execution/run_backend_regression_suite.py).
- Added [seed_backend_test_data.py](/Users/seancheick/FieldsOps_ai/execution/seed_backend_test_data.py).
- Made the suite:
  - clean up stale local stacks
  - run Supabase from the correct `infra/` project root
  - seed data explicitly
  - resolve the active DB container dynamically
  - run the Sprint 1 verifier after rebuild

Why it mattered:
- Without deterministic setup, the same code can appear broken or working depending on leftover local state.
- That makes regressions hard to trust and hard to debug.

What to do earlier next time:
- Create an environment bootstrap script as soon as the first real end-to-end test exists.
- Never assume the local stack is already healthy.
- Never hardcode environment-specific runtime identifiers unless you also control them.

Reusable rule:
- If a verification path depends on local state, it is not a real gate yet.

### 5. Execution scripts are better than one-off terminal rituals

What we learned:
- Repeating a sequence of manual commands is fragile.
- If a workflow matters more than once, it should become a deterministic script.

What we fixed:
- Converted the backend proof path into explicit execution scripts instead of relying on remembered shell steps.

Why it mattered:
- The process became repeatable.
- The suite can now be run by another dev, by CI, or by a future agent without reconstructing context.

What to do earlier next time:
- Promote repeated shell workflows into scripts immediately.

Reusable rule:
- If it can be scripted, script it.

### 6. Test the orchestration layer, not only the business behavior

What we learned:
- The Sprint 1 business verifier was already good.
- The new risk lived in the orchestration around it:
  - command ordering
  - cleanup
  - seeding
  - working directory selection

What we fixed:
- Added unit tests for the runner and seed helper:
  - [test_run_backend_regression_suite.py](/Users/seancheick/FieldsOps_ai/execution/test_run_backend_regression_suite.py)
  - [test_seed_backend_test_data.py](/Users/seancheick/FieldsOps_ai/execution/test_seed_backend_test_data.py)

Why it mattered:
- Many failures came from environment orchestration, not domain logic.
- The suite runner itself needed to be trustworthy.

What to do earlier next time:
- Test the glue code as soon as you create it.

Reusable rule:
- Infrastructure glue is production logic if your team depends on it.

### 7. CI should run the same proof path that local development uses

What we learned:
- A separate CI-only test path would drift quickly.
- The strongest gate is the same one developers use locally.

What we fixed:
- Added [backend-regression.yml](/Users/seancheick/FieldsOps_ai/.github/workflows/backend-regression.yml).
- Pointed CI at the same local suite entrypoint.

Why it mattered:
- One verification path is easier to trust and maintain than two parallel ones.

What to do earlier next time:
- Add a CI gate as soon as the first valuable regression command exists.

Reusable rule:
- CI should execute the canonical proof command, not a cousin of it.

### 8. Backend completion and product completion are different milestones

What we learned:
- Sprint 1 backend was complete and verified.
- Sprint 1 as a user-facing product loop was not complete because the mobile worker app and supervisor web UI were not present in this repo.

What we fixed:
- Kept the backend tasks done.
- Moved the unimplemented worker/supervisor tasks into Sprint 2.

Why it mattered:
- This keeps sprint reporting honest.
- It also clarifies what to build next without pretending the product is further along than it is.

What to do earlier next time:
- Split sprint tasks by delivery surface from the start:
  - backend
  - mobile
  - web
  - infra

Reusable rule:
- Always report progress at the same layer the user experiences the product.

---

## Sprint 2 Lessons Learned

### 1. Respect roadmap order when multiple good ideas compete

What we learned:
- The complete plan, roadmap, and PRD all pointed to the same early mobile sequence:
  - login
  - home screen
  - job list
  - then clock, camera, timeline, and offline depth
- That alignment mattered because several later features were tempting to jump to first.

What we fixed:
- Re-checked the long-form plan and roadmap before picking the next task.
- Kept the team on `Mobile job list` after `Mobile login screen` instead of skipping ahead to camera or offline work.

Why it mattered:
- It prevents building impressive pieces in the wrong order.
- It keeps the UI scaffold aligned with the actual product loop and backend contracts already in place.
- It reduces rework because later worker actions need a stable assigned-job surface anyway.

### 2. "Review before upload" is a real workflow, not a polish detail

What we learned:
- The original mobile photo flow uploaded immediately after shutter.
- That was fast, but it skipped a critical field UX step: workers need to confirm the image, retake it if needed, and sometimes save it locally instead of sending it immediately.
- "Save for later" also has to be a real local state path, not just a button label.

What we fixed:
- Split capture from upload in the mobile camera flow.
- Added a dedicated review screen with:
  - retake
  - lightweight auto-enhance
  - upload now
  - save for later for standalone proof photos
- Added a local draft store in Drift and a saved-photos screen reachable from the job card.
- Kept task and expense capture flows on the same review screen, but did not fake deferred attachment where the surrounding workflow still requires an uploaded `media_asset_id`.

Why it mattered:
- Workers can now verify the evidence before it leaves the device.
- The app is more trustworthy under weak connectivity because a proof photo can exist locally without being lost.
- The workflow is honest: we did not pretend a saved local photo already satisfies task/expense attachment requirements.

What to do earlier next time:
- Design capture flows around states, not just screens:
  - captured
  - reviewed
  - saved locally
  - uploaded
  - failed
- Decide which actions truly support deferred send before wiring buttons into every capture entrypoint.

Reusable rule:
- In field apps, capture UX should be `camera -> review -> decision`, not `camera -> network immediately`.

What to do earlier next time:
- Reconcile the roadmap, tracker, and repo before picking the next implementation slice.
- Prefer the next dependency in the user flow over the most visually interesting task.

Reusable rule:
- Build the backbone in the order the product actually depends on it.

### 2. Realtime on partitioned Postgres tables is a database configuration problem first

What we learned:
- The supervisor timeline page already subscribed to the right logical event sources in the UI.
- Live updates still failed because the underlying event tables are partitioned, and Supabase Realtime was not fully configured to publish those changes in a way the frontend subscription could observe.
- In the same QA pass, the photo feed signing failure also turned out to be a database policy issue, not a React rendering issue.

What we fixed:
- Added a storage read policy for company-scoped media objects so supervisors can sign raw and stamped proof assets.
- Added realtime publication registration for the timeline/worker/map source tables.
- Enabled `publish_via_partition_root` on `supabase_realtime` so subscriptions on parent table names receive inserts from partition children.
- Added regression coverage in [test_sprint_1.py](/Users/seancheick/FieldsOps_ai/execution/test_sprint_1.py) for the realtime publication wiring and signed proof media access.

Why it mattered:
- Browser QA was correctly telling us the app was not live, but the root cause sat below the web app.
- Without publication wiring, the frontend can look correct in code review and still never receive events.
- Without storage policies, signed URLs fail even when the asset rows and proof metadata are otherwise correct.

What to do earlier next time:
- For any feature that depends on Supabase Realtime, verify the publication membership and partition behavior as part of backend setup, not after UI debugging starts.
- For any private Storage-backed UI, verify the read/sign policy path with a non-service user token before calling the page “done.”
- Add one backend-side assertion for every cross-layer assumption the UI depends on.

Reusable rule:
- When live UI data fails, check the publication, policy, and table shape before touching the component.

What to do earlier next time:
- Reconcile the PRD, roadmap, and sprint board before starting a new sprint slice.
- Treat roadmap order as a dependency map, not just a wishlist.

Reusable rule:
- When the product docs agree on sequence, follow the sequence unless there is a verified blocker.

### 2. Notes inside the task are often enough when connector behavior is inconsistent

What we learned:
- The Notion workspace accepted task property updates but had quirks on certain fields and comment payloads.
- `Assigned To` and comment creation were not as reliable as the board metadata suggested.

What we fixed:
- Stored verification proof in `Agent findings and Notes` when the connector behavior was inconsistent.

Why it mattered:
- Progress still got documented without blocking on tooling quirks.

What to do earlier next time:
- Use the most reliable writable field for proof notes if a connector is inconsistent.

Reusable rule:
- Preserve the evidence first; perfect tooling symmetry can come second.

### 3. The repo tracker has to mirror the real board, not just the active slice

What we learned:
- The Notion board already contained Sprint 2 and later backlog items that were not yet mirrored in the local tracker.
- That made the repo tracker easier to work from day to day, but less complete as a planning mirror.

What we fixed:
- Re-audited the roadmap against the Notion board.
- Mirrored the missing backlog items into [SPRINT_TRACKER.md](/Users/seancheick/FieldsOps_ai/SPRINT_TRACKER.md).
- Added explicit local tasks for roadmap gaps that were not yet represented cleanly on the board, including `Supervisor dashboard (minimal)` and `Server-side photo stamp pipeline`.

Why it mattered:
- A local tracker is only useful if it reflects the real queue, not only the task currently being coded.
- This makes future handoffs and sprint reviews less lossy.

What to do earlier next time:
- Sync the local tracker from the board when it is first created.
- Re-run a roadmap-to-board audit at the start of each sprint.

Reusable rule:
- If the repo tracker is meant to mirror the board, keep it complete enough to plan from, not just execute from.

### Sprint 1 Reusable Checklist

Before closing a sprint, confirm:
- The board matches the repo.
- `Done` items have fresh verification evidence.
- Unfinished work has been moved to the correct sprint.
- There is one canonical proof command.
- That command works on a clean local rebuild.
- CI is pointed at the same proof path.
- A local tracker exists in the repo.
- The sprint has a written lessons section here.

### 4. One widget per file, always

What we learned:
- The initial HomeScreen had 8 widget classes in a single 420-line file.
- LoginScreen had 3 widget classes inlined.
- This made it hard to find, reuse, or reason about individual components.

What we fixed:
- Extracted every widget into its own file under `widgets/` subdirectories.
- HomeScreen went from 420 lines to 110 lines.
- Each widget is now independently importable and testable.

Why it mattered:
- Components can be reused across different screens without importing the entire parent.
- Diffs are cleaner since changes to one widget don't touch unrelated ones.
- New developers can find widgets by file name instead of scrolling through a monolith.

What to do earlier next time:
- Start with one widget per file from the first commit. Never accumulate.

Reusable rule:
- Every widget class gets its own file. No exceptions. The cost is a few more imports; the benefit is permanent.

### 5. Strict analyzer settings from day one

What we learned:
- The default `analysis_options.yaml` was minimal — just `flutter_lints` with no strict settings.
- This allowed implicit dynamics, unused async, and broad catch clauses to pass unnoticed.

What we fixed:
- Enabled `strict-casts`, `strict-inference`, `strict-raw-types`.
- Added key lint rules: `avoid_print`, `unawaited_futures`, `prefer_final_locals`, `avoid_catches_without_on_clauses`, `always_use_package_imports`.

Why it mattered:
- Catches entire categories of bugs at analysis time instead of runtime.
- Forces explicit types and proper error handling from the start.

What to do earlier next time:
- Configure strict analysis before writing the first line of feature code.

Reusable rule:
- analysis_options.yaml is a safety gate, not a default to leave alone.

### 6. State classes need value equality for Riverpod

What we learned:
- `SessionState` and `ClockInState` had no `==` / `hashCode` overrides.
- Riverpod's `Notifier` uses identity comparison by default, so every `state = ...` triggered a rebuild even when nothing changed.

What we fixed:
- Added proper `==` and `hashCode` to all state classes.
- Used a sentinel pattern for `copyWith` on `ClockInState` so nullable fields can be explicitly set to null.

Why it mattered:
- Prevents unnecessary rebuilds.
- The sentinel `copyWith` pattern prevents a class of bugs where you can never clear a nullable field.

What to do earlier next time:
- Define `==` / `hashCode` on every state class at creation time. Consider using `freezed` or Dart records for new state objects.

Reusable rule:
- If a class is used as Riverpod state, it must have value equality.

### 7. Never hardcode credentials in app source

What we learned:
- Login screen had `TextEditingController(text: 'worker@test.com')` and `password123` baked in.
- These ship in the compiled binary and are extractable.

What we fixed:
- Removed hardcoded credentials. Fields start empty.
- Updated test that relied on pre-filled fields.

Why it mattered:
- Security: even test credentials in production builds are a liability.
- Sets a bad pattern for future developers.

What to do earlier next time:
- Never pre-fill credentials even during development. Use test helpers instead.

Reusable rule:
- If it's a credential, it never appears in widget source code.

### 8. Backend CORS, GPS validation, and transaction rollback need to be right before pilot

What we learned:
- CORS was `Access-Control-Allow-Origin: *` — acceptable for local dev but a security risk in production.
- GPS coordinates were type-checked but not range-validated (lat -90..90, lng -180..180). Invalid coordinates would pass geofence checks with nonsense distances.
- `media_finalize` had a transaction gap: if `photo_events` insert failed after `media_assets` was updated to "uploaded", the asset would be orphaned in a wrong state.

What we fixed:
- Added `ALLOWED_ORIGINS` env-driven CORS with fallback to `*` for local dev.
- Added `isValidGpsCoordinates()` helper with range validation, used in `sync_events` and `media_presign`.
- Added rollback of `media_assets.sync_status` back to "pending" when `photo_events` insert fails in `media_finalize`.

Why it mattered:
- These are the kind of issues that work fine in testing but cause real damage in production.
- GPS validation prevents impossible coordinates from corrupting the geofence system.
- Transaction rollback prevents orphaned records that break the proof chain.

What to do earlier next time:
- Run a backend security/consistency review as part of every sprint, not just at hardening time.

Reusable rule:
- If two writes must succeed together, the second failure must undo the first.

### 9. Accessibility is cheaper to add at build time than to retrofit

What we learned:
- No screens had `Semantics` labels, `liveRegion` annotations, or `semanticLabel` on icons.
- Adding them retroactively required touching every widget.

What we fixed:
- Added `Semantics` wrappers on all interactive elements (buttons, status panels, error banners).
- Added `liveRegion: true` on error panels so screen readers announce changes.
- Added `semanticLabel` on all icons.

Why it mattered:
- Field workers may have visual or motor impairments.
- App store review can reject apps with poor accessibility.
- It's 2 extra lines per widget at build time vs. a full retrofit later.

What to do earlier next time:
- Add semantics as you build the widget, not in a separate pass.

Reusable rule:
- Every interactive widget gets a `Semantics` wrapper at creation time. It costs nothing and prevents a retrofit.

### 10. Clock out is part of clock in — scope the full user action, not half of it

What we learned:
- The initial clock feature only implemented `clock_in`. The roadmap says "clock in/out" but the sprint task was titled "Clock in button".
- A worker who can clock in but not clock out has no complete flow.

What we fixed:
- Added `clockOut` to ClockRepository, shared the implementation via `_submitClockEvent()` to avoid duplication.
- Renamed `ClockInController` to `ClockController` with typedef alias for backward compat.
- Added "Clock out" button in ClockStatusPanel when clocked in, with spinner and post-clock-out messaging.

Why it mattered:
- Half a user action is not a shipped feature.
- The clock out button is the only way workers end their shift in the app.

What to do earlier next time:
- When a task says "clock in", read it as "clock in/out" — scope the full user action, not just the entry point.

Reusable rule:
- Every user-facing action that has a start must also have a stop.

### 11. Build the offline system before it hurts, not after

What we learned:
- The roadmap marks offline as "MUST WORK" in bold. We built it as part of Sprint 2 rather than deferring it.
- The sync engine, local database, connectivity detection, and retry logic are all foundational — they affect how clock events, photos, and future features behave.

What we fixed:
- Built Drift/SQLite local database with `PendingEvents` table.
- Built SyncEngine with 15s timer, connectivity check, exponential backoff (5s-80s, max 5 retries).
- Built SyncStatusBar widget showing offline/syncing state.
- Wired sync engine start into bootstrap.

Why it mattered:
- Field workers frequently lose connectivity. Without offline support, every API call becomes a user-visible failure.
- Building it early means every future feature (camera, tasks, notes) can write locally first.

What to do earlier next time:
- Build the offline system as soon as the first event-producing feature exists.

Reusable rule:
- If the product is mobile-first and field-used, offline support is infrastructure, not a feature.

### 12. RLS blocks unauthenticated web dashboards — auth first, queries second

What we learned:
- The web supervisor dashboard loaded correctly but showed "No active jobs found" even though the database had active jobs.
- The Supabase anon key was used without an authenticated session, so RLS policies (which check `current_company_id()` via `auth.uid()`) correctly returned nothing.

What we fixed:
- Added an AuthGuard component that wraps all web pages.
- Supervisor must sign in before seeing any data.
- NavBar shows the current user email and a Sign out button.

Why it mattered:
- RLS doing its job silently is worse than a visible error — you think the feature is broken when really it's the auth boundary working correctly.
- Every data-fetching surface needs an authenticated session if the database has RLS.

What to do earlier next time:
- When building a new frontend against an RLS-protected backend, add auth before writing the first data-fetching page.

Reusable rule:
- If RLS is on, unauthenticated queries return empty, not errors. Always add auth first.

### 13. macOS entitlements block network access by default

What we learned:
- The Flutter macOS desktop app crashed on sign-in because it couldn't make outbound HTTP requests.
- The default macOS entitlements include `network.server` but NOT `network.client`.
- Google Fonts fetching also failed silently, contributing to the crash.

What we fixed:
- Added `com.apple.security.network.client` to both `DebugProfile.entitlements` and `Release.entitlements`.

Why it mattered:
- Any app that calls an API needs outbound network permission on macOS.
- The error message ("Sign-in failed") didn't indicate a network permission issue — it looked like bad credentials.

What to do earlier next time:
- When scaffolding a Flutter project that talks to a backend, add `network.client` entitlement immediately.

Reusable rule:
- Flutter macOS apps need `com.apple.security.network.client` to make any HTTP requests. Add it to both Debug and Release entitlements at project creation time.

### 14. Clean the .next cache when module errors cascade

What we learned:
- After editing layout.tsx while the dev server was running, Next.js entered a corrupted state with `Cannot find module './373.js'` and `__webpack_modules__[moduleId] is not a function` errors.
- Refreshing and restarting the dev server didn't fix it — the `.next` build cache was stale.

What we fixed:
- Deleted `.next/` directory and restarted the dev server.

Why it mattered:
- Corrupted build caches waste debugging time. The fix is always the same: delete `.next` and restart.

What to do earlier next time:
- If you see `Cannot find module './NNN.js'` or `__webpack_modules__` errors in Next.js, delete `.next/` first before investigating further.

Reusable rule:
- When Next.js dev server spirals into module-not-found errors, `rm -rf .next && npm run dev` is the first fix, not the last resort.

### 15. Every page needs a way back

What we learned:
- The timeline page and dashboard had no back navigation. Users landed on the timeline via "View timeline" links but had no way to return except the browser back button or the nav bar.

What we fixed:
- Added a "Back to Dashboard" link at the top of every timeline page.
- Added a "Go to Dashboard" button on the empty timeline state (no job selected).

Why it mattered:
- Supervisors scanning multiple jobs need to move quickly between dashboard and timelines.
- Relying on the browser back button is not a UX pattern — it's a fallback.

What to do earlier next time:
- Add contextual back navigation to every page at build time.

Reusable rule:
- Every page that is reached via a link from another page needs an explicit back link. Never rely on the browser back button as the primary navigation.

### Sprint 2 Code Review Checklist

Before closing Sprint 2, confirm:
- analysis_options.yaml has strict settings enabled.
- All state classes have == / hashCode.
- No hardcoded credentials in any Dart source file.
- All widgets are in separate files (one widget per file).
- All screens have accessibility semantics.
- Backend CORS is restricted for non-local environments.
- GPS coordinates are range-validated before use.
- Multi-step writes have rollback logic.
- flutter analyze returns zero issues.
- flutter test passes all tests.

## Sprint 3 Lessons Learned

### 16. Riverpod family providers changed in v3 — check the API before coding

What we learned:
- `FamilyAsyncNotifier` and `AsyncNotifierProvider.family` don't exist in flutter_riverpod 3.x the same way.
- The first attempt used `FamilyAsyncNotifier<List<TaskItem>, String>` which compiled in 2.x docs but fails in 3.x.

What we fixed:
- Used a `Provider<String>` for the job ID with `ProviderScope` override when pushing the task screen.
- The `AsyncNotifier` watches the job ID provider and rebuilds when it changes.

Why it mattered:
- Wasted a build cycle debugging a type error that was an API migration issue, not a logic bug.

What to do earlier next time:
- When using a Riverpod pattern for the first time in a project, verify against the exact installed version, not docs from a different version.

Reusable rule:
- Always check the actual package version's API, not generic tutorials. Riverpod 2.x and 3.x have different family notifier APIs.

## Sprint 4 Lessons Learned

### 17. One edge function can serve multiple actions — route by action, not by endpoint

What we learned:
- OT request and OT approval are two logically distinct operations, but they share auth, rate limiting, idempotency, and the same data domain.
- Instead of two separate edge functions (`ot_request` and `ot_approve`), one `/ot` function with `action: "request"` and `action: "decide"` is cleaner.

What we fixed:
- Built a single `/ot` edge function that routes by POST `action` field.
- GET lists requests (workers see own, supervisors see all).
- POST with action=request creates, action=decide approves/denies.

Why it mattered:
- Reduced deployment surface (1 function instead of 2).
- Shared auth/rate-limit/idempotency logic lives in one place.
- The pattern scales: `/tasks` already uses GET/POST routing the same way.

What to do earlier next time:
- When two operations share the same domain and auth requirements, combine them in one function with action routing.

Reusable rule:
- One edge function per domain, not per operation. Route internally by action or HTTP method.

### 18. Immutable decisions need explicit guard rails — not just business logic

What we learned:
- OT approval decisions must be immutable per the PRD (append-only). But without explicit guards, a second approval call on the same request could overwrite the first.
- We needed: status check (must be pending), self-approval block, role check, and rollback on event insert failure.

What we fixed:
- Cannot approve own request (worker_id !== approver_id).
- Only pending requests accept decisions.
- If ot_approval_event insert fails, ot_requests.status rolls back to pending.
- Idempotency prevents replay with different payloads.

Why it mattered:
- Payroll accuracy depends on each OT decision being final and traceable.
- Without these guards, a race condition or retry could produce conflicting decisions.

What to do earlier next time:
- For any append-only decision (approvals, corrections), write the guard rails into the first implementation, not as a hardening pass later.

Reusable rule:
- If a decision is immutable, enforce it at every layer: status check, role check, self-check, rollback on failure, and idempotency.

## Sprint 5 Lessons Learned

### 19. Reports are just structured queries over existing event data — keep them simple

What we learned:
- The temptation was to build a complex PDF rendering pipeline (headless browser, Puppeteer, etc.).
- But the Sprint 5 definition of done is about data accuracy, not visual polish.
- A JSON report with structured data that matches source events exactly is more valuable than a pretty PDF that might round or approximate.

What we fixed:
- Built the report as a structured JSON response (job summary, worker hours, tasks, photos with verification codes, OT decisions).
- Timesheet as CSV with proper columns and 15-minute rounding.
- Both stored as export_artifacts for audit trail.
- PDF rendering deferred to a future Python worker — the data contract is what matters now.

Why it mattered:
- The PRD says "send to client and get paid." The client needs accurate data. Pretty formatting is secondary.
- Shipping accurate data now and adding PDF rendering later is better than shipping a pretty PDF with wrong numbers.

What to do earlier next time:
- Build the data assembly and accuracy first. Add rendering (PDF, charts) as a separate layer on top.

Reusable rule:
- Reports are data contracts first, documents second. Get the numbers right before making them pretty.

### 20. Review tasks should not stay in Review indefinitely — close them when evidence exists

What we learned:
- By Sprint 5, we had 18 tasks sitting in "Review" status across Sprints 2-5. All had code, tests, and build verification, but none were moved to Done.
- The board looked like nothing was finished even though 5 sprints of work were complete.

What we fixed:
- Audited every pre-Sprint-6 task in Notion.
- Moved 18 tasks from Review to Done in one pass.
- Added agent notes to the 2 tasks that were still Backlog with empty notes (Logging system, Server-side photo stamp).

Why it mattered:
- A board full of Review items creates the same false impression as a board full of false Done items — it distorts planning.
- New sessions or new developers can't tell what's actually finished.

What to do earlier next time:
- Move tasks to Done immediately after verification passes, not in a batch later.
- The pipeline should be: implement → verify → Done. Not implement → verify → Review → forget → batch-close later.

Reusable rule:
- If the code is written, analyze is clean, tests pass, and the build succeeds — it's Done, not Review. Close it the same session you verify it.

### Sprint 5 Closing Checklist

Before moving to Sprint 6, confirm:
- All Sprint 1-5 tasks are Done in Notion (18 tasks closed).
- Logging system is in Review (structured logging exists, observability tooling deferred).
- flutter analyze returns 0 issues.
- flutter test passes 9/9.
- next build passes with 5 pages.
- SPRINT_TRACKER.md matches Notion.
- SecondBrain vault is synced.

## Final Code Review Audit Lessons

### 21. Creating a file is not the same as wiring it in — dead code is invisible debt

What we learned:
- We built `ForemanHomeScreen` and `WorkerHistoryScreen` as complete widget files with premium UI. But neither was reachable from any navigation path. No button, no menu item, no route pushed either screen.
- They passed `flutter analyze` and `flutter test` — zero errors — because dead code is valid code. The analyzer doesn't know that no user can ever see it.
- We declared them Done in Notion and the sprint tracker based on "file exists + analyze passes." That was wrong.

What we fixed:
- Added a history icon button in the HomeScreen AppBar that pushes `WorkerHistoryScreen`.
- Foreman screen flagged for role-based routing (needs `role` field on `SessionState`).

Why it mattered:
- A feature that exists in the repo but can't be reached by a user is not a feature — it's dead code with a Done label.
- This passed through 3 review cycles without being caught because we were checking "does the file exist" not "can a user get to it."

What to do earlier next time:
- After creating any new screen, immediately verify: "What button or navigation action reaches this screen?" If the answer is "nothing," it's not done.
- Add a navigation wiring check to the definition of done for every UI task: "User can navigate to and from this screen."

Reusable rule:
- A screen without a navigation entry point is dead code. Always wire before marking done.

### 22. i18n setup without wiring is theater — ARB files mean nothing until MaterialApp knows about them

What we learned:
- We added `flutter_localizations` to pubspec, created `l10n.yaml`, wrote ARB files for English, French, and Arabic, generated the `AppLocalizations` class, and marked i18n as Done.
- But `MaterialApp` had no `localizationsDelegates` and no `supportedLocales`. The generated class was never imported. Every string in every widget was still a hardcoded English literal.
- The app would have shipped with zero localization despite all the infrastructure being in place.

What we fixed:
- Added `localizationsDelegates` and `supportedLocales` to `MaterialApp`.
- Imported `AppLocalizations` from the generated path.

Why it mattered:
- The plan explicitly says i18n is a Phase 2 REQUIREMENT, not optional. French, Arabic, and Thai for international deployments.
- Infrastructure without wiring is worse than no infrastructure — it creates a false sense of completion.

What to do earlier next time:
- After adding any SDK or configuration, verify it works end-to-end: "Can I call `AppLocalizations.of(context)!.signIn` and see it compile?"
- i18n is not done until at least one widget uses the generated strings instead of hardcoded text.

Reusable rule:
- Configuration without consumption is dead code. Wire it into at least one consumer before marking done.

### 23. copyWith patterns must be consistent across the entire codebase — one wrong pattern creates a ticking crash

What we learned:
- `ClockState` correctly uses the sentinel pattern for `copyWith` (allowing explicit null-setting).
- `OTRequestState` used a different pattern where `error` and `successId` always replace without sentinel checking — meaning calling `copyWith(isSubmitting: false)` silently clears `error` to null.
- This worked only because every caller happened to pass all fields explicitly. One future caller omitting a field would lose state silently.

What we fixed:
- Applied the sentinel pattern to `OTRequestState.copyWith`, matching `ClockState`.

Why it mattered:
- Inconsistent patterns across state classes mean every new contributor has to check which pattern each class uses. That's a guaranteed future bug.
- Silent data loss in state management is one of the hardest bugs to diagnose because the app doesn't crash — it just shows wrong information.

What to do earlier next time:
- When the codebase establishes a pattern (sentinel copyWith, value equality, etc.), apply it to EVERY new state class from the first implementation. Don't allow two patterns to coexist.

Reusable rule:
- If a pattern exists in one state class, it must exist in all state classes. Inconsistency is a bug waiting to happen.

### 24. Bang operators on nullable fields are crash timebombs even when gated by parent conditionals

What we learned:
- `ClockErrorPanel` used `state.errorTitle!` and `state.errorMessage!` with the bang operator. The panel was only rendered when `clockState.hasError` was true in the parent widget.
- But the panel widget itself never checked — it trusted the parent's conditional. Between build frames, if the state changed, the panel could receive a null value and crash.

What we fixed:
- Replaced `state.errorTitle!` with `state.errorTitle ?? ''` — null-safe regardless of caller.

Why it mattered:
- A widget that crashes when its invariant is broken by the framework's build lifecycle is fragile.
- The fix is trivial (null-aware access), but the crash in production is not.

What to do earlier next time:
- Never use bang operators in widget build methods. Always use null-aware access or guards.
- Treat every widget as independent — it must handle its own null safety, not trust the caller.

Reusable rule:
- Widgets must never use `!` on fields that could be null. Use `??` or early return. Trust no caller.

### 25. Dark mode requires auditing every hardcoded color — Colors.white breaks dark themes silently

What we learned:
- We built a full dark theme with proper tokens (`_darkBg`, `_darkSurface`, etc.) and wired `ThemeMode.system` into `MaterialApp`.
- But `ClockStatusPanel` and `ClockErrorPanel` used `Colors.white` directly in gradient endpoints and background colors.
- In dark mode, these panels rendered as white rectangles on a dark background — completely breaking the visual design.

What we fixed:
- Replaced all `Colors.white` in widget files with `palette.surfaceWhite` (which resolves to `_darkSurface` in dark mode).

Why it mattered:
- A dark mode that's 90% correct but has white rectangles in the main screen looks worse than no dark mode at all.
- Every hardcoded color is a dark mode bug.

What to do earlier next time:
- After adding dark mode, grep the entire codebase for `Colors.white`, `Colors.black`, and any hex color literals in widget files. Every one must use a palette token instead.

Reusable rule:
- If the app has dark mode, zero widget files should contain `Colors.white` or `Colors.black`. Use theme tokens everywhere.

### 26. ProviderObserver is not optional — provider failures are silently swallowed without one

What we learned:
- `ProviderContainer` was created without a `ProviderObserver`. When any `AsyncNotifier` or `Notifier` throws an uncaught exception, Riverpod's internal error handling swallows it silently.
- Combined with the global error handlers that only called `debugPrint` (stripped in release), this meant production crashes would be completely invisible.

What we fixed:
- Created `FieldOpsProviderObserver` extending `ProviderObserver` with `providerDidFail`.
- Wired it into `ProviderContainer(observers: [...])`.

Why it mattered:
- For a field operations app where workers may be on remote sites, silent crashes are the worst possible failure mode. No one reports them, and you don't know they're happening.

What to do earlier next time:
- Add `ProviderObserver` at the same time as creating the `ProviderContainer`. Never create a container without an observer.

Reusable rule:
- `ProviderContainer` without `ProviderObserver` is a monitoring blind spot. Add the observer at creation time, not during hardening.

### Final Audit Checklist (run before any sprint close)

Before closing any sprint, verify:
- [ ] Every new screen has a navigation entry point (button, menu, route)
- [ ] Every SDK/config addition is consumed by at least one widget
- [ ] All state classes use the same copyWith pattern (sentinel or otherwise)
- [ ] Zero bang operators in widget build methods
- [ ] Zero `Colors.white` or `Colors.black` in widget files (use palette tokens)
- [ ] `ProviderContainer` has an observer
- [ ] Global error handlers forward to a real reporting service (not just debugPrint)
- [ ] `flutter analyze` returns 0 issues
- [ ] `flutter test` passes all tests
- [ ] Web `next build` passes if applicable

## Git & GitHub Setup Lessons (2026-04-04)

### 27. Never write status-based docs without checking all three trackers first

What we learned:
- The README roadmap was written based on ROADMAP.md's step structure (Steps 0-8), without checking SPRINT_TRACKER.md or Notion.
- It incorrectly showed Sprints 2-5 as "In progress" or "Backlog" when all five sprints were Done.
- The README shipped publicly to GitHub with wrong status for ~30 minutes before being corrected.

What we fixed:
- Read SPRINT_TRACKER.md and queried Notion before updating the README.
- Rewrote the roadmap table to reflect actual sprint status, not the strategic step structure.

Why it mattered:
- Investors, partners, or future developers reading the README would have a false picture of how far along the product is.
- Status claims require evidence from authoritative sources (SPRINT_TRACKER + Notion), not structural documentation (ROADMAP.md).

What to do earlier next time:
- Before writing any status table or progress summary, open three tabs: SPRINT_TRACKER.md, Notion board, and the code itself.
- Cross-reference all three before publishing.

Reusable rule:
- ROADMAP.md describes architecture. SPRINT_TRACKER.md describes reality. Always use the tracker for status claims.

---

### 28. .env.example must always have placeholder values — real keys only in .env (gitignored)

What we learned:
- The initial `.env.example` contained real Supabase keys. It was committed to the repo.
- Even if keys are personal-use-only at the time, `.env.example` is a public contract — it gets committed and pushed.

What we fixed:
- Replaced real keys in `.env.example` with explicit placeholders (`your-anon-key`, `your-project-ref`).
- Created `.env` with the real keys (excluded by `.gitignore`).
- Verified `.env` was absent from `git status` before pushing.

Why it mattered:
- Keys in `.env.example` end up in git history permanently, even after you fix them. Rotation is the only real fix after a leak.
- The `.env.example` file purpose is to show structure, not to carry real values.

What to do earlier next time:
- When creating `.env.example`, use placeholder text from the first commit. Never copy-paste real values into it.

Reusable rule:
- `.env.example` = structure only. `.env` = real values, always gitignored. Audit both before every push.

---

### 29. GitHub creates a `main` branch with a LICENSE when you initialize a repo — merge before pushing

What we learned:
- When a GitHub repo is initialized with a license file, it creates a `main` branch with one commit.
- Pushing a local `master` branch succeeds but doesn't affect `main`.
- Pushing local `main` to remote `main` fails with "fetch first" because the two histories are unrelated.

What we fixed:
- Used `--allow-unrelated-histories` to merge the remote LICENSE commit into the local branch.
- Renamed local `master` → `main`, pushed, deleted remote `master`, and set `main` as default branch.

Why it mattered:
- First-time GitHub push is a one-shot moment — getting it wrong results in two branches with split history.
- Force-pushing `main` would have destroyed the LICENSE commit and created a messy history.

What to do earlier next time:
- After creating a GitHub repo with any auto-generated file (LICENSE, README), immediately `git fetch` and merge before creating your first local commit.
- Or: initialize the repo with no files and push freely.

Reusable rule:
- If GitHub initialized the repo with any file, fetch and merge `--allow-unrelated-histories` before your first push. Never force-push over it.

---

### 30. Verify all gitignore exclusions against actual `git status` output before the first push

What we learned:
- The initial `.gitignore` was missing 7 entries: `.claude/`, `OldAgentoberemoved.md`, `**/.DS_Store`, `**/__pycache__/`, `*.pyc`, `infra/supabase/.branches/`, `infra/supabase/.temp/`, and `FieldOps_AI_Complete_Plan_2026_v5.docx`.
- Several of these would have committed secrets-adjacent data (Claude session files), system junk (`.DS_Store`), or binary documents.

What we fixed:
- Audited every category of file in the repo against best practices for a monorepo with Python, Flutter, Next.js, and Supabase.
- Added all missing entries before the first commit.
- Verified with `git status --short` that excluded files were absent from staging.

Why it mattered:
- Secrets and session data in git history are permanent. You cannot "un-commit" them from a public repo without a full history rewrite.

What to do earlier next time:
- Before the first `git add`, generate a `.gitignore` that covers every language and tool in the project. Run `git status` and look for unexpected files.

Reusable rule:
- The first commit is the most important gitignore audit. Every file in `git status` before the initial commit is a deliberate choice.

---

### 31. Locale infrastructure is not product i18n until the high-traffic surfaces actually consume it

What we learned:
- It is easy to overclaim localization progress once a locale provider, translation map, and language toggle exist.
- That still does not mean the product is localized. The only honest question is: which user-facing screens actually switched from hardcoded text to translated strings?
- On this project, mobile already had Spanish assets, but the web product was still effectively English until the supervisor shell and the main operating pages were wired one by one.

What we fixed:
- Added a shared `en/es` locale provider for the web app.
- Wired the highest-traffic supervisor surfaces to it:
  - dashboard
  - workers
  - map
  - timeline
  - photos
  - overtime
  - reports
  - schedule
  - cost codes
- Re-verified with `npm run lint` and `npm run build` after the translations were actually consumed.

Why it mattered:
- A locale toggle without translated operational pages is another form of completion theater.
- The most important proof is whether the live worker/supervisor loop can operate in the target language, not whether translation infrastructure exists.

What to do earlier next time:
- Define localization scope by surface, not by setup.
- Start with the pages users hit every day.
- Track untranslated pages explicitly so “partial” cannot quietly become “done.”

Reusable rule:
- i18n is complete only when the real user surfaces are translated, verified, and enumerated.

### 32. Append-only event stores should be tested with clean resets or delta assertions, not destructive cleanup

What we learned:
- The worker-hours summary is derived from `clock_events`, and that table is intentionally append-only.
- A naive attempt to make the regression repeatable by deleting prior worker events failed, correctly, because the database blocks event mutation.
- Re-running the same event-derived test on a dirty local database can also produce misleading totals because old and new sessions interleave in time.

What we fixed:
- Kept the clean canonical backend gate as `python3 execution/run_backend_regression_suite.py`, which resets Supabase before running.
- Updated the worker-hours regression to compare `before` and `after` totals on a clean stack rather than assuming an empty event history.
- Cleared `api_request_logs` for the seeded users so repeat local runs do not trip rate limits unrelated to the behavior under test.

Why it mattered:
- This avoided weakening the event-store model just to make a test easier.
- It also made the regression honest about how append-only systems behave over time.

What to do earlier next time:
- When a feature is computed from an append-only ledger, decide up front whether the proof path is:

### 33. Proof-backed finance flows are not complete until both evidence and payout state are enforced

What we learned:
- Receipt capture looked “mostly there” because the mobile form, backend endpoint, and supervisor review page all existed.
- The slice was still incomplete because workers could submit without a real receipt asset, and supervisors had no final reimbursement state to close the loop.
- In other words, the UI suggested a proof-backed flow while the backend still allowed proof-less submission.

What we fixed:
- Required a real uploaded `media_asset_id` for expense submission in the backend.
- Added lightweight category suggestion from vendor and notes on mobile so the capture flow stays fast without pretending to be full OCR.
- Added reimbursement fields and supervisor reimbursement actions so approved expenses can move to a final tracked state.
- Verified the full slice through backend regression, mobile tests/analyze, and web lint/build.

Why it mattered:
- Finance features lose trust quickly if the proof requirement is optional or if approved items disappear into a manual side process.
- “Approved” and “reimbursed” are different operational states, and collapsing them hides work that payroll or finance still has to do.

What to do earlier next time:
- For any workflow that depends on evidence, enforce that evidence on the server before shipping the UI.
- Model the full lifecycle up front: submit, review, approve/deny, settle/export.
- Keep “smart” assistance lightweight unless it is truly reliable enough to own the workflow.

Reusable rule:
- A finance flow is not done when it stores a request; it is done when proof, approval, and settlement are all explicit and verifiable.

### 34. The fastest way to finish i18n debt is to turn the remaining untranslated surfaces into an explicit coverage list

What we learned:
- Once most of the app was localized, the remaining gap was not infrastructure. It was a short list of admin pages still carrying hardcoded English.
- Those low-traffic pages are easy to miss because the main dashboards already look “done.”

What we fixed:
- Identified the exact remaining pages: `onboarding`, `settings`, and `settings/staff`.
- Added a small regression check that fails unless those pages use `useI18n()` and the translation map contains matching sections.
- Finished the last web translations and re-verified with lint and build.

Why it mattered:
- This prevented Spanish support from staying in a permanent “almost done” state.
- It also gave the repo a concrete proof path for localization coverage instead of relying on a manual visual sweep.

What to do earlier next time:
- As soon as i18n is introduced, keep an explicit list of page surfaces and close them one by one.
- Add a small coverage check before the final i18n pass so untranslated pages cannot hide in the long tail.

Reusable rule:
- When localization is partially complete, turn the remaining untranslated surfaces into a finite checklist and gate it with a simple regression test.

### 35. A publish workflow becomes much simpler when the mobile notification cue is derived from publish metadata instead of blocked on push infrastructure

What we learned:
- The schedule feature was stalled in a “partial” state because the planner, worker view, and notification story were treated like separate systems.
- In practice, the backend already had the right backbone once `published_at` and worker-scoped reads were respected.

What we fixed:
- Extended the schedule contract so supervisors can edit drafts and workers can only read their own published shifts.
- Used `published_at` as the lightweight notification signal for the mobile app, surfacing newly published shifts with an in-app `Updated` badge.
- Added the missing worker mobile schedule screen and finished the supervisor planner with real edit plus drag-to-reschedule behavior.

Why it mattered:
- This avoided blocking a useful worker notification experience on Firebase/APNs setup.
- It also kept the schedule feature coherent across backend, supervisor web, and worker mobile instead of treating them as unrelated tasks.

What to do earlier next time:
- When a feature has a publish boundary, decide early what field proves “published” and let downstream clients react to that field.
- Use push notifications as an enhancement, not as the only way the product can communicate an update.

Reusable rule:
- If a publish timestamp already exists, use it as the first-class update signal before adding heavier notification infrastructure.
  - full reset, or
  - baseline-plus-delta
- Do not write tests that assume mutable history unless the system actually allows it.

Reusable rule:
- For append-only event models, prefer reset-based verification or delta assertions over destructive cleanup.

### 36. A global sed/find-replace is not a substitute for verification — multi-line patterns and nested widgets will be missed

What we learned:
- We used `find ... -exec sed ...` to replace all `Theme.of(context).extension<FieldOpsPalette>()!` with `context.palette` across 24 widget files. It worked for 23 of them.
- The 24th file (`foreman_home_screen.dart`) had the pattern split across 3 lines inside a nested `_QuickActionCard` widget builder, so the sed regex didn't match.
- The regression was only caught in the second code review pass.

What we fixed:
- Manually fixed the remaining instance. Added `grep` verification step after every global replace.

Why it mattered:
- A crash in production from one missed bang operator would have been trivially preventable.
- The fix took 10 seconds; finding it in production would take hours.

Reusable rule:
- After any global find-replace, ALWAYS grep for the old pattern to confirm zero remaining matches.
- Never trust a sed command as proof of completion — run `grep -rn "old_pattern"` and verify zero results.

### 37. Every test that exists must run in CI, or it's not a test — it's documentation

What we learned:
- `test_rls_validation.py` existed and was recently improved (new tables, env vars), but was NEVER included in `run_backend_regression_suite.py`.
- This meant RLS policy changes could silently break tenant isolation without CI catching it.
- The test was effectively dead code — it only ran when someone manually remembered to invoke it.

What we fixed:
- Added `test_rls_validation.py` to both code paths (normal and skip-reset) in the regression suite.

Why it mattered:
- RLS is the single most important security boundary in the product. A missing CI gate on it is a P0 process failure.

Reusable rule:
- When you create a new test file, the SAME PR must add it to the CI suite. Test files that aren't in CI don't protect anything.
- Periodically `ls execution/test_*.py` and compare against the suite runner's step list.

### 38. Authorization != Authentication — the auth guard is not a role gate

What we learned:
- The Next.js `AuthGuard` component in `layout.tsx` wraps all pages and checks if a session exists (authentication).
- But it does NOT check the user's role (authorization). Any authenticated worker could navigate directly to `/settings/staff` and promote themselves to admin.
- The Sidebar showed the "Staff" link to all users without role filtering.

What we fixed:
- Added a `useEffect` in `StaffPage` that queries the user's role from the `users` table and shows "Access denied" for non-admins.
- Added `adminOnly: true` flag to nav items and filtered the sidebar based on user role.

Why it mattered:
- This is a privilege escalation vulnerability. A worker promoting themselves to admin can access all company data, modify all users, generate all reports.

Reusable rule:
- Authentication (who are you?) and authorization (what can you do?) are separate concerns. Never assume one implies the other.
- Every admin-only page needs its own server-side role check, not just a hidden nav link. Hiding a link is not security.
- When adding a new settings/admin page, the PR checklist must include: "Does this page have a role gate?"

### 39. Idempotency must cover the ENTIRE request, not just the header — batch_id and body fields matter

What we learned:
- We fixed the sync engine's `Idempotency-Key` header to use a stable `local-event-${event.id}` instead of `_uuid.v4()`.
- But the request body still contained `batch_id: _uuid.v4()` — a fresh random UUID on every retry.
- This meant the server received the same idempotency header but a DIFFERENT request body, which could confuse server-side dedup logic.

What we fixed:
- Changed `batch_id` to `batch-${event.id}` so the entire request (header + body) is deterministic across retries.
- Also removed the now-unused `Uuid` dependency from `SyncEngine`.

Why it mattered:
- Partial idempotency is worse than no idempotency — it gives false confidence while still allowing duplicates.

Reusable rule:
- When implementing idempotency, ensure EVERY part of the request (headers, body, query params) is deterministic for retries.
- After fixing idempotency, grep for any remaining `uuid.v4()` or `randomUUID()` calls in the same function — they're likely also generating per-retry randomness.

---

## Cross-Project Rules Worth Reusing

- Never trust project status without checking the repo and running the proof command.
- Keep planning, execution, and proof in separate but connected layers.
- Script repeated workflows early.
- Test the orchestration around the system, not just the system itself.
- Use one canonical local verification command and make CI run that exact path.
- Treat environment setup as part of the product delivery pipeline, not as developer folklore.
- `.env.example` = structure only. Real values only in gitignored `.env`.
- ROADMAP.md describes architecture. SPRINT_TRACKER.md describes reality. Always use the tracker for status claims.
- The first commit is the most important gitignore audit. Verify `git status` before staging anything.
- After any global find-replace, grep for the old pattern to confirm zero matches. sed is not proof. (Lesson 36)
- Every test file must be in the CI suite, or it's dead code. When you create `test_*.py`, add it to the runner in the same PR. (Lesson 37)
- Authentication ≠ authorization. Every admin page needs a server-side role check, not just a hidden nav link. (Lesson 38)
- Idempotency must cover the full request (header + body + params), not just the key header. Grep for random UUID calls after fixing idempotency. (Lesson 39)
- `Stream.periodic` does NOT emit at t=0. Always use an async generator (`yield` first value, then `await for`) when you need an immediate first emission. (Lesson 40)
- Sprint tracker "Done" is not a source of truth. Always verify by running the code and checking the screen. Features marked complete can be missing entire views. (Lesson 41)
- `AppLocalizations` missing getter = compile failure in test suite. Any l10n key referenced in code that isn't in the ARB file will silently break `flutter test`. Fix by hardcoding the string OR adding the ARB key — never skip. (Lesson 42)
- `RepaintBoundary.toImage()` is the correct Flutter API for flattening a custom-paint canvas to a PNG with no extra packages. Pair with `getTemporaryDirectory()` from `path_provider`. (Lesson 43)
- Never pass the raw JWT to `supabase.auth.getUser(jwt)` in edge functions. Newer Supabase projects use ES256 (asymmetric) JWTs which cannot be verified locally — the call throws "Unsupported JWT algorithm ES256". Always call `supabase.auth.getUser()` with no argument; the client already holds the Authorization header and delegates verification to the Supabase auth service. (Lesson 44)
- Validate every edge-function DB reference against live migrations BEFORE shipping. A function referencing a non-existent column (`storage_url`, `stamp_metadata`, `jobs.address`) or enum value (`sync_status: 'synced'`, `kind: 'optimized_photo'`) returns empty data or silently errors at runtime — the failure only surfaces on `supabase db reset` or on real traffic. Pre-PR grep: `grep -rn "\\.from.*media_assets\\|\\.from.*jobs\\|sync_status:\\|kind:\\|export_kind:" infra/supabase/functions/` → cross-check each hit against `infra/supabase/migrations/*.sql`. When a function needs a new enum value, add it via `ALTER TYPE ... ADD VALUE IF NOT EXISTS` in the same migration that ships the function. (Lesson 45)
- Every Sprint cycle: start with a review pass before adding new code. Today's morning audit found 14 issues in the mobile app alone (3 crash-risk, 5 correctness, 4 anti-pattern, 2 polish) plus 11 accumulated lint warnings — all shipped in one review commit before the feature work began. Pattern: run the language's linter/analyzer at the top of every session and treat any non-zero count as a blocker. A clean analyzer is not optional; it's the minimum bar for "ready to build". (Lesson 46)
- Never persist stateful backend values (encryption keys, auth tokens) via a single secure-storage call without a try/catch + in-memory fallback. `FlutterSecureStorage` can throw `PlatformException` on first launch, keychain reset, rooted devices, or OEM quirks — if you don't handle it, the app crashes before it can even boot. Pattern: wrap the read in try/catch; on failure generate a transient value and proceed; log but don't block. (Lesson 47)
- `PlatformDispatcher.instance.onError` is NOT automatically wired by Sentry — you must set it explicitly before `Sentry.captureException` can receive async/isolate errors. `FlutterError.onError` is handled by Sentry's init, but PlatformDispatcher needs a manual handler that forwards to Sentry. Without it, unhandled Futures and isolate errors are silently dropped in production. Set the handler unconditionally at bootstrap, before any `await`s. (Lesson 48)
- Supabase's Kong gateway `verify_jwt = true` verifier is HS256-only. When the project rotates to asymmetric ES256 signing keys (the new default), every edge function call 401s with `UNAUTHORIZED_UNSUPPORTED_TOKEN_ALGORITHM`. Redeploying does not fix it. Fix: set `verify_jwt = false` and rely on in-function `supabase.auth.getUser()` (delegates to GoTrue which is JWKS-aware). (Lesson 49)
- Client↔server contract mismatches are silent production failures. Sentry catches them only after a field worker hits the bug. The only real defense is a contract test per edge function that hits the live endpoint with the exact body shape the mobile client produces. When adding a new `action` on either side, update both in the same PR and link mobile callsite ↔ server branch. (Lesson 50)
- Every custom Dart exception class must override `toString`. Default `Object.toString` turns every crash in Sentry into `"Instance of 'XxxException'"` — all events look identical, all diagnostic info is lost. 16 classes in this repo had the bug; fix is one line per class. In review, flag any `class XException implements Exception` without a toString. (Lesson 51)
- Hierarchies in field-service software are inherently optional. If your data model requires a manager for every worker to function, you've encoded HR-org assumptions that don't hold on small crews. Design the empty-path behaviour first: a foreman with no job assignments should return an empty crew, not an error; jobs with no foreman should still work end-to-end. (Lesson 52)
- `supabase functions deploy --no-verify-jwt` sets the gateway flag for that one deploy, but `config.toml` is the source of truth for the next one. If `[functions.<name>] verify_jwt = false` is missing from `config.toml`, the next CI deploy flips verify_jwt back to true and ES256 outages return silently. Lesson: whenever you pass a flag to `deploy`, mirror it in `config.toml` in the same PR. Ship a grep check: every dir under `infra/supabase/functions/` (minus `_shared`) must have a matching `[functions.<name>]` block. (Lesson 53)
- TypeScript literal `as const` string tuples feeding a `.in("status", ...)` query against a PostgreSQL enum will pass typecheck even when the string is not a valid enum member — the schema is not known to the client type system. Any ad-hoc status list introduced in UI code (foremen admin, filter dropdowns, job board columns) must be grepped against `CREATE TYPE <name> AS ENUM (...)` at review time, or the first render throws `invalid input value for enum`. Cheapest defensive measure: generate a shared `JOB_STATUS_VALUES` constant from the migration and import it everywhere instead of typing the list by hand. (Lesson 54)
- Positional-argument helpers fail silently. The shared `jsonResponse(payload, status, requestId, extraHeaders)` signature was called as `jsonResponse(requestId, payload)` in the breadcrumbs edge function. TypeScript didn't catch it because both the swapped-in `requestId` (string) and the swapped-in `payload` (object) satisfy the loose `JsonValue | unknown` types, and the runtime error (`new Response(_, {status: <object>})` → `RangeError`) lands in the function's outer `try/catch` and gets re-emitted as a generic 500. Net effect: feature was broken in production with no Sentry signal beyond a flat 500 stream. Two defenses: (1) prefer keyword-only or single-object arg helpers for response builders; (2) every edge function needs a contract test that reads the success envelope at least once — passing an arg-order bug through CI requires the suite to never have actually exercised the success path. (Lesson 55)
