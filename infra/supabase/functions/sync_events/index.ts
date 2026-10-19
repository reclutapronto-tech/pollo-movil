import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.4"
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import {
  applyRateLimit,
  corsHeaders,
  errorResponse,
  haversineDistanceMeters,
  isValidGpsCoordinates,
  jsonResponse,
  logRequestError,
  logRequestResult,
  logRequestStart,
  lookupIdempotency,
  makeRequestId,
  sha256Hex,
  storeIdempotency,
} from "../_shared/api.ts"

const ENDPOINT = "sync_events"
const SYNC_RATE_LIMIT = 10

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders(req) })
  }

  const requestId = makeRequestId(req)
  const startedAt = Date.now()
  logRequestStart(ENDPOINT, requestId, req)

  try {
    if (req.method !== "POST") {
      return errorResponse(requestId, 405, "METHOD_NOT_ALLOWED", "Use POST for /sync/events")
    }

    const authHeader = req.headers.get("Authorization")
    if (!authHeader) {
      return errorResponse(requestId, 401, "UNAUTHORIZED", "Missing Authorization header")
    }

    const idempotencyKey = req.headers.get("Idempotency-Key")
    if (!idempotencyKey) {
      return errorResponse(requestId, 400, "INVALID_PAYLOAD", "Idempotency-Key header is required")
    }

    const payload = await req.json()
    const { batch_id, clock_events } = payload
    if (!batch_id || !Array.isArray(clock_events)) {
      return errorResponse(requestId, 400, "INVALID_PAYLOAD", "batch_id and clock_events are required")
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

    const { data: userRecord, error: userError } = await supabase
      .from("users")
      .select("id, company_id, role, is_active")
      .eq("id", user.id)
      .single()

    if (userError || !userRecord) {
      return errorResponse(requestId, 401, "UNAUTHORIZED", "User record not found")
    }
    if (!userRecord.is_active) {
      return errorResponse(requestId, 403, "FORBIDDEN", "User is inactive")
    }

    const requestHash = await sha256Hex(JSON.stringify(payload))
    const replay = await lookupIdempotency(supabaseAdmin, user.id, ENDPOINT, idempotencyKey, requestHash)
    if (replay.replay) {
      if (replay.conflict) {
        return errorResponse(replay.requestId, 409, "CONFLICT", "Idempotency key was reused with a different payload")
      }
      return jsonResponse(replay.body, replay.status, replay.requestId)
    }

    const rateLimit = await applyRateLimit(supabaseAdmin, user.id, ENDPOINT, requestId, SYNC_RATE_LIMIT)
    if (rateLimit.limited) {
      return errorResponse(requestId, 429, "RATE_LIMITED", "Too many sync requests", [], rateLimit.headers)
    }

    const jobIds = [...new Set(clock_events.map((event: any) => event.job_id).filter(Boolean))]

    // ─── Crew clock-in: collect worker_ids job assignments ──
    const crewWorkerIds = new Set<string>()
    for (const event of clock_events) {
      if (event.event_subtype === "crew_clock_in" || event.event_subtype === "crew_clock_out") {
        if (Array.isArray(event.worker_ids)) {
          for (const wid of event.worker_ids) crewWorkerIds.add(wid)
        }
      }
    }

    const { data: assignments, error: assignmentsError } = await supabase
      .from("assignments")
      .select(`
        job_id,
        jobs (
          id,
          site_lat,
          site_lng,
          geofence_radius_m,
          geofence_enforced
        )
      `)
      .eq("user_id", user.id)
      .eq("is_active", true)
      .in("job_id", jobIds)

    if (assignmentsError) {
      throw assignmentsError
    }

    const assignedJobs = new Map(
      (assignments || []).map((assignment: any) => [assignment.job_id, assignment.jobs]),
    )

    const accepted: string[] = []
    const duplicates: string[] = []
    const rejected: Array<{ id: string; reason: string; message?: string }> = []

    for (const event of clock_events) {
      if (!event?.id || !event?.job_id || !event?.event_subtype || !event?.occurred_at) {
        rejected.push({
          id: event?.id || "__MALFORMED_EVENT__",
          reason: "invalid_payload",
          message: "clock event missing required fields",
        })
        continue
      }

      const job = assignedJobs.get(event.job_id)
      if (!job) {
        rejected.push({
          id: event.id,
          reason: "forbidden_job",
          message: "user is not assigned to this job",
        })
        continue
      }

      if (!isValidGpsCoordinates(event.gps?.lat, event.gps?.lng)) {
        rejected.push({
          id: event.id,
          reason: "invalid_geofence",
          message: "GPS coordinates are missing or out of valid range (-90..90 lat, -180..180 lng)",
        })
        continue
      }

      // Geofence enforcement is opt-out per job. When `geofence_enforced = false`
      // (for remote / hybrid workers, office-based support, etc.) we still log
      // GPS for audit but skip the distance check and the "site coords must be
      // configured" check.
      if (job.geofence_enforced !== false) {
        if (!isValidGpsCoordinates(job.site_lat, job.site_lng)) {
          rejected.push({
            id: event.id,
            reason: "invalid_geofence",
            message: "job site coordinates are not configured",
          })
          continue
        }

        const distanceM = haversineDistanceMeters(job.site_lat, job.site_lng, event.gps.lat, event.gps.lng)
        if (distanceM > job.geofence_radius_m) {
          rejected.push({
            id: event.id,
            reason: "invalid_geofence",
            message: "worker is outside job geofence",
          })
          continue
        }
      }

      const { error: dedupeError } = await supabaseAdmin.from("ingest_event_keys").insert({
        company_id: userRecord.company_id,
        event_type: "clock_event",
        source_event_uuid: event.id,
      })

      if (dedupeError?.code === "23505") {
        duplicates.push(event.id)
        continue
      }
      if (dedupeError) {
        throw dedupeError
      }

      const insertPayload = {
        id: event.id,
        company_id: userRecord.company_id,
        user_id: user.id,
        job_id: event.job_id,
        event_subtype: event.event_subtype,
        occurred_at: event.occurred_at,
        received_at: new Date().toISOString(),
        gps_lat: event.gps?.lat,
        gps_lng: event.gps?.lng,
        gps_accuracy_m: event.gps?.accuracy_m,
        geofence_passed: true,
        task_classification: event.task_classification || null,
        cost_code: event.cost_code || null,
        rate_code: event.rate_code || null,
        notes: event.notes || null,
        source_event_uuid: event.id,
      }

      const { error: insertError } = await supabaseAdmin.from("clock_events").insert([insertPayload])
      if (insertError) {
        await supabaseAdmin
          .from("ingest_event_keys")
          .delete()
          .eq("company_id", userRecord.company_id)
          .eq("event_type", "clock_event")
          .eq("source_event_uuid", event.id)
        throw insertError
      }

      accepted.push(event.id)
    }

    const responseBody = {
      status: "success",
      batch_id,
      accepted,
      duplicates,
      rejected,
      server_time: new Date().toISOString(),
      request_id: requestId,
    }

    await storeIdempotency(
      supabaseAdmin,
      user.id,
      ENDPOINT,
      idempotencyKey,
      requestHash,
      200,
      responseBody,
      requestId,
    )

    logRequestResult(ENDPOINT, requestId, 200, {
      user_id: user.id,
      accepted_count: accepted.length,
      duplicate_count: duplicates.length,
      rejected_count: rejected.length,
      latency_ms: Date.now() - startedAt,
    })

    return jsonResponse(responseBody, 200, requestId, rateLimit.headers)
  } catch (error) {
    logRequestError(ENDPOINT, requestId, error)
    console.error("Sync events error:", error)
    return errorResponse(requestId, 500, "INTERNAL_ERROR", error.message || "Internal server error")
  }
})
