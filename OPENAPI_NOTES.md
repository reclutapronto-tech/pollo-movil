# FieldOps AI — OPENAPI_NOTES.md

---

# 1. Purpose

This document defines:

- Runtime rules for API usage
- Idempotency behavior
- Retry logic
- Authentication enforcement
- Endpoint classification
- Failure handling

This file is REQUIRED for:

- backend engineers
- mobile engineers
- infra engineers

---

# 2. Core Philosophy

## Rule 1 — Events are truth

- APIs NEVER mutate core history
- APIs ONLY append events
- Corrections are separate events

---

## Rule 2 — Mobile is unreliable

Assume:
- requests will fail
- requests will retry
- requests will duplicate

👉 API must be resilient

---

## Rule 3 — Server is authoritative

Never trust:
- client timestamps
- client job_id blindly
- client ownership

Always validate:
- JWT → user → company → assignment

---

# 3. Endpoint Classification

---

## 3.1 Mobile Endpoints

Used by:
- worker app
- foreman app

Endpoints:

- /sync/events
- /jobs/active
- /media/presign
- /media/finalize
- /media/stamp
- /ot/request

Sprint 1 note:
- `/sync/events` currently accepts `clock_events` only.
- photo timeline visibility is established by appending `photo_events` during `/media/finalize`.

---

## 3.2 Web/Admin Endpoints

Used by:
- supervisor dashboard
- admin users

Endpoints:

- /ot/approve
- /reports/compile

---

## 3.3 Internal Endpoints

Used by:
- workers (Temporal)
- system services

Endpoints:

- /media/stamp
- /reports/compile

---

# 4. Authentication Rules

---

## 4.1 JWT Requirements

All endpoints require:

Authorization: Bearer <JWT>

---

## 4.2 Server Validation

On every request:

1. Extract user_id from JWT
2. Load user record
3. Validate:
   - user is active
   - user belongs to company
   - user has required role
   - user is assigned to job (if applicable)

---

## 4.3 Forbidden Conditions

Return 403 if:

- job_id not in user's company
- user not assigned to job
- role insufficient (e.g. worker trying OT approve)

---

# 5. Idempotency Rules (CRITICAL)

---

## 5.1 Required Endpoints

Idempotency-Key REQUIRED for:

- /sync/events
- /media/presign
- /media/finalize
- /media/stamp
- /ot/request
- /ot/approve
- /reports/compile

---

## 5.2 Behavior

If same Idempotency-Key is reused:

👉 return SAME response

Never:
- create duplicate rows
- re-trigger workflows

---

## 5.3 Storage

Store:

- idempotency_key
- endpoint
- request_hash
- response
- created_at

---

## 5.4 TTL

- Default: 24 hours
- Cleanup job runs periodically

---

# 6. Sync System Rules

---

## 6.1 Batch Constraints

- max 50 events per type
- max payload ~1MB

---

## 6.2 Deduplication

Events are deduplicated by:

- event_id (UUID)
- source_event_uuid (if provided)
- a server-owned ingest dedupe registry for cross-partition safety

---

## 6.3 Response Semantics

```json
{
  "status": "success",
  "batch_id": "",
  "accepted": [],
  "duplicates": [],
  "rejected": [],
  "server_time": "",
  "request_id": ""
}
```

---

## 6.4 Rejection Reasons

Examples:

* invalid_job
* invalid_geofence
* unauthorized_user
* invalid_payload

---

## 6.5 Retry Logic (CLIENT)

Client MUST:

* retry rejected events individually
* NOT resend accepted events
* resend duplicates safely

---

# 7. Media Upload Rules

---

## 7.1 Flow

1. /media/presign
2. Upload to storage
3. /media/finalize
4. /media/stamp

Sprint 1 behavior:
- `/media/finalize` appends a `photo_event` so supervisor timelines can render uploaded proof immediately.

---

## 7.2 Constraints

* max size: 15MB
* allowed types: image/jpeg, image/png

---

## 7.3 Security

* only signed URLs
* no public buckets
* validate checksum (if provided)

---

## 7.4 Stamping

* async only
* NEVER block request

---

# 8. Rate Limiting

---

## 8.1 Mobile

* sync: 10 req/min
* media: 20 req/min

---

## 8.2 Admin

* relaxed limits

---

## 8.3 Response Headers

* X-RateLimit-Limit
* X-RateLimit-Remaining
* X-RateLimit-Reset

---

## 8.4 Behavior

Return:

429 Too Many Requests

---

# 9. Error Handling

---

## 9.1 Standard Format

```json
{
  "status": "error",
  "error_code": "INVALID_PAYLOAD",
  "message": "Missing required field",
  "details": [],
  "request_id": ""
}
```

---

## 9.2 Error Codes

* INVALID_PAYLOAD
* UNAUTHORIZED
* FORBIDDEN
* NOT_FOUND
* CONFLICT
* RATE_LIMITED
* INTERNAL_ERROR

---

## 9.3 Retryable Errors

Retry:

* 500
* 503
* 429

Do NOT retry:

* 400
* 403

---

# 10. Versioning

---

## 10.1 Header

X-Client-Version required for mobile

---

## 10.2 Behavior

Backend can:

* block outdated versions
* enforce upgrades

---

# 11. Observability

---

## 11.1 Required Headers

* X-Request-ID

---

## 11.2 Logging

Log:

* request_id
* user_id
* company_id
* endpoint
* latency
* error_code

---

## 11.3 Tracing

All async jobs must include:

* parent request_id

---

# 12. Async Workflows

---

## 12.1 Async Endpoints

* /media/stamp
* /reports/compile

---

## 12.2 Behavior

Return:

202 Accepted

---

## 12.3 Tracking

* worker_job_id returned
* status tracked internally

---

# 13. Security Rules

---

## 13.1 Never trust client

Always validate:

* job ownership
* assignment
* role

---

## 13.2 Sensitive Data

Never expose:

* raw storage paths
* internal IDs unnecessarily

---

## 13.3 Media Access

Only via:

* signed URLs

---

# 14. Breaking Changes Policy

---

## 14.1 Rules

* no breaking changes without version bump
* support older clients temporarily

---

## 14.2 Deprecation

* warn clients before removal
* log usage of old versions

---

# 15. Final Principles

---

## DO

* keep endpoints minimal
* push complexity to workers
* validate everything server-side
* log everything important

---

## DO NOT

* mutate events
* trust client blindly
* block on heavy operations
* expose internal logic

---

# End of File
