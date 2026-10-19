import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.4"
import {
  applyRateLimit,
  corsHeaders,
  errorResponse,
  isValidGpsCoordinates,
  jsonResponse,
  logRequestError,
  logRequestResult,
  logRequestStart,
  lookupIdempotency,
  makeRequestId,
  sha256Hex,
  storeIdempotency,
} from "../_shared/api.ts"

const DEFAULT_BUCKET = "fieldops-media"
const DEFAULT_UPLOAD_EXPIRY_SECONDS = 900
const MEDIA_RATE_LIMIT = 20
const ENDPOINT = "media_presign"

function getUploadExtension(mimeType: string) {
  switch (mimeType) {
    case "image/png":
      return "png"
    case "image/webp":
      return "webp"
    default:
      return "jpg"
  }
}

function getExpiresAt(uploadUrl: string) {
  try {
    const token = new URL(uploadUrl).searchParams.get("token")
    if (!token) {
      return new Date(Date.now() + (DEFAULT_UPLOAD_EXPIRY_SECONDS * 1000)).toISOString()
    }

    const [, payload] = token.split(".")
    if (!payload) {
      return new Date(Date.now() + (DEFAULT_UPLOAD_EXPIRY_SECONDS * 1000)).toISOString()
    }

    const decoded = JSON.parse(atob(payload.replace(/-/g, "+").replace(/_/g, "/")))
    if (typeof decoded.exp !== "number") {
      return new Date(Date.now() + (DEFAULT_UPLOAD_EXPIRY_SECONDS * 1000)).toISOString()
    }

    return new Date(decoded.exp * 1000).toISOString()
  } catch {
    return new Date(Date.now() + (DEFAULT_UPLOAD_EXPIRY_SECONDS * 1000)).toISOString()
  }
}

