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
  sha256Hex,
} from "../_shared/api.ts"
import { DEFAULT_COMPANY_SETTINGS } from "../_shared/settings.ts"

const ENDPOINT = "platform_admin"
type JsonValue = null | boolean | number | string | JsonValue[] | { [key: string]: JsonValue }

// ─── Helpers ─────────────────────────────────────────────────

/** Log platform-level admin actions to admin_audit_log (company_id is nullable). */
async function logPlatformAction(
  supabaseAdmin: any,
  req: Request,
  params: {
    actor_id: string
    action: string
    company_id?: string
    target_type?: string
    target_id?: string
    before?: Record<string, unknown>
    after?: Record<string, unknown>
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
    settings_version: null,
    ip_address: ipAddress,
    user_agent: userAgent,
  })

  if (error) throw new Error("AUDIT_WRITE_FAILED")
}

function sanitizeAuditValue(value: unknown): JsonValue {
  if (value === null || typeof value === "string" || typeof value === "boolean" || typeof value === "number") return value
  if (Array.isArray(value)) return value.map(sanitizeAuditValue)
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value as Record<string, unknown>)
      .filter(([key]) => !/(token|password|secret|claim_url|invite_link)/i.test(key))
      .map(([key, entry]) => [key, sanitizeAuditValue(entry)])) as { [key: string]: JsonValue }
  }
  return null
}

