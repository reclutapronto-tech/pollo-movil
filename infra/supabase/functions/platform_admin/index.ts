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
  lookupIdempotency,
  makeRequestId,
  sha256Hex,
  storeIdempotency,
} from "../_shared/api.ts"
import { DEFAULT_COMPANY_SETTINGS } from "../_shared/settings.ts"
import { OWNER_ROLE } from "../_shared/roles.ts"

const ENDPOINT = "platform_admin"

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

  if (error) {
    console.error("[platform_audit] Failed to write audit log:", error.message)
  }
}

function generateTempPassword(): string {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789!@#$%"
  let password = ""
  const array = new Uint8Array(16)
  crypto.getRandomValues(array)
  for (let i = 0; i < 16; i++) {
    password += chars[array[i] % chars.length]
  }
  return password
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders(req) })
  }

  const requestId = makeRequestId(req)
  logRequestStart(ENDPOINT, requestId, req)

  try {
    const payload = req.method === "POST" ? await req.json() : null
    const allowUnauthedClaim = req.method === "POST" && payload?.action === "claim_invite"

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

    let user: { id: string } | null = null
    let platformAdmin: { id: string; role: string; is_active: boolean } | null = null

    if (!allowUnauthedClaim) {
      const jwt = authHeader!.replace("Bearer ", "")
      const { data: authData, error: authError } = await supabase.auth.getUser()
      if (authError || !authData.user) {
        return errorResponse(requestId, 401, "UNAUTHORIZED", "Invalid auth token")
      }
      user = authData.user

      const { data: adminRecord } = await supabaseAdmin
        .from("platform_admins")
        .select("id, role, is_active")
        .eq("auth_user_id", user.id)
        .eq("is_active", true)
        .single()

      if (!adminRecord) {
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
          actor_id: user.id,
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

        logRequestResult(ENDPOINT, requestId, 200, {
          actor_id: user.id,
          action: "company_detail",
          company_id: companyId,
        })
        return jsonResponse({
          status: "success",
          company,
          user_count: userCount || 0,
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
          actor_id: user.id,
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

      // ── list_admins ────────────────────────────────────────
      if (action === "list_admins") {
        const { data: admins, error: adminsError } = await supabaseAdmin
          .from("platform_admins")
          .select("id, auth_user_id, role, full_name, email, is_active, created_at")
          .order("created_at", { ascending: false })
          .limit(100)

        if (adminsError) throw adminsError

        logRequestResult(ENDPOINT, requestId, 200, {
          actor_id: user.id,
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
          actor_email: log.actor_id ? (actorEmails.get(log.actor_id) || null) : null,
        }))

        const nextCursor = (enrichedLogs.length === limit)
          ? enrichedLogs[enrichedLogs.length - 1].created_at
          : null

        logRequestResult(ENDPOINT, requestId, 200, {
          actor_id: user.id,
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

      // ── create_company ─────────────────────────────────────
      if (action === "create_company") {
        const idempotencyKey = req.headers.get("Idempotency-Key")
        if (!idempotencyKey) {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", "Idempotency-Key header is required")
        }

        const owner_email = payload.owner_email || payload.admin_email
        const owner_name = payload.owner_name || payload.admin_name
        const { name, slug, industry, timezone } = payload

        if (!name || !slug || !owner_email || !owner_name) {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD",
            "name, slug, owner_email, and owner_name are required")
        }

        const requestHash = await sha256Hex(JSON.stringify(payload))
        const replay = await lookupIdempotency(supabaseAdmin, user.id, ENDPOINT + ":create_company", idempotencyKey, requestHash)
        if (replay.replay) {
          if (replay.conflict) {
            return errorResponse(replay.requestId, 409, "CONFLICT", "Idempotency key reused with different payload")
          }
          return jsonResponse(replay.body, replay.status, replay.requestId)
        }

        // Check slug uniqueness
        const { data: existingSlug } = await supabaseAdmin
          .from("companies")
          .select("id")
          .eq("slug", slug)
          .maybeSingle()

        if (existingSlug) {
          return errorResponse(requestId, 409, "CONFLICT", "Company slug already exists")
        }

        // Create company
        const companyId = crypto.randomUUID()
        const { error: companyError } = await supabaseAdmin
          .from("companies")
          .insert({
            id: companyId,
            name,
            slug,
            industry: industry || null,
            timezone: timezone || "America/New_York",
            status: "active",
            settings: DEFAULT_COMPANY_SETTINGS,
            settings_version: 1,
          })

        if (companyError) throw companyError

        // Create auth user for the company admin
        const tempPassword = generateTempPassword()
        const { data: authUser, error: authCreateError } = await supabaseAdmin.auth.admin.createUser({
          email: owner_email,
          password: tempPassword,
          email_confirm: true,
        })

        if (authCreateError) {
          // Rollback company creation
          await supabaseAdmin.from("companies").delete().eq("id", companyId)
          if (authCreateError.message?.includes("already")) {
            return errorResponse(requestId, 409, "CONFLICT", "Admin email already has an account")
          }
          throw authCreateError
        }

        // Create user record
        const { error: userInsertError } = await supabaseAdmin
          .from("users")
          .insert({
            id: authUser.user.id,
            company_id: companyId,
            full_name: owner_name,
            email: owner_email,
            role: OWNER_ROLE,
            is_active: true,
          })

        if (userInsertError) {
          // Rollback auth user and company
          await supabaseAdmin.auth.admin.deleteUser(authUser.user.id)
          await supabaseAdmin.from("companies").delete().eq("id", companyId)
          throw userInsertError
        }

        await logPlatformAction(supabaseAdmin, req, {
          actor_id: user.id,
          action: "create_company",
          company_id: companyId,
          target_type: "company",
          target_id: companyId,
          after: { name, slug, owner_email },
        })

        const responseBody = {
          status: "success",
          company: {
            id: companyId,
            name,
            slug,
            industry: industry || null,
            timezone: timezone || "America/New_York",
          },
          owner_user: {
            id: authUser.user.id,
            email: owner_email,
            full_name: owner_name,
            temp_password: tempPassword,
          },
          request_id: requestId,
        }

        await storeIdempotency(
          supabaseAdmin,
          user.id,
          ENDPOINT + ":create_company",
          idempotencyKey,
          requestHash,
          201,
          responseBody,
          requestId,
        )

        logRequestResult(ENDPOINT, requestId, 201, {
          actor_id: user.id,
          action: "create_company",
          company_id: companyId,
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

        // Get current state
        const { data: company, error: companyError } = await supabaseAdmin
          .from("companies")
          .select("id, name, status")
          .eq("id", company_id)
          .single()

        if (companyError || !company) {
          return errorResponse(requestId, 404, "NOT_FOUND", "Company not found")
        }

        if (company.status === status) {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", `Company is already '${status}'`)
        }

        // Update company status
        const { error: updateError } = await supabaseAdmin
          .from("companies")
          .update({ status })
          .eq("id", company_id)

        if (updateError) throw updateError

        // Ban or unban all users in the company
        const { data: companyUsers, error: usersError } = await supabaseAdmin
          .from("users")
          .select("id")
          .eq("company_id", company_id)

        if (usersError) throw usersError

        const banErrors: string[] = []
        for (const companyUser of (companyUsers || [])) {
          try {
            if (status === "suspended") {
              // Ban for ~100 years
              await supabaseAdmin.auth.admin.updateUserById(companyUser.id, {
                ban_duration: "876000h",
              })
            } else {
              // Unban
              await supabaseAdmin.auth.admin.updateUserById(companyUser.id, {
                ban_duration: "none",
              })
            }
          } catch (banErr) {
            banErrors.push(`${companyUser.id}: ${banErr instanceof Error ? banErr.message : String(banErr)}`)
          }
        }

        await logPlatformAction(supabaseAdmin, req, {
          actor_id: user.id,
          action: status === "suspended" ? "suspend_company" : "reactivate_company",
          company_id: company_id,
          target_type: "company",
          target_id: company_id,
          before: { status: company.status },
          after: { status, users_affected: (companyUsers || []).length },
        })

        const responseBody = {
          status: "success",
          company_id,
          new_status: status,
          users_affected: (companyUsers || []).length,
          ban_errors: banErrors.length > 0 ? banErrors : undefined,
          request_id: requestId,
        }

        logRequestResult(ENDPOINT, requestId, 200, {
          actor_id: user.id,
          action: "toggle_company",
          company_id,
          new_status: status,
        })
        return jsonResponse(responseBody, 200, requestId)
      }

      // ── create_invite ──────────────────────────────────────
      if (action === "create_invite") {
        const { email } = payload

        if (!email) {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", "email is required")
        }

        // Check if already a platform admin
        const { data: existingAdmin } = await supabaseAdmin
          .from("platform_admins")
          .select("id")
          .eq("email", email)
          .eq("is_active", true)
          .maybeSingle()

        if (existingAdmin) {
          return errorResponse(requestId, 409, "CONFLICT", "Email is already a platform admin")
        }

        const inviteToken = crypto.randomUUID()
        const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString() // 7 days

        const { error: inviteError } = await supabaseAdmin
          .from("platform_admin_invites")
          .insert({
            email,
            invite_token: inviteToken,
            created_by: platformAdmin.id,
            expires_at: expiresAt,
          })

        if (inviteError) throw inviteError

        const claimUrl = `${Deno.env.get("APP_URL") || ""}/claim?token=${inviteToken}`

        await logPlatformAction(supabaseAdmin, req, {
          actor_id: user.id,
          action: "create_invite",
          target_type: "platform_admin_invite",
          target_id: inviteToken,
          after: { email, expires_at: expiresAt },
        })

        // NOTE: Do NOT log the claim URL or invite token — anyone with
        // log-viewer access could claim platform-admin privileges. The
        // token is already returned in the API response body to the
        // authenticated admin who created the invite.

        const responseBody = {
          status: "success",
          invite_token: inviteToken,
          claim_url: claimUrl,
          expires_at: expiresAt,
          request_id: requestId,
        }

        logRequestResult(ENDPOINT, requestId, 201, {
          actor_id: user.id,
          action: "create_invite",
          email,
        })
        return jsonResponse(responseBody, 201, requestId)
      }

      // ── claim_invite ───────────────────────────────────────
      if (action === "claim_invite") {
        const { invite_token, email, password, full_name } = payload

        if (!invite_token || !email || !password || !full_name) {
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
        const { data: invite, error: inviteError } = await supabaseAdmin
          .from("platform_admin_invites")
          .select("id, email, invite_token, expires_at, claimed_at")
          .eq("invite_token", invite_token)
          .single()

        if (inviteError || !invite) {
          await logPlatformAction(supabaseAdmin, req, {
            actor_id: "anonymous",
            action: "claim_invite_failed",
            after: { reason: "invite_not_found", invite_token },
          })
          return errorResponse(requestId, 404, "NOT_FOUND", "Invite not found")
        }

        if (invite.claimed_at) {
          await logPlatformAction(supabaseAdmin, req, {
            actor_id: "anonymous",
            action: "claim_invite_failed",
            target_type: "platform_admin_invite",
            target_id: invite.id,
            after: { reason: "already_claimed" },
          })
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", "Invite has already been claimed")
        }

        if (new Date(invite.expires_at) < new Date()) {
          await logPlatformAction(supabaseAdmin, req, {
            actor_id: "anonymous",
            action: "claim_invite_failed",
            target_type: "platform_admin_invite",
            target_id: invite.id,
            after: { reason: "invite_expired" },
          })
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", "Invite has expired")
        }

        if (invite.email !== email) {
          await logPlatformAction(supabaseAdmin, req, {
            actor_id: "anonymous",
            action: "claim_invite_failed",
            target_type: "platform_admin_invite",
            target_id: invite.id,
            after: { reason: "email_mismatch" },
          })
          return errorResponse(requestId, 403, "FORBIDDEN", "Email does not match invite")
        }

        // Check if an active platform_admin already exists for this email.
        // We rely on the platform_admins table rather than listUsers() so
        // that the check is scoped to platform-level access, not any auth
        // account. A separate createUser() call below handles the
        // "auth.users already has this email" case via its error message.
        const { data: existingUserRecord } = await supabaseAdmin
          .from("platform_admins")
          .select("id")
          .eq("email", email)
          .eq("is_active", true)
          .maybeSingle()

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
          if (authCreateError.message?.includes("already")) {
            return errorResponse(requestId, 409, "CONFLICT", "An account with this email already exists")
          }
          throw authCreateError
        }

        // Insert into platform_admins
        const { error: adminInsertError } = await supabaseAdmin
          .from("platform_admins")
          .insert({
            auth_user_id: authUser.user.id,
            full_name,
            email,
            role: "platform_admin",
            is_active: true,
          })

        if (adminInsertError) {
          // Rollback auth user
          await supabaseAdmin.auth.admin.deleteUser(authUser.user.id)
          throw adminInsertError
        }

        // Mark invite as claimed
        const { error: claimError } = await supabaseAdmin
          .from("platform_admin_invites")
          .update({
            claimed_at: new Date().toISOString(),
          })
          .eq("id", invite.id)

        if (claimError) {
          console.error("[platform_admin] Failed to mark invite as claimed:", claimError.message)
        }

        await logPlatformAction(supabaseAdmin, req, {
          actor_id: authUser.user.id,
          action: "claim_invite",
          target_type: "platform_admin",
          target_id: authUser.user.id,
          after: { email, full_name, invite_token },
        })

        const responseBody = {
          status: "success",
          platform_admin: {
            auth_user_id: authUser.user.id,
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

      return errorResponse(requestId, 400, "INVALID_PAYLOAD",
        "Unknown POST action. Use: create_company, toggle_company, create_invite, claim_invite")
    }

    return errorResponse(requestId, 405, "METHOD_NOT_ALLOWED", "Use GET or POST for /platform_admin")
  } catch (error) {
    logRequestError(ENDPOINT, requestId, error)
    console.error("platform_admin error:", error)
    return errorResponse(requestId, 500, "INTERNAL_ERROR", error.message || "Internal server error")
  }
})
