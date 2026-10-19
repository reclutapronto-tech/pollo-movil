---
title: FieldOps Data Model
tags:
  - database
  - schema
  - data-model
aliases:
  - Data Model
  - Schema
related:
  - "[[architecture]]"
  - "[[PRD]]"
  - "[[SPRINT_TRACKER]]"
---

# FieldOps AI — DATA_MODEL.md

## 1. Purpose

This document defines the canonical data model for FieldOps AI.

It covers:

- core relational entities
- immutable event tables
- read-model / projection tables
- indexes
- constraints
- tenancy and access-control rules
- storage linkage for proof media
- future-safe fields needed for payroll, compliance, and AI

This schema is designed to support the product’s core principle:

> Every meaningful field action becomes a trusted event.

---

## 2. Design Principles

### 2.1 Append-only operational history
Operational truth lives in immutable events.

Examples:
- clock in
- clock out
- break start / end
- photo submitted
- task completed
- OT requested
- OT approved
- note added
- correction added

No business-critical event should be overwritten in place.

---

### 2.2 Relational core + flexible payload edge
Use relational tables for:
- tenants
- users
- jobs
- tasks
- assignments
- shift reports
- media assets
- approvals

Use `jsonb` only where flexibility is beneficial:
- event payload details
- device metadata
- audit metadata
- AI/result metadata
- structured export snapshots

PostgreSQL documents that `jsonb` can be efficiently indexed with GIN indexes for key and key/value queries.

---

### 2.3 Database-enforced tenancy
All tenant-owned tables carry `company_id`.

Authorization is enforced with Row Level Security at the database layer, not only in app code. Supabase explicitly recommends RLS for application access control, and Auth integrates with RLS.

---

### 2.4 Private proof storage
All photos and generated reports are private by default and served through signed URLs. Supabase Storage is designed to work with RLS, and signed URLs are supported for time-limited access.

---

### 2.5 Future-safe schema
Some fields exist before the feature that fully uses them.

Example:
- `task_classification` on clock events
- wage / classification fields
- correction linkage fields
- verification code fields

That keeps later certified payroll, union rates, and compliance exports from requiring painful backfills.

---

## 3. Naming Conventions

### 3.1 Table naming
Use plural snake_case for tables:

- `companies`
- `users`
- `jobs`
- `clock_events`

### 3.2 Column naming
Use snake_case.

Examples:
- `company_id`
- `occurred_at`
- `created_at`
- `gps_accuracy_m`

### 3.3 ID strategy
Use `uuid` primary keys across all business tables.

Recommended:
- `uuidv7()` where available for time-ordered inserts
- otherwise application-generated UUIDs are acceptable

PostgreSQL documents native support for UUID storage and native generation for UUIDv4 and UUIDv7 in current releases.

---

## 4. Core Entity Map

```text
Company
  ├── Users
  ├── Projects
  │    └── Jobs
  │         ├── Tasks
  │         ├── Assignments
  │         ├── Job Sites
  │         ├── Event Streams
  │         ├── Media Assets
  │         ├── OT Approvals
  │         ├── Shift Reports
  │         └── Exports
  └── Integration Connections
```

---

## 5. Enums

Use Postgres enums for stable, high-signal value sets.

```sql
create type user_role as enum ('admin', 'supervisor', 'foreman', 'worker');

create type project_status as enum ('draft', 'active', 'on_hold', 'completed', 'archived');

create type job_status as enum ('draft', 'active', 'in_progress', 'review', 'completed', 'archived');

create type task_status as enum ('not_started', 'in_progress', 'blocked', 'completed', 'skipped');

create type clock_event_type as enum ('clock_in', 'clock_out', 'break_start', 'break_end');

create type event_type as enum (
  'clock_event',
  'photo_event',
  'task_event',
  'note_event',
  'ot_request_event',
  'ot_approval_event',
  'alert_event',
  'correction_event',
  'shift_report_event',
  'assignment_event',
  'job_status_event'
);

create type media_kind as enum ('raw_photo', 'stamped_photo', 'thumbnail', 'report_pdf', 'video');

create type approval_decision as enum ('pending', 'approved', 'denied');

create type visibility_scope as enum ('internal', 'client');

create type sync_status as enum ('pending', 'uploaded', 'processed', 'failed');

create type alert_status as enum ('open', 'resolved', 'dismissed');

create type device_platform as enum ('android', 'ios', 'web');

create type employment_type as enum ('employee', 'contractor', 'temp');

create type export_kind as enum (
  'timesheet_pdf',
  'timesheet_csv',
  'job_report_pdf',
  'daily_shift_report_pdf',
  'client_report_pdf',
  'payroll_csv',
  'kmz_export'
);
```

