# 🚀 SPRINT 1 — “FIRST REAL USAGE LOOP”

## 🎯 Goal (non-negotiable)
A worker can:
- log in
- see assigned jobs
- clock in
- take a photo
- supervisor can see it

If that works → sprint is successful.

---

## 🧱 SCOPE (WHAT WE BUILD)

### INCLUDED

**Backend**
* Auth (Supabase)
* Users + assignments read
* `/jobs/active`
* `/sync/events` (basic)
* `/media/presign`
* `/media/finalize`

**Mobile (Flutter)**
* Login screen
* Job list
* Clock in button
* Camera capture
* Offline queue (basic)

**Web (Supervisor)**
* Job list
* Timeline (basic) (Show: clock events, photos)

### EXCLUDED (DO NOT BUILD YET)
* OT system
* AI
* reports
* integrations
* advanced dashboards
* map view

---

## 🧠 AGENT TASK BREAKDOWN

### 🔹 AGENT 1 — DATABASE + BACKEND CORE
**TASK**: Finalize backend foundation and expose minimal APIs.
**BUILD**:
1. Verify migrations (apply all migrations, confirm tables/partitions/RLS exist).
2. Create Edge Function `/jobs/active`.
3. Create Edge Function `/sync/events` (accept clock_events only for now, dedupe via UUID).
4. Create Edge Function `/media/presign`.
5. Create Edge Function `/media/finalize` (no stamping yet).

### 🔹 AGENT 2 — MOBILE APP (CRITICAL)
**TASK**: Build the worker app MVP.
**BUILD**:
1. Login screen (Supabase auth).
2. Job list screen (calls `/jobs/active`).
3. Clock In Button (calls `/sync/events`).
4. Camera Flow (open camera, `/media/presign`, upload, `/media/finalize`).
5. Offline Queue (store pending logic, retry on app open).

### 🔹 AGENT 3 — SUPERVISOR WEB
**TASK**: Build minimal dashboard.
**BUILD**:
1. Job list.
2. Timeline page (displays `job_timeline` view for clock events and photos).
3. Photo preview window.

### 🔹 AGENT 4 — INFRA + TESTING
**TASK**: Make system stable.
**BUILD**:
1. Logging (request_id, errors).
2. Basic rate limiting for sync/media endpoints.
3. Seed data (1 company, 2 workers, 1 supervisor, 2 jobs).

---

## 📊 SPRINT 1 DEFINITION OF DONE

### ✅ HARD REQUIREMENTS
* **Worker**: can login, sees assigned job, taps “clock in”, takes photo
* **Backend**: stores events, stores media, no duplicate events
* **Supervisor**: sees worker clock-in and photo

### ❌ FAILURE CONDITIONS
Sprint is NOT done if sync breaks, photos fail upload, worker flow is confusing, or crashes occur.

### 🔥 FINAL PRIORITY
If something breaks: **FIX WORKER FLOW FIRST.**
