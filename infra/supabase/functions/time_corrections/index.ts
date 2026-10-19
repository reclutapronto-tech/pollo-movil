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

const ENDPOINT = "time_corrections"
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

    // GET — list time corrections
    if (req.method === "GET") {
      const url = new URL(req.url)
      const workerId = url.searchParams.get("worker_id")
      const jobId = url.searchParams.get("job_id")
      const status = url.searchParams.get("status") || "pending"

      let query = supabaseAdmin
        .from("time_correction_summary")
        .select("*")
        .eq("company_id", userRecord.company_id)
        .eq("status", status)
        .order("created_at", { ascending: false })
        .limit(50)

      if (workerId) query = query.eq("worker_id", workerId)
      if (jobId) query = query.eq("job_id", jobId)

      // Workers only see their own corrections
      if (userRecord.role === "worker") {
        query = query.eq("worker_id", user.id)
      }

      const { data, error } = await query
      if (error) throw error

      logRequestResult(ENDPOINT, requestId, 200, { count: (data || []).length })
      return jsonResponse({ status: "success", corrections: data || [], request_id: requestId }, 200, requestId)
    }

    // POST — create or decide on correction
    if (req.method === "POST") {
      const idempotencyKey = req.headers.get("Idempotency-Key")
      if (!idempotencyKey) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "Idempotency-Key required")
      }

      const payload = await req.json()
      const { action } = payload

      const requestHash = await sha256Hex(JSON.stringify(payload))
      const replay = await lookupIdempotency(supabaseAdmin, user.id, ENDPOINT, idempotencyKey, requestHash)
      if (replay.replay) {
        if (replay.conflict) return errorResponse(replay.requestId, 409, "CONFLICT", "Idempotency key reused")
        return jsonResponse(replay.body, replay.status, replay.requestId)
      }

      const rateLimit = await applyRateLimit(supabaseAdmin, user.id, ENDPOINT, requestId, RATE_LIMIT)
      if (rateLimit.limited) {
        return errorResponse(requestId, 429, "RATE_LIMITED", "Too many requests", [], rateLimit.headers)
      }

      // Create correction request
      if (action === "create") {
        const {
          worker_id,
          job_id,
          original_event_id,
          original_event_subtype,
          original_occurred_at,
          corrected_event_subtype,
          corrected_occurred_at,
          reason,
          evidence_notes,
        } = payload

        if (!worker_id || !job_id || !corrected_event_subtype || !corrected_occurred_at || !reason) {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD",
            "worker_id, job_id, corrected_event_subtype, corrected_occurred_at, and reason required")
        }

        // Only supervisors/admins/foremen can create corrections
        if (!["supervisor", "admin", "foreman"].includes(userRecord.role)) {
          return errorResponse(requestId, 403, "FORBIDDEN", "Only supervisors can create time corrections")
        }

        // Verify worker exists and belongs to company
        const { data: worker } = await supabase
          .from("users")
          .select("id")
          .eq("id", worker_id)
          .eq("company_id", userRecord.company_id)
          .maybeSingle()

        if (!worker) {
          return errorResponse(requestId, 404, "NOT_FOUND", "Worker not found")
        }

        // Verify job exists
        const { data: job } = await supabase
          .from("jobs")
          .select("id")
          .eq("id", job_id)
          .eq("company_id", userRecord.company_id)
          .maybeSingle()

        if (!job) {
          return errorResponse(requestId, 404, "NOT_FOUND", "Job not found")
        }

        // If original event provided, verify it exists AND belongs to this worker/company
        if (original_event_id) {
          const { data: originalEvent } = await supabase
            .from("clock_events")
            .select("id, event_subtype, occurred_at")
            .eq("id", original_event_id)
            .eq("company_id", userRecord.company_id)
            .eq("user_id", worker_id)
            .maybeSingle()

          if (!originalEvent) {
            return errorResponse(requestId, 404, "NOT_FOUND", "Original event not found")
          }
        }

        const correctionId = crypto.randomUUID()
        const now = new Date().toISOString()

        const { error: insertError } = await supabaseAdmin
          .from("time_corrections")
          .insert({
            id: correctionId,
            company_id: userRecord.company_id,
            worker_id,
            job_id,
            original_event_id: original_event_id || null,
            original_event_subtype: original_event_subtype || null,
            original_occurred_at: original_occurred_at || null,
            corrected_event_subtype,
            corrected_occurred_at,
            reason,
            evidence_notes: evidence_notes || null,
            created_by: user.id,
            created_at: now,
            status: "pending",
          })

        if (insertError) throw insertError

        const responseBody = { status: "success", correction_id: correctionId, request_id: requestId }
        await storeIdempotency(supabaseAdmin, user.id, ENDPOINT, idempotencyKey, requestHash, 201, responseBody, requestId)
        logRequestResult(ENDPOINT, requestId, 201, { action: "create", correction_id: correctionId })
        return jsonResponse(responseBody, 201, requestId, rateLimit.headers)
      }

      // Approve or deny correction
      if (action === "decide") {
        const { correction_id, decision, decision_reason } = payload

        if (!correction_id || !decision || !["approved", "denied"].includes(decision)) {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD",
            "correction_id and decision (approved/denied) required")
        }

        // Only supervisors/admins can approve
        if (!isForemanOrAbove(userRecord.role)) {
          return errorResponse(requestId, 403, "FORBIDDEN", "Only foremen, supervisors, admins, or owners can approve corrections")
        }

        // Get correction details
        const { data: correction, error: fetchError } = await supabaseAdmin
          .from("time_corrections")
          .select("*")
          .eq("id", correction_id)
          .eq("company_id", userRecord.company_id)
          .eq("status", "pending")
          .maybeSingle()

        if (fetchError) throw fetchError
        if (!correction) {
          return errorResponse(requestId, 404, "NOT_FOUND", "Correction not found or already decided")
        }

        const now = new Date().toISOString()
        let resultingEventId: string | null = null

        // If approved, create the corrected clock event
        if (decision === "approved") {
          const eventId = crypto.randomUUID()

          const { error: eventError } = await supabaseAdmin
            .from("clock_events")
            .insert({
              id: eventId,
              company_id: userRecord.company_id,
              user_id: correction.worker_id,
              job_id: correction.job_id,
              event_subtype: correction.corrected_event_subtype,
              occurred_at: correction.corrected_occurred_at,
              notes: `Manual time correction by ${userRecord.full_name}. Reason: ${correction.reason}`,
              // clock_events has no is_correction/correction_id/created_by columns —
              // persist the correction linkage via source_event_uuid + metadata.
              source_event_uuid: correction_id,
              metadata: { is_correction: true, correction_id, created_by: user.id },
            })

          if (eventError) throw eventError
          resultingEventId = eventId
        }

        // Update correction status
        const { error: updateError } = await supabaseAdmin
          .from("time_corrections")
          .update({
            status: decision,
            decided_by: user.id,
            decided_at: now,
            decision_reason: decision_reason || null,
            resulting_event_id: resultingEventId,
          })
          .eq("id", correction_id)
          .eq("company_id", userRecord.company_id)

        if (updateError) throw updateError

        const responseBody = {
          status: "success",
          correction_id,
          decision,
          resulting_event_id: resultingEventId,
          request_id: requestId,
        }
        await storeIdempotency(supabaseAdmin, user.id, ENDPOINT, idempotencyKey, requestHash, 200, responseBody, requestId)
        logRequestResult(ENDPOINT, requestId, 200, { action: "decide", correction_id, decision })
        return jsonResponse(responseBody, 200, requestId, rateLimit.headers)
      }

      return errorResponse(requestId, 400, "INVALID_PAYLOAD", "action must be 'create' or 'decide'")
    }

    return errorResponse(requestId, 405, "METHOD_NOT_ALLOWED", "Use GET or POST")
  } catch (error) {
    logRequestError(ENDPOINT, requestId, error)
    return errorResponse(
      requestId,
      500,
      "INTERNAL_ERROR",
      error instanceof Error ? error.message : "Internal server error",
    )
  }
})