---

## 6. Foundation Tables

## 6.1 companies

```sql
create table companies (
  id uuid primary key default uuidv7(),
  name text not null,
  slug text unique not null,
  logo_url text,
  timezone text not null default 'UTC',
  default_locale text not null default 'en',
  status text not null default 'active',
  settings jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
```

Notes:

* `slug` supports branded URLs or white-label subdomains.
* `settings` stores company-level toggles and defaults.

Recommended indexes:

```sql
create unique index idx_companies_slug on companies(slug);
```

---

## 6.2 users

This is the app-level profile table, separate from `auth.users`.

```sql
create table users (
  id uuid primary key references auth.users(id) on delete cascade,
  company_id uuid not null references companies(id) on delete restrict,
  role user_role not null,
  full_name text not null,
  email text,
  phone text,
  employment_type employment_type,
  language_code text not null default 'en',
  timezone text,
  is_active boolean not null default true,
  avatar_url text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
```

Indexes:

```sql
create index idx_users_company_id on users(company_id);
create index idx_users_role on users(role);
create index idx_users_active on users(company_id, is_active);
create index idx_users_phone on users(phone);
```

---

## 6.3 devices

Tracks worker devices for sync, support, and integrity signals.

```sql
create table devices (
  id uuid primary key default uuidv7(),
  company_id uuid not null references companies(id) on delete restrict,
  user_id uuid not null references users(id) on delete cascade,
  device_platform device_platform not null,
  device_identifier text not null,
  app_version text,
  os_version text,
  model text,
  push_token text,
  last_seen_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, device_identifier)
);
```

Indexes:

```sql
create index idx_devices_company_user on devices(company_id, user_id);
create index idx_devices_last_seen on devices(last_seen_at desc);
```

---

## 7. Work Structure Tables

## 7.1 projects

```sql
create table projects (
  id uuid primary key default uuidv7(),
  company_id uuid not null references companies(id) on delete restrict,
  name text not null,
  code text,
  status project_status not null default 'draft',
  start_date date,
  end_date date,
  client_name text,
  client_reference text,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid references users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
```

Indexes:

```sql
create index idx_projects_company_status on projects(company_id, status);
create index idx_projects_company_created_at on projects(company_id, created_at desc);
```

---

## 7.2 jobs

A job is the main field execution unit.

```sql
create table jobs (
  id uuid primary key default uuidv7(),
  company_id uuid not null references companies(id) on delete restrict,
  project_id uuid references projects(id) on delete set null,
  name text not null,
  code text not null,
  status job_status not null default 'draft',
  site_name text,
  address_line_1 text,
  address_line_2 text,
  city text,
  region text,
  postal_code text,
  country_code text,
  site_lat double precision,
  site_lng double precision,
  geofence_radius_m integer not null default 100,
  scheduled_start_at timestamptz,
  scheduled_end_at timestamptz,
  actual_started_at timestamptz,
  actual_completed_at timestamptz,
  client_visible boolean not null default false,
  metadata jsonb not null default '{}'::jsonb,
  created_by uuid references users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (company_id, code)
);
```

Indexes:

```sql
create index idx_jobs_company_status on jobs(company_id, status);
create index idx_jobs_project_id on jobs(project_id);
create index idx_jobs_company_created_at on jobs(company_id, created_at desc);
create index idx_jobs_site_coords on jobs(site_lat, site_lng);
```

---

## 7.3 tasks

