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
import { isForemanOrAbove } from "../_shared/roles.ts"

const ENDPOINT = "ot"
const OT_RATE_LIMIT = 20

// ─── State-Specific OT Computation ──────────────────────────
// Jurisdiction-aware OT calculation (Sprint 6 — Payroll & Compliance)
export interface OTBreakdown {
  regular: number    // regular hours
  overtime: number   // 1.5x hours
  doubletime: number // 2x hours (CA only)
}

/**
 * Compute OT breakdown based on jurisdiction rules.
 *
 * @param jurisdiction - "federal" | "california"
 * @param dailyHours  - Array of daily hours worked (length = 7 for a week)
 * @returns OTBreakdown with regular, overtime, and doubletime hours
 */
export function computeOTHours(
  jurisdiction: string,
  dailyHours: number[],
): OTBreakdown {
  if (jurisdiction === "california") {
    return computeCaliforniaOT(dailyHours)
  }
  // Default: federal — OT after 40h/week
  return computeFederalOT(dailyHours)
}

function computeFederalOT(dailyHours: number[]): OTBreakdown {
  const totalWeekly = dailyHours.reduce((sum, h) => sum + h, 0)
  const regular = Math.min(totalWeekly, 40)
  const overtime = Math.max(totalWeekly - 40, 0)
  return { regular, overtime, doubletime: 0 }
}

