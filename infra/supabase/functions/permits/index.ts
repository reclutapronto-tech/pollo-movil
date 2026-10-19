import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.4"
import {
  applyRateLimit,
  corsHeaders,
  errorResponse,
  jsonResponse,
  logRequestError,
  logRequestResult,
  logRequestStart,
  lookupIdempotency,
  makeRequestId,
  sha256Hex,
  storeIdempotency,
} from "../_shared/api.ts"
import { isSupervisorOrAbove } from "../_shared/roles.ts"

const ENDPOINT = "permits"
const PERMITS_RATE_LIMIT = 30
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const PERMIT_TYPES = ["hv_electrical","confined_space","hot_work","working_at_heights","lockout_tagout","excavation","general","other"] as const
type PermitType = (typeof PERMIT_TYPES)[number]
const PERMIT_STATUSES = ["draft","issued","active","expired","revoked"] as const
type PermitStatus = (typeof PERMIT_STATUSES)[number]
const PERMIT_NUMBER_MAX = 64

const PERMIT_COLUMNS =
  "id, company_id, job_id, permit_number, permit_type, description, status, " +
  "issued_by, issued_at, expires_at, revoked_by, revoked_at, revocation_reason, " +
  "pdf_path, created_by, created_at, updated_at"

const isUuid = (v: unknown): v is string => typeof v === "string" && UUID_RE.test(v)
const isIsoOrNull = (v: unknown) => v === null || (typeof v === "string" && Number.isFinite(Date.parse(v)))
const isPermitNumber = (v: unknown): v is string =>
  typeof v === "string" && v.trim().length > 0 && v.length <= PERMIT_NUMBER_MAX

// Server-side projection of "active": rows stored as 'issued' but past their
// expires_at report as 'expired' in the response. We never write the projection
// back — a future sweeper job owns that mutation.
// deno-lint-ignore no-explicit-any
function projectStatus(row: any, nowMs: number): PermitStatus {
  if (row?.status === "issued" && row?.expires_at) {
    const ms = Date.parse(row.expires_at)
    if (Number.isFinite(ms) && ms <= nowMs) return "expired"
  }
  return row?.status as PermitStatus
}

