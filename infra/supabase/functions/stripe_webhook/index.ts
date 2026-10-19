import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import Stripe from "npm:stripe@18.5.0"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.4"
import { corsHeaders, errorResponse, jsonResponse, logRequestError, makeRequestId } from "../_shared/api.ts"

function planFromSubscription(subscription: Stripe.Subscription | null): string {
  const price = subscription?.items.data[0]?.price
  const candidate = (
    price?.lookup_key ||
    price?.nickname ||
    price?.metadata?.plan ||
    "starter"
  ).toLowerCase()

  if (["starter", "pro", "business", "enterprise"].includes(candidate)) {
    return candidate
  }
  return "starter"
}

function paymentStatusFromSubscription(status?: string | null): string {
  switch (status) {
    case "trialing":
      return "trialing"
    case "active":
      return "active"
    case "past_due":
    case "unpaid":
      return "past_due"
    case "canceled":
    case "incomplete_expired":
      return "cancelled"
    default:
      return "trialing"
  }
}

async function syncCompanyBilling(
  supabaseAdmin: ReturnType<typeof createClient>,
  stripe: Stripe,
  customerId: string,
  subscriptionId?: string | null,
  fallbackEmail?: string | null,
) {
  let subscription: Stripe.Subscription | null = null
  if (subscriptionId) {
    subscription = await stripe.subscriptions.retrieve(subscriptionId)
  }

  const { error } = await supabaseAdmin
    .from("companies")
    .update({
      stripe_customer_id: customerId,
      stripe_subscription_id: subscriptionId || null,
      billing_email: fallbackEmail || null,
      billing_plan: planFromSubscription(subscription),
      payment_status: paymentStatusFromSubscription(subscription?.status),
    })
    .eq("stripe_customer_id", customerId)

  if (error) throw error
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders(req) })
  }

  const requestId = makeRequestId(req)

  try {
    if (req.method !== "POST") {
      return errorResponse(requestId, 405, "METHOD_NOT_ALLOWED", "Use POST for /stripe_webhook")
    }

    const stripeSecretKey = Deno.env.get("STRIPE_SECRET_KEY") || ""
    const stripeWebhookSecret = Deno.env.get("STRIPE_WEBHOOK_SECRET") || ""
    const supabaseUrl = Deno.env.get("SUPABASE_URL") || ""
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || ""
    const signature = req.headers.get("stripe-signature")

    if (!stripeSecretKey || !stripeWebhookSecret) {
      return errorResponse(requestId, 500, "MISSING_CONFIG", "Stripe webhook config is missing")
    }
    if (!signature) {
      return errorResponse(requestId, 400, "INVALID_PAYLOAD", "Missing stripe-signature header")
    }

    const stripe = new Stripe(stripeSecretKey)
    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey)
    const body = await req.text()
    const event = await stripe.webhooks.constructEventAsync(body, signature, stripeWebhookSecret)

    switch (event.type) {
      case "checkout.session.completed": {
        const session = event.data.object as Stripe.Checkout.Session
        if (typeof session.customer === "string") {
          await syncCompanyBilling(
            supabaseAdmin,
            stripe,
            session.customer,
            typeof session.subscription === "string" ? session.subscription : null,
            session.customer_details?.email || null,
          )
        }
        break
      }
      case "customer.subscription.created":
      case "customer.subscription.updated":
      case "customer.subscription.deleted": {
        const subscription = event.data.object as Stripe.Subscription
        const customerId = typeof subscription.customer === "string" ? subscription.customer : null
        if (customerId) {
          await syncCompanyBilling(
            supabaseAdmin,
            stripe,
            customerId,
            subscription.id,
            null,
          )
        }
        break
      }
      default:
        break
    }

    return jsonResponse({
      status: "success",
      event_type: event.type,
      request_id: requestId,
    }, 200, requestId)
  } catch (error) {
    logRequestError("stripe_webhook", requestId, error)
    return errorResponse(requestId, 500, "INTERNAL_ERROR", error instanceof Error ? error.message : "Internal server error")
  }
})
