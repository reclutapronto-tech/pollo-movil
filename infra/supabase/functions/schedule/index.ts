import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.4"
import {
  applyRateLimit,
  CORS_HEADERS,
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

const ENDPOINT = "schedule"
const RATE_LIMIT = 20

function isUuid(value: unknown): value is string {
  return typeof value === "string"
    && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value)
}

type ShiftSummary = {
  shift_date: string
  start_time: string
  end_time: string
  job_id: string
  job_name: string
}

function shapeSwapRow(
  row: Record<string, unknown>,
  names: Map<string, string>,
  shifts: Map<string, ShiftSummary>,
) {
  const requesterId = row.requester_id as string
  const targetId = (row.swap_with_user_id as string | null) ?? null
  const shiftId = row.shift_id as string
  return {
    id: row.id as string,
    shift_id: shiftId,
    requester_id: requesterId,
    requester_name: names.get(requesterId) ?? "Unknown worker",
    swap_with_user_id: targetId,
    swap_with_name: targetId ? (names.get(targetId) ?? null) : null,
    notes: (row.notes as string | null) ?? null,
    status: row.status as string,
    created_at: row.created_at as string,
    decided_at: (row.decided_at as string | null) ?? null,
    decided_by: (row.decided_by as string | null) ?? null,
    decision_reason: (row.decision_reason as string | null) ?? null,
    shift: shifts.get(shiftId) ?? null,
  }
}

function mondayFor(date: Date) {
  const copy = new Date(date)
  const day = copy.getUTCDay()
  const offset = day === 0 ? -6 : 1 - day
  copy.setUTCDate(copy.getUTCDate() + offset)
  return copy
}

function weekRange(weekStart: string | null) {
  const base = weekStart ? new Date(`${weekStart}T00:00:00Z`) : mondayFor(new Date())
  if (Number.isNaN(base.getTime())) return null
  const end = new Date(base)
  end.setUTCDate(end.getUTCDate() + 6)
  return {
    start: base.toISOString().slice(0, 10),
    end: end.toISOString().slice(0, 10),
  }
}

