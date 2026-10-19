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

const ENDPOINT = "media_optimize"
const WEBP_QUALITY = 0.80
const MAX_DIMENSION = 2048

declare const OffscreenCanvas: {
  new (width: number, height: number): {
    getContext(contextId: "2d"): { drawImage: (...args: unknown[]) => void } | null
    convertToBlob(options: { type: string; quality: number }): Promise<Blob>
  }
}

type MediaAssetRow = {
  id: string
  bucket_name: string
  storage_path: string
  mime_type: string
  file_size_bytes: number
  kind: string
  company_id: string
  metadata: Record<string, unknown> | null
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders(req) })
  }

  const requestId = makeRequestId(req)
  logRequestStart(ENDPOINT, requestId, req)

  try {
    if (req.method !== "POST") {
      return errorResponse(requestId, 405, "METHOD_NOT_ALLOWED", "Use POST for /media_optimize")
    }

    // Require CRON_SECRET for all invocations. This endpoint runs with the
    // service-role key and bypasses RLS; it must never be callable by an
    // unauthenticated client. The cron scheduler is configured to send this
    // header on every scheduled call.
    const cronSecret = Deno.env.get("CRON_SECRET") || ""
    if (!cronSecret || req.headers.get("x-cron-secret") !== cronSecret) {
      return errorResponse(requestId, 401, "UNAUTHORIZED", "Invalid or missing cron secret")
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") || ""
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || ""
    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey)

    const payload = await req.json()
    const { media_asset_id, job_id: bgJobId } = payload

    // ── Mode 1: Direct call with media_asset_id ──
    // ── Mode 2: Background job polling (no media_asset_id) ──
    const assetIds: string[] = []

    if (media_asset_id) {
      assetIds.push(media_asset_id)
    } else {
      // Claim up to 5 pending media_optimize jobs from the queue
      const { data: jobs, error: claimError } = await supabaseAdmin
        .rpc("claim_next_job", { p_types: ["media_optimize"] })

      if (claimError) {
        throw claimError
      }

      if (jobs && Array.isArray(jobs)) {
        for (const job of jobs) {
          if (job.payload?.media_asset_id) {
            assetIds.push(job.payload.media_asset_id)
          }
          // Complete the background job claim
          await supabaseAdmin.rpc("complete_job", { p_id: job.id })
        }
      }
    }

    if (assetIds.length === 0) {
      return jsonResponse(
        { status: "success", message: "No assets to optimize", optimized: 0, request_id: requestId },
        200,
        requestId,
      )
    }

    const results: Array<{
      media_asset_id: string
      original_bytes: number
      optimized_bytes: number
      compression_ratio: number
      status: string
    }> = []

    for (const assetId of assetIds) {
      try {
        const result = await optimizeAsset(supabaseAdmin, assetId, requestId)
        results.push(result)
      } catch (err) {
        console.error(`[${requestId}] Failed to optimize ${assetId}:`, err)
        results.push({
          media_asset_id: assetId,
          original_bytes: 0,
          optimized_bytes: 0,
          compression_ratio: 1,
          status: "failed",
        })

        // If this was a background job, re-enqueue with error
        if (bgJobId) {
          await supabaseAdmin.rpc("complete_job", {
            p_id: bgJobId,
            p_error: err instanceof Error ? err.message : String(err),
          })
        }
      }
    }

    const responseBody = {
      status: "success",
      optimized: results.filter((r) => r.status === "optimized").length,
      skipped: results.filter((r) => r.status === "skipped").length,
      failed: results.filter((r) => r.status === "failed").length,
      results,
      request_id: requestId,
    }

    logRequestResult(ENDPOINT, requestId, 200, {
      optimized_count: responseBody.optimized,
      skipped_count: responseBody.skipped,
    })

    return jsonResponse(responseBody, 200, requestId)
  } catch (error) {
    logRequestError(ENDPOINT, requestId, error)
    console.error("media_optimize error:", error)
    return errorResponse(
      requestId,
      500,
      "INTERNAL_ERROR",
      error instanceof Error ? error.message : "Internal server error",
    )
  }
})

