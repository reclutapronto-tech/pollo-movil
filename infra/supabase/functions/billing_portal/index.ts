import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import Stripe from "npm:stripe@18.5.0"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.4"
import { corsHeaders, errorResponse, jsonResponse, makeRequestId, logRequestError } from "../_shared/api.ts"
import { isManagementRole } from "../_shared/roles.ts"

const ENDPOINT = "billing_portal"

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders(req) })
  }

  const requestId = makeRequestId(req)

  try {
    if (req.method !== "POST") {
      return errorResponse(requestId, 405, "METHOD_NOT_ALLOWED", "Use POST for /billing_portal")
    }

    const authHeader = req.headers.get("Authorization")
    if (!authHeader) {
      return errorResponse(requestId, 401, "UNAUTHORIZED", "Missing Authorization header")
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") || ""
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || ""
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") || ""
    const stripeSecretKey = Deno.env.get("STRIPE_SECRET_KEY") || ""
    const appUrl = Deno.env.get("APP_URL") || ""

    const stripe = stripeSecretKey ? new Stripe(stripeSecretKey) : null
    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    })
    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey)

    const jwt = authHeader.replace("Bearer ", "")
    const { data: authData, error: authError } = await supabase.auth.getUser()
    if (authError || !authData.user) {
      return errorResponse(requestId, 401, "UNAUTHORIZED", "Invalid auth token")
    }

    const { data: userRecord } = await supabaseAdmin
      .from("users")
      .select("id, company_id, role, email, full_name, is_active")
      .eq("id", authData.user.id)
      .single()

    if (!userRecord?.is_active) {
      return errorResponse(requestId, 403, "FORBIDDEN", "User is inactive")
    }
    if (!isManagementRole(userRecord.role)) {
      return errorResponse(requestId, 403, "FORBIDDEN", "Only owners or admins can manage billing")
    }

    const { data: company, error: companyError } = await supabaseAdmin
      .from("companies")
      .select("id, name, billing_mode, stripe_customer_id, billing_email")
      .eq("id", userRecord.company_id)
      .single()

    if (companyError || !company) {
      return errorResponse(requestId, 404, "NOT_FOUND", "Company not found")
    }

    if (company.billing_mode === "demo" || !stripe) {
      return jsonResponse({
        status: "success",
        mode: "demo",
        request_id: requestId,
      }, 200, requestId)
    }

    const payload = await req.json().catch(() => ({}))
    const returnUrl = typeof payload.return_url === "string" && payload.return_url.length > 0
      ? payload.return_url
      : `${appUrl}/settings/billing`

    let stripeCustomerId = company.stripe_customer_id
    if (!stripeCustomerId) {
      const customer = await stripe.customers.create({
        name: company.name,
        email: company.billing_email || userRecord.email || undefined,
        metadata: {
          company_id: company.id,
        },
      })
      stripeCustomerId = customer.id

      const { error: updateError } = await supabaseAdmin
        .from("companies")
        .update({
          stripe_customer_id: stripeCustomerId,
          billing_email: company.billing_email || userRecord.email || null,
        })
        .eq("id", company.id)

      if (updateError) throw updateError
    }

    const session = await stripe.billingPortal.sessions.create({
      customer: stripeCustomerId,
      return_url: returnUrl,
    })

    return jsonResponse({
      status: "success",
      url: session.url,
      request_id: requestId,
    }, 200, requestId)
  } catch (error) {
    logRequestError(ENDPOINT, requestId, error)
    return errorResponse(requestId, 500, "INTERNAL_ERROR", error instanceof Error ? error.message : "Internal server error")
  }
})
