---
title: FieldOps Architecture
tags:
  - architecture
  - tech-stack
  - system-design
aliases:
  - Architecture
related:
  - "[[PRD]]"
  - "[[ROADMAP]]"
  - "[[DATA_MODEL]]"
  - "[[SPRINT_TRACKER]]"
---

# FieldOps AI — Architecture

## 1. Purpose

FieldOps AI is a mobile-first field operations platform for construction, electrical, infrastructure, and service teams.

Its core architectural goal is simple:

**capture field reality once, store it as trusted events, and turn those events into proof, payroll, operations, and AI insight.**

This architecture is designed around the product’s actual requirements:

* GPS-verified clock events
* in-app photo capture with server-side stamped proof
* append-only timelines
* offline-first operation
* multi-company isolation
* real-time supervisor views
* scalable reporting and later AI features built on structured event data. 

---

## 2. Architecture Principles

### 2.1 Event-first, not record-first

The platform stores work as immutable events, not mutable “current state” rows.

Examples:

* `clock_in`
* `clock_out`
* `photo_uploaded`
* `task_completed`
* `ot_requested`
* `ot_approved`
* `note_added`
* `correction_added`

Why:

* preserves auditability
* makes dispute resolution stronger
* simplifies timeline generation
* creates high-quality inputs for reporting and AI. 

### 2.2 Offline-first by design

The worker app must continue to work with weak or no connectivity. Flutter’s official architecture guidance explicitly supports offline-first patterns, and Flutter’s SQL persistence guidance fits a local event queue well.

### 2.3 Multi-tenant and database-enforced security

Tenant isolation must be enforced at the database layer, not just in app code. Supabase Auth integrates with Postgres Row Level Security, and Supabase explicitly recommends always applying RLS. 

### 2.4 Async-heavy backend

Photo stamping, PDF generation, sync reconciliation, AI summarization, and downstream integrations should run as queued jobs, not inline request/response flows.

### 2.5 Mobile and web are different products

Workers need a low-friction mobile app. Supervisors/admins need a dense desktop web console. Do not force both audiences into one UI model. This recommendation follows from your own product requirements: glove-friendly worker UX, low-end Android support, real-time maps, dashboards, scheduling, and reporting. 

---

## 3. Recommended Tech Stack

## 3.1 Client Applications

### Worker / Foreman mobile app

* **Flutter**
* **Dart**
* **Riverpod** for state management
* **go_router** for navigation
* **Drift (SQLite)** for local offline database
* **camera** plugin for in-app capture
* **background sync service** for upload queue
* **FCM** for push notifications

Why Flutter:

* one codebase for Android and iOS
* strong fit for camera-heavy, form-light workflows
* official offline-first guidance exists
* good performance on lower-end devices when kept disciplined.

### Admin / Supervisor web app

* **Next.js**
* **TypeScript**
* **React**
* **Tailwind CSS**
* **TanStack Query**
* **Mapbox GL JS** for mapping
* **shadcn/ui** for fast, consistent desktop UI

Why not Flutter Web for admin?

* the worker app should stay Flutter
* the admin dashboard will benefit more from a mature React/Next desktop ecosystem, stronger tables/forms/charting ergonomics, and easier hiring

### Shared design/system choices

* Type-safe API contracts
* role-based layouts
* localization from day one
* dark/light support

---

## 3.2 Backend Platform

### Core backend

* **Supabase**

  * Postgres
  * Auth
  * Storage
  * Realtime
  * Edge Functions

Supabase gives you Postgres, Auth, Realtime, instant APIs, Edge Functions, and Storage with RLS integration, which fits this product unusually well. Auth integrates with RLS; Storage is integrated with Postgres and RLS policies; Realtime supports low-latency broadcast and Postgres change subscriptions.

### Background jobs / workers

* **Temporal** for workflow orchestration
* **Node.js + TypeScript** workers for business logic
* **Python** workers for image/PDF/AI utility tasks where libraries are stronger

Why Temporal:

* durable retries
* visibility into long-running workflows
* strong fit for photo processing, report generation, export jobs, and integration syncs

### API layer

* **Supabase PostgREST** for straightforward CRUD
* **Edge Functions** for lightweight secure endpoints
* **Dedicated backend service** for complex orchestration and privileged operations

Important:

* Supabase secret keys and privileged backend components bypass RLS, so only backend services and workers should hold them. Publishable keys are safe for clients.

---

## 3.3 Storage and Media

### Structured data

* **PostgreSQL (Supabase)**

### Media

* **Supabase Storage** initially
* optional move to **S3 + CloudFront** later if storage economics or media throughput justify it

