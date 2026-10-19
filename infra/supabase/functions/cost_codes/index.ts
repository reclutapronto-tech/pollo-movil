import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.4"
import {
  corsHeaders,
  errorResponse,
  jsonResponse,
  logRequestError,
  logRequestResult,
  logRequestStart,
  makeRequestId,
} from "../_shared/api.ts"

/**
 * Cost codes management + job profitability.
 *
 * GET /cost_codes — List cost codes for the company
 * GET /cost_codes?job_id=X&report=profitability — Job profitability breakdown
 * POST /cost_codes — Create/update cost codes
 *
 * Workers select a cost code at clock-in via task_classification field on clock_events.
 * This endpoint manages the available codes and reports labor allocation.
 */
serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders(req) })
  }

  const requestId = makeRequestId(req)
  logRequestStart("cost_codes", requestId, req)

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
      .select("id, company_id, role, is_active")
      .eq("id", user.id)
      .single()

    if (!userRecord?.is_active) {
      return errorResponse(requestId, 403, "FORBIDDEN", "User is inactive")
    }

    if (req.method === "GET") {
      const url = new URL(req.url)
      const jobId = url.searchParams.get("job_id")
      const report = url.searchParams.get("report")

      // Profitability report: hours per cost code for a job
      if (report === "profitability" && jobId) {
        const { data: events } = await supabaseAdmin
          .from("clock_events")
          .select("id, user_id, task_classification, event_subtype, occurred_at, users!clock_events_user_id_fkey(full_name)")
          .eq("job_id", jobId)
          .eq("company_id", userRecord.company_id)
          .order("occurred_at", { ascending: true })

        // Pair clock_in/clock_out and sum hours per cost code
        const codeHours: Record<string, { hours: number; workers: Set<string> }> = {}
        const openSessions: Record<string, { code: string; time: number }> = {}

        for (const e of events || []) {
          const uid = e.user_id as string
          const code = (e.task_classification as string) || "unclassified"

          if (e.event_subtype === "clock_in") {
            openSessions[uid] = { code, time: new Date(e.occurred_at as string).getTime() }
          } else if (e.event_subtype === "clock_out" && openSessions[uid]) {
            const session = openSessions[uid]
            const hours = (new Date(e.occurred_at as string).getTime() - session.time) / 3600000
            if (!codeHours[session.code]) {
              codeHours[session.code] = { hours: 0, workers: new Set() }
            }
            codeHours[session.code].hours += hours
            codeHours[session.code].workers.add(uid)
            delete openSessions[uid]
          }
        }

        const breakdown = Object.entries(codeHours).map(([code, data]) => ({
          cost_code: code,
          total_hours: +data.hours.toFixed(2),
          worker_count: data.workers.size,
        }))

        logRequestResult("cost_codes", requestId, 200, {
          user_id: user.id,
          report: "profitability",
          job_id: jobId,
          result_count: breakdown.length,
        })
        return jsonResponse({
          status: "success",
          job_id: jobId,
          breakdown,
          total_hours: +breakdown.reduce((s, b) => s + b.total_hours, 0).toFixed(2),
          request_id: requestId,
        }, 200, requestId)
      }

      // List company cost codes (from unique task_classification values)
      const { data: codes } = await supabaseAdmin
        .from("clock_events")
        .select("task_classification")
        .eq("company_id", userRecord.company_id)
        .not("task_classification", "is", null)

      const uniqueCodes = [...new Set((codes || []).map((c: any) => c.task_classification).filter(Boolean))]

      logRequestResult("cost_codes", requestId, 200, {
        user_id: user.id,
        result_count: uniqueCodes.length,
      })
      return jsonResponse({
        status: "success",
        cost_codes: uniqueCodes,
        request_id: requestId,
      }, 200, requestId)
    }

    return errorResponse(requestId, 405, "METHOD_NOT_ALLOWED", "Use GET for /cost_codes")
  } catch (error) {
    logRequestError("cost_codes", requestId, error)
    return errorResponse(requestId, 500, "INTERNAL_ERROR", error.message || "Internal server error")
  }
})
