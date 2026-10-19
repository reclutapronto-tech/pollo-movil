# OPERATIONS

One-stop runbook for testing FieldOps AI locally and on the live deploys. Share this with anyone who needs to test the app.

> **Heads-up on credentials**: the test users below work against the **local Supabase stack only** (they come from `infra/supabase/seed.sql`). Do NOT try them against the live Supabase project — create a real account via the signup flow there.

---

## 1. Live deploys (click-to-test)

| What | URL | Notes |
|---|---|---|
| **Web app (production)** | Set this to your Vercel URL (e.g. `https://fieldopsai.vercel.app`) | Latest `main` auto-deploys on push |
| **Supabase (production)** | `https://cpqrazrszhcxjvursuci.supabase.co` | Hosts auth + DB + edge functions + storage |
| **Sentry (monitoring)** | `https://sentry.io` → FieldOps project | Live crash/error tracking |

> If the Vercel URL isn't known yet, run `npx vercel ls` inside `apps/fieldops_web/` or check the Vercel dashboard.

### Before you test against the live web app
After every push that includes Supabase migrations or edge-function changes, someone needs to deploy them separately — Vercel only redeploys the frontend:

```bash
cd infra
supabase link --project-ref cpqrazrszhcxjvursuci    # one-time per machine
supabase db push                                    # apply new migrations
supabase functions deploy tags galleries client_portal reports media_optimize
```

---

## 2. Mobile app (Flutter, iPhone / Android)

### One-liner to run on a connected phone

```bash
cd /Users/seancheick/FieldsOps_ai/apps/fieldops_mobile
./run.sh
```

`run.sh` wraps `flutter run` with all three required `--dart-define` flags (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SENTRY_DSN`). It auto-selects the only connected mobile device; pass `-d "<device name>"` to pick one explicitly.

### Connecting a physical device

1. iPhone: unlock, trust the computer, enable **Developer Mode** (Settings → Privacy & Security → Developer Mode → On). For wireless debugging, join the same Wi-Fi as the Mac.
2. Android: enable **USB debugging** (Settings → About phone → tap Build Number 7×, then Settings → Developer options → USB debugging).

Verify the device shows up:
```bash
flutter devices
```

### Other useful commands

```bash
# Clean state when the build misbehaves
flutter clean && flutter pub get && ./run.sh

# Run analyzer (must be 0 issues before pushing)
flutter analyze --no-pub

# Run tests
flutter test

# iOS release build (needs an Apple Developer account for distribution)
flutter build ipa --release \
  --dart-define=SUPABASE_URL=https://cpqrazrszhcxjvursuci.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY

# Android release APK
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://cpqrazrszhcxjvursuci.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY
```

### Stream logs to a file (when reporting a crash)

```bash
./run.sh 2>&1 | tee /tmp/fieldops.log
# Share the last ~50 lines of /tmp/fieldops.log
```

---

## 3. Web app (Next.js)

### Dev server (hot reload)

```bash
cd /Users/seancheick/FieldsOps_ai/apps/fieldops_web
npm install          # first time or after dependency changes
npm run dev          # starts on http://localhost:3000
```

Open http://localhost:3000 — the app talks to the production Supabase by default (reads `NEXT_PUBLIC_SUPABASE_URL` + `NEXT_PUBLIC_SUPABASE_ANON_KEY` from `.env.local`).

### Production build verification

```bash
npm run build        # builds .next, type-checks, surfaces any lint errors
npm run start        # serves the built output on :3000
```

### Other useful commands

```bash
# Strict type check (same one used in CI)
npx tsc --noEmit

# Lint (warnings are errors — CI rule)
npm run lint

# End-to-end (Playwright) — requires dev server OR config will start one
npx playwright test
npx playwright test e2e/public_gallery.spec.ts      # single spec
```

---

## 4. Supabase local stack (only if you need full end-to-end without the production DB)

Requires Docker Desktop running.

```bash
cd /Users/seancheick/FieldsOps_ai/infra
supabase start                      # boots Postgres, storage, auth, edge runtime
supabase db reset                   # applies every migration + runs seed.sql
supabase functions serve            # serves edge functions at :54321
supabase stop                       # tear it all down
```

Local endpoints:
- API / PostgREST: http://localhost:54321
- Studio (DB admin UI): http://localhost:54323
- Edge functions: http://localhost:54321/functions/v1/<name>

### Deploy to production Supabase

```bash
cd infra
supabase link --project-ref cpqrazrszhcxjvursuci    # one-time
supabase db push                                    # push migrations
supabase functions deploy <fn-name>                 # per function
# or deploy all at once
supabase functions deploy tags galleries client_portal reports media_optimize \
                         media_presign media_finalize media_stamp media_optimize \
                         sync_events breadcrumbs schedule ot pto timecards
```

---

## 5. Test accounts (LOCAL seed only — `password123` for all)

These ship in `infra/supabase/seed.sql` and are only valid after `supabase db reset` on a local stack. They will NOT work on the production site.

| Role | Email | Password | Company |
|---|---|---|---|
| Worker | `worker@test.com` | `password123` | Test Company |
| Worker | `worker2@test.com` | `password123` | Test Company |
| Supervisor | `supervisor@test.com` | `password123` | Test Company |
| Admin | `admin@test.com` | `password123` | Test Company |
| Worker (different tenant — used to verify RLS isolation) | `worker@rival.com` | `password123` | Rival Co |

### Production / staging accounts
Not seeded — sign up through the web app's registration page or have an admin invite you via **Settings → Team**. Never share production credentials in this file.

---

## 6. Troubleshooting the mobile crash path

All three crash vectors from the morning review were fixed in commit `dd378d9` (on `main` now):

| Symptom | Root cause | Fix commit |
|---|---|---|
| App crashes at first launch / after re-install | `FlutterSecureStorage.read` throwing `PlatformException` from `_openConnection` in `local_database.dart` | wrapped in try/catch with transient-key fallback |
| Red "flutter error" screen in production | No custom `ErrorWidget.builder` | friendly error screen added for `kReleaseMode` |
| Async errors silently dropped in production | `PlatformDispatcher.onError` not wired when Sentry is on | set unconditionally at bootstrap, forwards to Sentry |

If the app still crashes, run with logs (`./run.sh 2>&1 | tee /tmp/fieldops.log`) and share the tail of the log — Sentry should also have captured it automatically.

---

## 7. Git + CI workflow

```bash
# Before opening a PR: must all be clean
cd apps/fieldops_mobile && flutter analyze --no-pub && flutter test
cd apps/fieldops_web     && npm run lint && npx tsc --noEmit
cd infra/supabase/functions && deno test tags/index_test.ts galleries/index_test.ts

# Typical push
git add <files>
git commit -m "feat(scope): short summary"
git push origin main       # main auto-deploys to Vercel
```

---

## 8. Quick links

- Repo: https://github.com/seancheick/FieldOpsAi
- Sprint tracker: `/SPRINT_TRACKER.md`
- Lessons learned: `/LESSONS_LEARNED.md`
- Data model: `/DATA_MODEL.md`
- Architecture: `/architecture.md`
