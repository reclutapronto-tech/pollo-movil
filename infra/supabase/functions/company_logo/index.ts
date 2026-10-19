import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.4"
import {
  applyRateLimit,
  checkCompanyActive,
  corsHeaders,
  errorResponse,
  jsonResponse,
  logAdminAction,
  logRequestError,
  logRequestResult,
  logRequestStart,
  makeRequestId,
} from "../_shared/api.ts"
import { isManagementRole } from "../_shared/roles.ts"

const ENDPOINT = "company_logo"
const LOGO_BUCKET = "company-logos"
const LOGO_RATE_LIMIT = 5
const LOGO_RATE_WINDOW_SECONDS = 300
const PRESIGN_EXPIRY_SECONDS = 900

serve(async (req) => {
  if (req.method === "OPTIONS") {
    // Must include Access-Control-Allow-Origin — the bare CORS_HEADERS constant
    // omits it so the preflight fails and the browser reports "Failed to fetch".
    return new Response("ok", { headers: corsHeaders(req) })
  }

  const requestId = makeRequestId(req)
  logRequestStart(ENDPOINT, requestId, req)

  try {
    if (req.method !== "POST") {
      return errorResponse(requestId, 405, "METHOD_NOT_ALLOWED", "Use POST for /company_logo")
    }

    // ── Auth ──────────────────────────────────────────────────
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

    const jwt = authHeader.replace("Bearer ", "")
    const { data: { user }, error: authError } = await supabase.auth.getUser()
    if (authError || !user) {
      return errorResponse(requestId, 401, "UNAUTHORIZED", "Invalid auth token")
    }

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

    // Only owners/admins can manage logos
    if (!isManagementRole(userRecord.role)) {
      return errorResponse(requestId, 403, "FORBIDDEN", "Only owners or admins can manage company logos")
    }

    // Company active check
    const companyBlock = await checkCompanyActive(supabaseAdmin, userRecord.company_id, requestId)
    if (companyBlock) return companyBlock

    // Rate limit
    const rateLimit = await applyRateLimit(
      supabaseAdmin,
      user.id,
      ENDPOINT,
      requestId,
      LOGO_RATE_LIMIT,
      LOGO_RATE_WINDOW_SECONDS,
    )
    if (rateLimit.limited) {
      return errorResponse(requestId, 429, "RATE_LIMITED", "Too many logo requests", [], rateLimit.headers)
    }

    const payload = await req.json()
    const { action } = payload

    if (!action || !["presign", "finalize", "remove"].includes(action)) {
      return errorResponse(
        requestId,
        400,
        "INVALID_PAYLOAD",
        "action must be 'presign', 'finalize', or 'remove'",
      )
    }

    const companyId = userRecord.company_id

    // ── ACTION: presign ──────────────────────────────────────
    // Returns a signed upload URL for the client to PUT a logo file.
    if (action === "presign") {
      const storagePath = `${companyId}/logo.png`

      const { data: signedData, error: signedError } = await supabaseAdmin
        .storage
        .from(LOGO_BUCKET)
        .createSignedUploadUrl(storagePath, {
          upsert: true,
        })

      if (signedError) {
        console.error("Logo presign error:", signedError)
        return errorResponse(requestId, 500, "INTERNAL_ERROR", "Failed to generate upload URL")
      }

      const responseBody = {
        status: "success",
        action: "presign",
        upload_url: signedData?.signedUrl || "",
        upload_method: "PUT",
        upload_headers: {
          "Content-Type": "image/png",
        },
        storage_path: storagePath,
        expires_at: new Date(Date.now() + PRESIGN_EXPIRY_SECONDS * 1000).toISOString(),
        request_id: requestId,
      }

      await logAdminAction(supabaseAdmin, req, {
        company_id: companyId,
        actor_id: user.id,
        action: "logo_presign",
        target_type: "company",
        target_id: companyId,
      })

      logRequestResult(ENDPOINT, requestId, 200, {
        user_id: user.id,
        action: "presign",
      })
      return jsonResponse(responseBody, 200, requestId, rateLimit.headers)
    }

    // ── ACTION: finalize ─────────────────────────────────────
    // After the client uploads, this reads the file, generates a public URL,
    // converts to base64 data URI, and saves both to the companies table.
    if (action === "finalize") {
      const storagePath = `${companyId}/logo.png`

      // Download the uploaded file from storage
      const { data: fileData, error: downloadError } = await supabaseAdmin
        .storage
        .from(LOGO_BUCKET)
        .download(storagePath)

      if (downloadError || !fileData) {
        console.error("Logo download error:", downloadError)
        return errorResponse(
          requestId,
          400,
          "INVALID_PAYLOAD",
          "Logo file not found in storage. Upload via the presign URL first.",
        )
      }

      // Generate a public URL. Cache-buster (`?v=<ms>`) forces <img src> to
      // refetch after re-uploads — the storage path is always `logo.png` so
      // the unqualified URL would hit a stale CDN copy from the previous upload.
      const { data: publicUrlData } = supabaseAdmin
        .storage
        .from(LOGO_BUCKET)
        .getPublicUrl(storagePath)

      const baseUrl = publicUrlData?.publicUrl || ""
      const logoUrl = baseUrl ? `${baseUrl}?v=${Date.now()}` : ""

      // Convert to base64 data URI for stamp embedding
      const buffer = await fileData.arrayBuffer()
      const bytes = new Uint8Array(buffer)
      let binary = ""
      for (let i = 0; i < bytes.length; i++) {
        binary += String.fromCharCode(bytes[i])
      }
      const base64 = btoa(binary)
      const logoDataUri = `data:image/png;base64,${base64}`

      // Fetch current values for audit before/after
      const { data: currentCompany } = await supabaseAdmin
        .from("companies")
        .select("logo_url, logo_data_uri")
        .eq("id", companyId)
        .single()

      // Update companies table
      const { error: updateError } = await supabaseAdmin
        .from("companies")
        .update({
          logo_url: logoUrl,
          logo_data_uri: logoDataUri,
        })
        .eq("id", companyId)

      if (updateError) {
        console.error("Logo finalize update error:", updateError)
        return errorResponse(requestId, 500, "INTERNAL_ERROR", "Failed to save logo to company record")
      }

      await logAdminAction(supabaseAdmin, req, {
        company_id: companyId,
        actor_id: user.id,
        action: "logo_finalize",
        target_type: "company",
        target_id: companyId,
        before: {
          logo_url: currentCompany?.logo_url || null,
          logo_data_uri: currentCompany?.logo_data_uri ? "(set)" : null,
        },
        after: {
          logo_url: logoUrl,
          logo_data_uri: "(set)",
        },
      })

      const responseBody = {
        status: "success",
        action: "finalize",
        logo_url: logoUrl,
        data_uri_length: logoDataUri.length,
        request_id: requestId,
      }

      logRequestResult(ENDPOINT, requestId, 200, {
        user_id: user.id,
        action: "finalize",
        logo_url: logoUrl,
      })
      return jsonResponse(responseBody, 200, requestId, rateLimit.headers)
    }

    // ── ACTION: remove ───────────────────────────────────────
    // Deletes the logo from storage and clears the company record.
    if (action === "remove") {
      const storagePath = `${companyId}/logo.png`

      // Fetch current values for audit
      const { data: currentCompany } = await supabaseAdmin
        .from("companies")
        .select("logo_url, logo_data_uri")
        .eq("id", companyId)
        .single()

      // Remove from storage (non-fatal if not found)
      const { error: removeError } = await supabaseAdmin
        .storage
        .from(LOGO_BUCKET)
        .remove([storagePath])

      if (removeError) {
        console.error("Logo storage remove error (non-fatal):", removeError)
      }

      // Clear company record
      const { error: updateError } = await supabaseAdmin
        .from("companies")
        .update({
          logo_url: null,
          logo_data_uri: null,
        })
        .eq("id", companyId)

      if (updateError) {
        console.error("Logo remove update error:", updateError)
        return errorResponse(requestId, 500, "INTERNAL_ERROR", "Failed to clear logo from company record")
      }

      await logAdminAction(supabaseAdmin, req, {
        company_id: companyId,
        actor_id: user.id,
        action: "logo_remove",
        target_type: "company",
        target_id: companyId,
        before: {
          logo_url: currentCompany?.logo_url || null,
          logo_data_uri: currentCompany?.logo_data_uri ? "(set)" : null,
        },
        after: {
          logo_url: null,
          logo_data_uri: null,
        },
      })

      const responseBody = {
        status: "success",
        action: "remove",
        request_id: requestId,
      }

      logRequestResult(ENDPOINT, requestId, 200, {
        user_id: user.id,
        action: "remove",
      })
      return jsonResponse(responseBody, 200, requestId, rateLimit.headers)
    }

    return errorResponse(requestId, 400, "INVALID_PAYLOAD", "Unknown action")
  } catch (error) {
    logRequestError(ENDPOINT, requestId, error)
    console.error("company_logo error:", error)
    return errorResponse(requestId, 500, "INTERNAL_ERROR", error.message || "Internal server error")
  }
})
