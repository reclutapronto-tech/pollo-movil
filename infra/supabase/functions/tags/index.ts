// tags — photo tag CRUD, autocomplete, and job-scoped listing.
// Pattern: mirrors client_portal/index.ts for auth + structured logging,
// media_finalize/index.ts for idempotency on mutations.
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.4"
import {
  CORS_HEADERS,
  corsHeaders,
  errorResponse,
  jsonResponse,
  logRequestError,
  logRequestResult,
  logRequestStart,
  makeRequestId,
} from "../_shared/api.ts"

const ENDPOINT = "tags"
const MAX_BULK = 200
const MAX_TAG_LENGTH = 64

function normalizeTag(raw: unknown): string | null {
  if (typeof raw !== "string") return null
  const trimmed = raw.trim()
  if (trimmed.length < 1 || trimmed.length > MAX_TAG_LENGTH) return null
  return trimmed
}

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

    const url = new URL(req.url)
    const path = url.pathname.replace(/\/+$/, "")
    const isSuggest = path.endsWith("/suggest")

    // ── GET /tags?job_id= | GET /tags/suggest?q= ────────────────
    if (req.method === "GET") {
      if (isSuggest) {
        const q = (url.searchParams.get("q") || "").trim().toLowerCase()
        // Return most-used tags in the company, optionally filtered by prefix.
        // We fetch lightly (1000 rows) and aggregate in-process — photo_tags is
        // cheap to scan at tenant-scale and avoids adding a materialized view.
        let query = supabaseAdmin
          .from("photo_tags")
          .select("tag")
          .eq("company_id", userRecord.company_id)
          .limit(1000)
        if (q) query = query.ilike("tag", `${q}%`)

        const { data: rows, error } = await query
        if (error) throw error

        const counts = new Map<string, { tag: string; count: number }>()
        for (const row of rows || []) {
          const key = (row.tag as string).toLowerCase()
          const existing = counts.get(key)
          if (existing) {
            existing.count += 1
          } else {
            counts.set(key, { tag: row.tag as string, count: 1 })
          }
        }
        const suggestions = [...counts.values()]
          .sort((a, b) => b.count - a.count || a.tag.localeCompare(b.tag))
          .slice(0, 20)

        logRequestResult(ENDPOINT, requestId, 200, { op: "suggest", returned: suggestions.length })
        return jsonResponse({ status: "success", suggestions, request_id: requestId }, 200, requestId)
      }

      const jobId = url.searchParams.get("job_id")
      const includePhotos = url.searchParams.get("include_photos") === "1"
      // Join media_assets to scope by job. Aggregate tag usage counts for the UI.
      let query = supabaseAdmin
        .from("photo_tags")
        .select("tag, media_asset_id, media_assets!inner(job_id, company_id)")
        .eq("company_id", userRecord.company_id)
        .limit(5000)
      if (jobId) {
        query = query.eq("media_assets.job_id", jobId)
      }

      const { data: rows, error } = await query
      if (error) throw error

      const counts = new Map<string, number>()
      // Optional tag → media_asset_ids map powers client-side tag filtering.
      const photosByTag = new Map<string, string[]>()
      for (const row of rows || []) {
        const key = (row.tag as string).toLowerCase()
        counts.set(key, (counts.get(key) || 0) + 1)
        if (includePhotos) {
          const list = photosByTag.get(key) || []
          list.push(row.media_asset_id as string)
          photosByTag.set(key, list)
        }
      }
      const tags = [...counts.entries()]
        .map(([tag, count]) => ({
          tag,
          count,
          ...(includePhotos ? { media_asset_ids: photosByTag.get(tag) ?? [] } : {}),
        }))
        .sort((a, b) => b.count - a.count || a.tag.localeCompare(b.tag))

      logRequestResult(ENDPOINT, requestId, 200, { op: "list", returned: tags.length })
      return jsonResponse({ status: "success", tags, request_id: requestId }, 200, requestId)
    }

    // ── POST /tags — bulk attach ────────────────────────────────
    if (req.method === "POST") {
      const body = await req.json().catch(() => null) as
        | { media_asset_ids?: unknown; tag?: unknown }
        | null

      const tag = normalizeTag(body?.tag)
      const ids = Array.isArray(body?.media_asset_ids) ? body!.media_asset_ids : null

      if (!tag) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "tag must be 1-64 chars")
      }
      if (!ids || ids.length === 0 || ids.length > MAX_BULK) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", `media_asset_ids must be 1..${MAX_BULK}`)
      }
      const validIds = ids.filter((id: unknown): id is string => typeof id === "string")
      if (validIds.length !== ids.length) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "media_asset_ids must all be strings")
      }

      // Verify every media asset belongs to the caller's company.
      const { data: assets, error: assetError } = await supabaseAdmin
        .from("media_assets")
        .select("id, company_id")
        .in("id", validIds)
      if (assetError) throw assetError

      const ownedIds = (assets || [])
        .filter((a) => a.company_id === userRecord.company_id)
        .map((a) => a.id as string)

      if (ownedIds.length === 0) {
        return errorResponse(requestId, 403, "FORBIDDEN", "No accessible media assets")
      }

      const rows = ownedIds.map((id) => ({
        company_id: userRecord.company_id,
        media_asset_id: id,
        tag,
        created_by: userRecord.id,
      }))

      // Upsert so re-tagging is idempotent. The unique index is on
      // (media_asset_id, lower(tag)) — rely on ON CONFLICT DO NOTHING via the
      // `ignoreDuplicates` option.
      const { error: insertError } = await supabaseAdmin
        .from("photo_tags")
        .upsert(rows, { onConflict: "media_asset_id,tag", ignoreDuplicates: true })
      if (insertError) throw insertError

      logRequestResult(ENDPOINT, requestId, 201, { op: "tag_add", count: ownedIds.length })
      return jsonResponse({
        status: "success",
        tagged: ownedIds.length,
        skipped: validIds.length - ownedIds.length,
        request_id: requestId,
      }, 201, requestId)
    }

    // ── DELETE /tags — remove one tag from one photo ────────────
    if (req.method === "DELETE") {
      const body = await req.json().catch(() => null) as
        | { media_asset_id?: unknown; tag?: unknown }
        | null

      const tag = normalizeTag(body?.tag)
      const mediaAssetId = typeof body?.media_asset_id === "string" ? body!.media_asset_id as string : null

      if (!tag || !mediaAssetId) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "media_asset_id and tag are required")
      }

      const { error: delError } = await supabaseAdmin
        .from("photo_tags")
        .delete()
        .eq("company_id", userRecord.company_id)
        .eq("media_asset_id", mediaAssetId)
        .ilike("tag", tag)
      if (delError) throw delError

      logRequestResult(ENDPOINT, requestId, 200, { op: "tag_delete" })
      return jsonResponse({ status: "success", request_id: requestId }, 200, requestId)
    }

    return errorResponse(requestId, 405, "METHOD_NOT_ALLOWED", "Method not allowed")
  } catch (error) {
    logRequestError(ENDPOINT, requestId, error)
    return errorResponse(requestId, 500, "INTERNAL_ERROR", (error as Error).message || "Internal error")
  }
})
