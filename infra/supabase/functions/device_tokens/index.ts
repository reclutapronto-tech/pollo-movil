// Device token registration for push notifications (FCM / APNs).
//
// Actions:
//   POST register  — upsert device token for the authenticated user
//   POST unregister — remove device token (on sign-out)
//   GET  list       — list tokens for a user (admin/supervisor only)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import {
  corsHeaders,
  errorResponse,
  jsonResponse,
  logRequestStart,
  logRequestResult,
  logRequestError,
  makeRequestId,
} from "../_shared/api.ts"

const ENDPOINT = "device_tokens"

Deno.serve(async (req) => {
  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders(req) })
  }

  const requestId = makeRequestId(req)
  logRequestStart(ENDPOINT, requestId, req)

  try {
    // Auth
    const authHeader = req.headers.get("Authorization")
    if (!authHeader) {
      const r = errorResponse(requestId, 401, "UNAUTHORIZED", "Missing authorization header")
      logRequestResult(ENDPOINT, requestId, 401)
      return r
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    )

    const { data: { user }, error: authError } = await supabase.auth.getUser()
    if (authError || !user) {
      const r = errorResponse(requestId, 401, "UNAUTHORIZED", "Invalid session")
      logRequestResult(ENDPOINT, requestId, 401)
      return r
    }

    // Resolve role + company from the DB (NOT JWT metadata, which can be stale
    // after a role change / company move). All operations below use the service
    // role with explicit company scoping rather than leaning on the JWT.
    const supabaseAdmin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    )
    const { data: userRecord, error: userError } = await supabaseAdmin
      .from("users")
      .select("id, company_id, role, is_active")
      .eq("id", user.id)
      .single()
    if (userError || !userRecord) {
      const r = errorResponse(requestId, 401, "UNAUTHORIZED", "User record not found")
      logRequestResult(ENDPOINT, requestId, 401)
      return r
    }
    if (!userRecord.is_active) {
      const r = errorResponse(requestId, 403, "FORBIDDEN", "User is inactive")
      logRequestResult(ENDPOINT, requestId, 403)
      return r
    }
    const userId = userRecord.id
    const companyId = userRecord.company_id

    // Route by method
    if (req.method === "GET") {
      // List tokens — supervisor/admin only (role from DB, not JWT)
      if (!["owner", "supervisor", "admin", "platform_admin"].includes(userRecord.role)) {
        const r = errorResponse(requestId, 403, "FORBIDDEN", "Supervisors only")
        logRequestResult(ENDPOINT, requestId, 403)
        return r
      }

      const url = new URL(req.url)
      const targetUserId = url.searchParams.get("user_id")

      // Always scope to the caller's company (service role bypasses RLS, so this
      // explicit filter is the tenant guard); optionally narrow to one user.
      let query = supabaseAdmin
        .from("device_tokens")
        .select("id, user_id, platform, created_at, last_seen_at")
        .eq("company_id", companyId)
        .order("last_seen_at", { ascending: false })
        .limit(50)

      if (targetUserId) {
        query = query.eq("user_id", targetUserId)
      }

      const { data, error } = await query
      if (error) {
        logRequestError(ENDPOINT, requestId, error)
        const r = errorResponse(requestId, 500, "QUERY_FAILED", "Failed to list tokens")
        logRequestResult(ENDPOINT, requestId, 500)
        return r
      }

      const r = jsonResponse({ status: "ok", tokens: data }, 200, requestId)
      logRequestResult(ENDPOINT, requestId, 200, { count: data?.length ?? 0 })
      return r
    }

    if (req.method !== "POST") {
      const r = errorResponse(requestId, 405, "METHOD_NOT_ALLOWED", "Use GET or POST")
      logRequestResult(ENDPOINT, requestId, 405)
      return r
    }

    // POST actions
    const body = await req.json()
    const action = body.action as string

    if (action === "register") {
      const token = body.token as string
      const platform = body.platform as string // 'ios' | 'android'

      if (!token || !platform) {
        const r = errorResponse(requestId, 400, "INVALID_PAYLOAD", "token and platform required")
        logRequestResult(ENDPOINT, requestId, 400)
        return r
      }

      if (!["ios", "android"].includes(platform)) {
        const r = errorResponse(requestId, 400, "INVALID_PLATFORM", "platform must be ios or android")
        logRequestResult(ENDPOINT, requestId, 400)
        return r
      }

      // Upsert: same user + token → update last_seen; new token → insert
      const { error } = await supabaseAdmin
        .from("device_tokens")
        .upsert(
          {
            user_id: userId,
            company_id: companyId,
            token,
            platform,
            last_seen_at: new Date().toISOString(),
          },
          { onConflict: "user_id,token" },
        )

      if (error) {
        logRequestError(ENDPOINT, requestId, error)
        const r = errorResponse(requestId, 500, "REGISTER_FAILED", "Failed to register token")
        logRequestResult(ENDPOINT, requestId, 500)
        return r
      }

      const r = jsonResponse({ status: "ok", message: "Token registered" }, 200, requestId)
      logRequestResult(ENDPOINT, requestId, 200, { action: "register", platform })
      return r
    }

    if (action === "unregister") {
      const token = body.token as string
      if (!token) {
        const r = errorResponse(requestId, 400, "INVALID_PAYLOAD", "token required")
        logRequestResult(ENDPOINT, requestId, 400)
        return r
      }

      const { error } = await supabaseAdmin
        .from("device_tokens")
        .delete()
        .eq("user_id", userId)
        .eq("token", token)

      if (error) {
        logRequestError(ENDPOINT, requestId, error)
        const r = errorResponse(requestId, 500, "UNREGISTER_FAILED", "Failed to remove token")
        logRequestResult(ENDPOINT, requestId, 500)
        return r
      }

      const r = jsonResponse({ status: "ok", message: "Token removed" }, 200, requestId)
      logRequestResult(ENDPOINT, requestId, 200, { action: "unregister" })
      return r
    }

    const r = errorResponse(requestId, 400, "UNKNOWN_ACTION", `Unknown action: ${action}`)
    logRequestResult(ENDPOINT, requestId, 400)
    return r
  } catch (err) {
    logRequestError(ENDPOINT, requestId, err)
    return errorResponse(requestId, 500, "INTERNAL_ERROR", "Unexpected server error")
  }
})
