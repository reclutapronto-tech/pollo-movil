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

const ENDPOINT = "tasks"
const TASKS_RATE_LIMIT = 30

// Valid status transitions — prevents impossible state changes
const VALID_TRANSITIONS: Record<string, string[]> = {
  not_started: ["in_progress"],
  in_progress: ["completed", "blocked", "skipped"],
  blocked: ["in_progress", "skipped"],
  // completed and skipped are terminal — no transitions out
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
      .select("id, company_id, role, is_active")
      .eq("id", user.id)
      .single()

    if (userError || !userRecord) {
      return errorResponse(requestId, 401, "UNAUTHORIZED", "User record not found")
    }
    if (!userRecord.is_active) {
      return errorResponse(requestId, 403, "FORBIDDEN", "User is inactive")
    }

    // ──────────────────────────────────────────
    // GET /tasks?job_id=<uuid> — List tasks for a job
    // ──────────────────────────────────────────
    if (req.method === "GET") {
      const url = new URL(req.url)
      const jobId = url.searchParams.get("job_id")

      if (!jobId) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "job_id query parameter is required")
      }

      // Verify user is assigned to this job
      const { data: assignment } = await supabase
        .from("assignments")
        .select("job_id")
        .eq("user_id", user.id)
        .eq("job_id", jobId)
        .eq("is_active", true)
        .maybeSingle()

      if (!assignment) {
        return errorResponse(requestId, 403, "FORBIDDEN", "User is not assigned to this job")
      }

      const { data: tasks, error: tasksError } = await supabaseAdmin
        .from("tasks")
        .select("id, name, description, status, sort_order, requires_photo, requires_before_after, assigned_to, completed_at, completed_by, created_at")
        .eq("job_id", jobId)
        .eq("company_id", userRecord.company_id)
        .is("deleted_at", null)
        .order("sort_order", { ascending: true })
        .order("created_at", { ascending: true })

      if (tasksError) throw tasksError

      logRequestResult(ENDPOINT, requestId, 200, {
        user_id: user.id,
        job_id: jobId,
        result_count: (tasks || []).length,
      })
      return jsonResponse({
        status: "success",
        job_id: jobId,
        tasks: tasks || [],
        count: (tasks || []).length,
        request_id: requestId,
      }, 200, requestId)
    }

    // ──────────────────────────────────────────
    // POST /tasks — Update task status
    // ──────────────────────────────────────────
    if (req.method === "POST") {
      const idempotencyKey = req.headers.get("Idempotency-Key")
      if (!idempotencyKey) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "Idempotency-Key header is required")
      }

      const payload = await req.json()
      const { task_id, action, note, media_asset_id } = payload

      if (!task_id || !action) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "task_id and action are required")
      }

      if (!["start", "complete", "block", "skip"].includes(action)) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "action must be one of: start, complete, block, skip")
      }

      // Idempotency check
      const requestHash = await sha256Hex(JSON.stringify(payload))
      const replay = await lookupIdempotency(supabaseAdmin, user.id, ENDPOINT, idempotencyKey, requestHash)
      if (replay.replay) {
        if (replay.conflict) {
          return errorResponse(replay.requestId, 409, "CONFLICT", "Idempotency key was reused with a different payload")
        }
        return jsonResponse(replay.body, replay.status, replay.requestId)
      }

      // Rate limit
      const rateLimit = await applyRateLimit(supabaseAdmin, user.id, ENDPOINT, requestId, TASKS_RATE_LIMIT)
      if (rateLimit.limited) {
        return errorResponse(requestId, 429, "RATE_LIMITED", "Too many task requests", [], rateLimit.headers)
      }

      // Fetch the task
      const { data: task, error: taskError } = await supabaseAdmin
        .from("tasks")
        .select("id, job_id, company_id, status, requires_photo, assigned_to")
        .eq("id", task_id)
        .eq("company_id", userRecord.company_id)
        .maybeSingle()

      if (taskError) throw taskError
      if (!task) {
        return errorResponse(requestId, 404, "NOT_FOUND", "Task not found")
      }

      // Verify assignment to the job
      const { data: jobAssignment } = await supabase
        .from("assignments")
        .select("job_id")
        .eq("user_id", user.id)
        .eq("job_id", task.job_id)
        .eq("is_active", true)
        .maybeSingle()

      if (!jobAssignment) {
        return errorResponse(requestId, 403, "FORBIDDEN", "User is not assigned to this job")
      }

      // Map action to target status
      const targetStatus: Record<string, string> = {
        start: "in_progress",
        complete: "completed",
        block: "blocked",
        skip: "skipped",
      }
      const toStatus = targetStatus[action]

      // Validate transition
      const allowedNext = VALID_TRANSITIONS[task.status] || []
      if (!allowedNext.includes(toStatus)) {
        return errorResponse(requestId, 400, "INVALID_TRANSITION",
          `Cannot transition from '${task.status}' to '${toStatus}'. Allowed: ${allowedNext.join(", ") || "none (terminal state)"}`)
      }

      // Photo enforcement — completing a photo-required task needs a media_asset_id
      if (action === "complete" && task.requires_photo && !media_asset_id) {
        return errorResponse(requestId, 400, "PHOTO_REQUIRED",
          "This task requires a photo before it can be completed. Provide media_asset_id.")
      }

      // If photo provided, verify it exists and belongs to the right job
      if (media_asset_id) {
        const { data: mediaAsset } = await supabaseAdmin
          .from("media_assets")
          .select("id, job_id, company_id")
          .eq("id", media_asset_id)
          .maybeSingle()

        if (!mediaAsset || mediaAsset.job_id !== task.job_id || mediaAsset.company_id !== userRecord.company_id) {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", "media_asset_id is invalid or does not belong to this job")
        }
      }

      // Update the task
      const now = new Date().toISOString()
      const updateFields: Record<string, unknown> = {
        status: toStatus,
        updated_at: now,
      }
      if (toStatus === "completed") {
        updateFields.completed_at = now
        updateFields.completed_by = user.id
      }

      const { error: updateError } = await supabaseAdmin
        .from("tasks")
        .update(updateFields)
        .eq("id", task_id)

      if (updateError) throw updateError

      // Create task_event in the event store
      const eventId = crypto.randomUUID()
      const taskEvent = {
        id: eventId,
        company_id: userRecord.company_id,
        job_id: task.job_id,
        task_id: task_id,
        user_id: user.id,
        occurred_at: now,
        received_at: now,
        from_status: task.status,
        to_status: toStatus,
        note: note || null,
        source_event_uuid: eventId,
        metadata: media_asset_id ? { media_asset_id } : {},
      }

      const { error: eventError } = await supabaseAdmin
        .from("task_events")
        .insert(taskEvent)

      if (eventError) {
        // Rollback task status on event insert failure
        await supabaseAdmin
          .from("tasks")
          .update({ status: task.status, completed_at: null, completed_by: null, updated_at: task.updated_at })
          .eq("id", task_id)
        throw eventError
      }

      const responseBody = {
        status: "success",
        task_id,
        from_status: task.status,
        to_status: toStatus,
        task_event_id: eventId,
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
        action,
        task_id,
        from_status: task.status,
        to_status: toStatus,
      })
      return jsonResponse(responseBody, 200, requestId, rateLimit.headers)
    }

    return errorResponse(requestId, 405, "METHOD_NOT_ALLOWED", "Use GET or POST for /tasks")
  } catch (error) {
    logRequestError(ENDPOINT, requestId, error)
    console.error("tasks error:", error)
    return errorResponse(requestId, 500, "INTERNAL_ERROR", error.message || "Internal server error")
  }
})
