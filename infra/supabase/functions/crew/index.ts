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
import { FOREMAN_ROLE, isForemanOrAbove, WORKER_ROLE } from "../_shared/roles.ts"

const ENDPOINT = "crew"
const CREW_RATE_LIMIT = 60

type ClockSubtype = "clock_in" | "clock_out" | "break_start" | "break_end"
type AttendanceStatus = "clocked_in" | "on_break" | "late" | "absent"

interface ClockEventRow {
  user_id: string
  event_subtype: ClockSubtype
  occurred_at: string
  job_id: string | null
}

interface ScheduleShiftRow {
  worker_id: string
  start_time: string // "HH:MM:SS"
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders(req) })
  }

  const requestId = makeRequestId(req)
  logRequestStart(ENDPOINT, requestId, req)

  try {
    if (req.method !== "POST") {
      return errorResponse(requestId, 405, "METHOD_NOT_ALLOWED", "Use POST for /crew")
    }

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
      .select("id, company_id, role, is_active")
      .eq("id", user.id)
      .single()

    if (!userRecord) {
      return errorResponse(requestId, 401, "UNAUTHORIZED", "User record not found")
    }
    if (!userRecord.is_active) {
      return errorResponse(requestId, 403, "FORBIDDEN", "User is inactive")
    }
    if (!isForemanOrAbove(userRecord.role)) {
      return errorResponse(requestId, 403, "FORBIDDEN", "Only foreman, supervisor, admin, or owner can view crew attendance")
    }

    // Rate limit
    const rateLimit = await applyRateLimit(supabaseAdmin, user.id, ENDPOINT, requestId, CREW_RATE_LIMIT, 60)
    if (rateLimit.limited) {
      logRequestResult(ENDPOINT, requestId, 429, { reason: "rate_limited" })
      return errorResponse(requestId, 429, "RATE_LIMITED", "Too many requests", [], rateLimit.headers)
    }

    const payload = await req.json().catch(() => ({}))
    const { action } = payload ?? {}

    if (action !== "attendance") {
      return errorResponse(requestId, 400, "INVALID_PAYLOAD", "action must be 'attendance'")
    }

    // Jobs without a foreman assignment are intentionally supported — their workers simply
    // do not appear in any foreman's /crew view. Supervisors see the full roster via a separate branch.
    let targetWorkerIds: string[] = []

    if (userRecord.role === FOREMAN_ROLE) {
      // Find jobs this foreman is actively assigned to.
      const { data: foremanAssignments, error: foremanAssignmentsError } = await supabaseAdmin
        .from("assignments")
        .select("job_id")
        .eq("company_id", userRecord.company_id)
        .eq("user_id", user.id)
        .eq("assigned_role", FOREMAN_ROLE)
        .eq("is_active", true)

      if (foremanAssignmentsError) {
        logRequestError(ENDPOINT, requestId, foremanAssignmentsError)
        return errorResponse(requestId, 500, "INTERNAL_ERROR", "Failed to fetch foreman assignments")
      }

      const foremanJobIds = Array.from(
        new Set(((foremanAssignments || []) as { job_id: string }[]).map((a) => a.job_id)),
      )

      if (foremanJobIds.length === 0) {
        logRequestResult(ENDPOINT, requestId, 200, { user_id: user.id, count: 0, scope: "foreman_no_jobs" })
        return jsonResponse({ crew: [], request_id: requestId }, 200, requestId)
      }

      // Workers actively assigned to any of those jobs.
      const { data: workerAssignments, error: workerAssignmentsError } = await supabaseAdmin
        .from("assignments")
        .select("user_id")
        .eq("company_id", userRecord.company_id)
        .eq("assigned_role", WORKER_ROLE)
        .eq("is_active", true)
        .in("job_id", foremanJobIds)

      if (workerAssignmentsError) {
        logRequestError(ENDPOINT, requestId, workerAssignmentsError)
        return errorResponse(requestId, 500, "INTERNAL_ERROR", "Failed to fetch crew assignments")
      }

      targetWorkerIds = Array.from(
        new Set(((workerAssignments || []) as { user_id: string }[]).map((a) => a.user_id)),
      )

      if (targetWorkerIds.length === 0) {
        logRequestResult(ENDPOINT, requestId, 200, { user_id: user.id, count: 0, scope: "foreman_no_workers" })
        return jsonResponse({ crew: [], request_id: requestId }, 200, requestId)
      }
    }

    // Supervisor / admin / owner branch (and foreman filter above converges here):
    // fetch user rows for the resolved crew. Foreman path constrains by id; the
    // higher-privilege path returns every active worker in the company.
    const workersQuery = supabaseAdmin
      .from("users")
      .select("id, full_name, avatar_url")
      .eq("company_id", userRecord.company_id)
      .eq("role", WORKER_ROLE)
      .eq("is_active", true)

    const { data: workers, error: workersError } = userRecord.role === FOREMAN_ROLE
      ? await workersQuery.in("id", targetWorkerIds)
      : await workersQuery

    if (workersError) {
      logRequestError(ENDPOINT, requestId, workersError)
      return errorResponse(requestId, 500, "INTERNAL_ERROR", "Failed to fetch crew workers")
    }

    if (!workers || workers.length === 0) {
      logRequestResult(ENDPOINT, requestId, 200, { user_id: user.id, count: 0 })
      return jsonResponse({ crew: [], request_id: requestId }, 200, requestId)
    }

    const workerIds = workers.map((w: { id: string }) => w.id)

    // Today's UTC window
    const now = new Date()
    const todayStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()))
    const todayStartIso = todayStart.toISOString()
    const todayDateStr = todayStartIso.slice(0, 10) // YYYY-MM-DD for schedule_shifts.shift_date

    // Single batch fetch of today's clock events for all target workers
    const { data: events, error: eventsError } = await supabaseAdmin
      .from("clock_events")
      .select("user_id, event_subtype, occurred_at, job_id")
      .in("user_id", workerIds)
      .gte("occurred_at", todayStartIso)
      .lte("occurred_at", now.toISOString())
      .order("occurred_at", { ascending: false })

    if (eventsError) {
      logRequestError(ENDPOINT, requestId, eventsError)
      return errorResponse(requestId, 500, "INTERNAL_ERROR", "Failed to fetch clock events")
    }

    // Group events by user_id (already sorted DESC, so first is latest)
    const eventsByUser = new Map<string, ClockEventRow[]>()
    for (const evt of (events || []) as ClockEventRow[]) {
      const arr = eventsByUser.get(evt.user_id) ?? []
      arr.push(evt)
      eventsByUser.set(evt.user_id, arr)
    }

    // Fetch today's scheduled shifts for late-vs-absent disambiguation
    const { data: shifts, error: shiftsError } = await supabaseAdmin
      .from("schedule_shifts")
      .select("worker_id, start_time")
      .eq("company_id", userRecord.company_id)
      .eq("shift_date", todayDateStr)
      .eq("status", "published")
      .in("worker_id", workerIds)

    if (shiftsError) {
      logRequestError(ENDPOINT, requestId, shiftsError)
      return errorResponse(requestId, 500, "INTERNAL_ERROR", "Failed to fetch scheduled shifts")
    }

    // Earliest scheduled start_time per worker today (UTC treatment — shift_date + start_time)
    const shiftStartByUser = new Map<string, Date>()
    for (const s of (shifts || []) as ScheduleShiftRow[]) {
      const startIso = `${todayDateStr}T${s.start_time}Z`
      const startDate = new Date(startIso)
      const existing = shiftStartByUser.get(s.worker_id)
      if (!existing || startDate < existing) {
        shiftStartByUser.set(s.worker_id, startDate)
      }
    }

    // Collect job ids referenced by latest events for one batched jobs lookup
    const jobIdsToResolve = new Set<string>()
    for (const [, evts] of eventsByUser) {
      const latest = evts[0]
      if (latest?.job_id) jobIdsToResolve.add(latest.job_id)
    }

    let jobNameById = new Map<string, string>()
    if (jobIdsToResolve.size > 0) {
      const { data: jobs, error: jobsError } = await supabaseAdmin
        .from("jobs")
        .select("id, name")
        .eq("company_id", userRecord.company_id)
        .in("id", Array.from(jobIdsToResolve))

      if (jobsError) {
        logRequestError(ENDPOINT, requestId, jobsError)
        return errorResponse(requestId, 500, "INTERNAL_ERROR", "Failed to fetch job names")
      }

      jobNameById = new Map((jobs || []).map((j: { id: string; name: string }) => [j.id, j.name]))
    }

    // Derive per-worker status + payload
    const crew = workers.map((w: { id: string; full_name: string | null; avatar_url: string | null }) => {
      const evts = eventsByUser.get(w.id) ?? []
      const latest = evts[0]

      // Most recent clock_in today (used for `clocked_in_at`)
      const lastClockIn = evts.find((e) => e.event_subtype === "clock_in") ?? null

      let status: AttendanceStatus
      let jobId: string | null = null

      if (!latest) {
        const shiftStart = shiftStartByUser.get(w.id)
        if (shiftStart && shiftStart.getTime() <= now.getTime()) {
          status = "late"
        } else {
          status = "absent"
        }
      } else {
        jobId = latest.job_id
        switch (latest.event_subtype) {
          case "clock_in":
            status = "clocked_in"
            break
          case "break_end":
            // Resumed work after a break — treat as clocked in
            status = "clocked_in"
            break
          case "break_start":
            status = "on_break"
            break
          case "clock_out":
            status = "late"
            break
          default:
            status = "absent"
        }
      }

      return {
        worker_id: w.id,
        worker_name: w.full_name ?? "",
        status,
        job_name: jobId ? (jobNameById.get(jobId) ?? null) : null,
        clocked_in_at: lastClockIn?.occurred_at ?? null,
        avatar_url: w.avatar_url ?? null,
      }
    })

    logRequestResult(ENDPOINT, requestId, 200, {
      user_id: user.id,
      count: crew.length,
      action: "attendance",
    })
    return jsonResponse({ crew, request_id: requestId }, 200, requestId)
  } catch (error) {
    logRequestError(ENDPOINT, requestId, error)
    console.error("crew error:", error)
    return errorResponse(requestId, 500, "INTERNAL_ERROR", (error as Error).message || "Internal server error")
  }
})
