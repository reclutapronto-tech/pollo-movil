import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.4"
import bcrypt from "https://esm.sh/bcryptjs@2.4.3"
import {
  CORS_HEADERS,
  corsHeaders,
  errorResponse,
  jsonResponse,
  makeRequestId,
  logRequestError,
} from "../_shared/api.ts"

const ENDPOINT = "client_portal"

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders(req) })
  }

  const requestId = makeRequestId(req)
  const supabaseUrl = Deno.env.get("SUPABASE_URL") || ""
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || ""
  const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey)

  try {
    // ── GET: public portal view ──────────────────────────────
    if (req.method === "GET") {
      const url = new URL(req.url)
      const token = url.searchParams.get("token")
      const password = url.searchParams.get("password") || ""

      if (!token) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "token is required")
      }

      // Look up token (includes password + watermark added in 20260420000000)
      const { data: shareToken, error: tokenError } = await supabaseAdmin
        .from("job_share_tokens")
        .select("id, token, job_id, company_id, label, expires_at, revoked_at, view_count, password_hash, brand_watermark")
        .eq("token", token)
        .single()

      if (tokenError || !shareToken) {
        return errorResponse(requestId, 404, "NOT_FOUND", "Share link not found or expired")
      }

      if (shareToken.revoked_at) {
        return errorResponse(requestId, 410, "GONE", "This share link has been revoked")
      }

      if (shareToken.expires_at && new Date(shareToken.expires_at) < new Date()) {
        return errorResponse(requestId, 410, "GONE", "This share link has expired")
      }

      // Optional password gate. Respond with 401 + status:password_required so
      // the web client can render a prompt without treating the token as invalid.
      const passwordHash = (shareToken as any).password_hash as string | null
      if (passwordHash) {
        if (!password) {
          return jsonResponse({
            status: "password_required",
            label: shareToken.label,
            request_id: requestId,
          }, 401, requestId)
        }
        const ok = await bcrypt.compare(password, passwordHash)
        if (!ok) {
          return errorResponse(requestId, 401, "UNAUTHORIZED", "Incorrect password")
        }
      }

      // Fetch job details
      const { data: job } = await supabaseAdmin
        .from("jobs")
        .select("id, name, code, status, address_line_1, address_line_2, start_date, end_date")
        .eq("id", shareToken.job_id)
        .single()

      // Flatten address for UI, keep both lines for the template that wants them.
      const jobWithAddress = job
        ? {
            ...job,
            address:
              [job.address_line_1, job.address_line_2].filter(Boolean).join(", ") || null,
          }
        : null

      // Fetch company branding
      const { data: company } = await supabaseAdmin
        .from("companies")
        .select("name, logo_data_uri")
        .eq("id", shareToken.company_id)
        .single()

      // Fetch stamped photos: prefer the stamped derivative when one exists so
      // the public viewer shows the embossed version with proof metadata.
      // We select by `kind` on media_assets (enum, actual column) rather than
      // the legacy `stamp_metadata`/`asset_type` columns that never existed.
      const { data: photos } = await supabaseAdmin
        .from("media_assets")
        .select("id, bucket_name, storage_path, mime_type, kind, captured_at, created_at, sha256_hash, verification_code, gps_lat, gps_lng")
        .eq("job_id", shareToken.job_id)
        .eq("company_id", shareToken.company_id)
        .in("kind", ["stamped_photo", "raw_photo"])
        .order("created_at", { ascending: false })
        .limit(50)

      // Generate signed URLs per bucket for the public viewer.
      const signedPhotos: Array<Record<string, unknown>> = []
      if (photos && photos.length > 0) {
        const byBucket = new Map<string, typeof photos>()
        for (const p of photos) {
          const bucket = (p as any).bucket_name as string
          const list = byBucket.get(bucket) || ([] as typeof photos)
          list.push(p)
          byBucket.set(bucket, list)
        }
        for (const [bucket, rows] of byBucket.entries()) {
          const paths = rows.map((r: any) => r.storage_path as string)
          const { data: urls } = await (supabaseAdmin as any).storage
            .from(bucket)
            .createSignedUrls(paths, 3600)
          rows.forEach((row: any, idx: number) => {
            signedPhotos.push({
              id: row.id,
              storage_url: urls?.[idx]?.signedUrl || null,
              created_at: row.created_at,
              captured_at: row.captured_at,
              mime_type: row.mime_type,
              sha256_hash: row.sha256_hash,
              verification_code: row.verification_code,
              gps_lat: row.gps_lat,
              gps_lng: row.gps_lng,
              // Preserved for backwards compatibility with the `/portal` page;
              // mirrors what the prior (broken) query intended to return.
              stamp_metadata: row.verification_code
                ? { verification_code: row.verification_code, sha256: row.sha256_hash }
                : null,
              asset_type: row.kind,
            })
          })
        }
      }

      // Fetch task summary
      const { data: tasks } = await supabaseAdmin
        .from("tasks")
        .select("id, name, status, requires_photo, sort_order")
        .eq("job_id", shareToken.job_id)
        .order("sort_order", { ascending: true })

      // Increment view count (fire and forget)
      supabaseAdmin
        .from("job_share_tokens")
        .update({ view_count: (shareToken as any).view_count + 1, last_viewed_at: new Date().toISOString() })
        .eq("id", shareToken.id)
        .then(() => {})

      return jsonResponse({
        status: "success",
        job: jobWithAddress,
        company: { name: company?.name, logo: company?.logo_data_uri },
        photos: signedPhotos,
        tasks: tasks || [],
        label: shareToken.label,
        brand_watermark: (shareToken as any).brand_watermark ?? true,
        request_id: requestId,
      }, 200, requestId)
    }

    // ── POST: authenticated token management ─────────────────
    if (req.method === "POST") {
      const authHeader = req.headers.get("Authorization")
      if (!authHeader) {
        return errorResponse(requestId, 401, "UNAUTHORIZED", "Authorization required")
      }

      const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") || ""
      const supabase = createClient(supabaseUrl, supabaseAnonKey, {
        global: { headers: { Authorization: authHeader } },
      })

      const jwt = authHeader.replace("Bearer ", "")
      const { data: authData, error: authError } = await supabase.auth.getUser()
      if (authError || !authData.user) {
        return errorResponse(requestId, 401, "UNAUTHORIZED", "Invalid auth token")
      }

      const { data: userRecord } = await supabaseAdmin
        .from("users")
        .select("id, company_id, role")
        .eq("id", authData.user.id)
        .single()

      if (!userRecord) {
        return errorResponse(requestId, 403, "FORBIDDEN", "User not found")
      }

      const allowedRoles = ["owner", "admin", "supervisor", "foreman"]
      if (!allowedRoles.includes(userRecord.role)) {
        return errorResponse(requestId, 403, "FORBIDDEN", "Insufficient role to manage share links")
      }

      const payload = await req.json()
      const { action } = payload

      if (action === "create_token") {
        const { job_id, label, expires_days, password, brand_watermark } = payload
        if (!job_id) {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", "job_id is required")
        }

        // Verify job belongs to company
        const { data: job } = await supabaseAdmin
          .from("jobs")
          .select("id")
          .eq("id", job_id)
          .eq("company_id", userRecord.company_id)
          .single()

        if (!job) {
          return errorResponse(requestId, 404, "NOT_FOUND", "Job not found")
        }

        const expiresAt = expires_days
          ? new Date(Date.now() + expires_days * 86400000).toISOString()
          : null
        const passwordHash = typeof password === "string" && password.length > 0
          ? await bcrypt.hash(password, 10)
          : null

        const { data: newToken, error: insertError } = await supabaseAdmin
          .from("job_share_tokens")
          .insert({
            job_id,
            company_id: userRecord.company_id,
            created_by: userRecord.id,
            label: label || null,
            expires_at: expiresAt,
            password_hash: passwordHash,
            brand_watermark: brand_watermark !== false,
          })
          .select("id, token, label, expires_at, brand_watermark, created_at")
          .single()

        if (insertError) throw insertError

        return jsonResponse({
          status: "success",
          token: newToken,
          share_url: `/portal/${newToken.token}`,
          request_id: requestId,
        }, 201, requestId)
      }

      if (action === "revoke_token") {
        const { token_id } = payload
        if (!token_id) {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", "token_id is required")
        }

        const { error: revokeError } = await supabaseAdmin
          .from("job_share_tokens")
          .update({ revoked_at: new Date().toISOString() })
          .eq("id", token_id)
          .eq("company_id", userRecord.company_id)

        if (revokeError) throw revokeError

        return jsonResponse({ status: "success", request_id: requestId }, 200, requestId)
      }

      if (action === "list_tokens") {
        const { job_id } = payload
        const query = supabaseAdmin
          .from("job_share_tokens")
          // `has_password` derived in-process so the hash itself never leaves the server.
          .select("id, token, job_id, label, expires_at, revoked_at, view_count, last_viewed_at, brand_watermark, password_hash, created_at")
          .eq("company_id", userRecord.company_id)
          .order("created_at", { ascending: false })

        if (job_id) query.eq("job_id", job_id)

        const { data: tokens, error: listError } = await query
        if (listError) throw listError

        const sanitized = (tokens || []).map((t: any) => {
          const { password_hash, ...rest } = t
          return { ...rest, has_password: !!password_hash }
        })

        return jsonResponse({ status: "success", tokens: sanitized, request_id: requestId }, 200, requestId)
      }

      if (action === "set_password") {
        const { token_id, password } = payload
        if (!token_id) {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", "token_id is required")
        }
        const passwordHash = typeof password === "string" && password.length > 0
          ? await bcrypt.hash(password, 10)
          : null
        const { error } = await supabaseAdmin
          .from("job_share_tokens")
          .update({ password_hash: passwordHash })
          .eq("id", token_id)
          .eq("company_id", userRecord.company_id)
        if (error) throw error
        return jsonResponse({ status: "success", request_id: requestId }, 200, requestId)
      }

      return errorResponse(requestId, 400, "INVALID_PAYLOAD", "Unknown action. Use: create_token, revoke_token, list_tokens, set_password")
    }

    return errorResponse(requestId, 405, "METHOD_NOT_ALLOWED", "Method not allowed")
  } catch (error) {
    logRequestError("client_portal", requestId, error)
    return errorResponse(requestId, 500, "INTERNAL_ERROR", (error as Error).message || "Internal error")
  }
})