async function optimizeAsset(
  supabaseAdmin: any,
  assetId: string,
  requestId: string,
) {
  // Fetch the asset record
  const { data: assetRow, error: assetError } = await supabaseAdmin
    .from("media_assets")
    .select("id, bucket_name, storage_path, mime_type, file_size_bytes, kind, company_id, metadata")
    .eq("id", assetId)
    .single()

  if (assetError || !assetRow) {
    throw new Error(`Asset ${assetId} not found`)
  }
  const asset = assetRow as MediaAssetRow

  // Skip if already optimized or not a photo
  if (asset.kind === "optimized_photo") {
    return {
      media_asset_id: assetId,
      original_bytes: asset.file_size_bytes,
      optimized_bytes: asset.file_size_bytes,
      compression_ratio: 1,
      status: "skipped",
    }
  }

  // Skip non-image types
  if (!["image/jpeg", "image/png", "image/webp"].includes(asset.mime_type)) {
    return {
      media_asset_id: assetId,
      original_bytes: asset.file_size_bytes,
      optimized_bytes: asset.file_size_bytes,
      compression_ratio: 1,
      status: "skipped",
    }
  }

  // Download original from storage
  const { data: fileData, error: downloadError } = await supabaseAdmin
    .storage
    .from(asset.bucket_name)
    .download(asset.storage_path)

  if (downloadError || !fileData) {
    throw new Error(`Failed to download ${asset.storage_path}: ${downloadError?.message}`)
  }

  const originalBytes = fileData.size
  let optimizedBlob: Blob
  let optimizedMimeType = "image/webp"

  // Attempt canvas-based re-encoding to WebP
  try {
    const imageBitmap = await createImageBitmap(fileData)

    // Scale down if larger than MAX_DIMENSION
    let targetWidth = imageBitmap.width
    let targetHeight = imageBitmap.height

    if (targetWidth > MAX_DIMENSION || targetHeight > MAX_DIMENSION) {
      const scale = MAX_DIMENSION / Math.max(targetWidth, targetHeight)
      targetWidth = Math.round(targetWidth * scale)
      targetHeight = Math.round(targetHeight * scale)
    }

    const canvas = new OffscreenCanvas(targetWidth, targetHeight)
    const ctx = canvas.getContext("2d")
    if (!ctx) {
      throw new Error("Failed to get 2d context")
    }

    ctx.drawImage(imageBitmap, 0, 0, targetWidth, targetHeight)
    optimizedBlob = await canvas.convertToBlob({
      type: "image/webp",
      quality: WEBP_QUALITY,
    })
    imageBitmap.close()
  } catch (canvasErr) {
    // Canvas API not available in this runtime — enqueue for external processing
    console.warn(`[${requestId}] Canvas encoding unavailable, enqueuing background job:`, canvasErr)

    await supabaseAdmin.rpc("enqueue_job", {
      p_type: "media_optimize_external",
      p_payload: { media_asset_id: assetId, reason: "canvas_unavailable" },
    })

    return {
      media_asset_id: assetId,
      original_bytes: originalBytes,
      optimized_bytes: originalBytes,
      compression_ratio: 1,
      status: "enqueued",
    }
  }

  const optimizedBytes = optimizedBlob.size

  // Only upload if we actually achieved compression (>5% reduction)
  if (optimizedBytes >= originalBytes * 0.95) {
    return {
      media_asset_id: assetId,
      original_bytes: originalBytes,
      optimized_bytes: originalBytes,
      compression_ratio: 1,
      status: "skipped",
    }
  }

  // Upload optimized version alongside original
  const optimizedPath = asset.storage_path.replace(/\.[^.]+$/, "_optimized.webp")

  const { error: uploadError } = await supabaseAdmin
    .storage
    .from(asset.bucket_name)
    .upload(optimizedPath, optimizedBlob, {
      contentType: optimizedMimeType,
      upsert: true,
    })

  if (uploadError) {
    throw new Error(`Failed to upload optimized: ${uploadError.message}`)
  }

  // Insert a derivative record in media_assets
  const { error: insertError } = await supabaseAdmin
    .from("media_assets")
    .insert({
      id: crypto.randomUUID(),
      company_id: asset.company_id,
      job_id: null,
      uploaded_by: null,
      // `optimized_photo` isn't in the media_kind enum — a compressed/optimized
      // derivative is functionally a stamped_photo variant from the viewer's
      // perspective, so store it under the closest valid kind and link it via
      // the stamped_media_id pointer from the original.
      kind: "stamped_photo",
      bucket_name: asset.bucket_name,
      storage_path: optimizedPath,
      mime_type: optimizedMimeType,
      file_size_bytes: optimizedBytes,
      sync_status: "processed",
      original_media_id: assetId,
    })

  // Insert may still fail for unrelated reasons — fall back to updating the
  // original asset pointer directly so the optimized bytes aren't orphaned.
  if (insertError) {
    console.warn(`[${requestId}] Could not insert derivative record (${insertError.message}), recording pointer on original`)
    // media_assets has no optimized_path/optimized_size_bytes columns — record
    // the pointer in the existing metadata jsonb (merged so we don't clobber it).
    await supabaseAdmin
      .from("media_assets")
      .update({
        metadata: {
          ...(asset.metadata ?? {}),
          optimized_path: optimizedPath,
          optimized_size_bytes: optimizedBytes,
        },
      })
      .eq("id", assetId)
  }

  const compressionRatio = +(originalBytes / optimizedBytes).toFixed(2)
  console.log(
    `[${requestId}] Optimized ${assetId}: ${originalBytes} → ${optimizedBytes} bytes (${compressionRatio}x compression)`,
  )

  return {
    media_asset_id: assetId,
    original_bytes: originalBytes,
    optimized_bytes: optimizedBytes,
    compression_ratio: compressionRatio,
    status: "optimized",
  }
}
