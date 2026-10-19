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

// Permits Phase 2 — auto-expiry sweeper.
//
// Flips `work_permits.status` from 'issued' → 'expired' for any row whose
// `expires_at` has passed. Scoped by DB side only (no company filter) — the
// WHERE clause is the safety boundary. NULL `expires_at` means "never
// expires" and is intentionally skipped.
//
// Invocation: cron via Supabase Scheduler (hourly is plenty; permit gates on
// the mobile side compute "active" in-line from (status='issued' AND
// (expires_at IS NULL OR expires_at > now())) so a late sweep never lets an
// expired permit pass the clock-in gate — the sweep only keeps the admin UI
// honest.

const ENDPOINT = "permits_expiry_cron"

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders(req) })
  }

  const requestId = makeRequestId(req)
  logRequestStart(ENDPOINT, requestId, req)

  try {
    if (req.method !== "POST") {
      return errorResponse(requestId, 405, "METHOD_NOT_ALLOWED", "Use POST")
    }

    const cronSecret = Deno.env.get("CRON_SECRET") || ""
    if (!cronSecret || req.headers.get("x-cron-secret") !== cronSecret) {
      return errorResponse(requestId, 401, "UNAUTHORIZED", "Invalid or missing cron secret")
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") || ""
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || ""
    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey)

    const { data, error } = await supabaseAdmin
      .from("work_permits")
      .update({ status: "expired" })
      .eq("status", "issued")
      .not("expires_at", "is", null)
      .lt("expires_at", new Date().toISOString())
      .select("id, company_id, job_id, permit_number, expires_at")

    if (error) {
      logRequestError(ENDPOINT, requestId, error)
      return errorResponse(requestId, 500, "SWEEP_FAILED", error.message)
    }

    const flipped = data ?? []
    logRequestResult(ENDPOINT, requestId, 200, {
      expired_count: flipped.length,
      ids: flipped.map((r) => r.id),
    })

    return jsonResponse(
      {
        status: "success",
        expired: flipped.length,
        permits: flipped,
        request_id: requestId,
      },
      200,
      requestId,
    )
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err)
    logRequestError(ENDPOINT, requestId, err)
    return errorResponse(requestId, 500, "INTERNAL_ERROR", message)
  }
})