```sql
create table tasks (
  id uuid primary key default uuidv7(),
  company_id uuid not null references companies(id) on delete restrict,
  job_id uuid not null references jobs(id) on delete cascade,
  parent_task_id uuid references tasks(id) on delete cascade,
  name text not null,
  description text,
  status task_status not null default 'not_started',
  sort_order integer not null default 0,
  requires_photo boolean not null default false,
  requires_before_after boolean not null default false,
  checkpoint_code text,
  assigned_to uuid references users(id),
  due_at timestamptz,
  completed_at timestamptz,
  completed_by uuid references users(id),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
```

Indexes:

```sql
create index idx_tasks_job_status on tasks(job_id, status);
create index idx_tasks_job_sort on tasks(job_id, sort_order);
create index idx_tasks_assigned_to on tasks(assigned_to);
```

---

## 7.4 assignments

Links users to jobs and, optionally, task scopes.

```sql
create table assignments (
  id uuid primary key default uuidv7(),
  company_id uuid not null references companies(id) on delete restrict,
  job_id uuid not null references jobs(id) on delete cascade,
  user_id uuid not null references users(id) on delete cascade,
  assigned_role user_role not null,
  assigned_by uuid references users(id),
  starts_at timestamptz,
  ends_at timestamptz,
  is_active boolean not null default true,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (job_id, user_id)
);
```

Indexes:

```sql
create index idx_assignments_company_user on assignments(company_id, user_id);
create index idx_assignments_job_active on assignments(job_id, is_active);
```

---

## 8. Media Tables

## 8.1 media_assets

Stores media records and their proof derivatives.

```sql
create table media_assets (
  id uuid primary key default uuidv7(),
  company_id uuid not null references companies(id) on delete restrict,
  job_id uuid references jobs(id) on delete cascade,
  task_id uuid references tasks(id) on delete set null,
  uploaded_by uuid not null references users(id) on delete restrict,
  kind media_kind not null default 'raw_photo',
  bucket_name text not null,
  storage_path text not null,
  mime_type text,
  file_size_bytes bigint,
  width_px integer,
  height_px integer,
  sha256_hash text,
  perceptual_hash text,
  verification_code text,
  original_media_id uuid references media_assets(id) on delete set null,
  stamped_media_id uuid references media_assets(id) on delete set null,
  thumbnail_media_id uuid references media_assets(id) on delete set null,
  sync_status sync_status not null default 'pending',
  captured_at timestamptz,
  gps_lat double precision,
  gps_lng double precision,
  gps_accuracy_m double precision,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  processed_at timestamptz
);
```

Indexes:

```sql
create index idx_media_company_job on media_assets(company_id, job_id);
create index idx_media_uploaded_by on media_assets(uploaded_by);
create index idx_media_hash on media_assets(sha256_hash);
create unique index idx_media_verification_code on media_assets(verification_code)
  where verification_code is not null;
create index idx_media_sync_status on media_assets(sync_status);
```

---

## 9. Event Tables

There are two valid patterns:

1. one universal `events` table with `jsonb` payload
2. specialized event tables per event domain

For FieldOps AI, use **specialized event tables + an optional union view**.
Reason: clearer validation, better indexes, easier payroll/reporting logic.

---

## 9.1 clock_events

```sql
create table clock_events (
  id uuid primary key default uuidv7(),
  company_id uuid not null references companies(id) on delete restrict,
  job_id uuid not null references jobs(id) on delete cascade,
  user_id uuid not null references users(id) on delete restrict,
  device_id uuid references devices(id) on delete set null,
  event_subtype clock_event_type not null,
  occurred_at timestamptz not null,
  received_at timestamptz not null default now(),
  gps_lat double precision,
  gps_lng double precision,
  gps_accuracy_m double precision,
  geofence_passed boolean,
  task_classification text,
  rate_code text,
  shift_label text,
  notes text,
  source_event_uuid uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
```

Indexes:

```sql
create index idx_clock_events_company_job_time on clock_events(company_id, job_id, occurred_at desc);
create index idx_clock_events_company_user_time on clock_events(company_id, user_id, occurred_at desc);
create index idx_clock_events_job_subtype_time on clock_events(job_id, event_subtype, occurred_at desc);
create unique index idx_clock_events_source_uuid on clock_events(source_event_uuid)
  where source_event_uuid is not null;
```

