import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.4"
import {
  CORS_HEADERS,
  corsHeaders,
  errorResponse,
  jsonResponse,
  logRequestError,
  logRequestResult,
  logRequestStart,
  makeRequestId,
} from "../_shared/api.ts"

const ENDPOINT = "worker_history"

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders(req) })
  }

  const requestId = makeRequestId(req)
  logRequestStart(ENDPOINT, requestId, req)

  try {
    if (req.method !== "POST") {
      return errorResponse(requestId, 405, "METHOD_NOT_ALLOWED", "Use POST for /worker_history")
    }

    const authHeader = req.headers.get("Authorization")
    if (!authHeader) {
      return errorResponse(requestId, 401, "UNAUTHORIZED", "Missing Authorization header")
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") || ""
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") || ""
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || ""

    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    })
    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey)

    const jwt = authHeader.replace("Bearer ", "")
    const { data: { user }, error: authError } = await supabase.auth.getUser()
    if (authError || !user) {
      return errorResponse(requestId, 401, "UNAUTHORIZED", "Invalid auth token")
    }

    const { data: userRecord, error: userError } = await supabaseAdmin
      .from("users")
      .select("id, is_active")
      .eq("id", user.id)
      .single()

    if (userError || !userRecord) {
      return errorResponse(requestId, 401, "UNAUTHORIZED", "User record not found")
    }
    if (!userRecord.is_active) {
      return errorResponse(requestId, 403, "FORBIDDEN", "User is inactive")
    }

    const body = await req.json().catch(() => ({}))
    const action = body?.action ?? "list"
    const limit = Math.min(Number(body?.limit ?? 50), 200)

    if (action === "list") {
      // Fetch recent timecards (clock_in/clock_out pairs) for this worker
      const { data: events, error: eventsError } = await supabaseAdmin
        .from("clock_events")
        .select("id, job_id, event_subtype, occurred_at, jobs(name, code)")
        .eq("user_id", user.id)
        .in("event_subtype", ["clock_in", "clock_out"])
        .order("occurred_at", { ascending: false })
        .limit(limit * 2) // fetch double to pair in/out

      if (eventsError) throw eventsError

      // Pair clock_in/clock_out into history entries
      const entries: Array<Record<string, unknown>> = []
      const opens = new Map<string, Record<string, unknown>>()

      for (const e of (events || []).reverse()) {
        const evt = e as Record<string, unknown>
        if (evt.event_subtype === "clock_in") {
          opens.set(evt.job_id as string, evt)
        } else if (evt.event_subtype === "clock_out") {
          const open = opens.get(evt.job_id as string)
          if (open) {
            const startMs = new Date(open.occurred_at as string).getTime()
            const endMs = new Date(evt.occurred_at as string).getTime()
            const hours = (endMs - startMs) / 3600000
            const job = evt.jobs as Record<string, unknown> | null
            entries.push({
              id: evt.id,
              job_id: evt.job_id,
              job_name: job?.name ?? "Unknown job",
              job_code: job?.code ?? null,
              clock_in: open.occurred_at,
              clock_out: evt.occurred_at,
              hours: Math.round(hours * 100) / 100,
              date: (open.occurred_at as string).slice(0, 10),
            })
            opens.delete(evt.job_id as string)
          }
        }
      }

      // Most recent first, limited
      const result = entries.reverse().slice(0, limit)

      logRequestResult(ENDPOINT, requestId, 200, { user_id: user.id, count: result.length })
      return jsonResponse({ entries: result as any, request_id: requestId }, 200, requestId)
    }

    if (action === "summary") {
      const from = body?.from ? new Date(body.from as string) : new Date(Date.now() - 30 * 86400000)
      const to = body?.to ? new Date(body.to as string) : new Date()

      const { data: events, error: eventsError } = await supabaseAdmin
        .from("clock_events")
        .select("job_id, event_subtype, occurred_at")
        .eq("user_id", user.id)
        .gte("occurred_at", from.toISOString())
        .lte("occurred_at", to.toISOString())
        .order("occurred_at", { ascending: true })

      if (eventsError) throw eventsError

      let totalHours = 0
      let openIn: Date | null = null
      const jobSet = new Set<string>()

      for (const e of (events || [])) {
        const evt = e as Record<string, unknown>
        if (evt.event_subtype === "clock_in") {
          openIn = new Date(evt.occurred_at as string)
          jobSet.add(evt.job_id as string)
        } else if (evt.event_subtype === "clock_out" && openIn) {
          const hrs = (new Date(evt.occurred_at as string).getTime() - openIn.getTime()) / 3600000
          totalHours += hrs
          openIn = null
        }
      }

      // Fetch media and task counts
      const [{ count: photoCount }, { count: taskCount }] = await Promise.all([
        supabaseAdmin
          .from("media_assets")
          .select("*", { count: "exact", head: true })
          .eq("uploaded_by", user.id)
          .gte("created_at", from.toISOString())
          .lte("created_at", to.toISOString()),
        supabaseAdmin
          .from("tasks")
          .select("*", { count: "exact", head: true })
          .eq("completed_by", user.id)
          .gte("completed_at", from.toISOString())
          .lte("completed_at", to.toISOString()),
      ])

      // Assume regular = up to 8h/day * work days, OT = beyond
      const days = Math.ceil((to.getTime() - from.getTime()) / 86400000)
      const regularCap = days * 8
      const regularHours = Math.min(totalHours, regularCap)
      const otHours = Math.max(0, totalHours - regularCap)

      logRequestResult(ENDPOINT, requestId, 200, { user_id: user.id })
      return jsonResponse({
        total_hours: Math.round(totalHours * 100) / 100,
        regular_hours: Math.round(regularHours * 100) / 100,
        ot_hours: Math.round(otHours * 100) / 100,
        total_jobs: jobSet.size,
        total_photos: photoCount ?? 0,
        total_tasks: taskCount ?? 0,
        request_id: requestId,
      }, 200, requestId)
    }

    return errorResponse(requestId, 400, "INVALID_PAYLOAD", "Unknown action. Use 'list' or 'summary'.")
  } catch (error) {
    logRequestError(ENDPOINT, requestId, error)
    return errorResponse(requestId, 500, "INTERNAL_ERROR", (error as Error).message || "Internal server error")
  }
})