async function deliverCompanyAdminInvite(
  supabaseAdmin: any,
  supabaseMailer: any,
  req: Request,
  actorId: string,
  invite: { id: string; company_id: string; email: string; full_name: string },
) {
  const appUrl = (Deno.env.get("APP_URL") || "").replace(/\/+$/, "")
  let appOrigin: string | null = null
  try {
    const parsed = new URL(appUrl)
    const loopbackHttp = parsed.protocol === "http:" && ["localhost", "127.0.0.1", "[::1]"].includes(parsed.hostname)
    if ((parsed.protocol === "https:" || loopbackHttp) && !parsed.username && !parsed.password && !parsed.search && !parsed.hash) {
      appOrigin = parsed.origin
    }
  } catch { /* a missing or malformed origin is handled as a delivery failure below */ }
  if (!appOrigin) {
    const { error } = await supabaseAdmin.rpc("platform_record_company_invite_delivery", {
      p_actor_id: actorId, p_invite_id: invite.id, p_status: "delivery_failed",
      p_error_code: "app_url_not_configured",
    })
    if (error) throw new Error("INVITE_STATUS_AUDIT_FAILED")
    return { status: "delivery_failed", message: "La URL pública de la aplicación no está configurada." }
  }

  const { data: authUserId, error: lookupError } = await supabaseAdmin.rpc(
    "platform_find_auth_user_by_email", { p_email: invite.email },
  )
  if (lookupError) throw new Error("INVITE_IDENTITY_LOOKUP_FAILED")

  let linkedUserId: string | null = authUserId || null
  let deliveryErrorCode: string | null = null
  let emailError: unknown = null
  const redirectTo = `${appOrigin}/accept-company-invite?invitation=${encodeURIComponent(invite.id)}`

  if (linkedUserId) {
    const { data: profile, error: profileError } = await supabaseAdmin
      .from("users").select("company_id").eq("id", linkedUserId).maybeSingle()
    if (profileError) throw new Error("INVITE_PROFILE_LOOKUP_FAILED")
    if (profile && profile.company_id !== invite.company_id) {
      deliveryErrorCode = "existing_account_company_conflict"
    } else if (profile) {
      deliveryErrorCode = "account_already_has_company_access"
    } else {
      const { error } = await supabaseMailer.auth.resetPasswordForEmail(invite.email, { redirectTo })
      emailError = error
      if (error) deliveryErrorCode = "auth_email_delivery_failed"
    }
  } else {
    const { data, error } = await supabaseAdmin.auth.admin.inviteUserByEmail(invite.email, {
      data: { full_name: invite.full_name },
      redirectTo,
    })
    emailError = error
    linkedUserId = data?.user?.id || null
    if (error) deliveryErrorCode = "auth_email_delivery_failed"
  }

  const deliveryStatus = deliveryErrorCode ? "delivery_failed" : "sent"
  const { error: stateError } = await supabaseAdmin.rpc("platform_record_company_invite_delivery", {
    p_actor_id: actorId,
    p_invite_id: invite.id,
    p_status: deliveryStatus,
    p_auth_user_id: linkedUserId,
    p_error_code: deliveryErrorCode,
  })
  if (stateError) throw new Error("INVITE_STATUS_AUDIT_FAILED")

  if (emailError) {
    // Never serialize provider errors: they can contain request details.
    console.warn("[platform_admin] Company invitation email delivery failed", {
      request_id: makeRequestId(req), invite_id: invite.id, error_code: deliveryErrorCode,
    })
  }
  return {
    status: deliveryStatus,
    message: deliveryErrorCode === "existing_account_company_conflict"
      ? "El correo ya pertenece a otra empresa; no se cambió su asignación."
      : deliveryErrorCode === "account_already_has_company_access"
        ? "La cuenta ya tiene acceso a esta empresa."
        : deliveryErrorCode
          ? "No se pudo enviar el correo. La invitación quedó registrada para reintento."
          : "Invitación enviada; el acceso se activa al validar el correo.",
  }
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders(req) })
  }

  const requestId = makeRequestId(req)
  logRequestStart(ENDPOINT, requestId, req)
  let requestAction = ""

  try {
    const payload = req.method === "POST" ? await req.json() : null
    requestAction = typeof payload?.action === "string" ? payload.action : ""
    // All routes require a verified Supabase session. Legacy bearerless claim
    // invitations are retired; new corporate invitations use Auth email OTP.
    const allowUnauthedClaim = false

    const authHeader = req.headers.get("Authorization")
    if (!authHeader && !allowUnauthedClaim) {
      return errorResponse(requestId, 401, "UNAUTHORIZED", "Missing Authorization header")
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") || ""
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || ""
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") || ""
    const supabase = createClient(supabaseUrl, supabaseAnonKey, authHeader
      ? { global: { headers: { Authorization: authHeader } } }
      : undefined)
    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey)
    const supabaseMailer = createClient(supabaseUrl, supabaseAnonKey)

    let user: { id: string; email?: string } | null = null
    let platformAdmin: { id: string; role: string; is_active: boolean } | null = null
    const requireUser = () => {
      if (!user) throw new Error("UNAUTHORIZED")
      return user
    }
    const requirePlatformAdmin = () => {
      if (!platformAdmin) throw new Error("FORBIDDEN")
      return platformAdmin
    }

    if (!allowUnauthedClaim) {
      const jwt = authHeader!.replace("Bearer ", "")
      const { data: authData, error: authError } = await supabase.auth.getUser()
      if (authError || !authData.user) {
        return errorResponse(requestId, 401, "UNAUTHORIZED", "Invalid auth token")
      }
      user = { id: authData.user.id, email: authData.user.email }

      const { data: adminRecord } = await supabaseAdmin
        .from("platform_admins")
        .select("id, role, is_active")
        .eq("auth_user_id", authData.user.id)
        .eq("is_active", true)
        .single()

      if (!adminRecord || !["platform_admin", "platform_superadmin"].includes(adminRecord.role)) {
        return errorResponse(requestId, 403, "FORBIDDEN", "Not a platform administrator")
      }

      platformAdmin = adminRecord
    }

    // ══════════════════════════════════════════════════════════
    // GET routes — action via URL query param
    // ══════════════════════════════════════════════════════════
    if (req.method === "GET") {
      const url = new URL(req.url)
      const action = url.searchParams.get("action")

      if (action === "platform_overview") {
        const [{ data: terms, error: termsError }, { data: companies, error: companiesError },
          { data: licenses, error: licensesError }, { data: branchSummaries, error: branchSummaryError },
          { count: pendingInvitations, error: invitationsError }] = await Promise.all([
          supabaseAdmin.from("platform_license_terms").select("*").eq("singleton", true).single(),
          supabaseAdmin.from("company_summary").select("*").order("created_at", { ascending: false }).limit(1000),
          supabaseAdmin.from("platform_company_licenses").select("*").order("updated_at", { ascending: false }),
          supabaseAdmin.from("platform_company_branch_summary").select("company_id, branch_count, active_branch_count"),
          supabaseAdmin.from("platform_company_admin_invites").select("id", { count: "exact", head: true })
            .in("status", ["pending_delivery", "sent", "delivery_failed"])
            .gt("expires_at", new Date().toISOString()),
        ])
        if (termsError) throw termsError
        if (companiesError) throw companiesError
        if (licensesError) throw licensesError
        if (branchSummaryError) throw branchSummaryError
        if (invitationsError) throw invitationsError
        const branchCounts = new Map((branchSummaries || []).map((row: { company_id: string; branch_count: number; active_branch_count: number }) =>
          [row.company_id, { branch_count: Number(row.branch_count), active_branch_count: Number(row.active_branch_count) }]))
        const summaries = (companies || []).map((company: Record<string, unknown>) => ({
          ...company,
          branch_count: branchCounts.get(String(company.id))?.branch_count || 0,
          active_branch_count: branchCounts.get(String(company.id))?.active_branch_count || 0,
        }))
        return jsonResponse({ status: "success", terms, companies: summaries,
          licenses: licenses || [], pending_invitation_count: pendingInvitations || 0, request_id: requestId }, 200, requestId)
      }

      // ── list_companies ─────────────────────────────────────
      if (action === "list_companies") {
        const status = url.searchParams.get("status")

        let query = supabaseAdmin
          .from("company_summary")
          .select("*")
          .order("created_at", { ascending: false })
          .limit(100)

        if (status) {
          query = query.eq("status", status)
        }

        const { data: companies, error: fetchError } = await query
        if (fetchError) throw fetchError

        logRequestResult(ENDPOINT, requestId, 200, {
          actor_id: requireUser().id,
          action: "list_companies",
          count: (companies || []).length,
        })
        return jsonResponse({
          status: "success",
          companies: companies || [],
          count: (companies || []).length,
          request_id: requestId,
        }, 200, requestId)
      }

      // ── company_detail ─────────────────────────────────────
      if (action === "company_detail") {
        const companyId = url.searchParams.get("company_id")
        if (!companyId) {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", "company_id is required")
        }

        const { data: company, error: companyError } = await supabaseAdmin
          .from("companies")
          .select("*")
          .eq("id", companyId)
          .single()

        if (companyError || !company) {
          return errorResponse(requestId, 404, "NOT_FOUND", "Company not found")
        }

        // Get user count
        const { count: userCount } = await supabaseAdmin
          .from("users")
          .select("*", { count: "exact", head: true })
          .eq("company_id", companyId)

        const [branchesResult, membershipsResult, licensesResult, invitesResult, auditResult] = await Promise.all([
          supabaseAdmin.from("restaurant_branches").select("id, name, is_active, created_at, updated_at")
            .eq("company_id", companyId).order("created_at", { ascending: false }).limit(200),
          supabaseAdmin.from("restaurant_memberships").select("branch_id, user_id, access_role, is_active")
            .eq("company_id", companyId).eq("is_active", true).limit(500),
          supabaseAdmin.from("platform_company_licenses").select("*").eq("company_id", companyId).maybeSingle(),
          supabaseAdmin.from("platform_company_admin_invites")
            .select("id, email, full_name, status, expires_at, delivery_attempts, delivery_error_code, claimed_at, revoked_at, created_at")
            .eq("company_id", companyId).order("created_at", { ascending: false }).limit(100),
          supabaseAdmin.from("admin_audit_log")
            .select("id, actor_id, action, target_type, target_id, before_json, after_json, created_at")
            .eq("company_id", companyId).order("created_at", { ascending: false }).limit(100),
        ])
        if (branchesResult.error) throw branchesResult.error
        if (membershipsResult.error) throw membershipsResult.error
        if (licensesResult.error) throw licensesResult.error
        if (invitesResult.error) throw invitesResult.error
        if (auditResult.error) throw auditResult.error

        const responsibleIds = [...new Set((membershipsResult.data || [])
          .filter((membership: { access_role: string }) => membership.access_role === "admin")
          .map((membership: { user_id: string }) => membership.user_id))]
        const responsibleResult = responsibleIds.length
          ? await supabaseAdmin.from("users").select("id, full_name, email").in("id", responsibleIds)
          : { data: [], error: null }
        if (responsibleResult.error) throw responsibleResult.error
        const responsibleByBranch = new Map<string, Array<{ id: string; full_name: string | null; email: string | null }>>()
        for (const membership of membershipsResult.data || []) {
          if (membership.access_role !== "admin") continue
          const responsible = (responsibleResult.data || []).find((candidate: {
            id: string; full_name: string | null; email: string | null
          }) => candidate.id === membership.user_id)
          if (responsible) responsibleByBranch.set(membership.branch_id,
            [...(responsibleByBranch.get(membership.branch_id) || []), responsible])
        }
        const branches = (branchesResult.data || []).map((branch: {
          id: string; name: string; is_active: boolean; created_at: string; updated_at: string
        }) => ({
          ...branch, responsible_admins: responsibleByBranch.get(String(branch.id)) || [],
        }))
        const companyAudit = (auditResult.data || []).map((entry: Record<string, unknown>) => ({
          ...entry,
          target_id: entry.target_type === "platform_admin_invite" || typeof entry.target_id !== "string" ? null : entry.target_id,
          before_json: sanitizeAuditValue(entry.before_json),
          after_json: sanitizeAuditValue(entry.after_json),
        }))

        logRequestResult(ENDPOINT, requestId, 200, {
          actor_id: requireUser().id,
          action: "company_detail",
          company_id: companyId,
        })
        return jsonResponse({
          status: "success",
          company,
          user_count: userCount || 0,
          branches,
          license: licensesResult.data,
          invitations: invitesResult.data || [],
          audit: companyAudit,
          request_id: requestId,
        }, 200, requestId)
      }

      // ── company_users ──────────────────────────────────────
      if (action === "company_users") {
        const companyId = url.searchParams.get("company_id")
        if (!companyId) {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", "company_id is required")
        }

        const { data: users, error: usersError } = await supabaseAdmin
          .from("users")
          .select("id, full_name, email, role, is_active, created_at")
          .eq("company_id", companyId)
          .order("created_at", { ascending: false })
          .limit(200)

        if (usersError) throw usersError

        logRequestResult(ENDPOINT, requestId, 200, {
          actor_id: requireUser().id,
          action: "company_users",
          company_id: companyId,
          count: (users || []).length,
        })
        return jsonResponse({
          status: "success",
          users: users || [],
          count: (users || []).length,
          request_id: requestId,
        }, 200, requestId)
      }

      if (action === "company_admin_invites") {
        const companyId = url.searchParams.get("company_id")
        let query = supabaseAdmin.from("platform_company_admin_invites")
          .select("id, company_id, email, full_name, status, expires_at, delivery_attempts, delivery_error_code, claimed_at, revoked_at, created_at")
          .order("created_at", { ascending: false }).limit(500)
        if (companyId) query = query.eq("company_id", companyId)
        const { data: invitations, error: invitationsError } = await query
        if (invitationsError) throw invitationsError
        return jsonResponse({ status: "success", invitations: invitations || [], request_id: requestId }, 200, requestId)
      }

      // ── list_admins ────────────────────────────────────────
      if (action === "list_admins") {
        const { data: admins, error: adminsError } = await supabaseAdmin
          .from("platform_admins")
          .select("id, auth_user_id, role, full_name, email, is_active, created_at")
          .order("created_at", { ascending: false })
          .limit(100)

        if (adminsError) throw adminsError

        logRequestResult(ENDPOINT, requestId, 200, {
          actor_id: requireUser().id,
          action: "list_admins",
          count: (admins || []).length,
        })
        return jsonResponse({
          status: "success",
          admins: admins || [],
          count: (admins || []).length,
          request_id: requestId,
        }, 200, requestId)
      }

      // ── audit ──────────────────────────────────────────────
      if (action === "audit") {
        const companyId = url.searchParams.get("company_id")
        const limit = Math.min(parseInt(url.searchParams.get("limit") || "50", 10) || 50, 200)
        const before = url.searchParams.get("before") // ISO timestamp cursor

        let query = supabaseAdmin
          .from("admin_audit_log")
          .select("*")
          .order("created_at", { ascending: false })
          .limit(limit)

        if (companyId) {
          query = query.eq("company_id", companyId)
        }

        if (before) {
          query = query.lt("created_at", before)
        }

        const { data: logs, error: logsError } = await query
        if (logsError) throw logsError

        const actorIds = [...new Set((logs || []).map((log) => log.actor_id).filter(Boolean))]
        const actorEmails = new Map<string, string>()

        if (actorIds.length > 0) {
          const [{ data: platformActors }, { data: companyActors }] = await Promise.all([
            supabaseAdmin
              .from("platform_admins")
              .select("auth_user_id, email")
              .in("auth_user_id", actorIds),
            supabaseAdmin
              .from("users")
              .select("id, email")
              .in("id", actorIds),
          ])

          for (const actor of platformActors || []) {
            if (actor?.auth_user_id && actor?.email) {
              actorEmails.set(actor.auth_user_id, actor.email)
            }
          }
          for (const actor of companyActors || []) {
            if (actor?.id && actor?.email) {
              actorEmails.set(actor.id, actor.email)
            }
          }
        }

        const enrichedLogs = (logs || []).map((log) => ({
          ...log,
          target_id: log.target_type === "platform_admin_invite" ? null : log.target_id,
          before_json: sanitizeAuditValue(log.before_json),
          after_json: sanitizeAuditValue(log.after_json),
          actor_email: log.actor_id ? (actorEmails.get(log.actor_id) || null) : null,
        }))

        const nextCursor = (enrichedLogs.length === limit)
          ? enrichedLogs[enrichedLogs.length - 1].created_at
          : null

        logRequestResult(ENDPOINT, requestId, 200, {
          actor_id: requireUser().id,
          action: "audit",
          count: enrichedLogs.length,
        })
        return jsonResponse({
          status: "success",
          audit_logs: enrichedLogs,
          count: enrichedLogs.length,
          next_cursor: nextCursor,
          request_id: requestId,
        }, 200, requestId)
      }

      return errorResponse(requestId, 400, "INVALID_PAYLOAD",
        "Unknown GET action. Use: list_companies, company_detail, company_users, list_admins, audit")
    }

    // ══════════════════════════════════════════════════════════
    // POST routes — action in request body
    // ══════════════════════════════════════════════════════════
    if (req.method === "POST") {
      const { action } = payload

      if (!action) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "action is required in POST body")
      }

      if (action === "update_license_terms") {
        if (payload.commercially_authorized !== true) {
          return errorResponse(requestId, 400, "COMMERCIAL_AUTHORIZATION_REQUIRED", "Explicit commercial authorization is required")
        }
        const reference = typeof payload.authorization_reference === "string" ? payload.authorization_reference.trim() : ""
        const integer = (value: unknown) => Number.isSafeInteger(value)
        if (!reference || !integer(payload.package_branch_count) || !integer(payload.monthly_price_per_branch_cents)
          || !integer(payload.additional_branch_monthly_price_cents) || !integer(payload.maximum_additional_branches)
          || typeof payload.annual_custom_pricing_enabled !== "boolean" || typeof payload.currency !== "string") {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", "Provide valid terms and an authorization reference")
        }
        const { data, error } = await supabaseAdmin.rpc("platform_update_license_terms_audited", {
          p_actor_id: user!.id,
          p_package_branch_count: payload.package_branch_count,
          p_monthly_price_per_branch_cents: payload.monthly_price_per_branch_cents,
          p_additional_branch_monthly_price_cents: payload.additional_branch_monthly_price_cents,
          p_maximum_additional_branches: payload.maximum_additional_branches,
          p_annual_custom_pricing_enabled: payload.annual_custom_pricing_enabled,
          p_currency: payload.currency,
          p_authorization_reference: reference,
        })
        if (error) throw error
        return jsonResponse({ status: "success", terms: data, request_id: requestId }, 200, requestId)
      }

      if (action === "set_company_license") {
        if (payload.commercially_authorized !== true) {
          return errorResponse(requestId, 400, "COMMERCIAL_AUTHORIZATION_REQUIRED", "Explicit commercial authorization is required")
        }
        const reference = typeof payload.contract_reference === "string" ? payload.contract_reference.trim() : ""
        if (!reference || typeof payload.company_id !== "string" || !Number.isSafeInteger(payload.package_count)
          || !Number.isSafeInteger(payload.additional_branch_count)) {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", "Provide company, package quantities and contract reference")
        }
        const annualOverride = payload.annual_price_override_cents ?? null
        if (annualOverride !== null && !Number.isSafeInteger(annualOverride)) {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", "annual_price_override_cents must be an integer")
        }
        const { data, error } = await supabaseAdmin.rpc("platform_set_company_branch_license_audited", {
          p_actor_id: user!.id,
          p_company_id: payload.company_id,
          p_package_count: payload.package_count,
          p_additional_branch_count: payload.additional_branch_count,
          p_contract_reference: reference,
          p_annual_price_override_cents: annualOverride,
          p_annual_approval_reference: payload.annual_approval_reference ?? null,
        })
        if (error) throw error
        return jsonResponse({ status: "success", license: data, request_id: requestId }, 200, requestId)
      }

      // ── create_company ─────────────────────────────────────
      if (action === "create_company") {
        const idempotencyKey = req.headers.get("Idempotency-Key")
        if (!idempotencyKey) {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", "Idempotency-Key header is required")
        }

        const adminEmail = typeof payload.admin_email === "string" ? payload.admin_email.trim().toLowerCase() : ""
        const adminName = typeof payload.admin_name === "string" ? payload.admin_name.trim() : ""
        const { name, slug, industry, timezone } = payload
        if (typeof name !== "string" || typeof slug !== "string" || !adminEmail || !adminName) {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD",
            "name, slug, admin_email, and admin_name are required")
        }
        const requestHash = await sha256Hex(JSON.stringify({ name, slug, industry, timezone, adminEmail, adminName }))
        const { data, error } = await supabaseAdmin.rpc("platform_create_company_with_admin_invite", {
          p_actor_id: requireUser().id, p_name: name, p_slug: slug, p_industry: industry || null,
          p_timezone: timezone || "America/Mexico_City", p_admin_email: adminEmail, p_admin_name: adminName,
          p_settings: DEFAULT_COMPANY_SETTINGS, p_idempotency_key: idempotencyKey, p_request_hash: requestHash,
        })
        if (error) {
          if (error.code === "23505" && String(error.message || "").includes("IDEMPOTENCY_CONFLICT")) {
            return errorResponse(requestId, 409, "CONFLICT", "La clave de esta solicitud ya se utilizó con otros datos.")
          }
          if (error.code === "23505") return errorResponse(requestId, 409, "CONFLICT", "El identificador de empresa ya está registrado.")
          throw error
        }
        const company = data.company
        const invite = data.invite
        let delivery = { status: invite.status, message: "Invitación previamente procesada." }
        if (invite.status === "pending_delivery") {
          delivery = await deliverCompanyAdminInvite(supabaseAdmin, supabaseMailer, req, requireUser().id, invite)
        } else if (invite.status === "delivery_failed") {
          const { data: prepared, error: prepareError } = await supabaseAdmin.rpc("platform_prepare_company_admin_invite_delivery", {
            p_actor_id: requireUser().id, p_invite_id: invite.id,
          })
          if (prepareError) throw prepareError
          delivery = await deliverCompanyAdminInvite(supabaseAdmin, supabaseMailer, req, requireUser().id, prepared)
        }
        const responseBody = { status: "success", company, invitation: { id: invite.id, email: invite.email,
          status: delivery.status, message: delivery.message }, request_id: requestId }

        logRequestResult(ENDPOINT, requestId, 201, {
          actor_id: requireUser().id,
          action: "create_company",
          company_id: company.id,
        })
        return jsonResponse(responseBody, 201, requestId)
      }

      // ── toggle_company ─────────────────────────────────────
      if (action === "toggle_company") {
        const { company_id, status } = payload

        if (!company_id || !status) {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", "company_id and status are required")
        }
        if (!["active", "suspended"].includes(status)) {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", "status must be 'active' or 'suspended'")
        }

        const { data: company, error: statusError } = await supabaseAdmin.rpc("platform_set_company_status", {
          p_actor_id: requireUser().id, p_company_id: company_id, p_status: status,
        })
        if (statusError) throw statusError
        const responseBody = { status: "success", company_id, new_status: company.status, request_id: requestId }

        logRequestResult(ENDPOINT, requestId, 200, {
          actor_id: requireUser().id,
          action: "toggle_company",
          company_id,
          new_status: status,
        })
        return jsonResponse(responseBody, 200, requestId)
      }

      if (action === "update_company") {
        const { company_id, name, industry, address, phone, email, timezone } = payload
        if (typeof company_id !== "string" || typeof name !== "string" || typeof timezone !== "string") {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", "company_id, name, and timezone are required")
        }
        const { data: company, error: updateError } = await supabaseAdmin.rpc("platform_update_company", {
          p_actor_id: requireUser().id, p_company_id: company_id, p_name: name, p_industry: industry || null,
          p_address: address || null, p_phone: phone || null, p_email: email || null, p_timezone: timezone,
        })
        if (updateError) throw updateError
        return jsonResponse({ status: "success", company, request_id: requestId }, 200, requestId)
      }

      // ── create_invite ──────────────────────────────────────
      if (action === "create_invite") {
        return errorResponse(requestId, 410, "ENDPOINT_RETIRED",
          "Las invitaciones de superadministrador requieren un flujo de Auth verificado.")

        const email = typeof payload.email === "string" ? payload.email.trim().toLowerCase() : ""
        if (!email) {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", "email is required")
        }

        // Check if already a platform admin
        const { data: existingAdmin } = await supabaseAdmin
          .from("platform_admins")
          .select("id")
          .ilike("email", email)
          .eq("is_active", true)
          .maybeSingle()

        if (existingAdmin) {
          return errorResponse(requestId, 409, "CONFLICT", "Email is already a platform admin")
        }

        const inviteToken = crypto.randomUUID()
        const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString() // 7 days

        const inviteHash = await sha256Hex(inviteToken)
        const { data: invite, error: inviteError } = await supabaseAdmin.rpc("platform_create_admin_invite", {
          p_actor_id: requireUser().id, p_platform_admin_id: requirePlatformAdmin().id, p_email: email,
          p_token_hash: inviteHash, p_expires_at: expiresAt,
        })
        if (inviteError) throw inviteError

        const claimUrl = `${Deno.env.get("APP_URL") || ""}/claim?token=${inviteToken}`

        // NOTE: Do NOT log the claim URL or invite token — anyone with
        // log-viewer access could claim platform-admin privileges. The
        // token is already returned in the API response body to the
        // authenticated admin who created the invite.

        const responseBody = {
          status: "success",
          invite_token: inviteToken,
          claim_url: claimUrl,
          invite_id: invite.id,
          expires_at: expiresAt,
          request_id: requestId,
        }

        logRequestResult(ENDPOINT, requestId, 201, {
          actor_id: requireUser().id,
          action: "create_invite",
          email,
        })
        return jsonResponse(responseBody, 201, requestId)
      }

      // ── claim_invite ───────────────────────────────────────
      if (action === "claim_invite") {
        return errorResponse(requestId, 410, "ENDPOINT_RETIRED",
          "Las invitaciones de superadministrador requieren un flujo de Auth verificado.")

        const { invite_token, email, password, full_name } = payload

        if (typeof invite_token !== "string" || invite_token.length > 256
          || typeof email !== "string" || !email || typeof password !== "string"
          || typeof full_name !== "string" || !full_name) {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD",
            "invite_token, email, password, and full_name are required")
        }

        if (password.length < 8) {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", "Password must be at least 8 characters")
        }

        // Rate limit: check failed attempts from this IP in last 15 minutes
        const clientIp = req.headers.get("cf-connecting-ip") ||
          req.headers.get("x-real-ip") ||
          req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ||
          "unknown"

        if (clientIp !== "unknown") {
          const rateLimitWindow = new Date(Date.now() - 15 * 60 * 1000).toISOString()
          const { count: failedAttempts } = await supabaseAdmin
            .from("admin_audit_log")
            .select("id", { count: "exact", head: true })
            .eq("action", "claim_invite_failed")
            .eq("ip_address", clientIp)
            .gte("created_at", rateLimitWindow)

          if ((failedAttempts ?? 0) >= 5) {
            return errorResponse(requestId, 429, "RATE_LIMITED",
              "Too many failed attempts. Try again in 15 minutes.")
          }
        }

        // Validate invite
        const inviteHash = await sha256Hex(invite_token)
        let { data: invite, error: inviteError } = await supabaseAdmin
          .from("platform_admin_invites")
          .select("id, email, expires_at, claimed_at")
          .eq("invite_token_hash", inviteHash)
          .maybeSingle()

        // Legacy invite rows retain their original token column for
        // compatibility; no new invite writes a raw token to the database.
        if (!invite && !inviteError) {
          const legacy = await supabaseAdmin.from("platform_admin_invites")
            .select("id, email, expires_at, claimed_at")
            .eq("invite_token", invite_token).maybeSingle()
          invite = legacy.data
          inviteError = legacy.error
        }

        if (inviteError || !invite) {
          await logPlatformAction(supabaseAdmin, req, {
            actor_id: "anonymous",
            action: "claim_invite_failed",
            after: { reason: "invite_not_found" },
          })
          return errorResponse(requestId, 404, "NOT_FOUND", "Invite not found")
        }
        const validInvite = invite!

        if (validInvite.claimed_at) {
          await logPlatformAction(supabaseAdmin, req, {
            actor_id: "anonymous",
            action: "claim_invite_failed",
            target_type: "platform_admin_invite",
            target_id: validInvite.id,
            after: { reason: "already_claimed" },
          })
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", "Invite has already been claimed")
        }

        if (new Date(validInvite.expires_at) < new Date()) {
          await logPlatformAction(supabaseAdmin, req, {
            actor_id: "anonymous",
            action: "claim_invite_failed",
            target_type: "platform_admin_invite",
            target_id: validInvite.id,
            after: { reason: "invite_expired" },
          })
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", "Invite has expired")
        }

        if (validInvite.email !== email) {
          await logPlatformAction(supabaseAdmin, req, {
            actor_id: "anonymous",
            action: "claim_invite_failed",
            target_type: "platform_admin_invite",
            target_id: validInvite.id,
            after: { reason: "email_mismatch" },
          })
          return errorResponse(requestId, 403, "FORBIDDEN", "Email does not match invite")
        }

        const { data: existingUserRecord, error: existingUserError } = await supabaseAdmin
          .from("platform_admins")
          .select("id")
          .eq("email", email)
          .eq("is_active", true)
          .maybeSingle()

        if (existingUserError) throw existingUserError
        if (existingUserRecord) {
          return errorResponse(requestId, 409, "CONFLICT", "Email is already a platform admin")
        }

        // Create auth user
        const { data: authUser, error: authCreateError } = await supabaseAdmin.auth.admin.createUser({
          email,
          password,
          email_confirm: true,
        })

        if (authCreateError) {
          if (authCreateError?.message?.includes("already")) {
            return errorResponse(requestId, 409, "CONFLICT", "An account with this email already exists")
          }
          throw authCreateError
        }
        const createdAuthUser = authUser.user!

        const { error: claimError } = await supabaseAdmin.rpc("platform_claim_admin_invite", {
          p_invite_id: validInvite.id,
          p_auth_user_id: createdAuthUser.id,
          p_email: email,
          p_full_name: full_name,
        })
        if (claimError) {
          await supabaseAdmin.auth.admin.deleteUser(createdAuthUser.id)
          throw new Error("INVITE_CLAIM_FAILED")
        }

        const responseBody = {
          status: "success",
          platform_admin: {
            auth_user_id: createdAuthUser.id,
            email,
            full_name,
          },
          request_id: requestId,
        }

        logRequestResult(ENDPOINT, requestId, 201, {
          action: "claim_invite",
          email,
        })
        return jsonResponse(responseBody, 201, requestId)
      }

      if (action === "resend_company_admin_invite") {
        if (typeof payload.invitation_id !== "string") {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", "invitation_id is required")
        }
        const { data: invite, error: prepareError } = await supabaseAdmin.rpc("platform_prepare_company_admin_invite_delivery", {
          p_actor_id: requireUser().id, p_invite_id: payload.invitation_id,
        })
        if (prepareError) throw prepareError
        const delivery = await deliverCompanyAdminInvite(supabaseAdmin, supabaseMailer, req, requireUser().id, invite)
        return jsonResponse({ status: "success", invitation: { id: invite.id, status: delivery.status, message: delivery.message }, request_id: requestId }, 200, requestId)
      }

      if (action === "revoke_company_admin_invite") {
        if (typeof payload.invitation_id !== "string") {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", "invitation_id is required")
        }
        const { data: invite, error: revokeError } = await supabaseAdmin.rpc("platform_revoke_company_admin_invite", {
          p_actor_id: requireUser().id, p_invite_id: payload.invitation_id,
        })
        if (revokeError) throw revokeError
        return jsonResponse({ status: "success", invitation: { id: invite.id, status: invite.status }, request_id: requestId }, 200, requestId)
      }

      if (action === "claim_company_admin_invite") {
        if (typeof payload.invitation_id !== "string") {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", "invitation_id is required")
        }
        const { data: result, error: claimError } = await supabaseAdmin.rpc("platform_claim_company_admin_invite", {
          p_actor_id: requireUser().id, p_invite_id: payload.invitation_id,
        })
        if (claimError) throw claimError
        return jsonResponse({ status: "success", ...result, request_id: requestId }, 200, requestId)
      }

      return errorResponse(requestId, 400, "INVALID_PAYLOAD",
        "Unknown POST action")
    }

    return errorResponse(requestId, 405, "METHOD_NOT_ALLOWED", "Use GET or POST for /platform_admin")
  } catch (error) {
    const sensitiveInviteAction = ["claim_invite", "claim_company_admin_invite", "create_invite", "create_company",
      "resend_company_admin_invite"].includes(requestAction)
    const safeError = sensitiveInviteAction ? new Error("Platform invitation operation failed") : error
    logRequestError(ENDPOINT, requestId, safeError, { action: requestAction || "unknown" })
    return errorResponse(requestId, 500, "INTERNAL_ERROR",
      sensitiveInviteAction ? "No se pudo completar la operación de invitación." : "No se pudo completar la operación.")
  }
})
