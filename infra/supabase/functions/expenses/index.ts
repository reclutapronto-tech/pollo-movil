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
import { isSupervisorOrAbove } from "../_shared/roles.ts"

const ENDPOINT = "expenses"
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

    // Shared list implementation used by GET and POST action:'list'
    const listImpl = async (filters: {
      jobId?: string | null
      status?: string | null
    }) => {
      const status = filters.status || "pending"

      let query = supabaseAdmin
        .from("expense_events")
        .select("*, jobs!expense_events_job_id_fkey(name)")
        .eq("company_id", userRecord.company_id)
        .eq("status", status)
        .order("submitted_at", { ascending: false })
        .limit(50)

      if (filters.jobId) query = query.eq("job_id", filters.jobId)

      // Workers see only their own expenses; supervisors/admins see all company rows
      if (!isSupervisorOrAbove(userRecord.role)) {
        query = query.eq("submitted_by", user.id)
      }

      const { data, error: fetchError } = await query
      if (fetchError) throw fetchError

      // Flatten joined jobs.name to top-level job_name (string | null)
      const expenses = (data || []).map((row: Record<string, unknown>) => {
        const job = row.jobs as { name?: string | null } | null | undefined
        const { jobs: _jobs, ...rest } = row
        return { ...rest, job_name: job?.name ?? null }
      })

      return expenses
    }

    // GET — list expenses for a job or company
    if (req.method === "GET") {
      const url = new URL(req.url)
      const jobId = url.searchParams.get("job_id")
      const status = url.searchParams.get("status")

      const expenses = await listImpl({ jobId, status })

      logRequestResult(ENDPOINT, requestId, 200, {
        user_id: user.id,
        result_count: expenses.length,
      })
      return jsonResponse({ status: "success", expenses, request_id: requestId }, 200, requestId)
    }

    // POST — list, submit, decide, or reimburse
    if (req.method === "POST") {
      const payload = await req.json()
      const { action } = payload

      // action:'list' — mirror of GET list (no idempotency/rate-limit needed; read-only)
      if (action === "list") {
        const expenses = await listImpl({
          jobId: payload.job_id ?? null,
          status: payload.status ?? null,
        })

        logRequestResult(ENDPOINT, requestId, 200, {
          user_id: user.id,
          action: "list",
          result_count: expenses.length,
        })
        return jsonResponse({ status: "success", expenses, request_id: requestId }, 200, requestId)
      }

      const idempotencyKey = req.headers.get("Idempotency-Key")
      if (!idempotencyKey) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "Idempotency-Key required")
      }

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

      // Submit expense
      if (action === "submit") {
        const { job_id, category, amount, vendor, notes, media_asset_id } = payload

        if (!job_id || !category || !amount || !media_asset_id) {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", "job_id, category, amount, and media_asset_id are required")
        }

        if (!["materials", "fuel", "tools", "meals", "other"].includes(category)) {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", "Invalid category")
        }

        // Verify assignment
        const { data: assignment } = await supabase
          .from("assignments")
          .select("job_id")
          .eq("user_id", user.id)
          .eq("job_id", job_id)
          .eq("is_active", true)
          .maybeSingle()

        if (!assignment) {
          return errorResponse(requestId, 403, "FORBIDDEN", "Not assigned to this job")
        }

        const { data: receiptAsset, error: receiptError } = await supabaseAdmin
          .from("media_assets")
          .select("id, company_id, uploaded_by, job_id, sync_status")
          .eq("id", media_asset_id)
          .maybeSingle()

        if (receiptError) throw receiptError
        if (!receiptAsset) {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", "Receipt media asset not found")
        }
        if (receiptAsset.company_id !== userRecord.company_id || receiptAsset.uploaded_by !== user.id) {
          return errorResponse(requestId, 403, "FORBIDDEN", "Receipt asset does not belong to this worker")
        }
        if (receiptAsset.job_id !== job_id) {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", "Receipt asset must belong to the same job")
        }
        if (!["uploaded", "processed"].includes(receiptAsset.sync_status)) {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", "Receipt asset is not ready")
        }

        const expenseId = crypto.randomUUID()
        const now = new Date().toISOString()

        const { error: insertError } = await supabaseAdmin
          .from("expense_events")
          .insert({
            id: expenseId,
            company_id: userRecord.company_id,
            job_id,
            submitted_by: user.id,
            category,
            amount,
            vendor: vendor || null,
            notes: notes || null,
            media_asset_id,
            status: "pending",
            submitted_at: now,
          })

        if (insertError) throw insertError

        const responseBody = { status: "success", expense_id: expenseId, request_id: requestId }
        await storeIdempotency(supabaseAdmin, user.id, ENDPOINT, idempotencyKey, requestHash, 201, responseBody, requestId)
        logRequestResult(ENDPOINT, requestId, 201, {
          user_id: user.id,
          action: "submit",
          expense_id: expenseId,
        })
        return jsonResponse(responseBody, 201, requestId, rateLimit.headers)
      }

      // Approve/deny expense (supervisor/admin)
      if (action === "decide") {
        if (!isSupervisorOrAbove(userRecord.role)) {
          return errorResponse(requestId, 403, "FORBIDDEN", "Only supervisors, admins, or owners can approve expenses")
        }

        const { expense_id, decision, reason } = payload
        if (!expense_id || !decision || !["approved", "denied"].includes(decision)) {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", "expense_id and decision (approved/denied) required")
        }

        const { error: updateError } = await supabaseAdmin
          .from("expense_events")
          .update({
            status: decision,
            decided_by: user.id,
            decided_at: new Date().toISOString(),
            decision_reason: reason || null,
          })
          .eq("id", expense_id)
          .eq("company_id", userRecord.company_id)

        if (updateError) throw updateError

        const responseBody = { status: "success", expense_id, decision, request_id: requestId }
        await storeIdempotency(supabaseAdmin, user.id, ENDPOINT, idempotencyKey, requestHash, 200, responseBody, requestId)
        logRequestResult(ENDPOINT, requestId, 200, {
          user_id: user.id,
          action: "decide",
          expense_id,
          decision,
        })
        return jsonResponse(responseBody, 200, requestId, rateLimit.headers)
      }

      if (action === "reimburse") {
        if (!isSupervisorOrAbove(userRecord.role)) {
          return errorResponse(requestId, 403, "FORBIDDEN", "Only supervisors, admins, or owners can mark expenses reimbursed")
        }

        const { expense_id, reference, notes } = payload
        if (!expense_id || !reference) {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", "expense_id and reference are required")
        }

        const { data: expenseRow, error: expenseFetchError } = await supabaseAdmin
          .from("expense_events")
          .select("id, status, reimbursed_at")
          .eq("id", expense_id)
          .eq("company_id", userRecord.company_id)
          .maybeSingle()

        if (expenseFetchError) throw expenseFetchError
        if (!expenseRow) {
          return errorResponse(requestId, 404, "NOT_FOUND", "Expense not found")
        }
        if (expenseRow.status !== "approved") {
          return errorResponse(requestId, 409, "INVALID_STATE", "Only approved expenses can be reimbursed")
        }
        if (expenseRow.reimbursed_at) {
          return errorResponse(requestId, 409, "INVALID_STATE", "Expense has already been reimbursed")
        }

        const reimbursedAt = new Date().toISOString()
        const { error: reimburseError } = await supabaseAdmin
          .from("expense_events")
          .update({
            reimbursed_at: reimbursedAt,
            reimbursed_by: user.id,
            reimbursement_reference: reference,
            reimbursement_notes: notes || null,
          })
          .eq("id", expense_id)
          .eq("company_id", userRecord.company_id)

        if (reimburseError) throw reimburseError

        const responseBody = {
          status: "success",
          expense_id,
          reimbursed_at: reimbursedAt,
          reimbursement_reference: reference,
          request_id: requestId,
        }
        await storeIdempotency(supabaseAdmin, user.id, ENDPOINT, idempotencyKey, requestHash, 200, responseBody, requestId)
        logRequestResult(ENDPOINT, requestId, 200, {
          user_id: user.id,
          action: "reimburse",
          expense_id,
        })
        return jsonResponse(responseBody, 200, requestId, rateLimit.headers)
      }

      return errorResponse(requestId, 400, "INVALID_PAYLOAD", "action must be 'list', 'submit', 'decide', or 'reimburse'")
    }

    return errorResponse(requestId, 405, "METHOD_NOT_ALLOWED", "Use GET or POST")
  } catch (error) {
    logRequestError(ENDPOINT, requestId, error)
    return errorResponse(requestId, 500, "INTERNAL_ERROR", error.message || "Internal server error")
  }
})
