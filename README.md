<div align="center">

# FieldOps AI

### The system that proves work happened — automatically.

*Mobile-first field operations platform for construction, electrical, and infrastructure teams.*

[![CI](https://img.shields.io/github/actions/workflow/status/seancheick/FieldOpsAi/backend-regression.yml?label=backend%20tests&style=flat-square)](https://github.com/seancheick/FieldOpsAi/actions)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue?style=flat-square)](LICENSE)
[![Last Commit](https://img.shields.io/github/last-commit/seancheick/FieldOpsAi?style=flat-square)](https://github.com/seancheick/FieldOpsAi/commits/main)

</div>

---

## What is FieldOps AI?

Field companies lose money every day over disputes they can't resolve — unpaid invoices, payroll errors, "nobody told me" excuses. The root cause is always the same: **no proof of what happened in the field.**

FieldOps AI replaces the WhatsApp-photos-and-Excel workflow with a system that captures tamper-proof, GPS-verified, timestamped evidence of every clock-in, task, and photo — automatically.

**Who it's for:**
| Role | What they get |
|------|--------------|
| **Workers** | One-tap clock in/out, photo capture, task completion — under 30 seconds per action |
| **Foremen** | Crew status, shift logs, quick supervision from the job site |
| **Supervisors** | Live map, photo feed, OT approvals, real-time timeline — from any browser |
| **Owners** | Immutable proof of work for billing disputes and compliance |

---

## Features

- **GPS-verified clock in/out** — server timestamp + device GPS locked at the moment of action
- **Server-stamped photos** — proof burns directly into pixels (worker name, GPS, timestamp, job ref, verification hash)
- **Offline-first mobile** — works with no signal, syncs automatically when back online
- **Live supervisor dashboard** — Supabase Realtime powers instant updates, no polling
- **Immutable event store** — append-only Postgres partitions; nothing is ever deleted or edited
- **Multi-tenant RLS** — Row-Level Security enforced at the database layer, not the application layer
- **Role-based access** — worker, foreman, supervisor, and admin roles with scoped visibility
- **OT verification workflow** — overtime requests captured, routed, and approved with full audit trail
- **Shift reports** — foreman logs per job, per day
- **Report generation** — PDF timesheets and job summaries for billing

---

## Tech Stack

**Mobile (Worker & Foreman App)**

![Flutter](https://img.shields.io/badge/Flutter_3.8-02569B?logo=flutter&logoColor=white&style=flat-square)
![Dart](https://img.shields.io/badge/Dart_3.8-0175C2?logo=dart&logoColor=white&style=flat-square)
![Riverpod](https://img.shields.io/badge/Riverpod-blue?style=flat-square)
![Drift](https://img.shields.io/badge/Drift_SQLite-orange?style=flat-square)
![Sentry](https://img.shields.io/badge/Sentry-362D59?logo=sentry&logoColor=white&style=flat-square)

**Web (Supervisor Dashboard)**

![Next.js](https://img.shields.io/badge/Next.js_15-000?logo=nextdotjs&logoColor=white&style=flat-square)
![React](https://img.shields.io/badge/React_19-61DAFB?logo=react&logoColor=black&style=flat-square)
![TypeScript](https://img.shields.io/badge/TypeScript_5-3178C6?logo=typescript&logoColor=white&style=flat-square)
![Tailwind](https://img.shields.io/badge/Tailwind_4-06B6D4?logo=tailwindcss&logoColor=white&style=flat-square)
![PostHog](https://img.shields.io/badge/PostHog-FF6F00?logo=posthog&logoColor=white&style=flat-square)

**Backend & Infrastructure**

![Supabase](https://img.shields.io/badge/Supabase-3ECF8E?logo=supabase&logoColor=white&style=flat-square)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL_17-4169E1?logo=postgresql&logoColor=white&style=flat-square)
![Deno](https://img.shields.io/badge/Edge_Functions_(Deno)-000?logo=deno&logoColor=white&style=flat-square)
![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-2088FF?logo=githubactions&logoColor=white&style=flat-square)

---

## Repository Structure

This is a monorepo. Each app lives in `apps/`, infrastructure in `infra/`, and the Python regression suite in `execution/`.

```
FieldOpsAi/
├── apps/
│   ├── fieldops_mobile/       # Flutter app (worker + foreman)
│   │   ├── lib/
│   │   │   ├── app/           # Bootstrap, theme
│   │   │   ├── core/          # Config, local DB, sync engine, notifications
│   │   │   └── features/      # Clean architecture feature modules
│   │   │       ├── auth/      # Login + invite activation
│   │   │       ├── clock/     # Clock in/out with GPS
│   │   │       ├── camera/    # Proof photo capture
│   │   │       ├── tasks/     # Task list + completion
│   │   │       ├── foreman/   # Crew overview screen
│   │   │       └── ...        # Expenses, OT, history, timecards
│   │   └── pubspec.yaml
│   │
│   └── fieldops_web/          # Next.js supervisor dashboard
│       └── src/
│           ├── app/
│           │   ├── map/       # Live worker map (Mapbox)
│           │   ├── timeline/  # Full job event history
│           │   ├── photos/    # Stamped photo gallery
│           │   ├── overtime/  # OT approval queue
│           │   ├── reports/   # PDF generation + export
│           │   └── ...        # Workers, schedule, settings
│           ├── components/
│           └── lib/           # Supabase client, auth, types
│
├── infra/
│   └── supabase/
│       ├── migrations/        # 6 ordered SQL migrations
│       ├── functions/         # 14 Deno edge functions
│       │   ├── _shared/       # Shared CORS, auth, response utilities
│       │   ├── sync_events/   # Batch offline sync endpoint
│       │   ├── media_presign/ # Signed upload URL generation
│       │   ├── media_stamp/   # Server-side proof burning
│       │   ├── media_finalize/# Link asset to photo event
│       │   └── ...            # jobs_active, ot, reports, tasks, expenses
│       ├── config.toml
│       └── seed.sql
│
├── execution/                 # Python backend regression suite
│   ├── run_backend_regression_suite.py
│   ├── test_sprint_1.py
│   ├── test_rls_validation.py
│   └── requirements-regression.txt
│
├── .github/workflows/         # CI — runs backend tests on every PR
├── PRD.md                     # Product requirements
├── ROADMAP.md                 # Sprint roadmap (Step 0–10)
├── architecture.md            # Full architecture decisions
├── DATA_MODEL.md              # Database schema reference
└── OPENAPI.yaml               # API contract
```

---

## Getting Started

### Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| [Supabase CLI](https://supabase.com/docs/guides/cli) | ≥ 2.20 | `brew install supabase/tap/supabase` |
| [Flutter SDK](https://docs.flutter.dev/get-started/install) | ≥ 3.8 | flutter.dev |
| [Node.js](https://nodejs.org) | ≥ 20 | nodejs.org |
| [Python](https://www.python.org) | ≥ 3.13 | python.org |
| [Docker](https://docs.docker.com/get-docker/) | latest | Required by Supabase local |

---

### 1. Clone & configure

```bash
git clone https://github.com/seancheick/FieldOpsAi.git
cd FieldOpsAi

# Copy env template and fill in your Supabase project keys
cp .env.example .env
```

---

### 2. Start the backend (Supabase local)

```bash
cd infra
supabase start

# Supabase will output your local API URL + anon key — copy them for the next steps
supabase status
```

Seed test data:

```bash
cd ..
pip install -r execution/requirements-regression.txt
python3 execution/seed_backend_test_data.py
```

---

### 3. Run the mobile app (Flutter)

```bash
cd apps/fieldops_mobile

# iOS simulator
flutter run \
  --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=SUPABASE_ANON_KEY=<your-local-anon-key>

# Physical iPhone (replace IP with your Mac's LAN IP: `ipconfig getifaddr en0`)
flutter run \
  --dart-define=SUPABASE_URL=http://192.168.x.x:54321 \
  --dart-define=SUPABASE_ANON_KEY=<your-local-anon-key>

# Android emulator (10.0.2.2 maps to localhost)
flutter run \
  --dart-define=SUPABASE_URL=http://10.0.2.2:54321 \
  --dart-define=SUPABASE_ANON_KEY=<your-local-anon-key>
```

---

### 4. Run the web dashboard (Next.js)

```bash
cd apps/fieldops_web
cp .env.local.example .env.local   # fill in NEXT_PUBLIC_SUPABASE_URL + anon key
npm install
npm run dev
# → http://localhost:3000
```

### 4.5 Wire Vercel MCP into Codex

The repo-level `.mcp.json` now includes the official Vercel MCP endpoint for tools that read project MCP config.

For Codex itself, register Vercel once in your local Codex config:

```bash
codex mcp add vercel --url https://mcp.vercel.com
codex mcp list
```

On first use, Codex will open the Vercel OAuth flow so the MCP server can read your projects, deployments, logs, domains, and env metadata.

If you want Codex to prefer that server in this repo, add this guidance to your local AGENTS instructions:

```md
Always use the Vercel MCP server when you need live Vercel project, deployment, domain, environment variable, or log data.
```

---

### 5. Run backend tests

```bash
python3 execution/run_backend_regression_suite.py
```

The CI pipeline runs this automatically on every PR that touches `execution/`, `infra/`, or the OpenAPI spec.

---

## Architecture

FieldOps AI is built around four core principles:

**1. Event sourcing** — every action (clock-in, photo, task) is written to an immutable, append-only Postgres event table. Nothing is ever updated or deleted. This is the source of truth for billing, compliance, and disputes.

**2. Offline-first** — the Flutter app writes to a local SQLite (Drift) queue first. A background sync engine uploads batches to Supabase when connectivity is available. Workers never see a loading spinner for their core actions.

**3. Proof-by-default** — photos are not stored as-is. An Edge Function downloads the raw image, composites a visible proof stamp (GPS, timestamp, worker ID, verification hash) directly into the pixels, and stores that as the canonical version. The proof survives screenshots and forwards.

**4. Multi-tenant RLS** — every table has a `company_id` column. Postgres Row-Level Security policies ensure tenants can only ever access their own data, enforced at the database level regardless of what the application code does.

```
Worker/Foreman App (Flutter)
        │  offline queue (Drift SQLite)
        │  sync when online
        ▼
Supabase Edge Functions (Deno)
   sync_events → clock/photo/task events written to partitioned Postgres
   media_presign → signed upload URL
   media_finalize → link asset to event
        │
        ▼
Supabase Postgres (PostgreSQL 17)
   clock_events / photo_events / task_events (append-only, partitioned)
   companies / users / jobs / tasks / assignments (core tables)
   RLS policies enforce tenant isolation on every table
        │
        ▼                         ▼
media_stamp Edge Function    Supabase Realtime
   burns proof into pixels   pushes postgres_changes
   stores canonical photo    to supervisor dashboard
        │                         │
        ▼                         ▼
Supabase Storage           Next.js Dashboard
   private buckets          live updates, no polling
   signed URLs only         map, timeline, photos, OT
```

---

## Roadmap

| Sprint | What ships | Status |
|--------|-----------|--------|
| 1 | Core backend endpoints, regression suite, CI gate | ✅ Done |
| 2 | Worker loop (clock, camera, offline sync), supervisor dashboard, photo stamp pipeline | ✅ Done |
| 3 | Structured task checklists with photo enforcement | ✅ Done |
| 4 | Overtime request + supervisor approval workflow | ✅ Done |
| 5 | Reporting engine — PDF job reports, timesheet CSV export | ✅ Done |
| 6 | Competitive parity: worker hours dashboard, receipt capture, time card signatures, cost codes, schedule, Spanish i18n, state-specific OT rules | 🔄 Next |
| 7 | Field intelligence: crew clock-in, GPS breadcrumb trail, equipment tracking, safety sign-off, manual time entry | ⬜ Backlog |
| 8 | Billing + integrations: Stripe, QuickBooks, Zapier/webhooks, client portal | ⬜ Backlog |
| 9 | AI layer: daily report writing, anomaly detection, voice-to-log | ⬜ Backlog |
| 10 | Scale + platform: marketplace, advanced AI, enterprise SSO | ⬜ Backlog |

---

## Environment Variables

```bash
# Root .env (backend / tests)
SUPABASE_URL="https://your-project-ref.supabase.co"
SUPABASE_ANON_KEY="your-anon-key"
SUPABASE_SERVICE_ROLE_KEY="your-service-role-key"

# Web dashboard (.env.local)
NEXT_PUBLIC_SUPABASE_URL="..."
NEXT_PUBLIC_SUPABASE_ANON_KEY="..."
NEXT_PUBLIC_SENTRY_DSN="..."          # optional
NEXT_PUBLIC_POSTHOG_KEY="..."         # optional

# Mobile (dart-defines at build time)
SUPABASE_URL="..."
SUPABASE_ANON_KEY="..."
SENTRY_DSN="..."                      # optional
```

---

## License

MIT © 2026 [Sean Cheick Baradji](https://github.com/seancheick)
