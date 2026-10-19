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
import { isForemanOrAbove, isManagementRole, isSupervisorOrAbove } from "../_shared/roles.ts"

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const PTO_TYPES = ["vacation", "sick", "personal"] as const
type PtoType = (typeof PTO_TYPES)[number]

const ENDPOINT = "pto"
const PTO_RATE_LIMIT = 20

// Default PTO allocations per worker per year.
// TODO: replace with a dedicated pto_allocations table (per-company, per-user, per-year).
const DEFAULT_ALLOCATIONS = {
  vacation: 10,
  sick: 5,
  personal: 3,
}

// Flatten nested users.full_name into a top-level worker_name and alias pto_type → type
// so the Flutter PTORequest.fromJson (which reads `type` and `worker_name`) deserializes correctly.
// deno-lint-ignore no-explicit-any
function shapeRequestRow(row: any) {
  const users = row?.users
  const workerName = Array.isArray(users) ? users[0]?.full_name : users?.full_name
  const { users: _omit, ...rest } = row ?? {}
  return {
    ...rest,
    type: row?.pto_type,
    worker_name: workerName ?? null,
  }
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders(req) })
  }

  const requestId = makeRequestId(req)
  logRequestStart(ENDPOINT, requestId, req)

  try {
    const authHeader = req.headers.get("Authorization")
    if (!authHeader) {
      return errorResponse(requestId, 401, "UNAUTHORIZED", "Missing Authorization header")
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") || ""
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || ""
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") || ""
    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    })
    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey)

    const { data: { user }, error: authError } = await supabase.auth.getUser()
    if (authError || !user) {
      return errorResponse(requestId, 401, "UNAUTHORIZED", "Invalid auth token")
    }

    const { data: userRecord } = await supabase
      .from("users")
      .select("id, company_id, role, is_active, full_name")
      .eq("id", user.id)
      .single()

    if (!userRecord?.is_active) {
      return errorResponse(requestId, 403, "FORBIDDEN", "User is inactive")
    }

    // Rate limit
    const rateLimit = await applyRateLimit(supabaseAdmin, user.id, ENDPOINT, requestId, PTO_RATE_LIMIT, 60)
    if (rateLimit.limited) {
      logRequestResult(ENDPOINT, requestId, 429, { reason: "rate_limited" })
      return errorResponse(requestId, 429, "RATE_LIMITED", "Too many requests", [], rateLimit.headers)
    }

    // ── Inner: decide (shared by decide / approve / deny actions) ─────
    async function decideImpl(pto_request_id: string, decision: "approved" | "denied", reason?: string | null) {
      if (!isForemanOrAbove(userRecord.role)) {
        return errorResponse(requestId, 403, "FORBIDDEN", "Only foremen, supervisors, admins, or owners can decide PTO requests")
      }

      if (!pto_request_id) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "pto_request_id is required")
      }

      const { data: existing } = await supabaseAdmin
        .from("pto_requests")
        .select("id, status, user_id, company_id")
        .eq("id", pto_request_id)
        .eq("company_id", userRecord.company_id)
        .single()

      if (!existing) {
        return errorResponse(requestId, 404, "NOT_FOUND", "PTO request not found")
      }

      if (existing.status !== "pending") {
        return errorResponse(requestId, 409, "CONFLICT", `PTO request is already ${existing.status}`)
      }

      // Cannot approve own PTO
      if (existing.user_id === user.id) {
        return errorResponse(requestId, 403, "FORBIDDEN", "Cannot approve or deny your own PTO request")
      }

      const { data: updated, error: updateError } = await supabaseAdmin
        .from("pto_requests")
        .update({
          status: decision,
          decided_by: user.id,
          decided_at: new Date().toISOString(),
          decision_reason: reason || null,
          updated_at: new Date().toISOString(),
        })
        .eq("id", pto_request_id)
        .select("id, pto_type, start_date, end_date, day_count, status, decided_by, decided_at, decision_reason")
        .single()

      if (updateError) {
        logRequestError(ENDPOINT, requestId, updateError)
        return errorResponse(requestId, 500, "INTERNAL_ERROR", "Failed to update PTO request")
      }

      logRequestResult(ENDPOINT, requestId, 200, { user_id: user.id, pto_id: updated.id, decision })
      return jsonResponse({
        status: "decided",
        pto_request: updated,
        request_id: requestId,
      }, 200, requestId)
    }

    // ─── GET: List PTO requests ───────────────────────────
    if (req.method === "GET") {
      const url = new URL(req.url)
      const statusFilter = url.searchParams.get("status")

      let query = supabaseAdmin
        .from("pto_requests")
        .select("id, user_id, pto_type, start_date, end_date, day_count, status, notes, decided_by, decided_at, decision_reason, created_at, users!pto_requests_user_id_fkey(full_name)")
        .eq("company_id", userRecord.company_id)
        .order("start_date", { ascending: false })
        .limit(100)

      // Workers see only their own; supervisors/admins/owners see all
      if (!isSupervisorOrAbove(userRecord.role)) {
        query = query.eq("user_id", user.id)
      }

      if (statusFilter) {
        query = query.eq("status", statusFilter)
      }

      const { data: requests, error: fetchError } = await query

      if (fetchError) {
        logRequestError(ENDPOINT, requestId, fetchError)
        return errorResponse(requestId, 500, "INTERNAL_ERROR", "Failed to fetch PTO requests")
      }

      const shaped = (requests || []).map(shapeRequestRow)
      logRequestResult(ENDPOINT, requestId, 200, { user_id: user.id, count: shaped.length })
      return jsonResponse({ requests: shaped, request_id: requestId }, 200, requestId)
    }

    // ─── POST: Submit or decide ───────────────────────────
    if (req.method !== "POST") {
      return errorResponse(requestId, 405, "METHOD_NOT_ALLOWED", "Use GET or POST")
    }

    const payload = await req.json()
    const { action } = payload

    // ── Action: request ──────────────────────────────────
    if (action === "request") {
      const { pto_type, start_date, end_date, notes } = payload

      if (!pto_type || !start_date || !end_date) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "pto_type, start_date, and end_date are required")
      }

      if (!["vacation", "sick", "personal"].includes(pto_type)) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "pto_type must be vacation, sick, or personal")
      }

      if (start_date > end_date) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "start_date must be before or equal to end_date")
      }

      const { data: inserted, error: insertError } = await supabaseAdmin
        .from("pto_requests")
        .insert({
          company_id: userRecord.company_id,
          user_id: user.id,
          pto_type,
          start_date,
          end_date,
          notes: notes || null,
          status: "pending",
        })
        .select("id, pto_type, start_date, end_date, day_count, status, notes, created_at")
        .single()

      if (insertError) {
        logRequestError(ENDPOINT, requestId, insertError)
        return errorResponse(requestId, 500, "INTERNAL_ERROR", "Failed to submit PTO request")
      }

      logRequestResult(ENDPOINT, requestId, 201, { user_id: user.id, pto_id: inserted.id, pto_type })
      return jsonResponse({
        status: "submitted",
        pto_request: inserted,
        request_id: requestId,
      }, 201, requestId)
    }

    // ── Action: balance (compute on-the-fly) ─────────────
    if (action === "balance") {
      const currentYear = new Date().getUTCFullYear()
      const yearStart = `${currentYear}-01-01`
      const yearEnd = `${currentYear}-12-31`

      // One trip: pull this user's allocations for the current year (all three pto_types).
      const { data: allocRows, error: allocError } = await supabaseAdmin
        .from("pto_allocations")
        .select("pto_type, total_days")
        .eq("company_id", userRecord.company_id)
        .eq("user_id", user.id)
        .eq("year", currentYear)

      if (allocError) {
        logRequestError(ENDPOINT, requestId, allocError)
        return errorResponse(requestId, 500, "INTERNAL_ERROR", "Failed to load PTO allocations")
      }

      // Fallback while allocations are being backfilled — admin UI seeds per-worker rows.
      const totals = { ...DEFAULT_ALLOCATIONS }
      for (const row of allocRows || []) {
        if (row.pto_type in totals) {
          totals[row.pto_type as PtoType] = Number(row.total_days) || 0
        }
      }

      // Sum approved day_count per pto_type, scoped to the current year by start_date.
      const { data: rows, error: balanceError } = await supabaseAdmin
        .from("pto_requests")
        .select("pto_type, day_count, status, start_date")
        .eq("company_id", userRecord.company_id)
        .eq("user_id", user.id)
        .eq("status", "approved")
        .gte("start_date", yearStart)
        .lte("start_date", yearEnd)

      if (balanceError) {
        logRequestError(ENDPOINT, requestId, balanceError)
        return errorResponse(requestId, 500, "INTERNAL_ERROR", "Failed to compute PTO balance")
      }

      const used = { vacation: 0, sick: 0, personal: 0 }
      for (const row of rows || []) {
        if (row.pto_type in used) {
          used[row.pto_type as PtoType] += Number(row.day_count) || 0
        }
      }

      const balance = {
        vacation_total: totals.vacation,
        vacation_used: used.vacation,
        sick_total: totals.sick,
        sick_used: used.sick,
        personal_total: totals.personal,
        personal_used: used.personal,
      }

      logRequestResult(ENDPOINT, requestId, 200, { user_id: user.id, action: "balance" })
      return jsonResponse({ balance, request_id: requestId }, 200, requestId)
    }

    // ── Action: allocations_list (admin/owner only) ──────
    if (action === "allocations_list") {
      if (!isManagementRole(userRecord.role)) {
        return errorResponse(requestId, 403, "FORBIDDEN", "Only admins or owners can list PTO allocations")
      }

      const rawYear = payload?.year
      const year = Number.isInteger(rawYear) && rawYear > 2024
        ? rawYear
        : new Date().getUTCFullYear()

      // Active workers in this company, one row per (user, pto_type).
      const { data: workers, error: workersError } = await supabaseAdmin
        .from("users")
        .select("id, full_name")
        .eq("company_id", userRecord.company_id)
        .eq("is_active", true)

      if (workersError) {
        logRequestError(ENDPOINT, requestId, workersError)
        return errorResponse(requestId, 500, "INTERNAL_ERROR", "Failed to load workers")
      }

      const { data: allocRows, error: allocError } = await supabaseAdmin
        .from("pto_allocations")
        .select("user_id, pto_type, year, total_days")
        .eq("company_id", userRecord.company_id)
        .eq("year", year)

      if (allocError) {
        logRequestError(ENDPOINT, requestId, allocError)
        return errorResponse(requestId, 500, "INTERNAL_ERROR", "Failed to load PTO allocations")
      }

      // Index allocations by (user_id, pto_type) for O(1) lookup.
      const allocByKey = new Map<string, number>()
      for (const row of allocRows || []) {
        allocByKey.set(`${row.user_id}:${row.pto_type}`, Number(row.total_days) || 0)
      }

      // Emit one row per worker × pto_type. Missing rows use DEFAULT_ALLOCATIONS fallback
      // so the admin UI can prompt to seed a real value.
      const allocations: Array<{
        user_id: string
        worker_name: string | null
        pto_type: PtoType
        year: number
        total_days: number
      }> = []
      for (const worker of workers || []) {
        for (const pto_type of PTO_TYPES) {
          const key = `${worker.id}:${pto_type}`
          const total_days = allocByKey.has(key)
            ? allocByKey.get(key)!
            : DEFAULT_ALLOCATIONS[pto_type]
          allocations.push({
            user_id: worker.id,
            worker_name: worker.full_name ?? null,
            pto_type,
            year,
            total_days,
          })
        }
      }

      logRequestResult(ENDPOINT, requestId, 200, { user_id: user.id, action: "allocations_list", count: allocations.length })
      return jsonResponse({ allocations, request_id: requestId }, 200, requestId)
    }

    // ── Action: allocations_upsert (admin/owner only; requires Idempotency-Key) ─
    if (action === "allocations_upsert") {
      if (!isManagementRole(userRecord.role)) {
        return errorResponse(requestId, 403, "FORBIDDEN", "Only admins or owners can upsert PTO allocations")
      }

      const { user_id, pto_type, year, total_days } = payload

      if (!user_id || typeof user_id !== "string" || !UUID_RE.test(user_id)) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "user_id must be a valid uuid")
      }

      if (!PTO_TYPES.includes(pto_type)) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "pto_type must be vacation, sick, or personal")
      }

      if (!Number.isInteger(year) || year <= 2024) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "year must be an integer greater than 2024")
      }

      const totalDaysNum = Number(total_days)
      if (!Number.isFinite(totalDaysNum) || totalDaysNum < 0) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "total_days must be a number >= 0")
      }

      // Confirm the target worker belongs to this company.
      const { data: targetUser } = await supabaseAdmin
        .from("users")
        .select("id, company_id")
        .eq("id", user_id)
        .eq("company_id", userRecord.company_id)
        .maybeSingle()

      if (!targetUser) {
        return errorResponse(requestId, 404, "NOT_FOUND", "Worker not found in your company")
      }

      // Write actions require Idempotency-Key
      const idempotencyKey = req.headers.get("Idempotency-Key")
      if (!idempotencyKey) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "Idempotency-Key header is required")
      }

      const requestHash = await sha256Hex(JSON.stringify(payload))
      const replay = await lookupIdempotency(supabaseAdmin, user.id, ENDPOINT, idempotencyKey, requestHash)
      if (replay.replay) {
        if (replay.conflict) {
          return errorResponse(replay.requestId, 409, "CONFLICT", "Idempotency key reused with different payload")
        }
        return jsonResponse(replay.body, replay.status, replay.requestId)
      }

      const { data: upserted, error: upsertError } = await supabaseAdmin
        .from("pto_allocations")
        .upsert({
          company_id: userRecord.company_id,
          user_id,
          pto_type,
          year,
          total_days: totalDaysNum,
          updated_at: new Date().toISOString(),
        }, { onConflict: "company_id,user_id,pto_type,year" })
        .select("id, company_id, user_id, pto_type, year, total_days, created_at, updated_at")
        .single()

      if (upsertError) {
        logRequestError(ENDPOINT, requestId, upsertError)
        return errorResponse(requestId, 500, "INTERNAL_ERROR", "Failed to upsert PTO allocation")
      }

      const responseBody = {
        status: "upserted",
        allocation: upserted,
        request_id: requestId,
      }

      await storeIdempotency(supabaseAdmin, user.id, ENDPOINT, idempotencyKey, requestHash, 200, responseBody, requestId)
      logRequestResult(ENDPOINT, requestId, 200, { user_id: user.id, action: "allocations_upsert", target_user_id: user_id, pto_type, year })
      return jsonResponse(responseBody, 200, requestId)
    }

    // ── Action: pending_approvals (supervisor-gated list) ─
    if (action === "pending_approvals") {
      if (!isForemanOrAbove(userRecord.role)) {
        return errorResponse(requestId, 403, "FORBIDDEN", "Only foremen, supervisors, admins, or owners can view pending approvals")
      }

      const { data: requests, error: fetchError } = await supabaseAdmin
        .from("pto_requests")
        .select("id, user_id, pto_type, start_date, end_date, day_count, status, notes, decided_by, decided_at, decision_reason, created_at, users!pto_requests_user_id_fkey(full_name)")
        .eq("company_id", userRecord.company_id)
        .eq("status", "pending")
        .order("start_date", { ascending: true })
        .limit(100)

      if (fetchError) {
        logRequestError(ENDPOINT, requestId, fetchError)
        return errorResponse(requestId, 500, "INTERNAL_ERROR", "Failed to fetch pending PTO requests")
      }

      const shaped = (requests || []).map(shapeRequestRow)
      logRequestResult(ENDPOINT, requestId, 200, { user_id: user.id, count: shaped.length, action: "pending_approvals" })
      return jsonResponse({ requests: shaped, request_id: requestId }, 200, requestId)
    }

    // ── Action: decide (approve/deny) ────────────────────
    if (action === "decide") {
      const { pto_request_id, decision, reason } = payload

      if (!decision) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "pto_request_id and decision are required")
      }

      if (!["approved", "denied"].includes(decision)) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "decision must be approved or denied")
      }

      return await decideImpl(pto_request_id, decision, reason)
    }

    // ── Action: approve (mobile alias for decide with decision=approved) ─
    if (action === "approve") {
      const { request_id: ptoId } = payload
      return await decideImpl(ptoId, "approved", null)
    }

    // ── Action: deny (mobile alias for decide with decision=denied) ──────
    if (action === "deny") {
      const { request_id: ptoId, reason } = payload
      return await decideImpl(ptoId, "denied", reason)
    }

    // ── Action: cancel (worker cancels own pending) ──────
    if (action === "cancel") {
      const { pto_request_id } = payload

      if (!pto_request_id) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "pto_request_id is required")
      }

      const { data: existing } = await supabaseAdmin
        .from("pto_requests")
        .select("id, status, user_id, company_id")
        .eq("id", pto_request_id)
        .eq("company_id", userRecord.company_id)
        .eq("user_id", user.id)
        .single()

      if (!existing) {
        return errorResponse(requestId, 404, "NOT_FOUND", "PTO request not found")
      }

      if (existing.status !== "pending") {
        return errorResponse(requestId, 409, "CONFLICT", `Cannot cancel — PTO request is already ${existing.status}`)
      }

      const { error: cancelError } = await supabaseAdmin
        .from("pto_requests")
        .update({ status: "cancelled", updated_at: new Date().toISOString() })
        .eq("id", pto_request_id)

      if (cancelError) {
        logRequestError(ENDPOINT, requestId, cancelError)
        return errorResponse(requestId, 500, "INTERNAL_ERROR", "Failed to cancel PTO request")
      }

      logRequestResult(ENDPOINT, requestId, 200, { user_id: user.id, pto_id: pto_request_id, action: "cancelled" })
      return jsonResponse({ status: "cancelled", request_id: requestId }, 200, requestId)
    }

    return errorResponse(
      requestId,
      400,
      "INVALID_PAYLOAD",
      "action must be 'request', 'balance', 'pending_approvals', 'decide', 'approve', 'deny', 'cancel', 'allocations_list', or 'allocations_upsert'",
    )
  } catch (error) {
    logRequestError(ENDPOINT, requestId, error)
    console.error("pto error:", error)
    return errorResponse(requestId, 500, "INTERNAL_ERROR", error.message || "Internal server error")
  }
})
