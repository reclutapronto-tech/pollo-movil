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

const ENDPOINT = "shift_reports"
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

    // GET — list shift reports for a job
    if (req.method === "GET") {
      const url = new URL(req.url)
      const jobId = url.searchParams.get("job_id")

      let query = supabaseAdmin
        .from("shift_report_events")
        .select("*")
        .eq("company_id", userRecord.company_id)
        .order("report_date", { ascending: false })
        .limit(30)

      if (jobId) query = query.eq("job_id", jobId)

      const { data, error: fetchError } = await query
      if (fetchError) throw fetchError

      logRequestResult(ENDPOINT, requestId, 200, {
        user_id: user.id,
        result_count: (data || []).length,
      })
      return jsonResponse({ status: "success", reports: data || [], request_id: requestId }, 200, requestId)
    }

    // POST — create/update shift report
    if (req.method === "POST") {
      // Only foremen and supervisors can submit shift reports
      if (!["foreman", "supervisor", "admin"].includes(userRecord.role)) {
        return errorResponse(requestId, 403, "FORBIDDEN", "Only foremen, supervisors, or admins can submit shift reports")
      }

      const idempotencyKey = req.headers.get("Idempotency-Key")
      if (!idempotencyKey) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "Idempotency-Key required")
      }

      const payload = await req.json()
      const { job_id, report_date, headcount, summary, blocked_items, next_steps } = payload

      if (!job_id || !report_date) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "job_id and report_date are required")
      }

      const requestHash = await sha256Hex(JSON.stringify(payload))
      const replay = await lookupIdempotency(supabaseAdmin, user.id, ENDPOINT, idempotencyKey, requestHash)
      if (replay.replay) {
        if (replay.conflict) {
          return errorResponse(replay.requestId, 409, "CONFLICT", "Idempotency key reused")
        }
        return jsonResponse(replay.body, replay.status, replay.requestId)
      }

      const rateLimit = await applyRateLimit(supabaseAdmin, user.id, ENDPOINT, requestId, RATE_LIMIT)
      if (rateLimit.limited) {
        return errorResponse(requestId, 429, "RATE_LIMITED", "Too many requests", [], rateLimit.headers)
      }

      // Auto-populate stats from today's events
      const { data: clockCount } = await supabaseAdmin
        .from("clock_events")
        .select("user_id", { count: "exact", head: true })
        .eq("job_id", job_id)
        .eq("company_id", userRecord.company_id)
        .eq("event_subtype", "clock_in")
        .gte("occurred_at", `${report_date}T00:00:00Z`)
        .lte("occurred_at", `${report_date}T23:59:59Z`)

      const { data: photoCount } = await supabaseAdmin
        .from("photo_events")
        .select("id", { count: "exact", head: true })
        .eq("job_id", job_id)
        .eq("company_id", userRecord.company_id)
        .gte("occurred_at", `${report_date}T00:00:00Z`)
        .lte("occurred_at", `${report_date}T23:59:59Z`)

      const { data: tasksDone } = await supabaseAdmin
        .from("task_events")
        .select("id", { count: "exact", head: true })
        .eq("job_id", job_id)
        .eq("company_id", userRecord.company_id)
        .eq("to_status", "completed")
        .gte("occurred_at", `${report_date}T00:00:00Z`)
        .lte("occurred_at", `${report_date}T23:59:59Z`)

      const reportId = crypto.randomUUID()
      const now = new Date().toISOString()

      const { error: insertError } = await supabaseAdmin
        .from("shift_report_events")
        .upsert({
          id: reportId,
          company_id: userRecord.company_id,
          job_id,
          foreman_id: user.id,
          report_date,
          headcount: headcount || 0,
          summary: summary || null,
          blocked_items: blocked_items || null,
          next_steps: next_steps || null,
          occurred_at: now,
          metadata: {
            auto_stats: {
              clock_ins: clockCount || 0,
              photos: photoCount || 0,
              tasks_completed: tasksDone || 0,
            },
            submitted_by: userRecord.full_name,
          },
        }, { onConflict: "job_id,report_date,foreman_id" })

      if (insertError) throw insertError

      const responseBody = {
        status: "success",
        report_id: reportId,
        report_date,
        request_id: requestId,
      }

      await storeIdempotency(supabaseAdmin, user.id, ENDPOINT, idempotencyKey, requestHash, 201, responseBody, requestId)
      logRequestResult(ENDPOINT, requestId, 201, {
        user_id: user.id,
        report_id: reportId,
        report_date,
      })
      return jsonResponse(responseBody, 201, requestId, rateLimit.headers)
    }

    return errorResponse(requestId, 405, "METHOD_NOT_ALLOWED", "Use GET or POST")
  } catch (error) {
    logRequestError(ENDPOINT, requestId, error)
    console.error("shift_reports error:", error)
    return errorResponse(requestId, 500, "INTERNAL_ERROR", error.message || "Internal server error")
  }
})