function dateRange(dateFrom: string | null, dateTo: string | null) {
  if (!dateFrom || !dateTo) return null
  const start = new Date(`${dateFrom}T00:00:00Z`)
  const end = new Date(`${dateTo}T00:00:00Z`)
  if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime()) || end < start) {
    return null
  }
  return {
    start: start.toISOString().slice(0, 10),
    end: end.toISOString().slice(0, 10),
  }
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

    if (userError || !userRecord?.is_active) {
      return errorResponse(requestId, 403, "FORBIDDEN", "User is inactive")
    }

    if (req.method === "GET") {
      const url = new URL(req.url)
      const range =
        dateRange(url.searchParams.get("date_from"), url.searchParams.get("date_to")) ??
        weekRange(url.searchParams.get("week_start"))
      if (!range) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "Invalid date range")
      }

      const view = url.searchParams.get("view") ?? "mine"

      let query = supabaseAdmin
        .from("schedule_shifts")
        .select(`
          id,
          worker_id,
          job_id,
          shift_date,
          start_time,
          end_time,
          status,
          notes,
          sort_order,
          published_at,
          published_by,
          users!schedule_shifts_worker_id_fkey(full_name),
          jobs!schedule_shifts_job_id_fkey(name, code)
        `)
        .eq("company_id", userRecord.company_id)
        .gte("shift_date", range.start)
        .lte("shift_date", range.end)

      // Scoping:
      //  - workers always see only their own published shifts.
      //  - foremen default to their own shifts, unless `view=crew` — then they
      //    see every published shift in their company for the range (used by
      //    the foreman crew schedule screen).
      if (userRecord.role === "worker") {
        query = query.eq("worker_id", user.id).eq("status", "published")
      } else if (userRecord.role === "foreman") {
        if (view === "crew") {
          query = query.eq("status", "published")
        } else {
          query = query.eq("worker_id", user.id).eq("status", "published")
        }
      }

      const { data, error } = await query
        .order("shift_date", { ascending: true })
        .order("sort_order", { ascending: true })
        .order("start_time", { ascending: true })

      const { data: ptoData, error: ptoError } = await supabaseAdmin
        .from("pto_requests")
        .select("id, user_id, pto_type, start_date, end_date, status")
        .eq("company_id", userRecord.company_id)
        .in("status", ["approved", "pending"])
        .lte("start_date", range.end)
        .gte("end_date", range.start)

      if (ptoError) throw ptoError

      const shifts = (data || []).map((shift: Record<string, unknown>) => ({
        id: shift.id,
        worker_id: shift.worker_id,
        worker_name: (shift.users as { full_name?: string } | null)?.full_name ?? "Unknown worker",
        job_id: shift.job_id,
        job_name: (shift.jobs as { name?: string } | null)?.name ?? "Unknown job",
        job_code: (shift.jobs as { code?: string } | null)?.code ?? null,
        date: shift.shift_date,
        start_time: typeof shift.start_time === "string" ? shift.start_time.slice(0, 5) : shift.start_time,
        end_time: typeof shift.end_time === "string" ? shift.end_time.slice(0, 5) : shift.end_time,
        status: shift.status,
        notes: shift.notes,
        sort_order: typeof shift.sort_order === "number" ? shift.sort_order : 0,
        published_at: shift.published_at,
        published_by: shift.published_by,
      }))

      logRequestResult(ENDPOINT, requestId, 200, {
        user_id: user.id,
        result_count: shifts.length,
      })
      return jsonResponse({
        status: "success",
        week_start: range.start,
        week_end: range.end,
        shifts,
        pto_requests: ptoData || [],
        request_id: requestId,
      }, 200, requestId)
    }

    if (req.method !== "POST") {
      return errorResponse(requestId, 405, "METHOD_NOT_ALLOWED", "Use GET or POST")
    }

    // Role gating is per-action below. `swap_request` and `swap_cancel` are
    // worker-originating (a worker manages their own swap request); all
    // other actions are supervisor-or-above. Gates live inside each action
    // branch.

    const payload = await req.json()
    const action = payload?.action

    // `swap_list` is a read — no Idempotency-Key required, no replay check,
    // and no idempotency store on the way out. Every other action requires
    // the header and uses the standard replay protection.
    const rawIdempotencyKey = req.headers.get("Idempotency-Key")
    if (action !== "swap_list" && !rawIdempotencyKey) {
      return errorResponse(requestId, 400, "INVALID_PAYLOAD", "Idempotency-Key required")
    }
    const idempotencyKey = rawIdempotencyKey ?? ""
    const requestHash = await sha256Hex(JSON.stringify(payload))
    if (action !== "swap_list") {
      const replay = await lookupIdempotency(supabaseAdmin, user.id, ENDPOINT, idempotencyKey, requestHash)
      if (replay.replay) {
        if (replay.conflict) return errorResponse(replay.requestId, 409, "CONFLICT", "Idempotency key reused")
        return jsonResponse(replay.body, replay.status, replay.requestId)
      }
    }

    const rateLimit = await applyRateLimit(supabaseAdmin, user.id, ENDPOINT, requestId, RATE_LIMIT)
    if (rateLimit.limited) {
      return errorResponse(requestId, 429, "RATE_LIMITED", "Too many requests", [], rateLimit.headers)
    }

    // ── Action: swap_request (worker-originating) ──────────
    // A worker or foreman asks to swap out of one of their own published
    // shifts. Inserts a row into shift_swap_requests; supervisors resolve.
    if (action === "swap_request") {
      const { shift_id, swap_with_user_id, notes } = payload
      if (!shift_id) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "shift_id is required")
      }

      const { data: shift } = await supabaseAdmin
        .from("schedule_shifts")
        .select("id, worker_id, company_id, status")
        .eq("id", shift_id)
        .eq("company_id", userRecord.company_id)
        .maybeSingle()

      if (!shift) {
        return errorResponse(requestId, 404, "NOT_FOUND", "Shift not found")
      }
      if (shift.worker_id !== user.id) {
        return errorResponse(requestId, 403, "FORBIDDEN", "Can only request swaps for your own shift")
      }
      if (shift.status !== "published") {
        return errorResponse(requestId, 409, "CONFLICT", `Cannot request swap on a ${shift.status} shift`)
      }

      if (swap_with_user_id) {
        const { data: target } = await supabaseAdmin
          .from("users")
          .select("id")
          .eq("id", swap_with_user_id)
          .eq("company_id", userRecord.company_id)
          .eq("is_active", true)
          .maybeSingle()
        if (!target) {
          return errorResponse(requestId, 404, "NOT_FOUND", "Target worker not found in this company")
        }
      }

      const { data: inserted, error: insertError } = await supabaseAdmin
        .from("shift_swap_requests")
        .insert({
          company_id: userRecord.company_id,
          shift_id,
          requester_id: user.id,
          swap_with_user_id: swap_with_user_id || null,
          notes: notes || null,
          status: "pending",
        })
        .select("id")
        .single()

      if (insertError) {
        logRequestError(ENDPOINT, requestId, insertError)
        return errorResponse(requestId, 500, "INTERNAL_ERROR", "Failed to create swap request")
      }

      const responseBody = {
        status: "submitted",
        swap_request_id: inserted.id,
        request_id: requestId,
      }
      await storeIdempotency(supabaseAdmin, user.id, ENDPOINT, idempotencyKey, requestHash, 201, responseBody, requestId)
      logRequestResult(ENDPOINT, requestId, 201, { user_id: user.id, action: "swap_request", shift_id })
      return jsonResponse(responseBody, 201, requestId, rateLimit.headers)
    }

    // ── Action: swap_cancel (worker-originating) ──────────
    // The original requester cancels their own pending swap request.
    if (action === "swap_cancel") {
      const { swap_request_id } = payload
      if (!isUuid(swap_request_id)) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "swap_request_id must be a uuid")
      }

      const { data: swapRow, error: fetchError } = await supabaseAdmin
        .from("shift_swap_requests")
        .select("id, company_id, requester_id, status")
        .eq("id", swap_request_id)
        .maybeSingle()

      if (fetchError) throw fetchError
      if (!swapRow || swapRow.company_id !== userRecord.company_id) {
        return errorResponse(requestId, 404, "NOT_FOUND", "Swap request not found")
      }
      if (swapRow.requester_id !== user.id) {
        return errorResponse(requestId, 403, "FORBIDDEN", "Only the requester can cancel this swap request")
      }
      if (swapRow.status !== "pending") {
        return errorResponse(requestId, 409, "CONFLICT", `Cannot cancel a ${swapRow.status} swap request`)
      }

      const now = new Date().toISOString()
      const { error: updateError } = await supabaseAdmin
        .from("shift_swap_requests")
        .update({ status: "cancelled", updated_at: now })
        .eq("id", swap_request_id)
        .eq("company_id", userRecord.company_id)

      if (updateError) {
        logRequestError(ENDPOINT, requestId, updateError)
        return errorResponse(requestId, 500, "INTERNAL_ERROR", "Failed to cancel swap request")
      }

      const responseBody = { status: "cancelled", request_id: requestId }
      await storeIdempotency(supabaseAdmin, user.id, ENDPOINT, idempotencyKey, requestHash, 200, responseBody, requestId)
      logRequestResult(ENDPOINT, requestId, 200, {
        user_id: user.id,
        action: "swap_cancel",
        swap_request_id,
      })
      return jsonResponse(responseBody, 200, requestId, rateLimit.headers)
    }

    // Every action below requires foreman-or-above (crew schedule writes).
    if (!isForemanOrAbove(userRecord.role)) {
      return errorResponse(requestId, 403, "FORBIDDEN", "Only foremen, supervisors, admins, or owners can manage schedules")
    }

    if (action === "create") {
      const { worker_id, job_id, shift_date, start_time, end_time, notes, publish } = payload

      if (!worker_id || !job_id || !shift_date || !start_time || !end_time) {
        return errorResponse(
          requestId,
          400,
          "INVALID_PAYLOAD",
          "worker_id, job_id, shift_date, start_time, and end_time are required",
        )
      }

      if (start_time >= end_time) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "start_time must be before end_time")
      }

      const [{ data: worker }, { data: job }] = await Promise.all([
        supabaseAdmin
          .from("users")
          .select("id")
          .eq("id", worker_id)
          .eq("company_id", userRecord.company_id)
          .in("role", ["worker", "foreman"])
          .maybeSingle(),
        supabaseAdmin
          .from("jobs")
          .select("id")
          .eq("id", job_id)
          .eq("company_id", userRecord.company_id)
          .maybeSingle(),
      ])

      if (!worker || !job) {
        return errorResponse(requestId, 404, "NOT_FOUND", "Worker or job not found")
      }

      const shiftId = crypto.randomUUID()
      const { data: inserted, error: insertError } = await supabaseAdmin
        .from("schedule_shifts")
        .insert({
          id: shiftId,
          company_id: userRecord.company_id,
          worker_id,
          job_id,
          shift_date,
          start_time,
          end_time,
          notes: notes || null,
          status: publish ? "published" : "draft",
          created_by: user.id,
          ...(publish ? { published_at: new Date().toISOString(), published_by: user.id } : {}),
        })
        .select(`
          id,
          worker_id,
          job_id,
          shift_date,
          start_time,
          end_time,
          status,
          notes,
          published_at,
          published_by,
          users!schedule_shifts_worker_id_fkey(full_name),
          jobs!schedule_shifts_job_id_fkey(name, code)
        `)
        .single()

      if (insertError) throw insertError

      const responseBody = {
        status: "success",
        shift: {
          id: inserted.id,
          worker_id: inserted.worker_id,
          worker_name: inserted.users?.full_name ?? "Unknown worker",
          job_id: inserted.job_id,
          job_name: inserted.jobs?.name ?? "Unknown job",
          job_code: inserted.jobs?.code ?? null,
          date: inserted.shift_date,
          start_time: typeof inserted.start_time === "string" ? inserted.start_time.slice(0, 5) : inserted.start_time,
          end_time: typeof inserted.end_time === "string" ? inserted.end_time.slice(0, 5) : inserted.end_time,
          status: inserted.status,
          notes: inserted.notes,
          published_at: inserted.published_at,
          published_by: inserted.published_by,
        },
        request_id: requestId,
      }
      await storeIdempotency(supabaseAdmin, user.id, ENDPOINT, idempotencyKey, requestHash, 201, responseBody, requestId)
      logRequestResult(ENDPOINT, requestId, 201, {
        user_id: user.id,
        action: "create",
        shift_id: shiftId,
      })
      return jsonResponse(responseBody, 201, requestId, rateLimit.headers)
    }

    if (action === "update") {
      const { shift_id, worker_id, job_id, shift_date, start_time, end_time, notes } = payload
      if (!shift_id) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "shift_id is required")
      }

      const updates: Record<string, unknown> = {}
      if (worker_id) updates.worker_id = worker_id
      if (job_id) updates.job_id = job_id
      if (shift_date) updates.shift_date = shift_date
      if (start_time) updates.start_time = start_time
      if (end_time) updates.end_time = end_time
      if (notes !== undefined) updates.notes = notes || null

      if (Object.keys(updates).length === 0) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "At least one editable field is required")
      }

      if (start_time && end_time && start_time >= end_time) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "start_time must be before end_time")
      }

      if (worker_id || job_id) {
        const [{ data: worker }, { data: job }] = await Promise.all([
          worker_id
            ? supabaseAdmin
                .from("users")
                .select("id")
                .eq("id", worker_id)
                .eq("company_id", userRecord.company_id)
                .in("role", ["worker", "foreman"])
                .maybeSingle()
            : Promise.resolve({ data: { id: "unchanged" } }),
          job_id
            ? supabaseAdmin
                .from("jobs")
                .select("id")
                .eq("id", job_id)
                .eq("company_id", userRecord.company_id)
                .maybeSingle()
            : Promise.resolve({ data: { id: "unchanged" } }),
        ])

        if (!worker || !job) {
          return errorResponse(requestId, 404, "NOT_FOUND", "Worker or job not found")
        }
      }

      const { data: updated, error: updateError } = await supabaseAdmin
        .from("schedule_shifts")
        .update(updates)
        .eq("id", shift_id)
        .eq("company_id", userRecord.company_id)
        .eq("status", "draft")
        .select(`
          id,
          worker_id,
          job_id,
          shift_date,
          start_time,
          end_time,
          status,
          notes,
          published_at,
          published_by,
          users!schedule_shifts_worker_id_fkey(full_name),
          jobs!schedule_shifts_job_id_fkey(name, code)
        `)
        .maybeSingle()

      if (updateError) throw updateError
      if (!updated) {
        return errorResponse(requestId, 404, "NOT_FOUND", "Draft shift not found")
      }

      const responseBody = {
        status: "success",
        shift: {
          id: updated.id,
          worker_id: updated.worker_id,
          worker_name: updated.users?.full_name ?? "Unknown worker",
          job_id: updated.job_id,
          job_name: updated.jobs?.name ?? "Unknown job",
          job_code: updated.jobs?.code ?? null,
          date: updated.shift_date,
          start_time: typeof updated.start_time === "string" ? updated.start_time.slice(0, 5) : updated.start_time,
          end_time: typeof updated.end_time === "string" ? updated.end_time.slice(0, 5) : updated.end_time,
          status: updated.status,
          notes: updated.notes,
          published_at: updated.published_at,
          published_by: updated.published_by,
        },
        request_id: requestId,
      }
      await storeIdempotency(supabaseAdmin, user.id, ENDPOINT, idempotencyKey, requestHash, 200, responseBody, requestId)
      logRequestResult(ENDPOINT, requestId, 200, {
        user_id: user.id,
        action: "update",
        shift_id,
      })
      return jsonResponse(responseBody, 200, requestId, rateLimit.headers)
    }

    if (action === "delete") {
      const shiftId = payload?.shift_id
      if (!shiftId) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "shift_id is required")
      }

      const { data: deleted, error: deleteError } = await supabaseAdmin
        .from("schedule_shifts")
        .delete()
        .eq("id", shiftId)
        .eq("company_id", userRecord.company_id)
        .eq("status", "draft")
        .select("id")
        .maybeSingle()

      if (deleteError) throw deleteError
      if (!deleted) {
        return errorResponse(requestId, 404, "NOT_FOUND", "Draft shift not found")
      }

      const responseBody = { status: "success", shift_id: shiftId, request_id: requestId }
      await storeIdempotency(supabaseAdmin, user.id, ENDPOINT, idempotencyKey, requestHash, 200, responseBody, requestId)
      logRequestResult(ENDPOINT, requestId, 200, {
        user_id: user.id,
        action: "delete",
        shift_id: shiftId,
      })
      return jsonResponse(responseBody, 200, requestId, rateLimit.headers)
    }

    if (action === "publish") {
      const shiftIds = Array.isArray(payload?.shift_ids) ? payload.shift_ids.filter(Boolean) : []
      if (shiftIds.length === 0) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "shift_ids is required")
      }

      const { data: published, error: publishError } = await supabaseAdmin
        .from("schedule_shifts")
        .update({
          status: "published",
          published_at: new Date().toISOString(),
          published_by: user.id,
        })
        .in("id", shiftIds)
        .eq("company_id", userRecord.company_id)
        .eq("status", "draft")
        .select("id")

      if (publishError) throw publishError

      const responseBody = {
        status: "success",
        published_count: (published || []).length,
        request_id: requestId,
      }
      await storeIdempotency(supabaseAdmin, user.id, ENDPOINT, idempotencyKey, requestHash, 200, responseBody, requestId)
      logRequestResult(ENDPOINT, requestId, 200, {
        user_id: user.id,
        action: "publish",
        published_count: (published || []).length,
      })
      return jsonResponse(responseBody, 200, requestId, rateLimit.headers)
    }

    if (action === "copy_week") {
      const { source_start, source_end, target_start } = payload
      if (!source_start || !source_end || !target_start) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "source_start, source_end, target_start are required")
      }

      const srcStartMs = new Date(`${source_start}T12:00:00Z`).getTime()
      const tgtStartMs = new Date(`${target_start}T12:00:00Z`).getTime()
      const diffDays = Math.round((tgtStartMs - srcStartMs) / 86400000)

      const { data: sourceShifts, error: fetchError } = await supabaseAdmin
        .from("schedule_shifts")
        .select("*")
        .eq("company_id", userRecord.company_id)
        .gte("shift_date", source_start)
        .lte("shift_date", source_end)

      if (fetchError) throw fetchError

      if (!sourceShifts || sourceShifts.length === 0) {
        const responseBody = { status: "success", copied_count: 0, request_id: requestId }
        await storeIdempotency(supabaseAdmin, user.id, ENDPOINT, idempotencyKey, requestHash, 200, responseBody, requestId)
        logRequestResult(ENDPOINT, requestId, 200, { user_id: user.id, action: "copy_week", copied_count: 0 })
        return jsonResponse(responseBody, 200, requestId, rateLimit.headers)
      }

      const newShifts = sourceShifts.map((shift) => {
        const d = new Date(`${shift.shift_date}T12:00:00Z`)
        d.setUTCDate(d.getUTCDate() + diffDays)
        const newDateStr = d.toISOString().slice(0, 10)
        return {
          id: crypto.randomUUID(),
          company_id: userRecord.company_id,
          worker_id: shift.worker_id,
          job_id: shift.job_id,
          shift_date: newDateStr,
          start_time: shift.start_time,
          end_time: shift.end_time,
          notes: shift.notes,
          status: "draft",
          created_by: user.id
        }
      })

      const { error: insertError } = await supabaseAdmin
        .from("schedule_shifts")
        .insert(newShifts)

      if (insertError) throw insertError

      const responseBody = { status: "success", copied_count: newShifts.length, request_id: requestId }
      await storeIdempotency(supabaseAdmin, user.id, ENDPOINT, idempotencyKey, requestHash, 201, responseBody, requestId)
      logRequestResult(ENDPOINT, requestId, 201, {
        user_id: user.id,
        action: "copy_week",
        copied_count: newShifts.length,
      })
      return jsonResponse(responseBody, 201, requestId, rateLimit.headers)
    }

    // ── Action: swap_list (supervisor read) ──────────────────
    // Supervisor-or-above (foreman included) views swap requests in their
    // company, filtered by status (default pending). Joins shift + requester
    // name; batched lookups, no N+1.
    if (action === "swap_list") {
      const statusFilter = typeof payload?.status === "string" ? payload.status : "pending"
      const allowedStatuses = ["pending", "approved", "denied", "cancelled"]
      if (!allowedStatuses.includes(statusFilter)) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "status must be pending|approved|denied|cancelled")
      }

      const { data: swapRows, error: swapError } = await supabaseAdmin
        .from("shift_swap_requests")
        .select("id, shift_id, requester_id, swap_with_user_id, notes, status, decided_by, decided_at, decision_reason, created_at")
        .eq("company_id", userRecord.company_id)
        .eq("status", statusFilter)
        .order("created_at", { ascending: false })

      if (swapError) throw swapError

      const rows = swapRows || []
      const userIds = new Set<string>()
      const shiftIds = new Set<string>()
      for (const r of rows) {
        if (r.requester_id) userIds.add(r.requester_id)
        if (r.swap_with_user_id) userIds.add(r.swap_with_user_id)
        if (r.shift_id) shiftIds.add(r.shift_id)
      }

      const names = new Map<string, string>()
      const shifts = new Map<string, ShiftSummary>()

      if (userIds.size > 0) {
        const { data: usersData, error: usersError } = await supabaseAdmin
          .from("users")
          .select("id, full_name")
          .in("id", Array.from(userIds))
          .eq("company_id", userRecord.company_id)
        if (usersError) throw usersError
        for (const u of usersData || []) {
          names.set(u.id as string, (u.full_name as string) ?? "Unknown worker")
        }
      }

      if (shiftIds.size > 0) {
        const { data: shiftsData, error: shiftsError } = await supabaseAdmin
          .from("schedule_shifts")
          .select("id, shift_date, start_time, end_time, job_id, jobs!schedule_shifts_job_id_fkey(name)")
          .in("id", Array.from(shiftIds))
          .eq("company_id", userRecord.company_id)
        if (shiftsError) throw shiftsError
        for (const s of shiftsData || []) {
          const startRaw = s.start_time
          const endRaw = s.end_time
          shifts.set(s.id as string, {
            shift_date: s.shift_date as string,
            start_time: typeof startRaw === "string" ? startRaw.slice(0, 5) : String(startRaw),
            end_time: typeof endRaw === "string" ? endRaw.slice(0, 5) : String(endRaw),
            job_id: s.job_id as string,
            job_name: (s.jobs as { name?: string } | null)?.name ?? "Unknown job",
          })
        }
      }

      const requests = rows.map((r) => shapeSwapRow(r as Record<string, unknown>, names, shifts))

      const responseBody = { status: "success", requests, request_id: requestId }
      logRequestResult(ENDPOINT, requestId, 200, {
        user_id: user.id,
        action: "swap_list",
        result_count: requests.length,
      })
      return jsonResponse(responseBody, 200, requestId, rateLimit.headers)
    }

    // ── Action: swap_decide (supervisor resolves a swap request) ──
    // Supervisor approves or denies a pending swap. Approval does NOT
    // auto-reassign the shift here — the supervisor handles reassignment
    // via the existing `update` action.
    // TODO(swap-auto-reassign): future sprint — on approve, reassign the
    // shift's worker_id to swap_with_user_id atomically.
    if (action === "swap_decide") {
      const { swap_request_id, decision, reason } = payload
      if (!isUuid(swap_request_id)) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "swap_request_id must be a uuid")
      }
      if (decision !== "approved" && decision !== "denied") {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "decision must be 'approved' or 'denied'")
      }
      if (decision === "denied" && (typeof reason !== "string" || reason.trim().length === 0)) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "reason is required when denying a swap request")
      }

      const { data: swapRow, error: fetchError } = await supabaseAdmin
        .from("shift_swap_requests")
        .select("id, company_id, status")
        .eq("id", swap_request_id)
        .maybeSingle()

      if (fetchError) throw fetchError
      if (!swapRow || swapRow.company_id !== userRecord.company_id) {
        return errorResponse(requestId, 404, "NOT_FOUND", "Swap request not found")
      }
      if (swapRow.status !== "pending") {
        return errorResponse(requestId, 409, "CONFLICT", `Cannot decide a ${swapRow.status} swap request`)
      }

      const now = new Date().toISOString()
      const normalizedReason =
        typeof reason === "string" && reason.trim().length > 0 ? reason : null

      const { data: updated, error: updateError } = await supabaseAdmin
        .from("shift_swap_requests")
        .update({
          status: decision,
          decided_by: user.id,
          decided_at: now,
          decision_reason: normalizedReason,
          updated_at: now,
        })
        .eq("id", swap_request_id)
        .eq("company_id", userRecord.company_id)
        .select("id, company_id, shift_id, requester_id, swap_with_user_id, notes, status, decided_by, decided_at, decision_reason, created_at, updated_at")
        .single()

      if (updateError) {
        logRequestError(ENDPOINT, requestId, updateError)
        return errorResponse(requestId, 500, "INTERNAL_ERROR", "Failed to decide swap request")
      }

      const responseBody = {
        status: "decided",
        swap_request: updated,
        request_id: requestId,
      }
      await storeIdempotency(supabaseAdmin, user.id, ENDPOINT, idempotencyKey, requestHash, 200, responseBody, requestId)
      logRequestResult(ENDPOINT, requestId, 200, {
        user_id: user.id,
        action: "swap_decide",
        swap_request_id,
        decision,
      })
      return jsonResponse(responseBody, 200, requestId, rateLimit.headers)
    }

    // ── Action: crew_reorder (foreman drag-to-reorder) ─────
    // Bulk-updates sort_order across a set of shifts. Foreman may only
    // reorder shifts in their own company; each shift must already exist
    // and belong to the caller's company.
    if (action === "crew_reorder") {
      const { shifts } = payload
      if (!Array.isArray(shifts) || shifts.length === 0) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "shifts array is required and must be non-empty")
      }

      const shiftIds: string[] = []
      for (const s of shifts) {
        if (!s || typeof s.shift_id !== "string" || typeof s.sort_order !== "number") {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", "each entry must have {shift_id:string, sort_order:number}")
        }
        shiftIds.push(s.shift_id)
      }

      const { data: owned, error: ownershipError } = await supabaseAdmin
        .from("schedule_shifts")
        .select("id")
        .eq("company_id", userRecord.company_id)
        .in("id", shiftIds)

      if (ownershipError) throw ownershipError
      const ownedIds = new Set((owned || []).map((r) => r.id))
      if (ownedIds.size !== shiftIds.length) {
        return errorResponse(requestId, 403, "FORBIDDEN", "One or more shifts do not belong to this company")
      }

      for (const s of shifts) {
        const { error: updErr } = await supabaseAdmin
          .from("schedule_shifts")
          .update({ sort_order: s.sort_order })
          .eq("id", s.shift_id)
          .eq("company_id", userRecord.company_id)
        if (updErr) throw updErr
      }

      const responseBody = { status: "success", success: true, updated_count: shifts.length, request_id: requestId }
      await storeIdempotency(supabaseAdmin, user.id, ENDPOINT, idempotencyKey, requestHash, 200, responseBody, requestId)
      logRequestResult(ENDPOINT, requestId, 200, {
        user_id: user.id,
        action: "crew_reorder",
        updated_count: shifts.length,
      })
      return jsonResponse(responseBody, 200, requestId, rateLimit.headers)
    }

    return errorResponse(requestId, 400, "INVALID_PAYLOAD", "Unsupported action")
  } catch (error) {
    logRequestError(ENDPOINT, requestId, error)
    return errorResponse(requestId, 500, "INTERNAL_ERROR", error.message || "Internal server error")
  }
})
