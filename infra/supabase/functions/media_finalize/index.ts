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

const ENDPOINT = "media_finalize"
const MEDIA_RATE_LIMIT = 20

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders(req) })
  }

  const requestId = makeRequestId(req)
  logRequestStart(ENDPOINT, requestId, req)

  try {
    if (req.method !== "POST") {
      return errorResponse(requestId, 405, "METHOD_NOT_ALLOWED", "Use POST for /media/finalize")
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
    const { media_asset_id, checksum_sha256, checksum } = payload
    if (!media_asset_id) {
      return errorResponse(requestId, 400, "INVALID_PAYLOAD", "Missing media_asset_id")
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

    const { data: userRecord, error: userError } = await supabaseAdmin
      .from("users")
      .select("id, company_id, is_active, role")
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

    const { data: asset, error: assetError } = await supabaseAdmin
      .from("media_assets")
      .select("id, bucket_name, storage_path, uploaded_by, company_id, job_id, task_id, captured_at, gps_lat, gps_lng, gps_accuracy_m, sync_status")
      .eq("id", media_asset_id)
      .maybeSingle()

    if (assetError) {
      throw assetError
    }
    if (!asset) {
      return errorResponse(requestId, 404, "NOT_FOUND", "Media asset not found")
    }
    if (asset.uploaded_by !== user.id || asset.company_id !== userRecord.company_id) {
      return errorResponse(requestId, 403, "FORBIDDEN", "Media asset does not belong to the authenticated user")
    }

    const { data: assignment, error: assignmentError } = await supabase
      .from("assignments")
      .select("job_id")
      .eq("user_id", user.id)
      .eq("job_id", asset.job_id)
      .eq("is_active", true)
      .maybeSingle()

    if (assignmentError) {
      throw assignmentError
    }
    if (!assignment) {
      return errorResponse(requestId, 403, "FORBIDDEN", "User is not assigned to this job")
    }

    const { error: storageError } = await supabaseAdmin
      .storage
      .from(asset.bucket_name)
      .download(asset.storage_path)

    if (storageError) {
      return errorResponse(requestId, 409, "CONFLICT", "Uploaded object not found")
    }

    const checksumValue = checksum_sha256 || checksum || null
    const { error: updateError } = await supabaseAdmin
      .from("media_assets")
      .update({ sync_status: "uploaded", sha256_hash: checksumValue })
      .eq("id", media_asset_id)
      .eq("uploaded_by", user.id)
      .eq("company_id", asset.company_id)

    if (updateError) {
      throw updateError
    }

    let photoEventId: string | null = null
    const { error: dedupeError } = await supabaseAdmin
      .from("ingest_event_keys")
      .insert({
        company_id: asset.company_id,
        event_type: "photo_event",
        source_event_uuid: media_asset_id,
      })

    if (dedupeError?.code === "23505") {
      const { data: existingPhotoEvent, error: existingPhotoEventError } = await supabaseAdmin
        .from("photo_events")
        .select("id")
        .eq("media_asset_id", media_asset_id)
        .order("created_at", { ascending: true })
        .limit(1)
        .maybeSingle()

      if (existingPhotoEventError) {
        throw existingPhotoEventError
      }

      photoEventId = existingPhotoEvent?.id || null
    } else if (dedupeError) {
      throw dedupeError
    } else {
      photoEventId = crypto.randomUUID()
      const { error: photoEventError } = await supabaseAdmin.from("photo_events").insert({
        id: photoEventId,
        company_id: asset.company_id,
        job_id: asset.job_id,
        task_id: asset.task_id,
        user_id: user.id,
        media_asset_id: media_asset_id,
        occurred_at: asset.captured_at || new Date().toISOString(),
        received_at: new Date().toISOString(),
        gps_lat: asset.gps_lat,
        gps_lng: asset.gps_lng,
        gps_accuracy_m: asset.gps_accuracy_m,
        is_checkpoint: false,
        source_event_uuid: media_asset_id,
      })

      if (photoEventError) {
        // Rollback: remove dedup key AND revert asset status to pending
        await Promise.all([
          supabaseAdmin
            .from("ingest_event_keys")
            .delete()
            .eq("company_id", asset.company_id)
            .eq("event_type", "photo_event")
            .eq("source_event_uuid", media_asset_id),
          supabaseAdmin
            .from("media_assets")
            .update({ sync_status: "pending", sha256_hash: null })
            .eq("id", media_asset_id)
            .eq("company_id", asset.company_id),
        ])
        throw photoEventError
      }
    }

    const responseBody = {
      status: "success",
      media_asset_id: media_asset_id,
      photo_event_id: photoEventId,
      request_id: requestId,
    }

    await storeIdempotency(
      supabaseAdmin,
      user.id,
      ENDPOINT,
      idempotencyKey,
      requestHash,
      200,
      responseBody,
      requestId,
    )

    // Trigger photo stamping asynchronously — non-blocking, does not affect response latency.
    // media_stamp computes SHA-256, creates SVG proof overlay, and writes a stamped_photo record.
    const stampUrl = `${supabaseUrl}/functions/v1/media_stamp`
    EdgeRuntime.waitUntil(
      fetch(stampUrl, {
        method: "POST",
        headers: {
          "Authorization": authHeader,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ media_asset_id }),
      }).then(async (res) => {
        if (!res.ok) {
          const body = await res.text()
          console.error(`media_stamp trigger failed (${res.status}): ${body}`)
        }
      }).catch((e) => {
        console.error("media_stamp trigger error:", e)
      })
    )

    logRequestResult(ENDPOINT, requestId, 200, {
      user_id: user.id,
      media_asset_id: media_asset_id,
      photo_event_id: photoEventId,
    })
    return jsonResponse(responseBody, 200, requestId, rateLimit.headers)
  } catch (error) {
    logRequestError(ENDPOINT, requestId, error)
    console.error("media_finalize error:", error)
    return errorResponse(requestId, 500, "INTERNAL_ERROR", error.message || "Internal server error")
  }
})
