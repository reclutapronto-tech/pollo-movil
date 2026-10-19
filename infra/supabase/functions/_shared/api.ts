import { captureEdgeError } from "./sentry.ts"

const stripTrailingSlash = (s: string) => s.replace(/\/+$/, "")

const ALLOWED_ORIGINS = (Deno.env.get("ALLOWED_ORIGINS") || "*")
  .split(",")
  .map((o: string) => stripTrailingSlash(o.trim()))

export function corsOrigin(req: Request): string {
  const origin = stripTrailingSlash(req.headers.get("Origin") || "")
  if (ALLOWED_ORIGINS.includes("*")) return "*"
  if (ALLOWED_ORIGINS.includes(origin)) return origin
  return ALLOWED_ORIGINS[0] || ""
}

// CORS_HEADERS does not include Access-Control-Allow-Origin — it is set dynamically
// by corsHeaders(req) for preflight and responseHeaders() for actual responses.
export const CORS_HEADERS = {
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, idempotency-key, x-request-id, x-client-version",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
}

export function corsHeaders(req: Request) {
  return {
    ...CORS_HEADERS,
    "Access-Control-Allow-Origin": corsOrigin(req),
  }
}

type JsonPrimitive = string | number | boolean | null
type JsonValue = JsonPrimitive | JsonValue[] | { [key: string]: JsonValue }
type JsonObject = Record<string, JsonValue>

function emitStructuredLog(level: "info" | "warn" | "error", payload: JsonObject) {
  const line = JSON.stringify({
    timestamp: new Date().toISOString(),
    level,
    ...payload,
  })

  if (level === "error") {
    console.error(line)
    return
  }

  if (level === "warn") {
    console.warn(line)
    return
  }

  console.log(line)
}

export function makeRequestId(req: Request) {
  return req.headers.get("x-request-id") || crypto.randomUUID()
}

export function logRequestStart(endpoint: string, requestId: string, req: Request, metadata: JsonObject = {}) {
  emitStructuredLog("info", {
    event: "request_start",
    endpoint,
    request_id: requestId,
    method: req.method,
    path: new URL(req.url).pathname,
    ...metadata,
  })
}

export function logRequestResult(
  endpoint: string,
  requestId: string,
  status: number,
  metadata: JsonObject = {},
) {
  emitStructuredLog(status >= 500 ? "error" : status >= 400 ? "warn" : "info", {
    event: "request_finish",
    endpoint,
    request_id: requestId,
    status,
    ...metadata,
  })
  if (status >= 500) {
    captureEdgeError(new Error(`request_finish ${status} on ${endpoint}`), {
      endpoint,
      requestId,
      status,
      metadata,
    })
  }
}

// requestIds whose failure was already sent to Sentry with a full stack
// via logRequestError — errorResponse() checks this to avoid a second,
// stackless event for the same request. Isolates are short-lived; the set
// stays tiny, but cap it defensively anyway.
const capturedRequestIds = new Set<string>()
const CAPTURED_IDS_MAX = 1000

export function markRequestCaptured(requestId: string) {
  if (capturedRequestIds.size >= CAPTURED_IDS_MAX) capturedRequestIds.clear()
  capturedRequestIds.add(requestId)
}

export function logRequestError(endpoint: string, requestId: string, error: unknown, metadata: JsonObject = {}) {
  emitStructuredLog("error", {
    event: "request_error",
    endpoint,
    request_id: requestId,
    error: error instanceof Error ? error.message : String(error),
    ...metadata,
  })
  // Every function's catch path funnels through here — one hook, full
  // fleet coverage. Fire-and-forget; never blocks the response.
  markRequestCaptured(requestId)
  captureEdgeError(error, { endpoint, requestId, metadata })
}

export function responseHeaders(requestId: string, extra: Record<string, string> = {}) {
  // Use the configured allowed origin (not a hardcoded wildcard).
  // In production, set the ALLOWED_ORIGINS env var to your domain(s).
  const origin = ALLOWED_ORIGINS.includes("*") ? "*" : (ALLOWED_ORIGINS[0] || "")
  return {
    ...CORS_HEADERS,
    "Access-Control-Allow-Origin": origin,
    "Content-Type": "application/json",
    "X-Request-ID": requestId,
    ...extra,
  }
}

export function jsonResponse(
  payload: JsonValue,
  status: number,
  requestId: string,
  extraHeaders: Record<string, string> = {},
) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: responseHeaders(requestId, extraHeaders),
  })
}

export function errorResponse(
  requestId: string,
  status: number,
  errorCode: string,
  message: string,
  details: JsonValue[] = [],
  extraHeaders: Record<string, string> = {},
) {
  // Safety net: every 5xx response reaches Sentry even when the calling
  // code returned errorResponse() directly without logRequestError().
  // Exception paths are deduped via markRequestCaptured().
  if (status >= 500 && !capturedRequestIds.has(requestId)) {
    markRequestCaptured(requestId)
    captureEdgeError(new Error(`${errorCode}: ${message}`), {
      endpoint: "errorResponse",
      requestId,
      status,
    })
  }
  return jsonResponse(
    {
      status: "error",
      error_code: errorCode,
      message,
      details,
      request_id: requestId,
    },
    status,
    requestId,
    extraHeaders,
  )
}

export async function sha256Hex(value: string) {
  const encoded = new TextEncoder().encode(value)
  const digest = await crypto.subtle.digest("SHA-256", encoded)
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("")
}

