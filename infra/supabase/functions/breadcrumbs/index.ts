import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.4"
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import {
  corsHeaders,
  errorResponse,
  isValidGpsCoordinates,
  jsonResponse,
  logRequestStart,
  makeRequestId,
  logRequestError,
} from "../_shared/api.ts"

const ENDPOINT = "breadcrumbs"

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
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") || ""
    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    })

    const { data: { user }, error: authError } = await supabase.auth.getUser()
    if (authError || !user) {
      return errorResponse(requestId, 401, "UNAUTHORIZED", "Invalid or expired token")
    }

    // GET — fetch breadcrumbs for a user + shift_date
    if (req.method === "GET") {
      const url = new URL(req.url)
      const userId = url.searchParams.get("user_id") || user.id
      const shiftDate = url.searchParams.get("shift_date")
      const jobId = url.searchParams.get("job_id")

      if (!shiftDate) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "shift_date is required")
      }

      let query = supabase
        .from("gps_breadcrumbs")
        .select("id, user_id, job_id, latitude, longitude, accuracy_m, recorded_at, shift_date")
        .eq("user_id", userId)
        .eq("shift_date", shiftDate)
        .order("recorded_at", { ascending: true })

      if (jobId) {
        query = query.eq("job_id", jobId)
      }

      const { data, error } = await query.limit(500)

      if (error) {
        return errorResponse(requestId, 500, "DB_ERROR", error.message)
      }

      return jsonResponse({ breadcrumbs: data ?? [], request_id: requestId }, 200, requestId)
    }

    // POST — insert breadcrumb(s)
    if (req.method === "POST") {
      const payload = await req.json()
      const { breadcrumbs } = payload

      if (!Array.isArray(breadcrumbs) || breadcrumbs.length === 0) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "breadcrumbs array is required")
      }

      if (breadcrumbs.length > 100) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "Max 100 breadcrumbs per batch")
      }

      const rows = []
      for (const bc of breadcrumbs) {
        if (!bc.job_id || !bc.latitude || !bc.longitude || !bc.shift_date) {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", "Each breadcrumb needs job_id, latitude, longitude, shift_date")
        }
        if (!isValidGpsCoordinates(bc.latitude, bc.longitude)) {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", "Invalid GPS coordinates")
        }
        rows.push({
          user_id: user.id,
          job_id: bc.job_id,
          latitude: bc.latitude,
          longitude: bc.longitude,
          accuracy_m: bc.accuracy_m ?? null,
          recorded_at: bc.recorded_at ?? new Date().toISOString(),
          shift_date: bc.shift_date,
        })
      }

      const { error } = await supabase.from("gps_breadcrumbs").insert(rows)

      if (error) {
        return errorResponse(requestId, 500, "DB_ERROR", error.message)
      }

      return jsonResponse({ inserted: rows.length, request_id: requestId }, 200, requestId)
    }

    return errorResponse(requestId, 405, "METHOD_NOT_ALLOWED", "Use GET or POST")
  } catch (e) {
    logRequestError(ENDPOINT, requestId, e)
    return errorResponse(requestId, 500, "INTERNAL_ERROR", e instanceof Error ? e.message : "Unknown error")
  }
})
