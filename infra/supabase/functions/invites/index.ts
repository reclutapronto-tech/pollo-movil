import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.4"
import {
  applyRateLimit,
  corsHeaders,
  errorResponse,
  jsonResponse,
  makeRequestId,
  logRequestError,
} from "../_shared/api.ts"
import { OWNER_ROLE, isManagementRole } from "../_shared/roles.ts"

const ENDPOINT = "invites"
// Supervisors can send at most 10 invites per hour. inviteUserByEmail
// consumes Supabase email quota and is an abuse vector on compromised
// accounts.
const INVITE_RATE_LIMIT = 10
const INVITE_RATE_WINDOW_SECONDS = 3600

/**
 * Worker invite system.
 *
 * POST /invites — Admin sends invite to worker via email or phone.
 * Creates an invite token, stores it, and sends via Supabase Auth magic link.
 * Worker clicks link → deep link opens app → account activates in under 2 minutes.
 *
 * GET /invites — List pending invites for the company.
 */
serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders(req) })
  }

  const requestId = makeRequestId(req)

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

    const jwt = authHeader.replace("Bearer ", "")
    const { data: { user }, error: authError } = await supabase.auth.getUser()
    if (authError || !user) {
      return errorResponse(requestId, 401, "UNAUTHORIZED", "Invalid auth token")
    }

    const { data: userRecord } = await supabase
      .from("users")
      .select("id, company_id, role, is_active")
      .eq("id", user.id)
      .single()

    if (!userRecord?.is_active) {
      return errorResponse(requestId, 403, "FORBIDDEN", "User is inactive")
    }

    // Owners, admins, and supervisors can send invites. Deliberately NOT
    // isForemanOrAbove — foremen must not mint company invites. The literal
    // check is equivalent to isSupervisorOrAbove; kept explicit so a future
    // roles.ts refactor can't silently widen this gate.
    if (!isManagementRole(userRecord.role) && userRecord.role !== "supervisor") {
      return errorResponse(requestId, 403, "FORBIDDEN", "Only owners, admins, or supervisors can send invites")
    }

    if (req.method === "POST") {
      const payload = await req.json()
      const { email, phone, full_name, role } = payload

      if (!email && !phone) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "email or phone required")
      }

      const workerRole = role || "worker"
      // Admins can invite supervisors; non-admins can only invite worker/foreman
      const allowedRoles = userRecord.role === OWNER_ROLE
        ? ["admin", "supervisor", "foreman", "worker"]
        : userRecord.role === "admin"
        ? ["worker", "foreman", "supervisor"]
        : ["worker", "foreman"]
      if (!allowedRoles.includes(workerRole)) {
        const allowed = allowedRoles.join(", ")
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", `role must be one of: ${allowed}`)
      }

      // Throttle invite sending — compromised supervisor accounts could
      // otherwise loop this endpoint and burn email quota.
      const rateLimit = await applyRateLimit(
        supabaseAdmin,
        user.id,
        ENDPOINT,
        requestId,
        INVITE_RATE_LIMIT,
        INVITE_RATE_WINDOW_SECONDS,
      )
      if (rateLimit.limited) {
        return errorResponse(
          requestId,
          429,
          "RATE_LIMITED",
          `Invite rate limit exceeded (${INVITE_RATE_LIMIT}/hour)`,
          [],
          rateLimit.headers,
        )
      }

      // Create invite via Supabase Auth.
      //
      // Strategy: try inviteUserByEmail first (sends an email if SMTP is
      // configured), then fall back to generateLink if email sending fails
      // (no SMTP configured, quota exhausted, domain blocked, etc.). In
      // either case, return the activation link to the admin so they can
      // copy/paste it into SMS, WhatsApp, or their own email client.
      // Without this fallback, a missing/throttled SMTP kills the whole
      // onboarding flow.
      if (email) {
        const metadata = {
          company_id: userRecord.company_id,
          full_name: full_name || email.split("@")[0],
          role: workerRole,
          invited_by: user.id,
        }

        let inviteUserId: string | null = null
        let emailSent = false
        let inviteLink: string | null = null
        let inviteErrorMessage: string | null = null

        const { data: inviteData, error: inviteError } =
          await supabaseAdmin.auth.admin.inviteUserByEmail(email, {
            data: metadata,
          })

        if (inviteError) {
          inviteErrorMessage = inviteError.message || String(inviteError)
        } else {
          inviteUserId = inviteData?.user?.id ?? null
          emailSent = true
        }

        // Always produce a shareable link so the admin has a way to onboard
        // the worker even when email delivery fails. If inviteUserByEmail
        // already created the auth user, generateLink just re-issues the
        // activation token for the same user.
        const { data: linkData, error: linkError } =
          await supabaseAdmin.auth.admin.generateLink({
            type: "invite",
            email,
            options: {
              data: metadata,
              redirectTo: Deno.env.get("PUBLIC_WEB_URL")
                ? `${Deno.env.get("PUBLIC_WEB_URL")}/sign-in`
                : undefined,
            },
          })

        if (!linkError && linkData) {
          inviteLink = linkData.properties?.action_link ?? null
          if (!inviteUserId) {
            inviteUserId = linkData.user?.id ?? null
          }
        }

        // Only surface a hard failure when BOTH paths failed.
        if (!emailSent && !inviteLink) {
          return errorResponse(
            requestId,
            500,
            "INTERNAL_ERROR",
            inviteErrorMessage || linkError?.message || "Failed to create invite",
          )
        }

        return jsonResponse({
          status: "success",
          invite_id: inviteUserId ?? crypto.randomUUID(),
          method: emailSent ? "email" : "link",
          recipient: email,
          email_sent: emailSent,
          email_error: emailSent ? null : inviteErrorMessage,
          invite_link: inviteLink,
          request_id: requestId,
        }, 201, requestId)
      }

      // Phone invite — create auth user + users record, SMS activation sent when Twilio is wired
      const { data: authUser, error: authCreateError } = await supabaseAdmin.auth.admin.createUser({
        phone,
        phone_confirm: false,
        user_metadata: {
          company_id: userRecord.company_id,
          full_name: full_name || phone,
          role: workerRole,
          invited_by: user.id,
        },
      })

      if (authCreateError) throw authCreateError

      const { error: insertError } = await supabaseAdmin
        .from("users")
        .insert({
          id: authUser.user.id,
          company_id: userRecord.company_id,
          role: workerRole,
          full_name: full_name || phone,
          phone,
          is_active: false,
        })

      if (insertError) throw insertError

      return jsonResponse({
        status: "success",
        invite_id: authUser.user.id,
        method: "phone",
        recipient: phone,
        note: "User record created. SMS activation will be sent once Twilio is configured.",
        request_id: requestId,
      }, 201, requestId)
    }

    if (req.method === "GET") {
      // List pending invites (users with no confirmed email)
      const { data: pendingUsers } = await supabaseAdmin
        .from("users")
        .select("id, full_name, email, role, created_at")
        .eq("company_id", userRecord.company_id)
        .eq("is_active", false)
        .order("created_at", { ascending: false })
        .limit(50)

      return jsonResponse({
        status: "success",
        invites: pendingUsers || [],
        request_id: requestId,
      }, 200, requestId)
    }

    return errorResponse(requestId, 405, "METHOD_NOT_ALLOWED", "Use GET or POST")
  } catch (error) {
    logRequestError("invites", requestId, error)
    return errorResponse(requestId, 500, "INTERNAL_ERROR", error.message || "Internal server error")
  }
})
