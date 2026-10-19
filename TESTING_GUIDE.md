---
title: Testing Guide
tags:
  - testing
  - setup
  - developer
aliases:
  - Dev Setup
related:
  - "[[SPRINT_TRACKER]]"
  - "[[architecture]]"
---

# FieldOps AI — Testing Guide

How to run every component locally and test from your phone.

---

## Prerequisites

- Docker Desktop running
- Supabase CLI (`supabase` in PATH)
- Flutter SDK (`flutter` in PATH)
- Node.js 18+ (`node` / `npm` in PATH)
- Xcode (for iOS simulator) or Android Studio (for Android emulator)

---

## 1. Start the Local Backend

```bash
cd infra
supabase start
```

Verify it's running:

```bash
supabase status
```

You should see API URL: `http://127.0.0.1:54321` and keys displayed.

### Seed test data

```bash
cd /path/to/FieldsOps_ai
python3 execution/seed_backend_test_data.py
```

This creates:

- A test company
- Two workers: `worker@test.com` and `worker2@test.com` (password: `password123`)
- A supervisor: `supervisor@test.com` (password: `password123`)
- Two active jobs with geofences
- Worker assignments

---

## Hosted Staging (Persistent Real-Life Testing)

For real phone testing, do not rely on local Docker data. Use a hosted Supabase
staging project so auth, storage, schedules, photos, and worker accounts persist.

### Single source of truth

Put your hosted values in the repo root [`.env`](/Users/seancheick/FieldsOps_ai/.env):

```bash
SUPABASE_URL="https://your-project-ref.supabase.co"
SUPABASE_ANON_KEY="your-anon-key"
SUPABASE_SERVICE_ROLE_KEY="your-service-role-key"
NEXT_PUBLIC_MAPTILER_KEY="your-maptiler-key"
NEXT_PUBLIC_SENTRY_DSN=""
NEXT_PUBLIC_POSTHOG_KEY=""
NEXT_PUBLIC_POSTHOG_HOST="https://app.posthog.com"
SENTRY_DSN=""
```

Then sync the repo-local runtime config:

```bash
cd /Users/seancheick/FieldsOps_ai
python3 scripts/sync_runtime_env.py
```

This writes:

- web: [apps/fieldops_web/.env.local](/Users/seancheick/FieldsOps_ai/apps/fieldops_web/.env.local)
- mobile: [apps/fieldops_mobile/env/staging.json](/Users/seancheick/FieldsOps_ai/apps/fieldops_mobile/env/staging.json)

### Full SQL snapshot option

If you want one copy-paste SQL file for an empty hosted project instead of
replaying the migration chain manually, generate:

```bash
cd /Users/seancheick/FieldsOps_ai
python3 scripts/generate_supabase_sql_snapshot.py
```

Outputs:

- [infra/supabase/generated/full_schema.sql](/Users/seancheick/FieldsOps_ai/infra/supabase/generated/full_schema.sql)
- [infra/supabase/generated/full_schema_with_seed.sql](/Users/seancheick/FieldsOps_ai/infra/supabase/generated/full_schema_with_seed.sql)

Use:

- `full_schema.sql` for hosted staging / production bootstrap
- `full_schema_with_seed.sql` only for local/demo/test environments

### Web against hosted Supabase

```bash
cd /Users/seancheick/FieldsOps_ai/apps/fieldops_web
npm run dev
```

### Mobile against hosted Supabase

```bash
cd /Users/seancheick/FieldsOps_ai/apps/fieldops_mobile
flutter run --dart-define-from-file=env/staging.json
```

### Vercel

Your Vercel deployment should use the same hosted values in the Vercel project:

- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`
- `NEXT_PUBLIC_MAPTILER_KEY`
- optional: `NEXT_PUBLIC_SENTRY_DSN`, `NEXT_PUBLIC_POSTHOG_KEY`, `NEXT_PUBLIC_POSTHOG_HOST`

Use hosted staging before production. Production should be a separate Supabase project.

### Run backend regression tests

```bash
python3 execution/run_backend_regression_suite.py
```

---

## 2. Run the Flutter Mobile App

### On iOS Simulator

```bash
cd apps/fieldops_mobile

# Boot a simulator (iPhone 16 Pro)
xcrun simctl boot "iPhone 16 Pro"
open -a Simulator

