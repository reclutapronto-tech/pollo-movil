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

const ENDPOINT = "budget"
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

    // GET — list budgets or get specific job budget
    if (req.method === "GET") {
      const url = new URL(req.url)
      const jobId = url.searchParams.get("job_id")
      const includeSummary = url.searchParams.get("summary") === "true"

      // Single job budget with summary
      if (jobId && includeSummary) {
        const { data, error } = await supabaseAdmin
          .from("job_budget_summary")
          .select("*")
          .eq("company_id", userRecord.company_id)
          .eq("job_id", jobId)
          .maybeSingle()

        if (error) throw error

        logRequestResult(ENDPOINT, requestId, 200, { job_id: jobId, summary: true })
        return jsonResponse({ status: "success", budget: data, request_id: requestId }, 200, requestId)
      }

      // Single job budget
      if (jobId) {
        const { data, error } = await supabaseAdmin
          .from("job_budgets")
          .select("*")
          .eq("company_id", userRecord.company_id)
          .eq("job_id", jobId)
          .maybeSingle()

        if (error) throw error

        logRequestResult(ENDPOINT, requestId, 200, { job_id: jobId })
        return jsonResponse({ status: "success", budget: data, request_id: requestId }, 200, requestId)
      }

      // List all budgets for company (summary view)
      const { data, error } = await supabaseAdmin
        .from("job_budget_summary")
        .select("*")
        .eq("company_id", userRecord.company_id)
        .order("updated_at", { ascending: false })
        .limit(50)

      if (error) throw error

      logRequestResult(ENDPOINT, requestId, 200, { count: (data || []).length })
      return jsonResponse({ status: "success", budgets: data || [], request_id: requestId }, 200, requestId)
    }

    // POST — create or update budget
    if (req.method === "POST") {
      const idempotencyKey = req.headers.get("Idempotency-Key")
      if (!idempotencyKey) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "Idempotency-Key required")
      }

      const payload = await req.json()
      const { action } = payload

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

      // Only supervisors/admins can manage budgets
      if (!isSupervisorOrAbove(userRecord.role)) {
        return errorResponse(requestId, 403, "FORBIDDEN", "Only supervisors, admins, or owners can manage budgets")
      }

      // Create budget
      if (action === "create") {
        const { job_id, budgeted_hours, budgeted_cost, hourly_rate, warning_threshold_percent } = payload

        if (!job_id || (!budgeted_hours && !budgeted_cost)) {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", "job_id and budgeted_hours or budgeted_cost required")
        }

        // Verify job exists and belongs to company
        const { data: job } = await supabase
          .from("jobs")
          .select("id")
          .eq("id", job_id)
          .eq("company_id", userRecord.company_id)
          .maybeSingle()

        if (!job) {
          return errorResponse(requestId, 404, "NOT_FOUND", "Job not found")
        }

        const budgetId = crypto.randomUUID()
        const now = new Date().toISOString()

        // Calculate derived values
        const hours = budgeted_hours || 0
        const cost = budgeted_cost || 0
        const rate = hourly_rate || (hours > 0 ? cost / hours : 0)

        const { error: insertError } = await supabaseAdmin
          .from("job_budgets")
          .insert({
            id: budgetId,
            company_id: userRecord.company_id,
            job_id,
            budgeted_hours: hours,
            budgeted_cost: cost,
            hourly_rate: rate,
            warning_threshold_percent: warning_threshold_percent || 80.0,
            created_by: user.id,
            created_at: now,
          })

        if (insertError) {
          if (insertError.message?.includes("unique constraint")) {
            return errorResponse(requestId, 409, "DUPLICATE", "Budget already exists for this job")
          }
          throw insertError
        }

        const responseBody = { status: "success", budget_id: budgetId, request_id: requestId }
        await storeIdempotency(supabaseAdmin, user.id, ENDPOINT, idempotencyKey, requestHash, 201, responseBody, requestId)
        logRequestResult(ENDPOINT, requestId, 201, { action: "create", budget_id: budgetId })
        return jsonResponse(responseBody, 201, requestId, rateLimit.headers)
      }

      // Update budget
      if (action === "update") {
        const { budget_id, budgeted_hours, budgeted_cost, hourly_rate, warning_threshold_percent } = payload

        if (!budget_id) {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", "budget_id required")
        }

        const updates: Record<string, unknown> = {}
        if (budgeted_hours !== undefined) updates.budgeted_hours = budgeted_hours
        if (budgeted_cost !== undefined) updates.budgeted_cost = budgeted_cost
        if (hourly_rate !== undefined) updates.hourly_rate = hourly_rate
        if (warning_threshold_percent !== undefined) updates.warning_threshold_percent = warning_threshold_percent

        if (Object.keys(updates).length === 0) {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", "No fields to update")
        }

        const { error: updateError } = await supabaseAdmin
          .from("job_budgets")
          .update(updates)
          .eq("id", budget_id)
          .eq("company_id", userRecord.company_id)

        if (updateError) throw updateError

        const responseBody = { status: "success", budget_id, request_id: requestId }
        await storeIdempotency(supabaseAdmin, user.id, ENDPOINT, idempotencyKey, requestHash, 200, responseBody, requestId)
        logRequestResult(ENDPOINT, requestId, 200, { action: "update", budget_id })
        return jsonResponse(responseBody, 200, requestId, rateLimit.headers)
      }

      // Delete budget
      if (action === "delete") {
        const { budget_id } = payload

        if (!budget_id) {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", "budget_id required")
        }

        const { error: deleteError } = await supabaseAdmin
          .from("job_budgets")
          .delete()
          .eq("id", budget_id)
          .eq("company_id", userRecord.company_id)

        if (deleteError) throw deleteError

        const responseBody = { status: "success", budget_id, request_id: requestId }
        await storeIdempotency(supabaseAdmin, user.id, ENDPOINT, idempotencyKey, requestHash, 200, responseBody, requestId)
        logRequestResult(ENDPOINT, requestId, 200, { action: "delete", budget_id })
        return jsonResponse(responseBody, 200, requestId, rateLimit.headers)
      }

      return errorResponse(requestId, 400, "INVALID_PAYLOAD", "action must be 'create', 'update', or 'delete'")
    }

    return errorResponse(requestId, 405, "METHOD_NOT_ALLOWED", "Use GET or POST")
  } catch (error) {
    logRequestError(ENDPOINT, requestId, error)
    return errorResponse(requestId, 500, "INTERNAL_ERROR", error.message || "Internal server error")
  }
})
