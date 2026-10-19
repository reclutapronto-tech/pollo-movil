// Feature flags — resolve flags for the authenticated user's company.
//
// Actions:
//   GET    — list all flags resolved for the user's company (override wins over default)
//   POST   — set a company override for a flag (admin only)
//   DELETE — remove a company override, reverting to global default (admin only)

import "jsr:@supabase/functions-js/edge-runtime.d.ts"
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
import { isManagementRole } from "../_shared/roles.ts"

const ENDPOINT = "feature_flags"

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders(req) })
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

    const jwt = authHeader.replace("Bearer ", "")
    const { data: { user }, error: authError } = await supabase.auth.getUser()
    if (authError || !user) {
      return errorResponse(requestId, 401, "UNAUTHORIZED", "Invalid auth token")
    }

    // Resolve company + role from users table
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

    const companyId = userRecord.company_id
    const role = userRecord.role

    // ── GET — resolved flags for the user's company ──────────

    if (req.method === "GET") {
      const { data: flags, error: flagsErr } = await supabase
        .from("feature_flags")
        .select("flag_key, description, default_enabled, created_at, updated_at")
        .order("flag_key")

      if (flagsErr) {
        logRequestError(ENDPOINT, requestId, flagsErr)
        return errorResponse(requestId, 500, "QUERY_FAILED", "Failed to fetch feature flags")
      }

      const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || ""
      const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey)

      const { data: overrides, error: overridesErr } = await supabaseAdmin
        .from("company_feature_overrides")
        .select("flag_key, enabled")
        .eq("company_id", companyId)

      if (overridesErr) {
        logRequestError(ENDPOINT, requestId, overridesErr)
        return errorResponse(requestId, 500, "QUERY_FAILED", "Failed to fetch overrides")
      }

      const overrideMap = new Map<string, boolean>()
      for (const o of overrides ?? []) {
        overrideMap.set(o.flag_key, o.enabled)
      }

      const resolved = (flags ?? []).map((f) => ({
        flag_key: f.flag_key,
        description: f.description,
        enabled: overrideMap.has(f.flag_key) ? overrideMap.get(f.flag_key)! : f.default_enabled,
        source: overrideMap.has(f.flag_key) ? "company_override" : "default",
      }))

      logRequestResult(ENDPOINT, requestId, 200, { count: resolved.length })
      return jsonResponse({ status: "ok", flags: resolved }, 200, requestId)
    }

    // ── POST — set a company override (admin only) ───────────

    if (req.method === "POST") {
      if (!isManagementRole(role)) {
        return errorResponse(requestId, 403, "FORBIDDEN", "Only owners or admins can set feature overrides")
      }

      const body = await req.json()
      const flagKey = body.flag_key as string
      const enabled = body.enabled as boolean

      if (!flagKey || typeof enabled !== "boolean") {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "flag_key (string) and enabled (boolean) are required")
      }

      const { data: flag } = await supabase
        .from("feature_flags")
        .select("flag_key")
        .eq("flag_key", flagKey)
        .maybeSingle()

      if (!flag) {
        return errorResponse(requestId, 404, "NOT_FOUND", `Flag '${flagKey}' does not exist`)
      }

      const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || ""
      const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey)

      const { error: upsertErr } = await supabaseAdmin
        .from("company_feature_overrides")
        .upsert(
          { company_id: companyId, flag_key: flagKey, enabled },
          { onConflict: "company_id,flag_key" },
        )

      if (upsertErr) {
        logRequestError(ENDPOINT, requestId, upsertErr)
        return errorResponse(requestId, 500, "UPSERT_FAILED", "Failed to set override")
      }

      logRequestResult(ENDPOINT, requestId, 200, { action: "set_override", flag_key: flagKey, enabled })
      return jsonResponse({ status: "ok", flag_key: flagKey, enabled }, 200, requestId)
    }

    // ── DELETE — remove a company override (admin only) ──────

    if (req.method === "DELETE") {
      if (!isManagementRole(role)) {
        return errorResponse(requestId, 403, "FORBIDDEN", "Only owners or admins can remove feature overrides")
      }

      const url = new URL(req.url)
      const flagKey = url.searchParams.get("flag_key")

      if (!flagKey) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "flag_key query parameter is required")
      }

      const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || ""
      const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey)

      const { error: deleteErr } = await supabaseAdmin
        .from("company_feature_overrides")
        .delete()
        .eq("company_id", companyId)
        .eq("flag_key", flagKey)

      if (deleteErr) {
        logRequestError(ENDPOINT, requestId, deleteErr)
        return errorResponse(requestId, 500, "DELETE_FAILED", "Failed to remove override")
      }

      logRequestResult(ENDPOINT, requestId, 200, { action: "remove_override", flag_key: flagKey })
      return jsonResponse({ status: "ok", flag_key: flagKey, message: "Override removed, reverted to default" }, 200, requestId)
    }

    return errorResponse(requestId, 405, "METHOD_NOT_ALLOWED", "Use GET, POST, or DELETE")
  } catch (error) {
    logRequestError(ENDPOINT, requestId, error)
    return errorResponse(requestId, 500, "INTERNAL_ERROR", error.message || "Unexpected server error")
  }
})
