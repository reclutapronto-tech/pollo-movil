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

const ENDPOINT = "safety"
const SAFETY_RATE_LIMIT = 30

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

function isUuid(value: unknown): value is string {
  return typeof value === "string" && UUID_RE.test(value)
}

// Compute start-of-today in UTC as an ISO string (e.g. "2026-04-19T00:00:00Z").
// Mirrors the mobile contract: new Date().toISOString().slice(0,10) + 'T00:00:00Z'.
function startOfTodayUtcIso(): string {
  return new Date().toISOString().slice(0, 10) + "T00:00:00Z"
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
    const rateLimit = await applyRateLimit(supabaseAdmin, user.id, ENDPOINT, requestId, SAFETY_RATE_LIMIT, 60)
    if (rateLimit.limited) {
      logRequestResult(ENDPOINT, requestId, 429, { reason: "rate_limited" })
      return errorResponse(requestId, 429, "RATE_LIMITED", "Too many requests", [], rateLimit.headers)
    }

    // ─── POST only ────────────────────────────────────────
    if (req.method !== "POST") {
      return errorResponse(requestId, 405, "METHOD_NOT_ALLOWED", "Use POST")
    }

    const payload = await req.json()
    const { action } = payload

    // ── Action: check (read-only — has this user completed today for this job?) ──
    if (action === "check") {
      const { job_id } = payload

      if (!isUuid(job_id)) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "job_id must be a uuid")
      }

      const todayUtc = startOfTodayUtcIso()

      const { data: existing, error: checkError } = await supabaseAdmin
        .from("safety_checklists")
        .select("id")
        .eq("user_id", user.id)
        .eq("job_id", job_id)
        .gte("completed_at", todayUtc)
        .limit(1)
        .maybeSingle()

      if (checkError) {
        logRequestError(ENDPOINT, requestId, checkError)
        return errorResponse(requestId, 500, "INTERNAL_ERROR", "Failed to check safety checklist")
      }

      const completed = !!existing
      logRequestResult(ENDPOINT, requestId, 200, { user_id: user.id, job_id, action: "check", completed })
      return jsonResponse({ completed, request_id: requestId }, 200, requestId)
    }

    // ── Action: submit (write — requires Idempotency-Key) ──
    if (action === "submit") {
      const { job_id, responses } = payload

      if (!isUuid(job_id)) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "job_id must be a uuid")
      }

      if (!Array.isArray(responses) || responses.length === 0) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "responses must be a non-empty array")
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

      // Confirm the job belongs to the caller's company.
      const { data: job, error: jobError } = await supabaseAdmin
        .from("jobs")
        .select("id, company_id")
        .eq("id", job_id)
        .maybeSingle()

      if (jobError) {
        logRequestError(ENDPOINT, requestId, jobError)
        return errorResponse(requestId, 500, "INTERNAL_ERROR", "Failed to load job")
      }

      if (!job) {
        return errorResponse(requestId, 404, "NOT_FOUND", "Job not found")
      }

      if (job.company_id !== userRecord.company_id) {
        return errorResponse(requestId, 403, "FORBIDDEN", "Job does not belong to your company")
      }

      const { data: inserted, error: insertError } = await supabaseAdmin
        .from("safety_checklists")
        .insert({
          company_id: userRecord.company_id,
          user_id: user.id,
          job_id,
          responses,
        })
        .select("id")
        .single()

      if (insertError) {
        logRequestError(ENDPOINT, requestId, insertError)
        return errorResponse(requestId, 500, "INTERNAL_ERROR", "Failed to submit safety checklist")
      }

      const responseBody = {
        status: "submitted",
        checklist_id: inserted.id,
        request_id: requestId,
      }

      await storeIdempotency(supabaseAdmin, user.id, ENDPOINT, idempotencyKey, requestHash, 201, responseBody, requestId)
      logRequestResult(ENDPOINT, requestId, 201, {
        user_id: user.id,
        job_id,
        checklist_id: inserted.id,
        action: "submit",
      })
      return jsonResponse(responseBody, 201, requestId)
    }

    return errorResponse(requestId, 400, "INVALID_PAYLOAD", "action must be 'submit' or 'check'")
  } catch (error) {
    logRequestError(ENDPOINT, requestId, error)
    console.error("safety error:", error)
    return errorResponse(requestId, 500, "INTERNAL_ERROR", error.message || "Internal server error")
  }
})
