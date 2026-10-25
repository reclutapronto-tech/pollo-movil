// Firebase Cloud Messaging HTTP v1 sender.
// Requires FIREBASE_SERVICE_ACCOUNT_JSON in the Edge Function environment.

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2"

export interface PushPayload {
  title: string
  body: string
  data?: Record<string, string>
}

export interface PushSendResult {
  ok: boolean
  staleToken: boolean
  error?: string
}

interface FirebaseServiceAccount {
  project_id: string
  client_email: string
  private_key: string
}

interface FCMMessage {
  message: {
    token: string
    notification: { title: string; body: string }
    data?: Record<string, string>
    android?: { priority: "HIGH" | "NORMAL" }
    apns?: { payload: { aps: { sound: string } } }
  }
}

let cachedAccessToken: string | null = null
let tokenExpiresAt = 0

function base64UrlEncode(bytes: Uint8Array): string {
  let binary = ""
  for (const byte of bytes) binary += String.fromCharCode(byte)
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "")
}

function encodeJson(value: Record<string, unknown>): string {
  return base64UrlEncode(new TextEncoder().encode(JSON.stringify(value)))
}

function loadServiceAccount(): FirebaseServiceAccount | null {
  const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON")
  if (!raw) return null
  try {
    const value = JSON.parse(raw)
    if (
      typeof value.project_id !== "string" ||
      typeof value.client_email !== "string" ||
      typeof value.private_key !== "string"
    ) return null
    return value as FirebaseServiceAccount
  } catch {
    return null
  }
}

async function getAccessToken(account: FirebaseServiceAccount): Promise<string | null> {
  if (cachedAccessToken && Date.now() < tokenExpiresAt - 60_000) {
    return cachedAccessToken
  }

  try {
    const now = Math.floor(Date.now() / 1000)
    const header = encodeJson({ alg: "RS256", typ: "JWT" })
    const payload = encodeJson({
      iss: account.client_email,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    })
    const signingInput = `${header}.${payload}`
    const pemKey = account.private_key
      .replace(/\\n/g, "\n")
      .replace("-----BEGIN PRIVATE KEY-----", "")
      .replace("-----END PRIVATE KEY-----", "")
      .replace(/\s/g, "")
    const binaryKey = Uint8Array.from(atob(pemKey), (character) => character.charCodeAt(0))
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
    const assertion = `${signingInput}.${base64UrlEncode(new Uint8Array(signature))}`

    const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion,
      }),
    })
    if (!tokenResponse.ok) return null

    const tokenData = await tokenResponse.json()
    if (typeof tokenData.access_token !== "string") return null
    cachedAccessToken = tokenData.access_token
    tokenExpiresAt = Date.now() + Number(tokenData.expires_in || 3600) * 1000
    return cachedAccessToken
  } catch {
    return null
  }
}

function isUnregisteredToken(responseBody: string): boolean {
  try {
    const parsed = JSON.parse(responseBody)
    const error = parsed?.error
    if (error?.status === "UNREGISTERED") return true
    return Array.isArray(error?.details) && error.details.some(
      (detail: Record<string, unknown>) => detail.errorCode === "UNREGISTERED",
    )
  } catch {
    return false
  }
}

export async function sendPushDetailed(
  token: string,
  payload: PushPayload,
): Promise<PushSendResult> {
  const account = loadServiceAccount()
  if (!account) {
    return {
      ok: false,
      staleToken: false,
      error: Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON")
        ? "firebase_service_account_invalid"
        : "firebase_not_configured",
    }
  }

  const accessToken = await getAccessToken(account)
  if (!accessToken) {
    return { ok: false, staleToken: false, error: "firebase_oauth_unavailable" }
  }

  const message: FCMMessage = {
    message: {
      token,
      notification: { title: payload.title, body: payload.body },
      data: payload.data,
      android: { priority: "HIGH" },
      apns: { payload: { aps: { sound: "default" } } },
    },
  }

  try {
    const response = await fetch(
      `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(account.project_id)}/messages:send`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(message),
      },
    )

    if (response.ok) return { ok: true, staleToken: false }
    const responseBody = await response.text()
    const staleToken = isUnregisteredToken(responseBody)
    return {
      ok: false,
      staleToken,
      error: staleToken ? "fcm_token_unregistered" : `fcm_http_${response.status}`,
    }
  } catch {
    return { ok: false, staleToken: false, error: "fcm_network_unavailable" }
  }
}

export async function sendPush(token: string, payload: PushPayload): Promise<boolean> {
  return (await sendPushDetailed(token, payload)).ok
}

export async function sendPushToUser(
  supabase: SupabaseClient,
  userId: string,
  payload: PushPayload,
): Promise<{ sent: number; failed: number }> {
  const { data: tokens, error } = await supabase
    .from("device_tokens")
    .select("id, token")
    .eq("user_id", userId)
  if (error || !tokens?.length) return { sent: 0, failed: 0 }

  let sent = 0
  let failed = 0
  const staleIds: string[] = []
  for (const row of tokens) {
    const result = await sendPushDetailed(row.token, payload)
    if (result.ok) sent++
    else if (result.staleToken) staleIds.push(row.id)
    else failed++
  }

  if (staleIds.length > 0) {
    await supabase.from("device_tokens").delete().in("id", staleIds)
  }
  return { sent, failed }
}

export async function sendPushToRole(
  supabase: SupabaseClient,
  companyId: string,
  role: string,
  payload: PushPayload,
): Promise<{ sent: number; failed: number }> {
  const { data: users } = await supabase
    .from("users")
    .select("id")
    .eq("company_id", companyId)
    .eq("role", role)
  if (!users?.length) return { sent: 0, failed: 0 }

  let sent = 0
  let failed = 0
  for (const user of users) {
    const result = await sendPushToUser(supabase, user.id, payload)
    sent += result.sent
    failed += result.failed
  }
  return { sent, failed }
}