Why:

* simple early-stage stack
* RLS-aware access model
* signed URL flows
* good enough for MVP through early scale. Supabase Storage is integrated with Postgres and RLS access policies.

### Image pipeline

* upload raw image
* verify metadata
* hash original
* stamp server-side
* store derivative versions:

  * original
  * stamped canonical
  * thumbnail
  * report-sized export

### File access

* private buckets only
* signed expiring URLs
* no raw public storage paths

---

## 3.4 Mapping and Location

### Maps

* **Mapbox**

  * Flutter SDK on mobile
  * GL JS on web

Why Mapbox:

* official Flutter SDK
* highly customizable
* better design flexibility for branded operational maps
* good fit for future GIS/KMZ direction from your roadmap. Mapbox’s Flutter SDK is actively documented for Flutter and supports custom maps from a single codebase.

### Location model

* capture GPS at:

  * clock in/out
  * break start/end
  * photo capture
  * OT photo
* later:

  * optional breadcrumb sampling during active shifts

---

## 3.5 Notifications

* **Firebase Cloud Messaging**

Why:

* reliable cross-platform push
* Flutter support is first-class in official docs
* fits OT approval alerts, sync status, shift reminders, and supervisor notifications.

---

## 3.6 AI Layer

### AI orchestration

* **Node.js/TypeScript AI service**
* provider abstraction supporting:

  * Gemini (Primary Free-Tier)
  * Groq (Fallback)
  * OpenRouter (Fallback)
  * future self-hosted model endpoints

### AI use cases

* daily report drafting
* anomaly explanations
* voice-to-log transcription
* schedule/risk summaries
* search over job history and reports

### Rules

* AI never writes authoritative system-of-record events
* AI only reads structured data and emits drafts, explanations, or classifications
* all final business decisions remain deterministic or human-approved

This matches your plan: AI is Phase 3 and should be built on real operational event data, not vague free-form generation. 

---

## 4. High-Level System Diagram

```text
Mobile App (Flutter) ─────┐
                          ├── API / Auth / Storage / Realtime (Supabase)
Web Admin (Next.js) ──────┘                 │
                                            │
                                   PostgreSQL Event Store
                                            │
                    ┌───────────────────────┼───────────────────────┐
                    │                       │                       │
             Job Workers              Media Pipeline          Notification Service
          (Temporal + TS/Python)   (hash/stamp/thumb/PDF)        (FCM)
                    │                       │                       │
                    └────────────── Integrations / AI ─────────────┘
```

---

## 5. Repository Strategy

## 5.1 Recommended repo layout

```text
fieldops/
  apps/
    worker_mobile/        # Flutter mobile app
    admin_web/            # Next.js admin + supervisor dashboard
  services/
    orchestration_api/    # TS backend for privileged workflows
    workers/              # Temporal workers
    media_service/        # image stamping, thumbnails, pdf rendering
    ai_service/           # summaries, anomaly explanation, transcription orchestration
    integration_service/  # QuickBooks, Trayd, Zapier, etc.
  packages/
    shared-types/         # TS types / schemas
    design-tokens/        # shared colors/icons/branding
    event-schemas/        # canonical event definitions
  infra/
    supabase/
      migrations/
      seeds/
      policies/
      functions/
    terraform/
    docker/
  docs/
    PRD.md
    ARCHITECTURE.md
    API.md
    DATA_MODEL.md
```

### Why monorepo

* easier shared contracts
* easier infra/version coordination
* better for a product with multiple apps and worker services

---

## 6. Core Domain Model

## 6.1 Tenant hierarchy

```text
Company
  └── Project
       └── Job
            ├── Task
            ├── Assignment
            ├── Timeline
            ├── Shift Report
            ├── Photos
            └── Exports
```

## 6.2 User model

* Company
* User
* Role
* Worker profile
* Supervisor scope
* Device registration
* Invite token
* Locale / timezone

## 6.3 Core entities

* `companies`
* `users`
* `memberships`
* `projects`
* `jobs`
* `tasks`
* `assignments`
* `job_sites`
* `devices`
* `media_assets`
* `exports`
* `integration_connections`

## 6.4 Event store tables

* `clock_events`
* `photo_events`
* `task_events`
* `note_events`
* `ot_approval_events`
* `alert_events`
* `correction_events`
* `shift_report_events`

This follows your append-only audit design and the event types already defined in your plan. 

---

## 7. Event-Sourced Design

## 7.1 Canonical event shape

