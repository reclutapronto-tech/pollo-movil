// galleries — curated photo share subsets with public tokenized viewer.
// Auth routes: POST create, PATCH update/revoke.
// Public route: GET /galleries/public?token=&password=
//
// Pattern: mirrors client_portal for the public read flow and media_finalize
// for the authenticated write flow. Password hashing uses bcryptjs via esm.sh.
import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.4"
import bcrypt from "https://esm.sh/bcryptjs@2.4.3"
import {
  corsHeaders,
  errorResponse,
  jsonResponse,
  logRequestError,
  logRequestResult,
  logRequestStart,
  makeRequestId,
} from "../_shared/api.ts"
import { isSupervisorOrAbove } from "../_shared/roles.ts"

const ENDPOINT = "galleries"
const MAX_PHOTOS_PER_GALLERY = 500
const SIGNED_URL_TTL = 3600 // 1 hour for public viewer links

function isUuid(value: unknown): value is string {
  return typeof value === "string"
    && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value)
}

type SupabaseAdmin = ReturnType<typeof createClient>

async function hashPassword(password: string | null | undefined): Promise<string | null> {
  if (!password) return null
  return await bcrypt.hash(password, 10)
}

async function verifyPassword(password: string, hash: string): Promise<boolean> {
  return await bcrypt.compare(password, hash)
}

