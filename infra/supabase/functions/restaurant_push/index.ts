import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import {
  corsHeaders,
  errorResponse,
  jsonResponse,
  logRequestError,
  logRequestResult,
  logRequestStart,
  makeRequestId,
} from "../_shared/api.ts"
import { sendPushDetailed } from "../_shared/push.ts"

type OutboxRow = {
  id: string
  notification_id: string
  attempts: number
}

type RestaurantNotification = {
  id: string
  branch_id: string
  recipient_id: string
  notification_type: string
  title: string
  body: string
  entity_type: string
  entity_id: string
  data: Record<string, unknown> | null
}

const ENDPOINT = "restaurant_push"
const MAX_BATCH = 40
const MAX_ATTEMPTS = 8
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

function targetTab(notificationType: string): string | null {
  if (notificationType.startsWith("incident_")) return "incidents"
  if (notificationType.startsWith("shift_handoff_")) return "handoff"
  if (notificationType === "inspection_attention" || notificationType.startsWith("waste_")) {
    return "waste"
  }
  if (
    notificationType.startsWith("task_") ||
    notificationType.startsWith("shift_") ||
    notificationType.startsWith("absence_")
  ) return "shift"
  return null
}

function asFcmData(notification: RestaurantNotification): Record<string, string> {
  const data: Record<string, string> = {}
  for (const [key, value] of Object.entries(notification.data ?? {})) {
    if (typeof value === "string" || typeof value === "number" || typeof value === "boolean") {
      data[key] = String(value)
    }
  }

  data.notification_id = notification.id
  data.notification_type = notification.notification_type
  data.entity_type = notification.entity_type
  data.entity_id = notification.entity_id
  data.branch_id = notification.branch_id
  const tab = targetTab(notification.notification_type)
  if (tab) data.tab = tab
  return data
}

function retryAt(attempts: number): string {
  const delaySeconds = Math.min(3600, 60 * 2 ** Math.max(0, attempts - 1))
  return new Date(Date.now() + delaySeconds * 1000).toISOString()
}