function computeCaliforniaOT(dailyHours: number[]): OTBreakdown {
  let regular = 0
  let overtime = 0
  let doubletime = 0
  let consecutiveDays = 0

  for (let i = 0; i < dailyHours.length; i++) {
    const hours = dailyHours[i]
    if (hours <= 0) {
      consecutiveDays = 0
      continue
    }
    consecutiveDays++

    if (consecutiveDays >= 7) {
      // 7th consecutive day: first 8h at OT, rest at doubletime
      const dtHours = Math.max(hours - 8, 0)
      const otHours = Math.min(hours, 8)
      overtime += otHours
      doubletime += dtHours
    } else {
      // Daily OT after 8h, doubletime after 12h
      const dtHours = Math.max(hours - 12, 0)
      const otHours = Math.max(Math.min(hours, 12) - 8, 0)
      const regHours = Math.min(hours, 8)
      regular += regHours
      overtime += otHours
      doubletime += dtHours
    }
  }

  // Also check weekly: if weekly regular > 40, shift excess to OT
  const weeklyTotal = regular + overtime + doubletime
  if (regular > 40) {
    const excess = regular - 40
    regular = 40
    overtime += excess
  }

  return {
    regular: +regular.toFixed(2),
    overtime: +overtime.toFixed(2),
    doubletime: +doubletime.toFixed(2),
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

    const jwt = authHeader.replace("Bearer ", "")
    const { data: { user }, error: authError } = await supabase.auth.getUser()
    if (authError || !user) {
      return errorResponse(requestId, 401, "UNAUTHORIZED", "Invalid auth token")
    }

    const { data: userRecord, error: userError } = await supabase
      .from("users")
      .select("id, company_id, role, is_active, full_name")
      .eq("id", user.id)
      .single()

    if (userError || !userRecord) {
      return errorResponse(requestId, 401, "UNAUTHORIZED", "User record not found")
    }
    if (!userRecord.is_active) {
      return errorResponse(requestId, 403, "FORBIDDEN", "User is inactive")
    }

    // ──────────────────────────────────────────────────────────
    // GET /ot?job_id=<uuid>&status=<pending|approved|denied>
    // List OT requests (workers see their own, supervisors see all for company)
    // ──────────────────────────────────────────────────────────
    if (req.method === "GET") {
      const url = new URL(req.url)
      const jobId = url.searchParams.get("job_id")
      const status = url.searchParams.get("status") || "pending"
      const offset = Number(url.searchParams.get("offset") || "0")
      const limit = Number(url.searchParams.get("limit") || "50")
      const safeOffset = Number.isFinite(offset) && offset >= 0 ? offset : 0
      const safeLimit = Number.isFinite(limit) && limit > 0 ? Math.min(limit, 100) : 50

      let query = supabaseAdmin
        .from("ot_requests")
        .select(`
          id,
          job_id,
          worker_id,
          requested_at,
          total_hours_at_request,
          notes,
          status,
          request_photo_event_id,
          created_at,
          users!ot_requests_worker_id_fkey ( full_name ),
          jobs!ot_requests_job_id_fkey ( name, code )
        `)
        .eq("company_id", userRecord.company_id)
        .eq("status", status)
        .order("requested_at", { ascending: false })
        .range(safeOffset, safeOffset + safeLimit - 1)

      if (jobId) {
        query = query.eq("job_id", jobId)
      }

      // Workers only see their own requests
      if (userRecord.role === "worker") {
        query = query.eq("worker_id", user.id)
      }

      const { data: requests, error: fetchError } = await query
      if (fetchError) throw fetchError

      logRequestResult(ENDPOINT, requestId, 200, {
        user_id: user.id,
        result_count: (requests || []).length,
      })
      return jsonResponse({
        status: "success",
        ot_requests: requests || [],
        count: (requests || []).length,
        request_id: requestId,
      }, 200, requestId)
    }

    // ──────────────────────────────────────────────────────────
    // POST /ot — Actions:
    //   "request" (worker submits)
    //   "pending" (supervisor lists pending — mobile contract)
    //   "decide"  (supervisor approves/denies with explicit decision+reason)
    //   "approve" (alias → decide approved, reason optional)
    //   "deny"    (alias → decide denied,   reason required)
    // ──────────────────────────────────────────────────────────
    if (req.method === "POST") {
      const payload = await req.json()
      const { action } = payload

      const ALLOWED_ACTIONS = ["request", "decide", "approve", "deny", "pending"]
      if (!action || !ALLOWED_ACTIONS.includes(action)) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD",
          "action must be 'request', 'decide', 'approve', 'deny', or 'pending'")
      }

      // ── ACTION: pending (supervisor list — mirrors GET with status=pending) ──
      // Read-only, no Idempotency-Key, no idempotency replay. Rate-limited.
      if (action === "pending") {
        if (!isForemanOrAbove(userRecord.role)) {
          return errorResponse(requestId, 403, "FORBIDDEN",
            "Only foremen, supervisors, admins, or owners can list pending OT requests")
        }

        const rateLimit = await applyRateLimit(supabaseAdmin, user.id, ENDPOINT, requestId, OT_RATE_LIMIT)
        if (rateLimit.limited) {
          return errorResponse(requestId, 429, "RATE_LIMITED", "Too many OT requests", [], rateLimit.headers)
        }

        const { data: rows, error: fetchError } = await supabaseAdmin
          .from("ot_requests")
          .select(`
            id,
            job_id,
            worker_id,
            requested_at,
            total_hours_at_request,
            notes,
            status,
            request_photo_event_id,
            created_at,
            jobs!ot_requests_job_id_fkey ( name, code )
          `)
          .eq("company_id", userRecord.company_id)
          .eq("status", "pending")
          .order("requested_at", { ascending: false })
          .limit(100)

        if (fetchError) throw fetchError

        // Resolve worker_name via second query (same pattern as timecards list action)
        const workerIds = Array.from(new Set((rows || [])
          .map((r: any) => r.worker_id)
          .filter(Boolean)))
        const workerNameById = new Map<string, string>()
        if (workerIds.length > 0) {
          const { data: workers, error: workersError } = await supabaseAdmin
            .from("users")
            .select("id, full_name")
            .in("id", workerIds)

          if (workersError) {
            logRequestError(ENDPOINT, requestId, workersError)
            return errorResponse(requestId, 500, "INTERNAL_ERROR", "Failed to resolve worker names")
          }
          for (const w of (workers || [])) {
            if (w?.id) workerNameById.set(w.id, w.full_name || "Unknown worker")
          }
        }

        const requests = (rows || []).map((r: any) => ({
          ...r,
          worker_name: workerNameById.get(r.worker_id) || "Unknown worker",
        }))

        logRequestResult(ENDPOINT, requestId, 200, {
          user_id: user.id,
          action: "pending",
          result_count: requests.length,
        })
        return jsonResponse({
          status: "success",
          requests,
          count: requests.length,
          request_id: requestId,
        }, 200, requestId, rateLimit.headers)
      }

      // Write actions below require Idempotency-Key
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

      const rateLimit = await applyRateLimit(supabaseAdmin, user.id, ENDPOINT, requestId, OT_RATE_LIMIT)
      if (rateLimit.limited) {
        return errorResponse(requestId, 429, "RATE_LIMITED", "Too many OT requests", [], rateLimit.headers)
      }

      // ── ACTION: request (worker submits OT request) ──
      if (action === "request") {
        const { job_id, total_hours, notes, photo_event_id } = payload

        if (!job_id) {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", "job_id is required")
        }

        if (total_hours !== undefined && total_hours !== null && typeof total_hours !== "number") {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", "total_hours must be a number")
        }

        // Verify worker is assigned
        const { data: assignment } = await supabase
          .from("assignments")
          .select("job_id")
          .eq("user_id", user.id)
          .eq("job_id", job_id)
          .eq("is_active", true)
          .maybeSingle()

        if (!assignment) {
          return errorResponse(requestId, 403, "FORBIDDEN", "Worker is not assigned to this job")
        }

        // Verify photo exists if provided
        if (photo_event_id) {
          const { data: photoEvent } = await supabaseAdmin
            .from("photo_events")
            .select("id")
            .eq("id", photo_event_id)
            .eq("company_id", userRecord.company_id)
            .maybeSingle()

          if (!photoEvent) {
            return errorResponse(requestId, 400, "INVALID_PAYLOAD", "photo_event_id not found")
          }
        }

        const otRequestId = crypto.randomUUID()
        const now = new Date().toISOString()

        const { error: insertError } = await supabaseAdmin
          .from("ot_requests")
          .insert({
            id: otRequestId,
            company_id: userRecord.company_id,
            job_id,
            worker_id: user.id,
            request_photo_event_id: photo_event_id || null,
            requested_at: now,
            total_hours_at_request: total_hours || null,
            notes: notes || null,
            status: "pending",
            source_event_uuid: otRequestId,
          })

        if (insertError) throw insertError

        const responseBody = {
          status: "success",
          ot_request_id: otRequestId,
          request_id: requestId,
        }

        await storeIdempotency(supabaseAdmin, user.id, ENDPOINT, idempotencyKey, requestHash, 201, responseBody, requestId)
        logRequestResult(ENDPOINT, requestId, 201, {
          user_id: user.id,
          action: "request",
          ot_request_id: otRequestId,
        })
        return jsonResponse(responseBody, 201, requestId, rateLimit.headers)
      }

      // ── Shared decide implementation (used by 'decide', 'approve', 'deny') ──
      const decideImpl = async (
        ot_request_id: string | undefined,
        decision: "approved" | "denied",
        reason: string | null,
        actionLabel: string,
      ): Promise<Response> => {
        if (!ot_request_id) {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", "ot_request_id is required")
        }
        if (!isForemanOrAbove(userRecord.role)) {
          return errorResponse(requestId, 403, "FORBIDDEN", "Only foremen, supervisors, admins, or owners can approve OT requests")
        }
        const { data: otRequest, error: otError } = await supabaseAdmin
          .from("ot_requests")
          .select("id, company_id, job_id, worker_id, status")
          .eq("id", ot_request_id)
          .maybeSingle()
        if (otError) throw otError
        if (!otRequest) {
          return errorResponse(requestId, 404, "NOT_FOUND", "OT request not found")
        }
        if (otRequest.company_id !== userRecord.company_id) {
          return errorResponse(requestId, 403, "FORBIDDEN", "OT request belongs to a different company")
        }
        if (otRequest.worker_id === user.id) {
          return errorResponse(requestId, 403, "FORBIDDEN", "Cannot approve your own OT request")
        }
        if (otRequest.status !== "pending") {
          return errorResponse(requestId, 400, "INVALID_TRANSITION",
            `OT request is already '${otRequest.status}'. Decisions are immutable.`)
        }
        const now = new Date().toISOString()
        const approvalEventId = crypto.randomUUID()
        const { error: updateError } = await supabaseAdmin
          .from("ot_requests")
          .update({ status: decision })
          .eq("id", ot_request_id)
        if (updateError) throw updateError
        const { error: eventError } = await supabaseAdmin
          .from("ot_approval_events")
          .insert({
            id: approvalEventId,
            company_id: userRecord.company_id,
            job_id: otRequest.job_id,
            ot_request_id,
            worker_id: otRequest.worker_id,
            approver_id: user.id,
            decision,
            reason,
            occurred_at: now,
            received_at: now,
            source_event_uuid: approvalEventId,
          })
        if (eventError) {
          // Rollback — revert status to pending
          await supabaseAdmin.from("ot_requests").update({ status: "pending" }).eq("id", ot_request_id)
          throw eventError
        }
        const responseBody = {
          status: "success",
          ot_request_id,
          decision,
          approval_event_id: approvalEventId,
          request_id: requestId,
        }
        await storeIdempotency(supabaseAdmin, user.id, ENDPOINT, idempotencyKey, requestHash, 200, responseBody, requestId)
        logRequestResult(ENDPOINT, requestId, 200, {
          user_id: user.id,
          action: actionLabel,
          ot_request_id,
          decision,
        })
        return jsonResponse(responseBody, 200, requestId, rateLimit.headers)
      }

      // ── ACTION: decide (explicit decision + reason required) ──
      if (action === "decide") {
        const { ot_request_id, decision, reason } = payload
        if (!decision) {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", "decision is required")
        }
        if (!["approved", "denied"].includes(decision)) {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", "decision must be 'approved' or 'denied'")
        }
        if (!reason || reason.trim().length === 0) {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", "reason is required for OT decisions")
        }
        return await decideImpl(ot_request_id, decision as "approved" | "denied", reason, "decide")
      }

      // ── ACTION: approve (alias — reason optional when approving) ──
      if (action === "approve") {
        const { ot_request_id, reason } = payload
        const normalizedReason =
          typeof reason === "string" && reason.trim().length > 0 ? reason : null
        return await decideImpl(ot_request_id, "approved", normalizedReason, "approve")
      }

      // ── ACTION: deny (alias — reason required for audit trail) ──
      if (action === "deny") {
        const { ot_request_id, reason } = payload
        if (!reason || typeof reason !== "string" || reason.trim().length === 0) {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", "reason is required when denying an OT request")
        }
        return await decideImpl(ot_request_id, "denied", reason, "deny")
      }
    }

    return errorResponse(requestId, 405, "METHOD_NOT_ALLOWED", "Use GET or POST for /ot")
  } catch (error) {
    logRequestError(ENDPOINT, requestId, error)
    console.error("ot error:", error)
    return errorResponse(requestId, 500, "INTERNAL_ERROR", error.message || "Internal server error")
  }
})