---

## 9.2 photo_events

```sql
create table photo_events (
  id uuid primary key default uuidv7(),
  company_id uuid not null references companies(id) on delete restrict,
  job_id uuid not null references jobs(id) on delete cascade,
  task_id uuid references tasks(id) on delete set null,
  user_id uuid not null references users(id) on delete restrict,
  device_id uuid references devices(id) on delete set null,
  media_asset_id uuid not null references media_assets(id) on delete restrict,
  occurred_at timestamptz not null,
  received_at timestamptz not null default now(),
  photo_role text,
  is_checkpoint boolean not null default false,
  before_after_group_id uuid,
  gps_lat double precision,
  gps_lng double precision,
  gps_accuracy_m double precision,
  source_event_uuid uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
```

Indexes:

```sql
create index idx_photo_events_company_job_time on photo_events(company_id, job_id, occurred_at desc);
create index idx_photo_events_task_id on photo_events(task_id);
create index idx_photo_events_before_after_group on photo_events(before_after_group_id);
create unique index idx_photo_events_source_uuid on photo_events(source_event_uuid)
  where source_event_uuid is not null;
```

---

## 9.3 task_events

```sql
create table task_events (
  id uuid primary key default uuidv7(),
  company_id uuid not null references companies(id) on delete restrict,
  job_id uuid not null references jobs(id) on delete cascade,
  task_id uuid not null references tasks(id) on delete cascade,
  user_id uuid not null references users(id) on delete restrict,
  occurred_at timestamptz not null,
  received_at timestamptz not null default now(),
  from_status task_status,
  to_status task_status,
  note text,
  source_event_uuid uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
```

Indexes:

```sql
create index idx_task_events_task_time on task_events(task_id, occurred_at desc);
create index idx_task_events_job_time on task_events(job_id, occurred_at desc);
create unique index idx_task_events_source_uuid on task_events(source_event_uuid)
  where source_event_uuid is not null;
```

---

## 9.4 note_events

```sql
create table note_events (
  id uuid primary key default uuidv7(),
  company_id uuid not null references companies(id) on delete restrict,
  job_id uuid not null references jobs(id) on delete cascade,
  task_id uuid references tasks(id) on delete set null,
  author_id uuid not null references users(id) on delete restrict,
  visibility visibility_scope not null default 'internal',
  content text not null,
  occurred_at timestamptz not null,
  received_at timestamptz not null default now(),
  source_event_uuid uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
```

Indexes:

```sql
create index idx_note_events_job_time on note_events(job_id, occurred_at desc);
create index idx_note_events_task_id on note_events(task_id);
```

---

## 9.5 ot_requests

Keep OT request and OT decision separate. It preserves the real workflow.

```sql
create table ot_requests (
  id uuid primary key default uuidv7(),
  company_id uuid not null references companies(id) on delete restrict,
  job_id uuid not null references jobs(id) on delete cascade,
  worker_id uuid not null references users(id) on delete restrict,
  request_photo_event_id uuid references photo_events(id) on delete set null,
  requested_at timestamptz not null,
  total_hours_at_request numeric(8,2),
  notes text,
  status approval_decision not null default 'pending',
  source_event_uuid uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
```

Indexes:

```sql
create index idx_ot_requests_job_status on ot_requests(job_id, status);
create index idx_ot_requests_worker_time on ot_requests(worker_id, requested_at desc);
```

---

## 9.6 ot_approval_events

```sql
create table ot_approval_events (
  id uuid primary key default uuidv7(),
  company_id uuid not null references companies(id) on delete restrict,
  job_id uuid not null references jobs(id) on delete cascade,
  ot_request_id uuid not null references ot_requests(id) on delete cascade,
  worker_id uuid not null references users(id) on delete restrict,
  approver_id uuid not null references users(id) on delete restrict,
  decision approval_decision not null,
  reason text,
  occurred_at timestamptz not null,
  received_at timestamptz not null default now(),
  source_event_uuid uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
```

Indexes:

```sql
create index idx_ot_approval_request on ot_approval_events(ot_request_id);
create index idx_ot_approval_job_time on ot_approval_events(job_id, occurred_at desc);
```