// Flatten joined names and apply projected status. names/jobs maps come from
// batched lookups — no N+1.
// deno-lint-ignore no-explicit-any
function shapeRow(row: any, names: Map<string, string>, jobs: Map<string, { name: string | null; code: string | null }>, nowMs: number) {
  return {
    ...row,
    status: projectStatus(row, nowMs),
    issuer_name: row?.issued_by ? (names.get(row.issued_by) ?? null) : null,
    revoker_name: row?.revoked_by ? (names.get(row.revoked_by) ?? null) : null,
    job_name: row?.job_id ? (jobs.get(row.job_id)?.name ?? null) : null,
    job_code: row?.job_id ? (jobs.get(row.job_id)?.code ?? null) : null,
  }
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders(req) })

  const requestId = makeRequestId(req)
  logRequestStart(ENDPOINT, requestId, req)

  try {
    const authHeader = req.headers.get("Authorization")
    if (!authHeader) return errorResponse(requestId, 401, "UNAUTHORIZED", "Missing Authorization header")

    const supabaseUrl = Deno.env.get("SUPABASE_URL") || ""
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || ""
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") || ""
    const supabase = createClient(supabaseUrl, supabaseAnonKey, { global: { headers: { Authorization: authHeader } } })
    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey)

    const { data: { user }, error: authError } = await supabase.auth.getUser()
    if (authError || !user) return errorResponse(requestId, 401, "UNAUTHORIZED", "Invalid auth token")

    const { data: userRecord } = await supabase
      .from("users")
      .select("id, company_id, role, is_active, full_name")
      .eq("id", user.id)
      .single()
    if (!userRecord?.is_active) return errorResponse(requestId, 403, "FORBIDDEN", "User is inactive")

    const rateLimit = await applyRateLimit(supabaseAdmin, user.id, ENDPOINT, requestId, PERMITS_RATE_LIMIT, 60)
    if (rateLimit.limited) {
      logRequestResult(ENDPOINT, requestId, 429, { reason: "rate_limited" })
      return errorResponse(requestId, 429, "RATE_LIMITED", "Too many requests", [], rateLimit.headers)
    }

    if (req.method !== "POST") return errorResponse(requestId, 405, "METHOD_NOT_ALLOWED", "Use POST")

    const payload = await req.json()
    const { action } = payload

    const loadPermit = (permit_id: string) =>
      supabaseAdmin.from("work_permits").select(PERMIT_COLUMNS)
        .eq("id", permit_id).eq("company_id", userRecord.company_id).maybeSingle()

    // Returns a Response (replay/short-circuit) or proceed metadata.
    async function checkIdempotency(): Promise<
      | { kind: "response"; response: Response }
      | { kind: "proceed"; idempotencyKey: string; requestHash: string }
    > {
      const idempotencyKey = req.headers.get("Idempotency-Key")
      if (!idempotencyKey) return { kind: "response", response: errorResponse(requestId, 400, "INVALID_PAYLOAD", "Idempotency-Key header is required") }
      const requestHash = await sha256Hex(JSON.stringify(payload))
      const replay = await lookupIdempotency(supabaseAdmin, user.id, ENDPOINT, idempotencyKey, requestHash)
      if (replay.replay) {
        if (replay.conflict) return { kind: "response", response: errorResponse(replay.requestId, 409, "CONFLICT", "Idempotency key reused with different payload") }
        return { kind: "response", response: jsonResponse(replay.body, replay.status, replay.requestId) }
      }
      return { kind: "proceed", idempotencyKey, requestHash }
    }

    // ── Action: list ────────────────────────────────────────
    if (action === "list") {
      const { job_id, status, limit } = payload
      const supervisorPlus = isSupervisorOrAbove(userRecord.role)

      if (job_id !== undefined && !isUuid(job_id)) return errorResponse(requestId, 400, "INVALID_PAYLOAD", "job_id must be a uuid")
      if (status !== undefined && !PERMIT_STATUSES.includes(status)) return errorResponse(requestId, 400, "INVALID_PAYLOAD", "status must be a valid permit status")
      const cap = Number.isInteger(limit) && limit > 0 && limit <= 200 ? limit : 100

      // Workers / non-supervisors see only active permits on jobs they're
      // assigned to. Resolve their visible job set up front (one trip).
      let visibleJobIds: string[] | null = null
      if (!supervisorPlus) {
        const { data: assigns, error: assignErr } = await supabaseAdmin
          .from("assignments").select("job_id")
          .eq("company_id", userRecord.company_id).eq("user_id", user.id)
          .eq("is_active", true).in("assigned_role", ["worker", "foreman"])
        if (assignErr) {
          logRequestError(ENDPOINT, requestId, assignErr)
          return errorResponse(requestId, 500, "INTERNAL_ERROR", "Failed to load assignments")
        }
        visibleJobIds = Array.from(new Set((assigns || []).map((a: { job_id: string }) => a.job_id)))
        if (visibleJobIds.length === 0 || (job_id && !visibleJobIds.includes(job_id))) {
          return jsonResponse({ permits: [], request_id: requestId }, 200, requestId)
        }
      }

      let query = supabaseAdmin.from("work_permits").select(PERMIT_COLUMNS)
        .eq("company_id", userRecord.company_id)
        .order("created_at", { ascending: false }).limit(cap)
      if (job_id) query = query.eq("job_id", job_id)
      if (status) query = query.eq("status", status)
      if (!supervisorPlus) query = query.eq("status", "issued").in("job_id", visibleJobIds!)

      const { data: rows, error: fetchError } = await query
      if (fetchError) {
        logRequestError(ENDPOINT, requestId, fetchError)
        return errorResponse(requestId, 500, "INTERNAL_ERROR", "Failed to fetch permits")
      }

      const nowMs = Date.now()
      // For workers, also drop rows whose projected status is 'expired'.
      const filtered = (rows || []).filter((r) => supervisorPlus || projectStatus(r, nowMs) === "issued")

      // Batch users + jobs lookups — no N+1.
      const userIds = new Set<string>(), jobIds = new Set<string>()
      for (const r of filtered) {
        if (r.issued_by) userIds.add(r.issued_by)
        if (r.revoked_by) userIds.add(r.revoked_by)
        if (r.job_id) jobIds.add(r.job_id)
      }
      const namesMap = new Map<string, string>()
      if (userIds.size > 0) {
        const { data: usersRows } = await supabaseAdmin.from("users").select("id, full_name").in("id", Array.from(userIds))
        for (const u of usersRows || []) if (u.full_name) namesMap.set(u.id, u.full_name)
      }
      const jobsMap = new Map<string, { name: string | null; code: string | null }>()
      if (jobIds.size > 0) {
        const { data: jobsRows } = await supabaseAdmin.from("jobs").select("id, name, code").in("id", Array.from(jobIds))
        for (const j of jobsRows || []) jobsMap.set(j.id, { name: j.name ?? null, code: j.code ?? null })
      }

      const shaped = filtered.map((r) => shapeRow(r, namesMap, jobsMap, nowMs))
      logRequestResult(ENDPOINT, requestId, 200, { user_id: user.id, action: "list", count: shaped.length })
      return jsonResponse({ permits: shaped, request_id: requestId }, 200, requestId)
    }

    // ── Action: create ─────────────────────────────────────
    if (action === "create") {
      if (!isSupervisorOrAbove(userRecord.role)) return errorResponse(requestId, 403, "FORBIDDEN", "Only supervisors, admins, or owners can create permits")
      const { job_id, permit_number, permit_type, description, expires_at, issue_now } = payload

      if (!isUuid(job_id)) return errorResponse(requestId, 400, "INVALID_PAYLOAD", "job_id must be a uuid")
      if (!isPermitNumber(permit_number)) return errorResponse(requestId, 400, "INVALID_PAYLOAD", `permit_number must be a non-empty string up to ${PERMIT_NUMBER_MAX} chars`)
      if (!PERMIT_TYPES.includes(permit_type)) return errorResponse(requestId, 400, "INVALID_PAYLOAD", "permit_type is invalid")
      if (expires_at !== undefined && !isIsoOrNull(expires_at)) return errorResponse(requestId, 400, "INVALID_PAYLOAD", "expires_at must be an ISO timestamp or null")

      const idem = await checkIdempotency()
      if (idem.kind === "response") return idem.response

      // Confirm job belongs to caller's company.
      const { data: job, error: jobError } = await supabaseAdmin.from("jobs").select("id, company_id").eq("id", job_id).maybeSingle()
      if (jobError) {
        logRequestError(ENDPOINT, requestId, jobError)
        return errorResponse(requestId, 500, "INTERNAL_ERROR", "Failed to load job")
      }
      if (!job || job.company_id !== userRecord.company_id) return errorResponse(requestId, 404, "NOT_FOUND", "Job not found in your company")

      const issueNow = issue_now !== false // default true
      const nowIso = new Date().toISOString()

      const { data: inserted, error: insertError } = await supabaseAdmin.from("work_permits").insert({
        company_id: userRecord.company_id,
        job_id,
        permit_number: permit_number.trim(),
        permit_type,
        description: description ?? null,
        expires_at: expires_at ?? null,
        status: issueNow ? "issued" : "draft",
        issued_by: issueNow ? user.id : null,
        issued_at: issueNow ? nowIso : null,
        created_by: user.id,
      }).select(PERMIT_COLUMNS).single()

      if (insertError) {
        // 23505 = unique_violation on (company_id, permit_number)
        // deno-lint-ignore no-explicit-any
        if ((insertError as any).code === "23505") return errorResponse(requestId, 409, "CONFLICT", "permit_number already exists in your company")
        logRequestError(ENDPOINT, requestId, insertError)
        return errorResponse(requestId, 500, "INTERNAL_ERROR", "Failed to create permit")
      }

      const responseBody = { permit: inserted, request_id: requestId }
      await storeIdempotency(supabaseAdmin, user.id, ENDPOINT, idem.idempotencyKey, idem.requestHash, 201, responseBody, requestId)
      logRequestResult(ENDPOINT, requestId, 201, { user_id: user.id, action: "create", permit_id: inserted.id })
      return jsonResponse(responseBody, 201, requestId)
    }

    // ── Action: update ─────────────────────────────────────
    if (action === "update") {
      if (!isSupervisorOrAbove(userRecord.role)) return errorResponse(requestId, 403, "FORBIDDEN", "Only supervisors, admins, or owners can update permits")
      const { permit_id, permit_number, permit_type, description, expires_at } = payload
      if (!isUuid(permit_id)) return errorResponse(requestId, 400, "INVALID_PAYLOAD", "permit_id must be a uuid")

      const { data: existing } = await loadPermit(permit_id)
      if (!existing) return errorResponse(requestId, 404, "NOT_FOUND", "Permit not found")
      if (existing.status === "revoked" || existing.status === "expired") {
        return errorResponse(requestId, 409, "CONFLICT", `Permit is ${existing.status} and cannot be updated`)
      }

      // deno-lint-ignore no-explicit-any
      const updates: Record<string, any> = { updated_at: new Date().toISOString() }
      if (description !== undefined) updates.description = description
      if (expires_at !== undefined) {
        if (!isIsoOrNull(expires_at)) return errorResponse(requestId, 400, "INVALID_PAYLOAD", "expires_at must be an ISO timestamp or null")
        updates.expires_at = expires_at
      }

      // permit_number / permit_type only editable while in 'draft'.
      if (permit_number !== undefined || permit_type !== undefined) {
        if (existing.status !== "draft") return errorResponse(requestId, 409, "CONFLICT", "permit_number and permit_type are immutable once issued")
        if (permit_number !== undefined) {
          if (!isPermitNumber(permit_number)) return errorResponse(requestId, 400, "INVALID_PAYLOAD", `permit_number must be a non-empty string up to ${PERMIT_NUMBER_MAX} chars`)
          updates.permit_number = permit_number.trim()
        }
        if (permit_type !== undefined) {
          if (!PERMIT_TYPES.includes(permit_type)) return errorResponse(requestId, 400, "INVALID_PAYLOAD", "permit_type is invalid")
          updates.permit_type = permit_type
        }
      }

      const { data: updated, error: updateError } = await supabaseAdmin.from("work_permits")
        .update(updates).eq("id", permit_id).eq("company_id", userRecord.company_id)
        .select(PERMIT_COLUMNS).single()

      if (updateError) {
        // deno-lint-ignore no-explicit-any
        if ((updateError as any).code === "23505") return errorResponse(requestId, 409, "CONFLICT", "permit_number already exists in your company")
        logRequestError(ENDPOINT, requestId, updateError)
        return errorResponse(requestId, 500, "INTERNAL_ERROR", "Failed to update permit")
      }

      logRequestResult(ENDPOINT, requestId, 200, { user_id: user.id, action: "update", permit_id })
      return jsonResponse({ permit: updated, request_id: requestId }, 200, requestId)
    }

    // ── Action: issue ──────────────────────────────────────
    if (action === "issue") {
      if (!isSupervisorOrAbove(userRecord.role)) return errorResponse(requestId, 403, "FORBIDDEN", "Only supervisors, admins, or owners can issue permits")
      const { permit_id } = payload
      if (!isUuid(permit_id)) return errorResponse(requestId, 400, "INVALID_PAYLOAD", "permit_id must be a uuid")

      const idem = await checkIdempotency()
      if (idem.kind === "response") return idem.response

      const { data: existing } = await loadPermit(permit_id)
      if (!existing) return errorResponse(requestId, 404, "NOT_FOUND", "Permit not found")
      if (existing.status !== "draft") return errorResponse(requestId, 409, "CONFLICT", `Permit is already ${existing.status}`)

      const nowIso = new Date().toISOString()
      const { data: updated, error: updateError } = await supabaseAdmin.from("work_permits").update({
        status: "issued", issued_by: user.id, issued_at: nowIso, updated_at: nowIso,
      }).eq("id", permit_id).eq("company_id", userRecord.company_id).select(PERMIT_COLUMNS).single()

      if (updateError) {
        logRequestError(ENDPOINT, requestId, updateError)
        return errorResponse(requestId, 500, "INTERNAL_ERROR", "Failed to issue permit")
      }

      const responseBody = { permit: updated, request_id: requestId }
      await storeIdempotency(supabaseAdmin, user.id, ENDPOINT, idem.idempotencyKey, idem.requestHash, 200, responseBody, requestId)
      logRequestResult(ENDPOINT, requestId, 200, { user_id: user.id, action: "issue", permit_id })
      return jsonResponse(responseBody, 200, requestId)
    }

    // ── Action: revoke ─────────────────────────────────────
    if (action === "revoke") {
      if (!isSupervisorOrAbove(userRecord.role)) return errorResponse(requestId, 403, "FORBIDDEN", "Only supervisors, admins, or owners can revoke permits")
      const { permit_id, reason } = payload
      if (!isUuid(permit_id)) return errorResponse(requestId, 400, "INVALID_PAYLOAD", "permit_id must be a uuid")
      if (typeof reason !== "string" || reason.trim().length === 0) return errorResponse(requestId, 400, "INVALID_PAYLOAD", "reason is required")

      const idem = await checkIdempotency()
      if (idem.kind === "response") return idem.response

      const { data: existing } = await loadPermit(permit_id)
      if (!existing) return errorResponse(requestId, 404, "NOT_FOUND", "Permit not found")
      if (existing.status !== "draft" && existing.status !== "issued") {
        return errorResponse(requestId, 409, "CONFLICT", `Permit is already ${existing.status}`)
      }

      const nowIso = new Date().toISOString()
      const { data: updated, error: updateError } = await supabaseAdmin.from("work_permits").update({
        status: "revoked", revoked_by: user.id, revoked_at: nowIso,
        revocation_reason: reason.trim(), updated_at: nowIso,
      }).eq("id", permit_id).eq("company_id", userRecord.company_id).select(PERMIT_COLUMNS).single()

      if (updateError) {
        logRequestError(ENDPOINT, requestId, updateError)
        return errorResponse(requestId, 500, "INTERNAL_ERROR", "Failed to revoke permit")
      }

      const responseBody = { permit: updated, request_id: requestId }
      await storeIdempotency(supabaseAdmin, user.id, ENDPOINT, idem.idempotencyKey, idem.requestHash, 200, responseBody, requestId)
      logRequestResult(ENDPOINT, requestId, 200, { user_id: user.id, action: "revoke", permit_id })
      return jsonResponse(responseBody, 200, requestId)
    }

    // ── Action: check_active ───────────────────────────────
    // Fast read used by the mobile clock-in gate. No idempotency / writes.
    if (action === "check_active") {
      const { job_id } = payload
      if (!isUuid(job_id)) return errorResponse(requestId, 400, "INVALID_PAYLOAD", "job_id must be a uuid")

      const { data: job, error: jobError } = await supabaseAdmin.from("jobs")
        .select("id, company_id, requires_permit, required_permit_type")
        .eq("id", job_id).maybeSingle()
      if (jobError) {
        logRequestError(ENDPOINT, requestId, jobError)
        return errorResponse(requestId, 500, "INTERNAL_ERROR", "Failed to load job")
      }
      if (!job || job.company_id !== userRecord.company_id) return errorResponse(requestId, 404, "NOT_FOUND", "Job not found in your company")

      // Active = status='issued' AND (expires_at IS NULL OR expires_at > now()).
      // Pull the latest matching issued row; required_permit_type narrows it
      // when the job mandates a specific type.
      const nowIso = new Date().toISOString()
      let q = supabaseAdmin.from("work_permits")
        .select("id, permit_number, permit_type, expires_at")
        .eq("company_id", userRecord.company_id).eq("job_id", job_id).eq("status", "issued")
        .or(`expires_at.is.null,expires_at.gt.${nowIso}`)
        .order("issued_at", { ascending: false }).limit(1)
      if (job.requires_permit && job.required_permit_type) q = q.eq("permit_type", job.required_permit_type)

      const { data: rows, error: permErr } = await q
      if (permErr) {
        logRequestError(ENDPOINT, requestId, permErr)
        return errorResponse(requestId, 500, "INTERNAL_ERROR", "Failed to load active permit")
      }

      const active = rows && rows.length > 0 ? rows[0] : null
      logRequestResult(ENDPOINT, requestId, 200, { user_id: user.id, action: "check_active", job_id, has_active: !!active })
      return jsonResponse({
        required: !!job.requires_permit,
        required_type: (job.required_permit_type as PermitType | null) ?? null,
        active_permit: active,
        request_id: requestId,
      }, 200, requestId)
    }

    return errorResponse(requestId, 400, "INVALID_PAYLOAD",
      "action must be 'list', 'create', 'update', 'issue', 'revoke', or 'check_active'")
  } catch (error) {
    logRequestError(ENDPOINT, requestId, error)
    console.error("permits error:", error)
    return errorResponse(requestId, 500, "INTERNAL_ERROR", error.message || "Internal server error")
  }
})