# Run the app with Supabase config
flutter run \
  --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0
```

### On a Physical iPhone (via USB)

1. Connect your iPhone via USB
2. Open `apps/fieldops_mobile/ios/Runner.xcworkspace` in Xcode
3. Select your device as the target
4. Set the signing team in Xcode (Runner > Signing & Capabilities)
5. Run:

```bash
cd apps/fieldops_mobile
flutter run \
  --dart-define=SUPABASE_URL=http://<YOUR_MAC_IP>:54321 \
  --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0
```

**Important for physical device:** Replace `127.0.0.1` with your Mac's local network IP (find it with `ipconfig getifaddr en0`). Your phone must be on the same Wi-Fi as your Mac.

### On Android Emulator

```bash
cd apps/fieldops_mobile

# Start an Android emulator first, then:
flutter run \
  --dart-define=SUPABASE_URL=http://10.0.2.2:54321 \
  --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0
```

Note: Android emulator uses `10.0.2.2` to reach the host machine's localhost.

### What to test on mobile

1. **Login** — Sign in with `worker@test.com` / `password123`
2. **Job list** — Should show assigned jobs with task counts and geofence info
3. **Pull to refresh** — Pull down on the job list
4. **Clock in** — Tap "Clock in" on a job card (will request location permission)
5. **Clock status** — After clocking in, status panel should show "Clocked in" with the job name
6. **Take photo** — "Take proof photo" button appears after clock-in. Tap it to open camera.
7. **Camera capture** — Capture a photo, watch the upload progress, auto-return to home
8. **Clock out** — Tap "Clock out" in the status panel
9. **Offline** — Turn on Airplane Mode, try to clock in. Should queue locally. Turn off Airplane Mode, sync bar should clear.
10. **Sign out** — Tap "Sign out" in the top bar

### Run Flutter tests

```bash
cd apps/fieldops_mobile
flutter analyze   # Should show: No issues found
flutter test      # Should show: All 9 tests passed
```

---

## 3. Run the Supervisor Web Dashboard

```bash
cd apps/fieldops_web
npm install     # First time only
npm run dev     # Starts on http://localhost:3000
```

Open `http://localhost:3000` in your browser.

### What to test on web

1. **Dashboard** — Shows active jobs as cards
2. **Job card** — Click "View timeline" on any job
3. **Timeline** — Shows chronological events (clock in/out, photos, tasks)
4. **Empty state** — Jobs with no events show "No events recorded yet"

---

## 4. Test from Your Physical Phone

### Option A: Same Wi-Fi (Recommended)

1. Find your Mac's IP: `ipconfig getifaddr en0` (e.g., `192.168.1.42`)
2. Run the Flutter app with your Mac's IP instead of `127.0.0.1`:

```bash
flutter run \
  --dart-define=SUPABASE_URL=http://192.168.1.42:54321 \
  --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0
```

3. For the web dashboard on your phone, open `http://192.168.1.42:3000`

### Option B: USB (iOS only)

1. Connect iPhone via USB
2. Use `127.0.0.1` as the Supabase URL (port forwarding is automatic via USB)
3. Run `flutter run` — it will deploy directly to the connected device

---

## 5. Verify the Full Worker Loop

The MVP loop from the PRD: **clock in -> take photo -> supervisor sees it**

1. Open the mobile app, sign in as worker
2. Clock in to a job
3. Take a proof photo
4. Open the web dashboard (`http://localhost:3000`)
5. Click "View timeline" on the same job
6. Verify the clock event and photo event appear in the timeline

---

## Quick Reference

| Component      | Command                                             | URL                      |
| -------------- | --------------------------------------------------- | ------------------------ |
| Backend        | `cd infra && supabase start`                        | `http://127.0.0.1:54321` |
| Backend Studio | (auto-started)                                      | `http://127.0.0.1:54323` |
| Mobile app     | `flutter run --dart-define=...`                     | On-device                |
| Web dashboard  | `cd apps/fieldops_web && npm run dev`               | `http://localhost:3000`  |
| Backend tests  | `python3 execution/run_backend_regression_suite.py` | N/A                      |
| Flutter tests  | `cd apps/fieldops_mobile && flutter test`           | N/A                      |
