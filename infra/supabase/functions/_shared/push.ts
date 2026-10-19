// Push notification sender utility.
//
// Sends FCM v1 HTTP messages to registered device tokens.
// Requires FIREBASE_SERVICE_ACCOUNT_JSON env var with the service account key.
//
// Usage from an edge function:
//   import { sendPush, sendPushToUser } from "../_shared/push.ts"
//
//   await sendPushToUser(supabase, userId, {
//     title: "OT Approved",
//     body: "Your overtime request was approved",
//     data: { route: "/overtime", entity_id: otRequestId, category: "ot_approval" },
//   })

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2"

interface PushPayload {
  title: string
  body: string
  data?: Record<string, string>
}

interface FCMMessage {
  message: {
    token: string
    notification: { title: string; body: string }
    data?: Record<string, string>
    android?: { priority: string; notification: { channel_id: string } }
    apns?: { payload: { aps: { sound: string; badge?: number } } }
  }
}

// Cache the OAuth2 access token (valid for ~1 hour).
let cachedAccessToken: string | null = null
let tokenExpiresAt = 0

async function getAccessToken(): Promise<string | null> {
  if (cachedAccessToken && Date.now() < tokenExpiresAt - 60_000) {
    return cachedAccessToken
  }

  const saJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON")
  if (!saJson) return null

  try {
    const sa = JSON.parse(saJson)
    const now = Math.floor(Date.now() / 1000)

    // Create JWT for Google OAuth2 token exchange
    const header = btoa(JSON.stringify({ alg: "RS256", typ: "JWT" }))
    const payload = btoa(
      JSON.stringify({
        iss: sa.client_email,
        scope: "https://www.googleapis.com/auth/firebase.messaging",
        aud: "https://oauth2.googleapis.com/token",
        iat: now,
        exp: now + 3600,
      }),
    )

    const signingInput = `${header}.${payload}`

    // Import the private key
    const pemKey = sa.private_key
      .replace("-----BEGIN PRIVATE KEY-----", "")
      .replace("-----END PRIVATE KEY-----", "")
      .replace(/\n/g, "")
    const binaryKey = Uint8Array.from(atob(pemKey), (c) => c.charCodeAt(0))

    const key = await crypto.subtle.importKey(
      "pkcs8",
      binaryKey,
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false,
      ["sign"],
    )

    const signature = await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      key,
      new TextEncoder().encode(signingInput),
    )

    const jwt = `${signingInput}.${btoa(
      String.fromCharCode(...new Uint8Array(signature)),
    )}`

    // Exchange JWT for access token
    const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
    })

    if (!tokenRes.ok) return null

    const tokenData = await tokenRes.json()
    cachedAccessToken = tokenData.access_token
    tokenExpiresAt = Date.now() + (tokenData.expires_in || 3600) * 1000
    return cachedAccessToken
  } catch {
    return null
  }
}

/**
 * Send a push notification to a specific device token.
 */
export async function sendPush(
  token: string,
  payload: PushPayload,
): Promise<boolean> {
  const accessToken = await getAccessToken()
  if (!accessToken) return false

  const saJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON")
  if (!saJson) return false

  const sa = JSON.parse(saJson)
  const projectId = sa.project_id

  const message: FCMMessage = {
    message: {
      token,
      notification: { title: payload.title, body: payload.body },
      data: payload.data,
      android: {
        priority: "high",
        notification: { channel_id: "fieldops_default" },
      },
      apns: {
        payload: { aps: { sound: "default" } },
      },
    },
  }

  try {
    const res = await fetch(
      `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(message),
      },
    )

    return res.ok
  } catch {
    return false
  }
}

/**
 * Send a push notification to all device tokens for a given user.
 * Stale tokens (404 from FCM) are automatically cleaned up.
 */
export async function sendPushToUser(
  supabase: SupabaseClient,
  userId: string,
  payload: PushPayload,
): Promise<{ sent: number; failed: number }> {
  const { data: tokens } = await supabase
    .from("device_tokens")
    .select("id, token")
    .eq("user_id", userId)

  if (!tokens || tokens.length === 0) return { sent: 0, failed: 0 }

  let sent = 0
  let failed = 0
  const staleIds: string[] = []

  for (const row of tokens) {
    const ok = await sendPush(row.token, payload)
    if (ok) {
      sent++
    } else {
      failed++
      staleIds.push(row.id)
    }
  }

  // Clean up stale tokens (best-effort)
  if (staleIds.length > 0) {
    await supabase.from("device_tokens").delete().in("id", staleIds)
  }

  return { sent, failed }
}

/**
 * Send a push notification to all users in a company with a given role.
 */
export async function sendPushToRole(
  supabase: SupabaseClient,
  companyId: string,
  role: string,
  payload: PushPayload,
): Promise<{ sent: number; failed: number }> {
  // Get users with the target role in the company
  const { data: users } = await supabase
    .from("users")
    .select("id")
    .eq("company_id", companyId)
    .eq("role", role)

  if (!users || users.length === 0) return { sent: 0, failed: 0 }

  let totalSent = 0
  let totalFailed = 0

  for (const user of users) {
    const result = await sendPushToUser(supabase, user.id, payload)
    totalSent += result.sent
    totalFailed += result.failed
  }

  return { sent: totalSent, failed: totalFailed }
}