export async function lookupIdempotency(
  supabaseAdmin: any,
  userId: string,
  endpoint: string,
  idempotencyKey: string,
  requestHash: string,
) {
  const { data, error } = await supabaseAdmin
    .from("api_idempotency_keys")
    .select("response_status, response_body, request_id, request_hash")
    .eq("user_id", userId)
    .eq("endpoint", endpoint)
    .eq("idempotency_key", idempotencyKey)
    .maybeSingle()

  if (error) {
    throw error
  }

  if (!data) {
    return { replay: false as const }
  }

  if (data.request_hash !== requestHash) {
    return {
      replay: true as const,
      conflict: true as const,
      requestId: data.request_id as string,
    }
  }

  return {
    replay: true as const,
    conflict: false as const,
    requestId: data.request_id as string,
    status: data.response_status as number,
    body: data.response_body as JsonValue,
  }
}

export async function storeIdempotency(
  supabaseAdmin: any,
  userId: string,
  endpoint: string,
  idempotencyKey: string,
  requestHash: string,
  responseStatus: number,
  responseBody: JsonValue,
  requestId: string,
) {
  const { error } = await supabaseAdmin
    .from("api_idempotency_keys")
    .insert({
      user_id: userId,
      endpoint: endpoint,
      idempotency_key: idempotencyKey,
      request_hash: requestHash,
      response_status: responseStatus,
      response_body: responseBody,
      request_id: requestId,
    })

  if (error && error.code !== "23505") {
    throw error
  }
}

export async function applyRateLimit(
  supabaseAdmin: any,
  userId: string,
  endpoint: string,
  requestId: string,
  limit: number,
  windowSeconds = 60,
) {
  const now = new Date()
  const windowStart = new Date(now.getTime() - (windowSeconds * 1000)).toISOString()

  const { count, error } = await supabaseAdmin
    .from("api_request_logs")
    .select("*", { count: "exact", head: true })
    .eq("user_id", userId)
    .eq("endpoint", endpoint)
    .gte("created_at", windowStart)

  if (error) {
    throw error
  }

  const resetEpoch = Math.floor(now.getTime() / 1000) + windowSeconds
  if ((count || 0) >= limit) {
    return {
      limited: true as const,
      headers: {
        "X-RateLimit-Limit": String(limit),
        "X-RateLimit-Remaining": "0",
        "X-RateLimit-Reset": String(resetEpoch),
      },
    }
  }

  const { error: insertError } = await supabaseAdmin
    .from("api_request_logs")
    .insert({
      user_id: userId,
      endpoint: endpoint,
      request_id: requestId,
    })

  if (insertError) {
    throw insertError
  }

  return {
    limited: false as const,
    headers: {
      "X-RateLimit-Limit": String(limit),
      "X-RateLimit-Remaining": String(Math.max(limit - ((count || 0) + 1), 0)),
      "X-RateLimit-Reset": String(resetEpoch),
    },
  }
}

export function isValidGpsCoordinates(lat: unknown, lng: unknown): boolean {
  if (typeof lat !== "number" || typeof lng !== "number") return false
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return false
  if (lat < -90 || lat > 90) return false
  if (lng < -180 || lng > 180) return false
  return true
}

export function haversineDistanceMeters(
  lat1: number,
  lng1: number,
  lat2: number,
  lng2: number,
) {
  const earthRadiusM = 6371000
  const toRadians = (degrees: number) => degrees * (Math.PI / 180)

  const dLat = toRadians(lat2 - lat1)
  const dLng = toRadians(lng2 - lng1)
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRadians(lat1)) *
      Math.cos(toRadians(lat2)) *
      Math.sin(dLng / 2) *
      Math.sin(dLng / 2)

  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
  return earthRadiusM * c
}

// ─── Company Status Check ───────────────────────────────────

/**
 * Checks that a company is active. Returns a 403 error response if
 * the company is suspended or deleted. Call at the top of every
 * authenticated edge function handler after resolving the user record.
 */
export async function checkCompanyActive(
  supabaseAdmin: any,
  companyId: string,
  requestId: string,
): Promise<Response | null> {
  const { data: company } = await supabaseAdmin
    .from("companies")
    .select("status, deleted_at")
    .eq("id", companyId)
    .single()

  if (!company) {
    return errorResponse(requestId, 403, "FORBIDDEN", "Company not found")
  }

  if (company.deleted_at) {
    return errorResponse(requestId, 403, "FORBIDDEN", "Company has been deactivated")
  }

  if (company.status === "suspended") {
    return errorResponse(requestId, 403, "FORBIDDEN", "Company account is suspended. Contact support.")
  }

  return null // company is active
}

// ─── Admin Audit Logging ────────────────────────────────────

/**
 * Logs an admin action to the admin_audit_log table.
 * Captures IP address and user-agent for SOC2/GDPR compliance.
 */
export async function logAdminAction(
  supabaseAdmin: any,
  req: Request,
  params: {
    company_id?: string
    actor_id: string
    action: string
    target_type?: string
    target_id?: string
    before?: Record<string, unknown>
    after?: Record<string, unknown>
    settings_version?: number
  },
) {
  const ipAddress =
    req.headers.get("cf-connecting-ip") ||
    req.headers.get("x-real-ip") ||
    req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ||
    "unknown"

  const userAgent = req.headers.get("user-agent") || "unknown"

  const { error } = await supabaseAdmin.from("admin_audit_log").insert({
    company_id: params.company_id || null,
    actor_id: params.actor_id,
    action: params.action,
    target_type: params.target_type || null,
    target_id: params.target_id || null,
    before_json: params.before || null,
    after_json: params.after || null,
    settings_version: params.settings_version || null,
    ip_address: ipAddress,
    user_agent: userAgent,
  })

  if (error) {
    // Audit log failure is non-fatal — log to console but don't crash the request
    console.error("[audit] Failed to write audit log:", error.message)
  }
}