```json
{
  "event_id": "uuid",
  "tenant_id": "uuid",
  "job_id": "uuid",
  "actor_user_id": "uuid",
  "event_type": "clock_in",
  "occurred_at_client": "2026-04-03T14:00:00Z",
  "received_at_server": "2026-04-03T14:00:03Z",
  "device_id": "string",
  "gps": {
    "lat": 0,
    "lng": 0,
    "accuracy_m": 12
  },
  "payload": {},
  "version": 1
}
```

## 7.2 Rules

* events are append-only
* corrections create new events
* canonical timeline is derived, not manually edited
* server timestamp always exists
* client timestamp is retained for offline ordering visibility

## 7.3 Derived read models

Build separate read models for:

* worker daily state
* active job dashboard
* OT queue
* job progress summary
* payroll export rows
* client portal view
* AI summary input packs

---

## 8. Offline-First Mobile Architecture

Flutter’s official architecture guidance explicitly covers offline-first patterns, and its SQL persistence guidance supports a local SQL store for complex app data.

## 8.1 Local storage

Use **Drift on SQLite** for:

* local assignments
* pending events
* unsynced media references
* cached job/task data
* sync metadata

## 8.2 Sync model

* every action writes locally first
* UI updates immediately from local DB
* sync engine uploads when network is available
* server acknowledges and returns canonical IDs/timestamps
* read models reconcile after sync

## 8.3 Conflict strategy

Because the system is append-only, conflicts are minimized:

* no destructive overwrites
* corrections are explicit
* upload order is preserved
* duplicate prevention uses client UUIDs and hashes

## 8.4 Media sync

* capture to local temp storage
* create pending media record
* background upload raw
* receive stamped canonical asset references
* update local event with server asset IDs

This matches your requirement for full offline capture, queued sync, strict chronological upload, and append-only conflict handling. 

---

## 9. Security Architecture

## 9.1 Auth

* Supabase Auth for user identity
* invite-based account activation
* JWT access tokens
* refresh rotation
* optional SSO at enterprise tier

Supabase Auth integrates with RLS, making it a clean fit for tenant-scoped authorization.

## 9.2 Authorization

* Postgres RLS as primary enforcement
* every tenant-owned table has `company_id`
* policies restrict by membership and role
* supervisor scope policies filter by assigned jobs/crews

## 9.3 Media security

* private storage buckets
* signed URLs
* no client access to privileged storage operations

## 9.4 Backend privilege boundary

* web/mobile clients use publishable keys
* workers/backend services use secret keys only in server-side contexts
* all privileged operations flow through backend services because secret keys bypass RLS.

---

## 10. Media and Proof Pipeline

## 10.1 Photo proof flow

```text
Capture photo in app
→ save locally
→ upload raw image
→ verify EXIF / request metadata
→ compute hash
→ stamp server-side
→ store canonical stamped image
→ create PhotoEvent
→ update timeline + feed + reporting assets
```

## 10.2 Canonical proof rules

* no gallery uploads for proof photos
* only in-app capture for proof-grade assets
* canonical stamped image is the source of truth
* every export uses the stamped canonical image
* every media item has:

  * original hash
  * stamped derivative
  * thumbnail
  * verification code

This directly reflects your proof-layer requirements. 

---

## 11. Real-Time Architecture

Supabase Realtime supports low-latency messaging, presence, and Postgres change subscriptions.

## 11.1 Use Realtime for

* active job feed refresh
* OT approval queue
* worker clock state changes
* dashboard counters
* supervisor alerts

## 11.2 Do not use Realtime for

* large historical queries
* report generation
* analytics
* guaranteed business workflows

Use Realtime for UI freshness, not as the system-of-record orchestration engine.

---

## 12. Background Jobs and Workflow Orchestration

## 12.1 Use queued jobs for

* image stamping
* thumbnail generation
* PDF generation
* payroll exports
* scheduled summaries
* integration sync
* anomaly scans
* nightly derived model refreshes

## 12.2 Worker split

### TypeScript workers

* orchestration
* business workflows
* integration logic

### Python workers

* image processing
* document rendering support
* data-heavy analytics utilities

## 12.3 Workflow examples

* `generate_job_completion_report`
* `process_uploaded_photo`
* `reconcile_offline_batch`
* `sync_quickbooks_timesheet`
* `create_daily_shift_digest`

---

## 13. Integration Architecture

Your roadmap already points toward QuickBooks, Zapier, Trayd, GIS/KMZ export, and white-label expansion. 

## 13.1 Integration pattern

Use a dedicated **integration service** with:

* OAuth/token storage
* outbound webhooks
* retry logic
* dead-letter queue
* idempotency keys