async function claimOutboxRow(
  admin: ReturnType<typeof createClient>,
  row: OutboxRow,
  now: string,
  leaseUntil: string,
) {
  const patch = { lease_until: leaseUntil, attempts: row.attempts + 1 }
  const claimUnleased = await admin
    .from("restaurant_push_outbox")
    .update(patch)
    .eq("id", row.id)
    .is("sent_at", null)
    .is("failed_at", null)
    .lte("available_at", now)
    .is("lease_until", null)
    .select("id, attempts")
    .maybeSingle()

  if (claimUnleased.error || claimUnleased.data) return claimUnleased

  return await admin
    .from("restaurant_push_outbox")
    .update(patch)
    .eq("id", row.id)
    .is("sent_at", null)
    .is("failed_at", null)
    .lte("available_at", now)
    .lte("lease_until", now)
    .select("id, attempts")
    .maybeSingle()
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders(req) })
  }

  const requestId = makeRequestId(req)
  logRequestStart(ENDPOINT, requestId, req)

  try {
    if (req.method !== "POST") {
      return errorResponse(requestId, 405, "METHOD_NOT_ALLOWED", "Use POST")
    }

    const cronSecret = Deno.env.get("CRON_SECRET") || ""
    if (!cronSecret || req.headers.get("x-cron-secret") !== cronSecret) {
      return errorResponse(requestId, 401, "UNAUTHORIZED", "Invalid or missing cron secret")
    }

    if (!Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON")) {
      return jsonResponse({ status: "push_not_configured", processed: 0 }, 202, requestId)
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") || ""
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || ""
    if (!supabaseUrl || !serviceKey) {
      return errorResponse(requestId, 500, "SERVER_CONFIGURATION", "Supabase service credentials are unavailable")
    }

    let requestedNotificationId: string | null = null
    const bodyText = await req.text()
    if (bodyText.trim().length > 0) {
      let payload: Record<string, unknown>
      try {
        payload = JSON.parse(bodyText)
      } catch {
        return errorResponse(requestId, 400, "INVALID_JSON", "Request body must be valid JSON")
      }
      if (payload?.notification_id !== undefined) {
        if (typeof payload.notification_id !== "string" || !UUID_PATTERN.test(payload.notification_id)) {
          return errorResponse(requestId, 400, "INVALID_NOTIFICATION_ID", "notification_id must be a UUID")
        }
        requestedNotificationId = payload.notification_id
      }
    }

    const admin = createClient(supabaseUrl, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    })
    const now = new Date().toISOString()
    let pending: OutboxRow[] = []

    if (requestedNotificationId) {
      const { data, error } = await admin
        .from("restaurant_push_outbox")
        .select("id, notification_id, attempts")
        .eq("notification_id", requestedNotificationId)
        .is("sent_at", null)
        .is("failed_at", null)
        .lte("available_at", now)
        .maybeSingle()
      if (error) throw error
      if (data) pending = [data as OutboxRow]
    } else {
      const [unleased, expiredLeases] = await Promise.all([
        admin.from("restaurant_push_outbox")
          .select("id, notification_id, attempts")
          .is("sent_at", null).is("failed_at", null).is("lease_until", null)
          .lte("available_at", now).order("created_at").limit(MAX_BATCH),
        admin.from("restaurant_push_outbox")
          .select("id, notification_id, attempts")
          .is("sent_at", null).is("failed_at", null).lte("lease_until", now)
          .lte("available_at", now).order("created_at").limit(MAX_BATCH),
      ])
      if (unleased.error) throw unleased.error
      if (expiredLeases.error) throw expiredLeases.error
      const unique = new Map<string, OutboxRow>()
      for (const row of [...(unleased.data ?? []), ...(expiredLeases.data ?? [])]) {
        unique.set(row.id, row as OutboxRow)
      }
      pending = [...unique.values()].slice(0, MAX_BATCH)
    }

    let processed = 0
    let delivered = 0
    let deferred = 0

    for (const row of pending) {
      const claimTime = new Date().toISOString()
      const leaseUntil = new Date(Date.now() + 2 * 60 * 1000).toISOString()
      const claim = await claimOutboxRow(admin, row, claimTime, leaseUntil)
      if (claim.error) throw claim.error
      if (!claim.data) continue

      const attempts = Number(claim.data.attempts)
      processed++

      try {
        const notificationResult = await admin
          .from("restaurant_notifications")
          .select("id, branch_id, recipient_id, notification_type, title, body, entity_type, entity_id, data")
          .eq("id", row.notification_id)
          .maybeSingle()
        if (notificationResult.error) throw notificationResult.error

        const notification = notificationResult.data as RestaurantNotification | null
        if (!notification) {
          const completed = await admin.from("restaurant_push_outbox")
            .update({ sent_at: new Date().toISOString(), lease_until: null })
            .eq("id", row.id)
          if (completed.error) throw completed.error
          continue
        }

        const [membership, user] = await Promise.all([
          admin.from("restaurant_memberships").select("user_id")
            .eq("branch_id", notification.branch_id)
            .eq("user_id", notification.recipient_id)
            .eq("is_active", true).maybeSingle(),
          admin.from("users").select("id, is_active")
            .eq("id", notification.recipient_id).maybeSingle(),
        ])
        if (membership.error) throw membership.error
        if (user.error) throw user.error

        if (!membership.data || !user.data?.is_active) {
          const completed = await admin.from("restaurant_push_outbox")
            .update({ sent_at: new Date().toISOString(), lease_until: null })
            .eq("id", row.id)
          if (completed.error) throw completed.error
          continue
        }

        const tokenResult = await admin.from("device_tokens")
          .select("id, token")
          .eq("user_id", notification.recipient_id)
        if (tokenResult.error) throw tokenResult.error

        const tokens = tokenResult.data ?? []
        if (tokens.length === 0) {
          const completed = await admin.from("restaurant_push_outbox")
            .update({ sent_at: new Date().toISOString(), lease_until: null })
            .eq("id", row.id)
          if (completed.error) throw completed.error
          continue
        }

        let sentCount = 0
        let retryableFailures = 0
        const staleTokenIds: string[] = []
        const pushPayload = {
          title: notification.title,
          body: notification.body,
          data: asFcmData(notification),
        }

        for (const token of tokens) {
          const result = await sendPushDetailed(token.token, pushPayload)
          if (result.ok) {
            sentCount++
          } else if (result.staleToken) {
            staleTokenIds.push(token.id)
          } else {
            retryableFailures++
          }
        }

        if (staleTokenIds.length > 0) {
          const cleanup = await admin.from("device_tokens").delete()
            .eq("user_id", notification.recipient_id)
            .in("id", staleTokenIds)
          if (cleanup.error) throw cleanup.error
        }

        if (retryableFailures > 0) {
          const exhausted = attempts >= MAX_ATTEMPTS
          const update = await admin.from("restaurant_push_outbox").update({
            lease_until: null,
            available_at: exhausted ? now : retryAt(attempts),
            failed_at: exhausted ? new Date().toISOString() : null,
            last_error: exhausted
              ? `Delivery failed after ${attempts} attempts (${sentCount} devices accepted)`
              : `Temporary FCM failure (${sentCount} devices accepted)`,
          }).eq("id", row.id)
          if (update.error) throw update.error
          deferred++
          continue
        }

        const completed = await admin.from("restaurant_push_outbox").update({
          sent_at: new Date().toISOString(),
          lease_until: null,
          last_error: null,
        }).eq("id", row.id)
        if (completed.error) throw completed.error
        delivered += sentCount
      } catch (error) {
        const exhausted = attempts >= MAX_ATTEMPTS
        await admin.from("restaurant_push_outbox").update({
          lease_until: null,
          available_at: exhausted ? now : retryAt(attempts),
          failed_at: exhausted ? new Date().toISOString() : null,
          last_error: error instanceof Error ? error.message.slice(0, 500) : "Push dispatch failed",
        }).eq("id", row.id)
        if (exhausted) deferred++
        logRequestError(ENDPOINT, requestId, error)
      }
    }

    logRequestResult(ENDPOINT, requestId, 200, { processed, delivered, deferred })
    return jsonResponse({ status: "ok", processed, delivered, deferred }, 200, requestId)
  } catch (error) {
    logRequestError(ENDPOINT, requestId, error)
    return errorResponse(requestId, 500, "PUSH_DISPATCH_FAILED", "Unable to dispatch restaurant push notifications")
  }
})