async function signPhotoUrls(supabaseAdmin: SupabaseAdmin, assets: Array<{ id: string; bucket_name: string; storage_path: string } & Record<string, unknown>>) {
  const grouped = new Map<string, Array<{ id: string; path: string }>>()
  for (const a of assets) {
    const list = grouped.get(a.bucket_name) || []
    list.push({ id: a.id, path: a.storage_path })
    grouped.set(a.bucket_name, list)
  }
  const signed = new Map<string, string>()
  for (const [bucket, items] of grouped.entries()) {
    const { data } = await (supabaseAdmin as any).storage
      .from(bucket)
      .createSignedUrls(items.map((i) => i.path), SIGNED_URL_TTL)
    if (Array.isArray(data)) {
      items.forEach((item, idx) => {
        const entry = data[idx]
        if (entry?.signedUrl) signed.set(item.id, entry.signedUrl)
      })
    }
  }
  return signed
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders(req) })
  }

  const requestId = makeRequestId(req)
  logRequestStart(ENDPOINT, requestId, req)

  const supabaseUrl = Deno.env.get("SUPABASE_URL") || ""
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || ""
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") || ""
  const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey)

  const url = new URL(req.url)
  const path = url.pathname.replace(/\/+$/, "")
  const isPublic = path.endsWith("/public")

  try {
    // ── PUBLIC: GET /galleries/public?token=&password= ──────────
    if (isPublic) {
      if (req.method !== "GET") {
        return errorResponse(requestId, 405, "METHOD_NOT_ALLOWED", "Use GET for public viewer")
      }
      const token = url.searchParams.get("token")
      const password = url.searchParams.get("password") || ""
      if (!isUuid(token)) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "token is required")
      }

      const { data: gallery, error: galleryError } = await supabaseAdmin
        .from("photo_galleries")
        .select("id, company_id, job_id, name, description, password_hash, expires_at, revoked_at, view_count, brand_watermark")
        .eq("share_token", token)
        .single()

      if (galleryError || !gallery) {
        return errorResponse(requestId, 404, "NOT_FOUND", "Gallery not found")
      }
      if (gallery.revoked_at) {
        return errorResponse(requestId, 410, "GONE", "This gallery has been revoked")
      }
      if (gallery.expires_at && new Date(gallery.expires_at) < new Date()) {
        return errorResponse(requestId, 410, "GONE", "This gallery has expired")
      }
      if (gallery.password_hash) {
        if (!password) {
          return jsonResponse({
            status: "password_required",
            gallery: { id: gallery.id, name: gallery.name, description: gallery.description },
            request_id: requestId,
          }, 401, requestId)
        }
        const ok = await verifyPassword(password, gallery.password_hash as string)
        if (!ok) {
          return errorResponse(requestId, 401, "UNAUTHORIZED", "Incorrect password")
        }
      }

      // Fetch gallery items (ordered) and join to media_assets.
      const { data: items, error: itemsError } = await supabaseAdmin
        .from("photo_gallery_items")
        .select("media_asset_id, position, media_assets!inner(id, bucket_name, storage_path, mime_type, captured_at, sha256_hash, verification_code, gps_lat, gps_lng)")
        .eq("gallery_id", gallery.id)
        .order("position", { ascending: true })
      if (itemsError) throw itemsError

      const assets = (items || []).map((i: any) => i.media_assets).filter(Boolean)
      const signed = await signPhotoUrls(supabaseAdmin, assets)

      const photos = assets.map((a: any) => ({
        id: a.id,
        url: signed.get(a.id) || null,
        mime_type: a.mime_type,
        captured_at: a.captured_at,
        sha256_hash: a.sha256_hash,
        verification_code: a.verification_code,
        gps_lat: a.gps_lat,
        gps_lng: a.gps_lng,
      }))

      // Fetch company branding (logo + name).
      const { data: company } = await supabaseAdmin
        .from("companies")
        .select("name, logo_data_uri")
        .eq("id", gallery.company_id)
        .single()

      // Fire-and-forget view-count increment — never block the response on it.
      const viewedAt = new Date().toISOString()
      void supabaseAdmin
        .from("photo_galleries")
        .update({ view_count: (gallery.view_count as number) + 1, last_viewed_at: viewedAt })
        .eq("id", gallery.id)
        .then(() => {})

      logRequestResult(ENDPOINT, requestId, 200, { op: "public_view", gallery_id: gallery.id })
      return jsonResponse({
        status: "success",
        gallery: {
          id: gallery.id,
          name: gallery.name,
          description: gallery.description,
          brand_watermark: gallery.brand_watermark,
        },
        photos,
        company: company ? { name: company.name, logo: (company as any).logo_data_uri } : null,
        request_id: requestId,
      }, 200, requestId)
    }

    // ── AUTHENTICATED routes require Bearer token ───────────────
    const authHeader = req.headers.get("Authorization")
    if (!authHeader) {
      return errorResponse(requestId, 401, "UNAUTHORIZED", "Missing Authorization header")
    }
    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    })
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
    if (!isSupervisorOrAbove(userRecord.role as string | null)) {
      return errorResponse(requestId, 403, "FORBIDDEN", "Gallery management requires supervisor+ role")
    }

    // ── POST /galleries — create ────────────────────────────────
    if (req.method === "POST") {
      const body = await req.json().catch(() => null) as
        | {
            job_id?: unknown
            name?: unknown
            description?: unknown
            media_asset_ids?: unknown
            password?: unknown
            expires_at?: unknown
            expires_days?: unknown
            brand_watermark?: unknown
          }
        | null

      if (!body || !isUuid(body.job_id) || typeof body.name !== "string") {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "job_id (uuid) and name are required")
      }
      const name = body.name.trim()
      if (name.length < 1 || name.length > 160) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "name must be 1-160 chars")
      }
      const ids = Array.isArray(body.media_asset_ids)
        ? body.media_asset_ids.filter(isUuid)
        : []
      if (ids.length === 0 || ids.length > MAX_PHOTOS_PER_GALLERY) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", `media_asset_ids must be 1..${MAX_PHOTOS_PER_GALLERY}`)
      }

      // Verify job + assets belong to caller's company.
      const { data: job } = await supabaseAdmin
        .from("jobs")
        .select("id")
        .eq("id", body.job_id as string)
        .eq("company_id", userRecord.company_id)
        .maybeSingle()
      if (!job) {
        return errorResponse(requestId, 404, "NOT_FOUND", "Job not found")
      }

      const { data: assets, error: assetsError } = await supabaseAdmin
        .from("media_assets")
        .select("id, company_id, job_id")
        .in("id", ids)
      if (assetsError) throw assetsError
      const validAssets = (assets || []).filter((a) => a.company_id === userRecord.company_id)
      if (validAssets.length === 0) {
        return errorResponse(requestId, 403, "FORBIDDEN", "No accessible media assets")
      }

      const passwordHash = await hashPassword(typeof body.password === "string" ? body.password : null)
      let expiresAt: string | null = null
      if (typeof body.expires_at === "string") {
        expiresAt = body.expires_at
      } else if (typeof body.expires_days === "number" && body.expires_days > 0) {
        expiresAt = new Date(Date.now() + body.expires_days * 86400000).toISOString()
      }

      const { data: gallery, error: insertError } = await supabaseAdmin
        .from("photo_galleries")
        .insert({
          company_id: userRecord.company_id,
          job_id: body.job_id as string,
          name,
          description: typeof body.description === "string" ? body.description : null,
          password_hash: passwordHash,
          expires_at: expiresAt,
          brand_watermark: body.brand_watermark !== false,
          created_by: userRecord.id,
        })
        .select("id, share_token, name, expires_at, brand_watermark, created_at")
        .single()
      if (insertError) throw insertError

      const itemRows = validAssets.map((a, idx) => ({
        gallery_id: gallery.id,
        media_asset_id: a.id as string,
        position: idx,
      }))
      const { error: itemsError } = await supabaseAdmin
        .from("photo_gallery_items")
        .insert(itemRows)
      if (itemsError) throw itemsError

      logRequestResult(ENDPOINT, requestId, 201, { op: "create", id: gallery.id, photos: itemRows.length })
      return jsonResponse({
        status: "success",
        gallery,
        share_url: `/g/${gallery.share_token}`,
        request_id: requestId,
      }, 201, requestId)
    }

    // ── PATCH /galleries — revoke or rotate token ───────────────
    if (req.method === "PATCH") {
      const body = await req.json().catch(() => null) as
        | { id?: unknown; action?: unknown; password?: unknown; expires_at?: unknown }
        | null
      if (!body || !isUuid(body.id) || typeof body.action !== "string") {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "id (uuid) and action are required")
      }

      if (body.action === "revoke") {
        const { error } = await supabaseAdmin
          .from("photo_galleries")
          .update({ revoked_at: new Date().toISOString() })
          .eq("id", body.id as string)
          .eq("company_id", userRecord.company_id)
        if (error) throw error
        return jsonResponse({ status: "success", request_id: requestId }, 200, requestId)
      }

      if (body.action === "rotate_token") {
        const { data, error } = await supabaseAdmin
          .from("photo_galleries")
          .update({ share_token: crypto.randomUUID() })
          .eq("id", body.id as string)
          .eq("company_id", userRecord.company_id)
          .select("id, share_token")
          .single()
        if (error) throw error
        return jsonResponse({ status: "success", gallery: data, share_url: `/g/${data.share_token}`, request_id: requestId }, 200, requestId)
      }

      if (body.action === "set_password") {
        const passwordHash = await hashPassword(typeof body.password === "string" ? body.password : null)
        const { error } = await supabaseAdmin
          .from("photo_galleries")
          .update({ password_hash: passwordHash })
          .eq("id", body.id as string)
          .eq("company_id", userRecord.company_id)
        if (error) throw error
        return jsonResponse({ status: "success", request_id: requestId }, 200, requestId)
      }

      if (body.action === "set_expiry") {
        const expiresAt = typeof body.expires_at === "string" ? body.expires_at : null
        const { error } = await supabaseAdmin
          .from("photo_galleries")
          .update({ expires_at: expiresAt })
          .eq("id", body.id as string)
          .eq("company_id", userRecord.company_id)
        if (error) throw error
        return jsonResponse({ status: "success", request_id: requestId }, 200, requestId)
      }

      return errorResponse(requestId, 400, "INVALID_PAYLOAD", "action must be revoke, rotate_token, set_password, or set_expiry")
    }

    // ── GET /galleries?job_id= — list for owner ─────────────────
    if (req.method === "GET") {
      const jobId = url.searchParams.get("job_id")
      let query = supabaseAdmin
        .from("photo_galleries")
        .select("id, job_id, name, description, share_token, expires_at, revoked_at, view_count, last_viewed_at, brand_watermark, created_at")
        .eq("company_id", userRecord.company_id)
        .order("created_at", { ascending: false })
        .limit(200)
      if (jobId) query = query.eq("job_id", jobId)
      const { data, error } = await query
      if (error) throw error
      return jsonResponse({ status: "success", galleries: data || [], request_id: requestId }, 200, requestId)
    }

    return errorResponse(requestId, 405, "METHOD_NOT_ALLOWED", "Method not allowed")
  } catch (error) {
    logRequestError(ENDPOINT, requestId, error)
    return errorResponse(requestId, 500, "INTERNAL_ERROR", (error as Error).message || "Internal error")
  }
})
