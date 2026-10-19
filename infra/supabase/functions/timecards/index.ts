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
  makeRequestId,
} from "../_shared/api.ts"
import { isSupervisorOrAbove } from "../_shared/roles.ts"

const ENDPOINT = "timecards"
const RATE_LIMIT = 20

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

    const { data: userRecord } = await supabase
      .from("users")
      .select("id, company_id, role, is_active, full_name")
      .eq("id", user.id)
      .single()

    if (!userRecord?.is_active) {
      return errorResponse(requestId, 403, "FORBIDDEN", "User is inactive")
    }

    // Rate limit
    const rateLimit = await applyRateLimit(supabaseAdmin, user.id, ENDPOINT, requestId, RATE_LIMIT, 60)
    if (rateLimit.limited) {
      logRequestResult(ENDPOINT, requestId, 429, { reason: "rate_limited" })
      return errorResponse(requestId, 429, "RATE_LIMITED", "Too many requests", [], rateLimit.headers)
    }

    // ─── GET: List timecards ─────────────────────────────────
    if (req.method === "GET") {
      const url = new URL(req.url)
      const weekStart = url.searchParams.get("week_start")
      const statusFilter = url.searchParams.get("status")

      let query = supabaseAdmin
        .from("timecard_signatures")
        .select("id, worker_id, supervisor_id, week_start, week_end, worker_signed_at, supervisor_signed_at, total_regular_hours, total_ot_hours, status, created_at")
        .eq("company_id", userRecord.company_id)
        .order("week_start", { ascending: false })
        .limit(50)

      // Workers see only their own; supervisors/admins/owners see all
      if (!isSupervisorOrAbove(userRecord.role)) {
        query = query.eq("worker_id", user.id)
      }

      if (weekStart) {
        query = query.eq("week_start", weekStart)
      }

      if (statusFilter) {
        query = query.eq("status", statusFilter)
      }

      const { data: timecards, error: fetchError } = await query

      if (fetchError) {
        logRequestError(ENDPOINT, requestId, fetchError)
        return errorResponse(requestId, 500, "INTERNAL_ERROR", "Failed to fetch timecards")
      }

      const workerIds = Array.from(new Set((timecards || []).map((t: any) => t.worker_id).filter(Boolean)))
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

      const shaped = (timecards || []).map((tc: any) => ({
        ...tc,
        users: { full_name: workerNameById.get(tc.worker_id) || "Unknown worker" },
      }))

      logRequestResult(ENDPOINT, requestId, 200, { user_id: user.id, count: (timecards || []).length })
      return jsonResponse({ timecards: shaped, request_id: requestId }, 200, requestId)
    }

    // ─── POST: Generate, sign, or countersign ────────────────
    if (req.method !== "POST") {
      return errorResponse(requestId, 405, "METHOD_NOT_ALLOWED", "Use GET or POST")
    }

    const payload = await req.json()
    const { action } = payload

    // ── Action: list ────────────────────────────────────────
    // Mobile clients invoke via POST (supabase.functions.invoke default).
    // Returns the caller's timecards shaped to the mobile contract:
    //   period_start, period_end, regular_hours, ot_hours, double_time_hours,
    //   worker_name, worker_signature?, supervisor_signature?
    if (action === "list") {
      const { week_start: weekStart, status: statusFilter } = payload

      let query = supabaseAdmin
        .from("timecard_signatures")
        .select(
          "id, worker_id, supervisor_id, week_start, week_end, " +
          "worker_signed_at, supervisor_signed_at, worker_signature, supervisor_signature, " +
          "total_regular_hours, total_ot_hours, status, created_at"
        )
        .eq("company_id", userRecord.company_id)
        .order("week_start", { ascending: false })
        .limit(50)

      if (!isSupervisorOrAbove(userRecord.role)) {
        query = query.eq("worker_id", user.id)
      }
      if (weekStart) query = query.eq("week_start", weekStart)
      if (statusFilter) query = query.eq("status", statusFilter)

      const { data: rows, error: listError } = await query
      if (listError) {
        logRequestError(ENDPOINT, requestId, listError)
        return errorResponse(requestId, 500, "INTERNAL_ERROR", "Failed to fetch timecards")
      }

      const workerIds = Array.from(
        new Set((rows || []).map((t: any) => t.worker_id).filter(Boolean))
      )
      const nameById = new Map<string, string>()
      if (workerIds.length > 0) {
        const { data: workers } = await supabaseAdmin
          .from("users")
          .select("id, full_name")
          .in("id", workerIds)
        for (const w of (workers || [])) {
          if (w?.id) nameById.set(w.id, w.full_name || "Unknown worker")
        }
      }

      const timecards = (rows || []).map((tc: any) => ({
        id: tc.id,
        worker_id: tc.worker_id,
        worker_name: nameById.get(tc.worker_id) || "Unknown worker",
        period_start: tc.week_start,
        period_end: tc.week_end,
        regular_hours: Number(tc.total_regular_hours ?? 0),
        ot_hours: Number(tc.total_ot_hours ?? 0),
        double_time_hours: 0,
        status: tc.status,
        worker_signature: tc.worker_signed_at
          ? {
              id: `${tc.id}-worker`,
              timecard_id: tc.id,
              signer_id: tc.worker_id,
              signer_name: nameById.get(tc.worker_id) || "",
              signer_role: "worker",
              signed_at: tc.worker_signed_at,
              signature_image_path: typeof tc.worker_signature === "string"
                ? tc.worker_signature
                : null,
            }
          : null,
        supervisor_signature: tc.supervisor_signed_at && tc.supervisor_id
          ? {
              id: `${tc.id}-supervisor`,
              timecard_id: tc.id,
              signer_id: tc.supervisor_id,
              signer_name: nameById.get(tc.supervisor_id) || "",
              signer_role: "supervisor",
              signed_at: tc.supervisor_signed_at,
              signature_image_path: typeof tc.supervisor_signature === "string"
                ? tc.supervisor_signature
                : null,
            }
          : null,
      }))

      logRequestResult(ENDPOINT, requestId, 200, { action: "list", count: timecards.length })
      return jsonResponse({ timecards, request_id: requestId }, 200, requestId)
    }

    // ── Action: generate ────────────────────────────────────
    if (action === "generate") {
      if (!isSupervisorOrAbove(userRecord.role)) {
        return errorResponse(requestId, 403, "FORBIDDEN", "Only supervisors, admins, or owners can generate timecards")
      }

      const { worker_id, week_start } = payload
      if (!worker_id || !week_start) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "worker_id and week_start are required")
      }

      // Calculate week_end (6 days after week_start)
      const startDate = new Date(week_start + "T00:00:00Z")
      const endDate = new Date(startDate)
      endDate.setUTCDate(endDate.getUTCDate() + 6)
      const weekEnd = endDate.toISOString().split("T")[0]

      // Fetch clock events for this worker in this week
      const { data: clockEvents } = await supabaseAdmin
        .from("clock_events")
        .select("id, event_subtype, occurred_at")
        .eq("company_id", userRecord.company_id)
        .eq("user_id", worker_id)
        .gte("occurred_at", `${week_start}T00:00:00Z`)
        .lte("occurred_at", `${weekEnd}T23:59:59Z`)
        .order("occurred_at", { ascending: true })

      // Compute hours from clock_in/clock_out pairs
      let totalMinutes = 0
      let lastClockIn: string | null = null

      for (const event of (clockEvents || [])) {
        if (event.event_subtype === "clock_in") {
          lastClockIn = event.occurred_at
        } else if (event.event_subtype === "clock_out" && lastClockIn) {
          const diff = new Date(event.occurred_at).getTime() - new Date(lastClockIn).getTime()
          totalMinutes += diff / 60000
          lastClockIn = null
        }
      }

      const totalHours = +(totalMinutes / 60).toFixed(2)
      const regularHours = +Math.min(totalHours, 40).toFixed(2)
      const otHours = +Math.max(totalHours - 40, 0).toFixed(2)

      // Upsert timecard
      const { data: existing } = await supabaseAdmin
        .from("timecard_signatures")
        .select("id")
        .eq("worker_id", worker_id)
        .eq("week_start", week_start)
        .maybeSingle()

      if (existing) {
        // Update existing
        const { error: updateError } = await supabaseAdmin
          .from("timecard_signatures")
          .update({
            total_regular_hours: regularHours,
            total_ot_hours: otHours,
            week_end: weekEnd,
          })
          .eq("id", existing.id)

        if (updateError) {
          logRequestError(ENDPOINT, requestId, updateError)
          return errorResponse(requestId, 500, "INTERNAL_ERROR", "Failed to update timecard")
        }

        logRequestResult(ENDPOINT, requestId, 200, { action: "generate", timecard_id: existing.id })
        return jsonResponse({
          status: "updated",
          timecard_id: existing.id,
          total_regular_hours: regularHours,
          total_ot_hours: otHours,
          request_id: requestId,
        }, 200, requestId)
      }

      // Create new
      const { data: inserted, error: insertError } = await supabaseAdmin
        .from("timecard_signatures")
        .insert({
          company_id: userRecord.company_id,
          worker_id,
          week_start,
          week_end: weekEnd,
          total_regular_hours: regularHours,
          total_ot_hours: otHours,
          status: "pending",
        })
        .select("id")
        .single()

      if (insertError) {
        logRequestError(ENDPOINT, requestId, insertError)
        return errorResponse(requestId, 500, "INTERNAL_ERROR", "Failed to create timecard")
      }

      logRequestResult(ENDPOINT, requestId, 201, { action: "generate", timecard_id: inserted.id })
      return jsonResponse({
        status: "created",
        timecard_id: inserted.id,
        total_regular_hours: regularHours,
        total_ot_hours: otHours,
        request_id: requestId,
      }, 201, requestId)
    }

    // ── Action: sign (worker signs their timecard) ──────────
    if (action === "sign") {
      const { timecard_id, signature } = payload

      if (!timecard_id || !signature) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "timecard_id and signature are required")
      }

      // Fetch the timecard — scope to the caller's company so a worker
      // from Company A cannot sign a timecard from Company B even if they
      // somehow learn the UUID.
      const { data: timecard } = await supabaseAdmin
        .from("timecard_signatures")
        .select("id, worker_id, status, company_id")
        .eq("id", timecard_id)
        .eq("company_id", userRecord.company_id)
        .maybeSingle()

      if (!timecard) {
        return errorResponse(requestId, 404, "NOT_FOUND", "Timecard not found")
      }

      if (timecard.worker_id !== user.id) {
        return errorResponse(requestId, 403, "FORBIDDEN", "Can only sign your own timecard")
      }

      if (timecard.status !== "pending") {
        return errorResponse(requestId, 409, "CONFLICT", `Timecard is already ${timecard.status}`)
      }

      const { error: signError } = await supabaseAdmin
        .from("timecard_signatures")
        .update({
          worker_signature: signature,
          worker_signed_at: new Date().toISOString(),
          status: "worker_signed",
        })
        .eq("id", timecard_id)

      if (signError) {
        logRequestError(ENDPOINT, requestId, signError)
        return errorResponse(requestId, 500, "INTERNAL_ERROR", "Failed to sign timecard")
      }

      logRequestResult(ENDPOINT, requestId, 200, { action: "sign", timecard_id })
      return jsonResponse({ status: "worker_signed", timecard_id, request_id: requestId }, 200, requestId)
    }

    // ── Action: countersign (supervisor approves) ───────────
    if (action === "countersign") {
      const { timecard_id, signature } = payload

      if (!timecard_id || !signature) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "timecard_id and signature are required")
      }

      if (!isSupervisorOrAbove(userRecord.role)) {
        return errorResponse(requestId, 403, "FORBIDDEN", "Only supervisors, admins, or owners can countersign timecards")
      }

      const { data: timecard } = await supabaseAdmin
        .from("timecard_signatures")
        .select("id, worker_id, status, company_id")
        .eq("id", timecard_id)
        .maybeSingle()

      if (!timecard) {
        return errorResponse(requestId, 404, "NOT_FOUND", "Timecard not found")
      }

      if (timecard.company_id !== userRecord.company_id) {
        return errorResponse(requestId, 403, "FORBIDDEN", "Timecard belongs to a different company")
      }

      if (timecard.status !== "worker_signed") {
        return errorResponse(requestId, 409, "CONFLICT", `Timecard must be worker_signed before countersigning (current: ${timecard.status})`)
      }

      if (timecard.worker_id === user.id) {
        return errorResponse(requestId, 403, "FORBIDDEN", "Cannot countersign your own timecard")
      }

      const { error: csError } = await supabaseAdmin
        .from("timecard_signatures")
        .update({
          supervisor_id: user.id,
          supervisor_signature: signature,
          supervisor_signed_at: new Date().toISOString(),
          status: "approved",
        })
        .eq("id", timecard_id)

      if (csError) {
        logRequestError(ENDPOINT, requestId, csError)
        return errorResponse(requestId, 500, "INTERNAL_ERROR", "Failed to countersign timecard")
      }

      logRequestResult(ENDPOINT, requestId, 200, { action: "countersign", timecard_id })
      return jsonResponse({ status: "approved", timecard_id, request_id: requestId }, 200, requestId)
    }

    return errorResponse(requestId, 400, "INVALID_PAYLOAD", "action must be 'generate', 'sign', or 'countersign'")
  } catch (error) {
    logRequestError(ENDPOINT, requestId, error)
    console.error("timecards error:", error)
    return errorResponse(requestId, 500, "INTERNAL_ERROR", error.message || "Internal server error")
  }
})