---

## 9.7 alert_events

```sql
create table alert_events (
  id uuid primary key default uuidv7(),
  company_id uuid not null references companies(id) on delete restrict,
  job_id uuid references jobs(id) on delete cascade,
  user_id uuid references users(id) on delete set null,
  alert_type text not null,
  severity text not null,
  status alert_status not null default 'open',
  message text not null,
  triggered_at timestamptz not null,
  resolved_at timestamptz,
  resolved_by uuid references users(id),
  source_event_uuid uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
```

Indexes:

```sql
create index idx_alert_events_company_status on alert_events(company_id, status);
create index idx_alert_events_job_status on alert_events(job_id, status);
create index idx_alert_events_triggered_at on alert_events(triggered_at desc);
```

---

## 9.8 correction_events

This is mandatory for an append-only model.

```sql
create table correction_events (
  id uuid primary key default uuidv7(),
  company_id uuid not null references companies(id) on delete restrict,
  job_id uuid references jobs(id) on delete cascade,
  corrected_table text not null,
  corrected_record_id uuid not null,
  corrected_field text,
  old_value jsonb,
  new_value jsonb,
  reason text not null,
  corrected_by uuid not null references users(id) on delete restrict,
  occurred_at timestamptz not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
```

Indexes:

```sql
create index idx_correction_events_record on correction_events(corrected_table, corrected_record_id);
create index idx_correction_events_job_time on correction_events(job_id, occurred_at desc);
```

---

## 9.9 shift_report_events

```sql
create table shift_report_events (
  id uuid primary key default uuidv7(),
  company_id uuid not null references companies(id) on delete restrict,
  job_id uuid not null references jobs(id) on delete cascade,
  foreman_id uuid not null references users(id) on delete restrict,
  report_date date not null,
  headcount integer,
  summary text,
  blocked_items text,
  next_steps text,
  occurred_at timestamptz not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (job_id, report_date, foreman_id)
);
```

Indexes:

```sql
create index idx_shift_report_events_job_date on shift_report_events(job_id, report_date desc);
```

---

## 10. Union Timeline View

Create one queryable unified timeline for the app and reports.

```sql
create view job_timeline as
select
  id,
  company_id,
  job_id,
  user_id,
  'clock_event'::text as event_type,
  occurred_at,
  jsonb_build_object(
    'subtype', event_subtype,
    'gps_lat', gps_lat,
    'gps_lng', gps_lng,
    'gps_accuracy_m', gps_accuracy_m,
    'task_classification', task_classification,
    'notes', notes
  ) as payload
from clock_events

union all

select
  id,
  company_id,
  job_id,
  user_id,
  'photo_event'::text as event_type,
  occurred_at,
  jsonb_build_object(
    'task_id', task_id,
    'media_asset_id', media_asset_id,
    'photo_role', photo_role,
    'is_checkpoint', is_checkpoint,
    'gps_lat', gps_lat,
    'gps_lng', gps_lng
  ) as payload
from photo_events

union all

select
  id,
  company_id,
  job_id,
  user_id,
  'task_event'::text as event_type,
  occurred_at,
  jsonb_build_object(
    'task_id', task_id,
    'from_status', from_status,
    'to_status', to_status,
    'note', note
  ) as payload
from task_events

union all

select
  id,
  company_id,
  job_id,
  author_id as user_id,
  'note_event'::text as event_type,
  occurred_at,
  jsonb_build_object(
    'visibility', visibility,
    'content', content
  ) as payload
from note_events

union all

select
  id,
  company_id,
  job_id,
  approver_id as user_id,
  'ot_approval_event'::text as event_type,
  occurred_at,
  jsonb_build_object(
    'ot_request_id', ot_request_id,
    'worker_id', worker_id,
    'decision', decision,
    'reason', reason
  ) as payload
from ot_approval_events

union all

select
  id,
  company_id,
  job_id,
  corrected_by as user_id,
  'correction_event'::text as event_type,
  occurred_at,
  jsonb_build_object(
    'corrected_table', corrected_table,
    'corrected_record_id', corrected_record_id,
    'corrected_field', corrected_field,
    'reason', reason
  ) as payload
from correction_events;
```

