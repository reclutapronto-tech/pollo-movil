// photo-comments — threaded comments + @mentions on a media_asset.
// Pattern: mirrors tags/index.ts for auth, structured logging, and the
// media_asset → company ownership guard. @mentions fan out to alert_events
// (alert_type='photo_mention'), deduped on (user_id, source_event_uuid).
//
// Routing uses POST { action } rather than HTTP verbs for create/delete to
// avoid browser/proxy edge cases with DELETE-bodies; GET lists comments.
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
} from "../_shared/api.ts"
import { isSupervisorOrAbove } from "../_shared/roles.ts"

const ENDPOINT = "photo-comments"
const MAX_BODY = 4000
// Matches the markup the client writes on @mention select: @[Display Name](uuid)
const MENTION_RE = /@\[([^\]]{1,120})\]\(([0-9a-fA-F-]{36})\)/g

function normalizeBody(raw: unknown): string | null {
  if (typeof raw !== "string") return null
  const trimmed = raw.trim()
  if (trimmed.length < 1 || trimmed.length > MAX_BODY) return null
  return trimmed
}

// Extract unique mentioned user uuids from comment markup.
function parseMentionUuids(body: string): string[] {
  const ids = new Set<string>()
  for (const match of body.matchAll(MENTION_RE)) {
    ids.add(match[2].toLowerCase())
  }
  return [...ids]
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders(req) })
  }

  const requestId = makeRequestId(req)
  logRequestStart(ENDPOINT, requestId, req)

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

    const { data: { user }, error: authError } = await supabase.auth.getUser()
    if (authError || !user) {
      return errorResponse(requestId, 401, "UNAUTHORIZED", "Invalid auth token")
    }

    const { data: userRecord, error: userError } = await supabaseAdmin
      .from("users")
      .select("id, company_id, is_active, role, full_name")
      .eq("id", user.id)
      .single()

    if (userError || !userRecord) {
      return errorResponse(requestId, 401, "UNAUTHORIZED", "User record not found")
    }
    if (!userRecord.is_active) {
      return errorResponse(requestId, 403, "FORBIDDEN", "User is inactive")
    }

    // Verify a media asset belongs to the caller's company; returns the asset
    // row (id, company_id, job_id) or null.
    async function loadOwnedAsset(mediaAssetId: string) {
      const { data, error } = await supabaseAdmin
        .from("media_assets")
        .select("id, company_id, job_id")
        .eq("id", mediaAssetId)
        .maybeSingle()
      if (error) throw error
      if (!data || data.company_id !== userRecord!.company_id) return null
      return data
    }

    // ── GET /photo-comments?media_asset_id= ─────────────────────
    if (req.method === "GET") {
      const url = new URL(req.url)
      const mediaAssetId = url.searchParams.get("media_asset_id")
      if (!mediaAssetId) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "media_asset_id is required")
      }

      const asset = await loadOwnedAsset(mediaAssetId)
      if (!asset) {
        return errorResponse(requestId, 403, "FORBIDDEN", "Media asset not accessible")
      }

      // Include soft-deleted rows so replies keep thread context; blank the body
      // of deleted rows and surface a `deleted` flag for placeholder rendering.
      const { data: rows, error } = await supabaseAdmin
        .from("photo_comments")
        .select("id, parent_id, author_id, body, deleted_at, created_at, updated_at, users:author_id(full_name, avatar_url)")
        .eq("media_asset_id", mediaAssetId)
        .eq("company_id", userRecord.company_id)
        .order("created_at", { ascending: true })
      if (error) throw error

      // Validated mention sets per comment (anti-spoof: the UI only renders a
      // mention chip when its uuid is in this server-validated set).
      const commentIds = (rows || []).map((r) => r.id as string)
      const mentionsByComment = new Map<string, string[]>()
      if (commentIds.length > 0) {
        const { data: mentionRows, error: mErr } = await supabaseAdmin
          .from("photo_comment_mentions")
          .select("comment_id, mentioned_user_id")
          .in("comment_id", commentIds)
        if (mErr) throw mErr
        for (const m of mentionRows || []) {
          const list = mentionsByComment.get(m.comment_id as string) || []
          list.push(m.mentioned_user_id as string)
          mentionsByComment.set(m.comment_id as string, list)
        }
      }

      const comments = (rows || []).map((r) => {
        const deleted = !!r.deleted_at
        return {
          id: r.id,
          parent_id: r.parent_id,
          author_id: r.author_id,
          author: r.users ?? null,
          body: deleted ? "" : r.body,
          deleted,
          created_at: r.created_at,
          updated_at: r.updated_at,
          mention_user_ids: mentionsByComment.get(r.id as string) ?? [],
        }
      })

      logRequestResult(ENDPOINT, requestId, 200, { op: "list", returned: comments.length })
      return jsonResponse({ status: "success", comments, request_id: requestId }, 200, requestId)
    }

    // ── POST /photo-comments { action } ─────────────────────────
    if (req.method === "POST") {
      const body = await req.json().catch(() => null) as
        | { action?: unknown; media_asset_id?: unknown; body?: unknown; parent_id?: unknown; comment_id?: unknown }
        | null

      const action = typeof body?.action === "string" ? body!.action : "create"

      // ── action: delete (soft delete) ──────────────────────────
      if (action === "delete") {
        const commentId = typeof body?.comment_id === "string" ? body!.comment_id : null
        if (!commentId) {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", "comment_id is required")
        }

        const { data: existing, error: fetchErr } = await supabaseAdmin
          .from("photo_comments")
          .select("id, company_id, author_id, deleted_at")
          .eq("id", commentId)
          .maybeSingle()
        if (fetchErr) throw fetchErr
        if (!existing || existing.company_id !== userRecord.company_id) {
          return errorResponse(requestId, 404, "NOT_FOUND", "Comment not found")
        }

        const canDelete =
          existing.author_id === userRecord.id || isSupervisorOrAbove(userRecord.role)
        if (!canDelete) {
          return errorResponse(requestId, 403, "FORBIDDEN", "Not allowed to delete this comment")
        }

        const { error: delErr } = await supabaseAdmin
          .from("photo_comments")
          .update({ deleted_at: new Date().toISOString() })
          .eq("id", commentId)
          .eq("company_id", userRecord.company_id)
        if (delErr) throw delErr

        logRequestResult(ENDPOINT, requestId, 200, { op: "delete" })
        return jsonResponse({ status: "success", request_id: requestId }, 200, requestId)
      }

      // ── action: create ────────────────────────────────────────
      const mediaAssetId = typeof body?.media_asset_id === "string" ? body!.media_asset_id : null
      const commentBody = normalizeBody(body?.body)
      const parentId = typeof body?.parent_id === "string" ? body!.parent_id : null

      if (!mediaAssetId) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "media_asset_id is required")
      }
      if (!commentBody) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", `body must be 1..${MAX_BODY} chars`)
      }

      const asset = await loadOwnedAsset(mediaAssetId)
      if (!asset) {
        return errorResponse(requestId, 403, "FORBIDDEN", "Media asset not accessible")
      }

      // Threading: a reply must point at a comment on the SAME photo, same company.
      if (parentId) {
        const { data: parent, error: pErr } = await supabaseAdmin
          .from("photo_comments")
          .select("id, company_id, media_asset_id")
          .eq("id", parentId)
          .maybeSingle()
        if (pErr) throw pErr
        if (
          !parent ||
          parent.company_id !== userRecord.company_id ||
          parent.media_asset_id !== mediaAssetId
        ) {
          return errorResponse(requestId, 400, "INVALID_PAYLOAD", "Invalid parent comment")
        }
      }

      // Validate parsed @mention uuids against same-company active users; drop
      // any that don't resolve (defense-in-depth — no foreign-user leak).
      const candidateIds = parseMentionUuids(commentBody)
      let validMentionIds: string[] = []
      if (candidateIds.length > 0) {
        const { data: users, error: uErr } = await supabaseAdmin
          .from("users")
          .select("id")
          .in("id", candidateIds)
          .eq("company_id", userRecord.company_id)
          .eq("is_active", true)
        if (uErr) throw uErr
        validMentionIds = (users || []).map((u) => u.id as string)
      }

      const commentId = crypto.randomUUID()
      const { error: insertErr } = await supabaseAdmin
        .from("photo_comments")
        .insert({
          id: commentId,
          company_id: userRecord.company_id,
          media_asset_id: mediaAssetId,
          parent_id: parentId,
          author_id: userRecord.id,
          body: commentBody,
        })
      if (insertErr) throw insertErr

      if (validMentionIds.length > 0) {
        const mentionRows = validMentionIds.map((uid) => ({
          comment_id: commentId,
          mentioned_user_id: uid,
          company_id: userRecord.company_id,
        }))
        const { error: mErr } = await supabaseAdmin
          .from("photo_comment_mentions")
          .insert(mentionRows)
        if (mErr) throw mErr

        // Fan out one alert per mentioned user, excluding self. Dedupe on
        // (user_id, source_event_uuid=commentId) so re-running mention parsing
        // on an edit never spams duplicates.
        const recipients = validMentionIds.filter((uid) => uid !== userRecord.id)
        if (recipients.length > 0) {
          const { data: existingAlerts } = await supabaseAdmin
            .from("alert_events")
            .select("user_id")
            .eq("source_event_uuid", commentId)
            .eq("alert_type", "photo_mention")
          const alreadyAlerted = new Set((existingAlerts || []).map((a) => a.user_id as string))
          const authorName = (userRecord.full_name as string) || "Someone"
          const nowIso = new Date().toISOString()
          const alertRows = recipients
            .filter((uid) => !alreadyAlerted.has(uid))
            .map((uid) => ({
              id: crypto.randomUUID(),
              company_id: userRecord.company_id,
              job_id: asset.job_id ?? null,
              user_id: uid,
              alert_type: "photo_mention",
              severity: "low",
              status: "open",
              message: `${authorName} mentioned you on a photo`,
              triggered_at: nowIso,
              source_event_uuid: commentId,
              metadata: { media_asset_id: mediaAssetId, comment_id: commentId, author_id: userRecord.id },
            }))
          if (alertRows.length > 0) {
            const { error: aErr } = await supabaseAdmin.from("alert_events").insert(alertRows)
            // Alert failure is non-fatal — the comment + mentions already persisted.
            if (aErr) console.error(`[${ENDPOINT}] alert insert failed:`, aErr.message)
          }
        }
      }

      logRequestResult(ENDPOINT, requestId, 201, { op: "create", mentions: validMentionIds.length })
      return jsonResponse(
        { status: "success", comment_id: commentId, mentioned: validMentionIds, request_id: requestId },
        201,
        requestId,
      )
    }

    return errorResponse(requestId, 405, "METHOD_NOT_ALLOWED", "Method not allowed")
  } catch (error) {
    logRequestError(ENDPOINT, requestId, error)
    return errorResponse(requestId, 500, "INTERNAL_ERROR", (error as Error).message || "Internal error")
  }
})