## 13.2 Phase order

### Phase 1

* CSV/PDF exports only

### Phase 2

* QuickBooks
* Zapier webhook layer
* client portal notifications

### Phase 3+

* Trayd
* GIS/KMZ export
* payroll/compliance connectors
* ERP/accounting partners

## 13.3 MCP layer

If you keep developing Antigravity in parallel, put external tools behind an MCP-style adapter layer so the AI/agent side never hardcodes vendor-specific integration logic.

---

## 14. Reporting Architecture

## 14.1 Report types

* worker timesheet
* daily shift report
* job completion report
* client-ready proof report
* payroll export
* audit export

## 14.2 Rendering model

* assemble report data from read models
* fetch canonical stamped assets
* generate PDF server-side
* store immutable export artifact
* surface download/share link

## 14.3 Recommendation

Use **headless HTML-to-PDF rendering** for branded reports rather than hand-built PDF drawing everywhere. It gives you faster iteration and cleaner design control.

---

## 15. AI Architecture

## 15.1 Data contract

AI never reads raw app chaos. It reads structured packs such as:

```json
{
  "job_summary": {},
  "timeline_events": [],
  "crew_hours": [],
  "task_status": [],
  "alerts": [],
  "photo_captions": []
}
```

## 15.2 AI services

* report draft generator
* anomaly explanation engine
* voice-to-log pipeline
* semantic search over jobs/reports
* benchmark summarizer

## 15.3 Guardrails

* AI cannot approve OT
* AI cannot alter timesheets
* AI cannot mutate event history
* AI can only produce drafts, labels, summaries, explanations, and search results

This keeps the AI layer consistent with your plan’s "structured operational data first" principle. 

---

## 16. Observability and Operations

## 16.1 Recommended stack

* **Sentry** for app and backend error monitoring
* **OpenTelemetry** for tracing
* **PostHog** for product analytics
* **Grafana / managed logs** for infra observability

## 16.2 Critical metrics

* clock-in success rate
* photo upload success rate
* offline queue depth
* median sync latency
* OT approval response time
* report generation latency
* failed worker actions by device model
* RLS policy denials
* storage growth by tenant

## 16.3 Operational dashboards

* mobile crash dashboard
* sync health dashboard
* media processing queue dashboard
* tenant activity dashboard
* integration failure dashboard

---

## 17. CI/CD and Environments

## 17.1 Environments

* `local`
* `dev`
* `staging`
* `prod`

## 17.2 Deployment

### Mobile

* Flutter CI
* internal builds for pilot
* staged rollout for production

### Web

* Vercel for admin web

### Backend/services

* Render / Fly.io / Railway for early stage
* move to AWS ECS/Fargate or Kubernetes only when justified

### Database

* Supabase hosted Postgres initially
* scheduled backups
* migration-first schema discipline

## 17.3 Release rules

* all DB changes via migrations
* backward-compatible API changes only
* feature flags for unfinished supervisor/admin features
* mobile sync protocol versioning from day one

---

## 18. Scaling Plan

## 18.1 MVP to early traction

Stay on:

* Flutter mobile
* Next.js web
* Supabase
* Temporal
* FCM
* Mapbox
* Supabase Storage

This is enough for launch and early growth if the event model and async workers are designed correctly.

## 18.2 Scale triggers

Re-architecture only when one of these becomes real:

* storage/media cost spikes
* realtime fanout becomes expensive
* long-running worker throughput becomes constrained
* tenant-specific compliance requires dedicated environments
* enterprise SSO/compliance deals demand stronger isolation

## 18.3 Likely future upgrades

* S3 + CloudFront for media
* dedicated Postgres read replicas/analytics warehouse
* Kafka or event bus for very high event throughput
* per-region deployments
* stronger document pipeline
* enterprise identity provider integration

---

## 19. Final Recommended Stack Summary

### Mobile

* Flutter
* Dart
* Riverpod
* Drift/SQLite
* FCM

### Web

* Next.js
* React
* TypeScript
* Tailwind
* TanStack Query

### Backend

* Supabase Postgres
* Supabase Auth
* Supabase Realtime
* Supabase Storage
* Supabase Edge Functions
* Node.js/TypeScript service layer
* Temporal workers
* Python utility workers

### Maps / location

* Mapbox

### AI

* provider-abstracted AI service
* Gemini/Groq/OpenRouter compatible
* structured-data-only workflows

### Observability

* Sentry
* OpenTelemetry
* PostHog

### Infra

* monorepo
* migration-driven database
* private media
* signed URLs
* append-only event store
* async-heavy processing