---

## 11. Projection / Read-Model Tables

Event tables are the source of truth.
Projection tables make UI fast.

---

## 11.1 worker_daily_state

```sql
create table worker_daily_state (
  company_id uuid not null,
  user_id uuid not null,
  work_date date not null,
  active_job_id uuid,
  is_clocked_in boolean not null default false,
  last_clock_event_id uuid,
  total_regular_hours numeric(8,2) not null default 0,
  total_ot_hours numeric(8,2) not null default 0,
  photo_count integer not null default 0,
  task_completed_count integer not null default 0,
  updated_at timestamptz not null default default now(),
  primary key (company_id, user_id, work_date)
);
```

---

## 11.2 job_live_summary

```sql
create table job_live_summary (
  company_id uuid not null,
  job_id uuid not null,
  status job_status not null,
  active_worker_count integer not null default 0,
  total_hours_today numeric(8,2) not null default 0,
  photo_count_today integer not null default 0,
  pending_ot_count integer not null default 0,
  open_alert_count integer not null default 0,
  last_photo_event_id uuid,
  last_activity_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (company_id, job_id)
);
```

---

## 11.3 export_artifacts

```sql
create table export_artifacts (
  id uuid primary key default uuidv7(),
  company_id uuid not null references companies(id) on delete restrict,
  job_id uuid references jobs(id) on delete cascade,
  generated_by uuid references users(id),
  export_kind export_kind not null,
  status text not null default 'queued',
  bucket_name text,
  storage_path text,
  file_size_bytes bigint,
  generated_at timestamptz,
  expires_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
```

Indexes:

```sql
create index idx_export_artifacts_company_created on export_artifacts(company_id, created_at desc);
create index idx_export_artifacts_job_kind on export_artifacts(job_id, export_kind);
```

---

## 12. Integration Tables

## 12.1 integration_connections

```sql
create table integration_connections (
  id uuid primary key default uuidv7(),
  company_id uuid not null references companies(id) on delete restrict,
  provider text not null,
  status text not null default 'active',
  external_account_id text,
  encrypted_credentials jsonb,
  settings jsonb not null default '{}'::jsonb,
  created_by uuid references users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (company_id, provider)
);
```

---

## 12.2 integration_sync_runs

```sql
create table integration_sync_runs (
  id uuid primary key default uuidv7(),
  company_id uuid not null references companies(id) on delete restrict,
  connection_id uuid not null references integration_connections(id) on delete cascade,
  run_type text not null,
  status text not null default 'queued',
  started_at timestamptz,
  completed_at timestamptz,
  records_processed integer not null default 0,
  error_message text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
```

Indexes:

```sql
create index idx_integration_sync_runs_connection_created on integration_sync_runs(connection_id, created_at desc);
```

---

## 13. JSONB Usage Rules

Use `jsonb` only when one of these is true:

1. the shape is provider-specific
2. the shape changes frequently
3. the data is auxiliary, not relational core
4. indexing needs are limited and known

When querying `jsonb` frequently, add GIN indexes.

Example:

```sql
create index idx_jobs_metadata_gin on jobs using gin (metadata);
create index idx_clock_events_metadata_gin on clock_events using gin (metadata);
```

---

## 14. Recommended RLS Model

### 14.2 Common helper function

```sql
create or replace function public.current_company_id()
returns uuid
language sql
stable
as $$
  select company_id
  from public.users
  where id = auth.uid()
$$;
```

### 14.3 Example policy

```sql
alter table jobs enable row level security;

create policy "jobs_select_same_company"
on jobs
for select
using (company_id = public.current_company_id());
```

---

## 15. Constraints and Business Rules

### 15.3 Correction model
Never update original event semantics directly. Instead:
1. append correction event
2. update projections/read models
3. preserve source event history

---

## 19. Triggers and Automation

### 19.3 immutable event protection

```sql
create or replace function prevent_event_mutation()
returns trigger
language plpgsql
as $$
begin
  raise exception 'Event tables are append-only';
end;
$$;

create trigger trg_no_update_clock_events
before update or delete on clock_events
for each row execute function prevent_event_mutation();
```

---

# End of File
