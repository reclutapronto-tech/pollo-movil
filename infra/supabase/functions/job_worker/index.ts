import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.4"
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import {
  corsHeaders,
  errorResponse,
  jsonResponse,
  logRequestStart,
  makeRequestId,
  logRequestError,
} from "../_shared/api.ts"

/**
 * job_worker — Background job processor edge function.
 *
 * Called by a cron/scheduler to claim and execute queued background jobs
 * from the `background_jobs` table.
 *
 * Supported job types:
 *   - "send_notification" — dispatch push notification
 *   - "generate_report"  — trigger report generation
 *   - "cleanup_expired"  — clean stale data
 */

const ENDPOINT = "job_worker"
const MAX_JOBS_PER_INVOCATION = 5

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

    // Verify internal caller via CRON_SECRET. This endpoint runs with the
    // service-role key and must only be invoked by the scheduled cron job.
    // A presence-only Authorization check is not enough — validate the
    // secret explicitly.
    const cronSecret = Deno.env.get("CRON_SECRET") || ""
    if (!cronSecret || req.headers.get("x-cron-secret") !== cronSecret) {
      return errorResponse(requestId, 401, "UNAUTHORIZED", "Invalid or missing cron secret")
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") || ""
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || ""
    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey)

    const results: Array<{ id: string; type: string; status: "completed" | "failed"; error?: string }> = []

    for (let i = 0; i < MAX_JOBS_PER_INVOCATION; i++) {
      // Claim next pending job
      const { data: claimed, error: claimErr } = await supabaseAdmin.rpc("claim_next_job")

      if (claimErr) {
        console.error(`[${ENDPOINT}] claim error:`, claimErr.message)
        break
      }

      if (!claimed || claimed.length === 0) {
        break // No more pending jobs
      }

      const job = claimed[0]

      try {
        await processJob(supabaseAdmin, job)
        await supabaseAdmin.rpc("complete_job", { p_id: job.id })
        results.push({ id: job.id, type: job.job_type, status: "completed" })
      } catch (e) {
        const errMsg = e instanceof Error ? e.message : "Unknown error"
        await supabaseAdmin.rpc("complete_job", { p_id: job.id, p_error: errMsg })
        results.push({ id: job.id, type: job.job_type, status: "failed", error: errMsg })
      }
    }

    return jsonResponse({
      processed: results.length,
      results,
      request_id: requestId,
    }, 200, requestId)
  } catch (e) {
    logRequestError("job_worker", requestId, e)
    return errorResponse(requestId, 500, "INTERNAL_ERROR", e instanceof Error ? e.message : "Unknown error")
  }
})

interface BackgroundJob {
  id: string
  job_type: string
  payload: Record<string, unknown>
  attempts: number
}

async function processJob(
  supabase: ReturnType<typeof createClient>,
  job: BackgroundJob,
): Promise<void> {
  switch (job.job_type) {
    case "send_notification": {
      const { user_id, title, body } = job.payload as { user_id?: string; title?: string; body?: string }
      if (!user_id || !title) throw new Error("Missing user_id or title in payload")
      // Insert into a notifications table (or integrate with push service)
      await supabase.from("alert_events").insert({
        user_id,
        alert_type: "push_notification",
        message: `${title}: ${body ?? ""}`,
        payload: job.payload,
      })
      break
    }

    case "generate_report": {
      const { job_id, report_type } = job.payload as { job_id?: string; report_type?: string }
      if (!job_id) throw new Error("Missing job_id in payload")
      console.log(`[${ENDPOINT}] Generating ${report_type ?? "standard"} report for job ${job_id}`)
      // Placeholder — in production, call the reports edge function or compute inline
      break
    }

    case "cleanup_expired": {
      // Clean synced events older than 7 days
      const cutoff = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString()
      const { error } = await supabase
        .from("background_jobs")
        .delete()
        .eq("status", "completed")
        .lt("completed_at", cutoff)
      if (error) throw new Error(`Cleanup failed: ${error.message}`)
      break
    }

    default:
      throw new Error(`Unknown job type: ${job.job_type}`)
  }
}
