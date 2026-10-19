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

type ClockEventRow = {
  job_id: string
  event_subtype: string
  occurred_at: string
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders(req) })
  }

  const requestId = makeRequestId(req)
  const endpoint = "worker_hours"

  try {
    if (req.method !== "GET") {
      return errorResponse(requestId, 405, "METHOD_NOT_ALLOWED", "Use GET for /worker_hours")
    }

    const authHeader = req.headers.get("Authorization")
    if (!authHeader) {
      return errorResponse(requestId, 401, "UNAUTHORIZED", "Missing Authorization header")
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") || ""
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") || ""
    const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || ""

    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    })
    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceRoleKey)

    const jwt = authHeader.replace("Bearer ", "")
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser()
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

    const rateLimit = await applyRateLimit(supabaseAdmin, user.id, endpoint, requestId, 30)
    if (rateLimit.limited) {
      return errorResponse(
        requestId,
        429,
        "RATE_LIMITED",
        "Too many worker hour requests. Please retry shortly.",
        [],
        rateLimit.headers,
      )
    }

    logRequestStart(endpoint, requestId, req, { user_id: user.id })

    const now = new Date()
    const monthStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1))

    const { data: events, error: eventsError } = await supabaseAdmin
      .from("clock_events")
      .select("job_id, event_subtype, occurred_at")
      .eq("user_id", user.id)
      .gte("occurred_at", monthStart.toISOString())
      .order("occurred_at", { ascending: true })

    if (eventsError) {
      throw eventsError
    }

    const totals = computeHoursSummary((events || []) as ClockEventRow[], now)

    const body = {
      status: "success",
      summary: totals,
      fetched_at: now.toISOString(),
      request_id: requestId,
    }
    logRequestResult(endpoint, requestId, 200, { user_id: user.id })
    return jsonResponse(body, 200, requestId, rateLimit.headers)
  } catch (error) {
    logRequestError(endpoint, requestId, error)
    return errorResponse(requestId, 500, "INTERNAL_ERROR", error.message || "Internal server error")
  }
})

function computeHoursSummary(events: ClockEventRow[], now: Date) {
  const startOfToday = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()))
  const currentDay = now.getUTCDay()
  const daysSinceMonday = currentDay === 0 ? 6 : currentDay - 1
  const startOfWeek = new Date(startOfToday)
  startOfWeek.setUTCDate(startOfWeek.getUTCDate() - daysSinceMonday)
  const startOfMonth = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1))

  let openSessionStart: Date | null = null
  let breakStartedAt: Date | null = null
  let sessionWorkedMinutes = 0

  let todayMinutes = 0
  let weekMinutes = 0
  let monthMinutes = 0

  const closeActiveSegment = (segmentEnd: Date) => {
    if (!openSessionStart) {
      return
    }
    const startMs = openSessionStart.getTime()
    const endMs = segmentEnd.getTime()
    if (endMs <= startMs) {
      openSessionStart = segmentEnd
      return
    }

    const minutes = (endMs - startMs) / 60000
    sessionWorkedMinutes += minutes
    todayMinutes += overlapMinutes(openSessionStart, segmentEnd, startOfToday, now)
    weekMinutes += overlapMinutes(openSessionStart, segmentEnd, startOfWeek, now)
    monthMinutes += overlapMinutes(openSessionStart, segmentEnd, startOfMonth, now)
    openSessionStart = segmentEnd
  }

  const resetSession = () => {
    openSessionStart = null
    breakStartedAt = null
    sessionWorkedMinutes = 0
  }

  for (const event of events) {
    const occurredAt = new Date(event.occurred_at)
    switch (event.event_subtype) {
      case "clock_in":
        resetSession()
        openSessionStart = occurredAt
        break
      case "break_start":
        if (openSessionStart) {
          closeActiveSegment(occurredAt)
          breakStartedAt = occurredAt
          openSessionStart = null
        }
        break
      case "break_end":
        if (breakStartedAt) {
          openSessionStart = occurredAt
          breakStartedAt = null
        }
        break
      case "clock_out":
        if (openSessionStart) {
          closeActiveSegment(occurredAt)
        }
        resetSession()
        break
    }
  }

  if (openSessionStart) {
    closeActiveSegment(now)
  }

  return {
    hours_today: roundHours(todayMinutes),
    hours_this_week: roundHours(weekMinutes),
    hours_this_month: roundHours(monthMinutes),
  }
}

function overlapMinutes(segmentStart: Date, segmentEnd: Date, windowStart: Date, windowEnd: Date) {
  const start = Math.max(segmentStart.getTime(), windowStart.getTime())
  const end = Math.min(segmentEnd.getTime(), windowEnd.getTime())
  if (end <= start) return 0
  return (end - start) / 60000
}

function roundHours(minutes: number) {
  return Number((minutes / 60).toFixed(2))
}