function getPublicOrigin(req: Request) {
  const requestUrl = new URL(req.url)
  const forwardedProto = req.headers.get("x-forwarded-proto") || requestUrl.protocol.replace(":", "")
  const forwardedHost = req.headers.get("x-forwarded-host")
  const forwardedPort = req.headers.get("x-forwarded-port")

  if (!forwardedHost) {
    return requestUrl.origin
  }

  const host = forwardedHost.includes(":") || !forwardedPort
    ? forwardedHost
    : `${forwardedHost}:${forwardedPort}`

  return `${forwardedProto}://${host}`
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders(req) })
  }

  const requestId = makeRequestId(req)
  logRequestStart(ENDPOINT, requestId, req)

  try {
    if (req.method !== "POST") {
      return errorResponse(requestId, 405, "METHOD_NOT_ALLOWED", "Use POST for /media/presign")
    }

    const authHeader = req.headers.get("Authorization")
    if (!authHeader) {
      return errorResponse(requestId, 401, "UNAUTHORIZED", "Missing Authorization header")
    }

    const idempotencyKey = req.headers.get("Idempotency-Key")
    if (!idempotencyKey) {
      return errorResponse(requestId, 400, "INVALID_PAYLOAD", "Idempotency-Key header is required")
    }

    const payload = await req.json()
    const {
      job_id,
      task_id,
      bucket_name,
      content_type,
      mime_type,
      file_size_bytes,
      captured_at,
      gps,
    } = payload

    const resolvedMimeType = mime_type || content_type
    const resolvedBucketName = bucket_name || DEFAULT_BUCKET

    if (!job_id || !resolvedMimeType || !file_size_bytes) {
      return errorResponse(requestId, 400, "INVALID_PAYLOAD", "job_id, mime_type, and file_size_bytes are required")
    }
    if (resolvedBucketName !== DEFAULT_BUCKET) {
      return errorResponse(requestId, 400, "INVALID_PAYLOAD", "Unsupported bucket")
    }
    if (!["image/jpeg", "image/png", "image/webp"].includes(resolvedMimeType)) {
      return errorResponse(requestId, 400, "INVALID_PAYLOAD", "Unsupported mime type")
    }
    if (file_size_bytes < 1 || file_size_bytes > 15728640) {
      return errorResponse(requestId, 400, "INVALID_PAYLOAD", "file_size_bytes must be between 1 and 15728640")
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
      .select("id, company_id, is_active")
      .eq("id", user.id)
      .single()

    if (userError || !userRecord) {
      return errorResponse(requestId, 401, "UNAUTHORIZED", "User record not found")
    }
    if (!userRecord.is_active) {
      return errorResponse(requestId, 403, "FORBIDDEN", "User is inactive")
    }

    const requestHash = await sha256Hex(JSON.stringify(payload))
    const replay = await lookupIdempotency(supabaseAdmin, user.id, ENDPOINT, idempotencyKey, requestHash)
    if (replay.replay) {
      if (replay.conflict) {
        return errorResponse(replay.requestId, 409, "CONFLICT", "Idempotency key was reused with a different payload")
      }
      return jsonResponse(replay.body, replay.status, replay.requestId)
    }

    const rateLimit = await applyRateLimit(supabaseAdmin, user.id, ENDPOINT, requestId, MEDIA_RATE_LIMIT)
    if (rateLimit.limited) {
      return errorResponse(requestId, 429, "RATE_LIMITED", "Too many media requests", [], rateLimit.headers)
    }

    const { data: assignment, error: assignmentError } = await supabase
      .from("assignments")
      .select("job_id")
      .eq("user_id", user.id)
      .eq("job_id", job_id)
      .eq("is_active", true)
      .maybeSingle()

    if (assignmentError) {
      throw assignmentError
    }
    if (!assignment) {
      return errorResponse(requestId, 403, "FORBIDDEN", "User is not assigned to this job")
    }

    if (task_id) {
      const { data: task, error: taskError } = await supabase
        .from("tasks")
        .select("id")
        .eq("id", task_id)
        .eq("job_id", job_id)
        .maybeSingle()

      if (taskError) {
        throw taskError
      }
      if (!task) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "task_id does not belong to the provided job")
      }
    }

    const assetId = crypto.randomUUID()
    const extension = getUploadExtension(resolvedMimeType)
    const storagePath = `${userRecord.company_id}/${job_id}/${assetId}.${extension}`

    const { error: insertError } = await supabaseAdmin.from("media_assets").insert([{
      id: assetId,
      company_id: userRecord.company_id,
      job_id: job_id,
      task_id: task_id,
      uploaded_by: user.id,
      kind: "raw_photo",
      bucket_name: resolvedBucketName,
      storage_path: storagePath,
      mime_type: resolvedMimeType,
      file_size_bytes: file_size_bytes,
      captured_at: captured_at || null,
      gps_lat: isValidGpsCoordinates(gps?.lat, gps?.lng) ? gps.lat : null,
      gps_lng: isValidGpsCoordinates(gps?.lat, gps?.lng) ? gps.lng : null,
      gps_accuracy_m: isValidGpsCoordinates(gps?.lat, gps?.lng) ? (gps?.accuracy_m || null) : null,
      sync_status: "pending",
    }])

    if (insertError) {
      console.error("Insert error:", insertError)
      return errorResponse(requestId, 500, "INTERNAL_ERROR", "Could not create media asset record")
    }

    const { data: signedData, error: signedError } = await supabaseAdmin
      .storage
      .from(resolvedBucketName)
      .createSignedUploadUrl(storagePath)

    if (signedError) {
      await supabaseAdmin.from("media_assets").delete().eq("id", assetId)
      console.error("Storage signed URL error:", signedError)
      return errorResponse(requestId, 500, "INTERNAL_ERROR", "Failed to generate upload URL")
    }

    const publicOrigin = getPublicOrigin(req)
    const origin = new URL(publicOrigin)
    const uploadUrl = new URL(signedData?.signedUrl || "", publicOrigin)
    uploadUrl.protocol = origin.protocol
    uploadUrl.host = origin.host

    const responseBody = {
      status: "success",
      upload_url: uploadUrl.toString(),
      upload_method: "PUT",
      upload_headers: {
        "Content-Type": resolvedMimeType,
      },
      media_asset_id: assetId,
      storage_path: storagePath,
      expires_at: getExpiresAt(uploadUrl.toString()),
      request_id: requestId,
    }

    await storeIdempotency(
      supabaseAdmin,
      user.id,
      ENDPOINT,
      idempotencyKey,
      requestHash,
      201,
      responseBody,
      requestId,
    )

    logRequestResult(ENDPOINT, requestId, 201, {
      user_id: user.id,
      media_asset_id: assetId,
    })
    return jsonResponse(responseBody, 201, requestId, rateLimit.headers)
  } catch (error) {
    logRequestError(ENDPOINT, requestId, error)
    console.error("media_presign error:", error)
    return errorResponse(requestId, 500, "INTERNAL_ERROR", error.message || "Internal server error")
  }
})
