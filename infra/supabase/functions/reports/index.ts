import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.4"
import { PDFDocument, StandardFonts, rgb } from "https://esm.sh/pdf-lib@1.17.1"
import {
  applyRateLimit,
  CORS_HEADERS,
  corsHeaders,
  errorResponse,
  jsonResponse,
  logRequestStart,
  logRequestResult,
  logRequestError,
  makeRequestId,
} from "../_shared/api.ts"
import { isSupervisorOrAbove } from "../_shared/roles.ts"

const ENDPOINT = "reports"

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders(req) })
  }

  const requestId = makeRequestId(req)

  try {
    if (req.method !== "POST") {
      return errorResponse(requestId, 405, "METHOD_NOT_ALLOWED", "Use POST for /reports")
    }

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
      .select("id, company_id, role, is_active, full_name")
      .eq("id", user.id)
      .single()

    if (!userRecord?.is_active) {
      return errorResponse(requestId, 403, "FORBIDDEN", "User is inactive")
    }

    // Only supervisors/admins/owners can generate reports
    if (!isSupervisorOrAbove(userRecord.role)) {
      return errorResponse(requestId, 403, "FORBIDDEN", "Only supervisors, admins, or owners can generate reports")
    }

    logRequestStart(ENDPOINT, requestId, req)

    // Rate limit: 10 requests per 60 seconds per user
    const rateLimit = await applyRateLimit(supabaseAdmin, user.id, ENDPOINT, requestId, 10, 60)
    if (rateLimit.limited) {
      logRequestResult(ENDPOINT, requestId, 429, { reason: "rate_limited" })
      return errorResponse(requestId, 429, "RATE_LIMITED", "Too many report requests. Try again shortly.", [], rateLimit.headers)
    }

    const payload = await req.json()
    const { report_type, job_id, date_from, date_to } = payload

    if (!report_type) {
      return errorResponse(requestId, 400, "INVALID_PAYLOAD", "report_type is required (job_report or timesheet)")
    }

    // ──────────────────────────────────────────
    // JOB REPORT — Full job summary with timeline
    // ──────────────────────────────────────────
    if (report_type === "job_report") {
      if (!job_id) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "job_id is required for job_report")
      }

      // Fetch job
      const { data: job } = await supabaseAdmin
        .from("jobs")
        .select("id, name, code, status, site_name, geofence_radius_m, created_at")
        .eq("id", job_id)
        .eq("company_id", userRecord.company_id)
        .single()

      if (!job) {
        return errorResponse(requestId, 404, "NOT_FOUND", "Job not found")
      }

      // Fetch all supplementary data in parallel (no dependencies between queries)
      const [
        { data: clockEvents },
        { data: tasks },
        { data: photoEvents },
        { data: otApprovals },
      ] = await Promise.all([
        supabaseAdmin
          .from("clock_events")
          .select("id, user_id, event_subtype, occurred_at, gps_lat, gps_lng, users!clock_events_user_id_fkey(full_name)")
          .eq("job_id", job_id)
          .eq("company_id", userRecord.company_id)
          .order("occurred_at", { ascending: true })
          .limit(500),
        supabaseAdmin
          .from("tasks")
          .select("id, name, status, requires_photo, completed_at, completed_by")
          .eq("job_id", job_id)
          .eq("company_id", userRecord.company_id)
          .order("sort_order", { ascending: true }),
        supabaseAdmin
          .from("photo_events")
          .select("id, occurred_at, media_asset_id, user_id, is_checkpoint")
          .eq("job_id", job_id)
          .eq("company_id", userRecord.company_id)
          .order("occurred_at", { ascending: true })
          .limit(200),
        supabaseAdmin
          .from("ot_approval_events")
          .select("id, worker_id, decision, reason, occurred_at, users!ot_approval_events_approver_id_fkey(full_name)")
          .eq("job_id", job_id)
          .eq("company_id", userRecord.company_id)
          .order("occurred_at", { ascending: true }),
      ])

      // Compute worker hours
      const workerHours = computeWorkerHours(clockEvents || [])

      // Fetch media verification codes for photos
      const mediaIds = (photoEvents || []).map((pe: any) => pe.media_asset_id).filter(Boolean)
      let mediaAssets: any[] = []
      if (mediaIds.length > 0) {
        const { data } = await supabaseAdmin
          .from("media_assets")
          .select("id, verification_code, sha256_hash")
          .in("id", mediaIds)
        mediaAssets = data || []
      }

      const report = {
        report_type: "job_report",
        generated_at: new Date().toISOString(),
        generated_by: userRecord.full_name,
        job: {
          name: job.name,
          code: job.code,
          status: job.status,
          site_name: job.site_name,
        },
        summary: {
          total_clock_events: (clockEvents || []).length,
          total_photos: (photoEvents || []).length,
          total_tasks: (tasks || []).length,
          completed_tasks: (tasks || []).filter((t: any) => t.status === "completed").length,
          total_ot_decisions: (otApprovals || []).length,
        },
        worker_hours: workerHours,
        tasks: (tasks || []).map((t: any) => ({
          name: t.name,
          status: t.status,
          requires_photo: t.requires_photo,
          completed_at: t.completed_at,
        })),
        photos: (photoEvents || []).map((pe: any) => {
          const asset = mediaAssets.find((a: any) => a.id === pe.media_asset_id)
          return {
            occurred_at: pe.occurred_at,
            verification_code: asset?.verification_code || null,
            is_checkpoint: pe.is_checkpoint,
          }
        }),
        ot_decisions: (otApprovals || []).map((ot: any) => ({
          decision: ot.decision,
          reason: ot.reason,
          occurred_at: ot.occurred_at,
          approver: ot.users?.full_name || "Unknown",
        })),
        clock_events: (clockEvents || []).map((ce: any) => ({
          worker: ce.users?.full_name || "Unknown",
          subtype: ce.event_subtype,
          occurred_at: ce.occurred_at,
          gps: ce.gps_lat && ce.gps_lng ? `${ce.gps_lat.toFixed(4)}, ${ce.gps_lng.toFixed(4)}` : null,
        })),
      }

      // Store as export artifact
      const artifactId = crypto.randomUUID()
      await supabaseAdmin.from("export_artifacts").insert({
        id: artifactId,
        company_id: userRecord.company_id,
        job_id,
        generated_by: user.id,
        export_kind: "job_report_pdf",
        status: "completed",
        generated_at: new Date().toISOString(),
        metadata: { report_data: report },
      })

      return jsonResponse({
        status: "success",
        artifact_id: artifactId,
        report,
        request_id: requestId,
      }, 200, requestId)
    }

    // ──────────────────────────────────────────
    // TIMESHEET — CSV-ready worker hours export
    // ──────────────────────────────────────────
    if (report_type === "timesheet") {
      const from = date_from || new Date(Date.now() - 7 * 86400000).toISOString().split("T")[0]
      const to = date_to || new Date().toISOString().split("T")[0]

      // Fetch all clock events in date range for this company
      const { data: clockEvents } = await supabaseAdmin
        .from("clock_events")
        .select("id, user_id, job_id, event_subtype, occurred_at, cost_code, users!clock_events_user_id_fkey(full_name), jobs!clock_events_job_id_fkey(code)")
        .eq("company_id", userRecord.company_id)
        .gte("occurred_at", `${from}T00:00:00Z`)
        .lte("occurred_at", `${to}T23:59:59Z`)
        .order("occurred_at", { ascending: true })
        .limit(2000)

      if (job_id) {
        // Filter client-side since we already have the data
      }

      // Build timesheet rows
      const rows = buildTimesheetRows(clockEvents || [], job_id)

      // Generate CSV. Escape each cell: double embedded quotes, and prefix a
      // leading =,+,-,@ (or control char) with a single quote to neutralise CSV
      // formula injection — these reports go to insurers/clients who open them
      // in Excel/Sheets.
      const csvCell = (v: unknown): string => {
        let s = String(v ?? "")
        if (/^[=+\-@\t\r]/.test(s)) s = `'${s}`
        return `"${s.replace(/"/g, '""')}"`
      }
      const csvHeader = "Worker,Date,Job Code,Cost Code,Clock In,Clock Out,Regular Hours,OT Hours,Total Hours"
      const csvRows = rows.map((r: any) =>
        [r.worker, r.date, r.job_code, r.cost_code || "", r.clock_in, r.clock_out, r.regular_hours, r.ot_hours, r.total_hours]
          .map(csvCell).join(",")
      )
      const csv = [csvHeader, ...csvRows].join("\n")

      // Store artifact
      const artifactId = crypto.randomUUID()
      await supabaseAdmin.from("export_artifacts").insert({
        id: artifactId,
        company_id: userRecord.company_id,
        job_id: job_id || null,
        generated_by: user.id,
        export_kind: "timesheet_csv",
        status: "completed",
        generated_at: new Date().toISOString(),
        metadata: { date_from: from, date_to: to, row_count: rows.length },
      })

      return jsonResponse({
        status: "success",
        artifact_id: artifactId,
        date_from: from,
        date_to: to,
        row_count: rows.length,
        csv,
        rows,
        request_id: requestId,
      }, 200, requestId)
    }

    // ──────────────────────────────────────────
    // PHOTO REPORT — PDF with cover, grid, appendix
    // ──────────────────────────────────────────
    if (
      report_type === "photo_insurance_claim"
      || report_type === "photo_daily_log"
      || report_type === "photo_before_after"
    ) {
      const { gallery_id, media_asset_ids } = payload
      const mediaIds: string[] = Array.isArray(media_asset_ids)
        ? (media_asset_ids as unknown[]).filter((v): v is string => typeof v === "string")
        : []

      // Resolve photo set: either a saved gallery or an explicit id list.
      let resolvedIds = mediaIds
      let galleryName: string | null = null
      let resolvedJobId: string | null = job_id || null
      if (gallery_id && typeof gallery_id === "string") {
        const { data: gallery } = await supabaseAdmin
          .from("photo_galleries")
          .select("id, name, job_id, company_id")
          .eq("id", gallery_id)
          .eq("company_id", userRecord.company_id)
          .maybeSingle()
        if (!gallery) {
          return errorResponse(requestId, 404, "NOT_FOUND", "Gallery not found")
        }
        galleryName = gallery.name as string
        resolvedJobId = gallery.job_id as string
        const { data: items } = await supabaseAdmin
          .from("photo_gallery_items")
          .select("media_asset_id, position")
          .eq("gallery_id", gallery.id)
          .order("position", { ascending: true })
        resolvedIds = (items || []).map((i: any) => i.media_asset_id as string)
      }

      if (resolvedIds.length === 0) {
        return errorResponse(requestId, 400, "INVALID_PAYLOAD", "gallery_id or media_asset_ids required")
      }

      const { data: assets, error: assetsError } = await supabaseAdmin
        .from("media_assets")
        .select("id, bucket_name, storage_path, mime_type, sha256_hash, verification_code, captured_at, gps_lat, gps_lng, company_id")
        .in("id", resolvedIds)
      if (assetsError) throw assetsError
      const tenantAssets = (assets || []).filter((a) => a.company_id === userRecord.company_id)
      if (tenantAssets.length === 0) {
        return errorResponse(requestId, 403, "FORBIDDEN", "No accessible photos")
      }
      // Preserve the caller's ordering.
      const order = new Map(resolvedIds.map((id, i) => [id, i]))
      tenantAssets.sort((a, b) => (order.get(a.id) ?? 0) - (order.get(b.id) ?? 0))

      // Fetch job + company for cover page.
      const [jobRow, companyRow] = await Promise.all([
        resolvedJobId
          ? supabaseAdmin.from("jobs").select("id, name, code, address_line_1, address_line_2").eq("id", resolvedJobId).maybeSingle()
          : Promise.resolve({ data: null } as any),
        supabaseAdmin.from("companies").select("name, logo_data_uri").eq("id", userRecord.company_id).maybeSingle(),
      ])

      const titleByType: Record<string, string> = {
        photo_insurance_claim: "Insurance Claim Photo Packet",
        photo_daily_log: "Daily Photo Log",
        photo_before_after: "Before / After Photo Report",
      }
      const reportTitle = titleByType[report_type]

      // Build PDF.
      const pdf = await PDFDocument.create()
      const font = await pdf.embedFont(StandardFonts.Helvetica)
      const fontBold = await pdf.embedFont(StandardFonts.HelveticaBold)

      // ── Cover page ─────────────────────────────
      const cover = pdf.addPage([612, 792]) // US Letter
      cover.drawText(reportTitle, { x: 54, y: 720, size: 22, font: fontBold, color: rgb(0.08, 0.17, 0.24) })
      cover.drawText((companyRow as any)?.data?.name || "", { x: 54, y: 695, size: 14, font, color: rgb(0.3, 0.3, 0.3) })
      if ((jobRow as any)?.data) {
        const j = (jobRow as any).data
        cover.drawText(`Project: ${j.name || j.code || ""}`, { x: 54, y: 660, size: 12, font })
        const address = [j.address_line_1, j.address_line_2].filter(Boolean).join(", ")
        if (address) cover.drawText(`Address: ${address}`, { x: 54, y: 642, size: 12, font })
      }
      if (galleryName) {
        cover.drawText(`Gallery: ${galleryName}`, { x: 54, y: 620, size: 12, font })
      }
      cover.drawText(`Generated: ${new Date().toISOString().slice(0, 16).replace("T", " ")} UTC`, { x: 54, y: 600, size: 11, font })
      cover.drawText(`Prepared by: ${userRecord.full_name || ""}`, { x: 54, y: 584, size: 11, font })
      cover.drawText(`Photos included: ${tenantAssets.length}`, { x: 54, y: 568, size: 11, font })
      cover.drawText("Every photo in this packet is chain-of-custody verified via SHA-256 hash and a unique verification code (see appendix).", {
        x: 54, y: 520, size: 10, font, color: rgb(0.4, 0.4, 0.4), maxWidth: 504, lineHeight: 13,
      })

      // Embed tenant logo on the cover if we have one (data URI only — simple path).
      const logoDataUri = (companyRow as any)?.data?.logo_data_uri as string | undefined
      if (logoDataUri && logoDataUri.startsWith("data:image/")) {
        try {
          const match = logoDataUri.match(/^data:image\/(png|jpe?g);base64,(.+)$/i)
          if (match) {
            const [, fmt, b64] = match
            const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0))
            const img = fmt.toLowerCase() === "png" ? await pdf.embedPng(bytes) : await pdf.embedJpg(bytes)
            const { width, height } = img.scaleToFit(140, 60)
            cover.drawImage(img, { x: 612 - 54 - width, y: 720, width, height })
          }
        } catch (_) {
          // Logo failure must never block the report.
        }
      }

      // ── Photo grid (3x4 per page) ──────────────
      const perPage = 12
      const cols = 3
      const margin = 36
      const gap = 10
      const cellW = (612 - margin * 2 - gap * (cols - 1)) / cols
      const cellH = 180
      const captionH = 26

      for (let i = 0; i < tenantAssets.length; i += perPage) {
        const page = pdf.addPage([612, 792])
        page.drawText(`${reportTitle} — Page ${Math.floor(i / perPage) + 1}`, {
          x: margin, y: 792 - margin, size: 10, font, color: rgb(0.45, 0.45, 0.45),
        })
        const slice = tenantAssets.slice(i, i + perPage)
        for (let j = 0; j < slice.length; j++) {
          const col = j % cols
          const row = Math.floor(j / cols)
          const x = margin + col * (cellW + gap)
          const y = 792 - margin - 20 - (row + 1) * cellH - row * gap

          const asset = slice[j]
          try {
            const { data: blob } = await (supabaseAdmin as any).storage
              .from(asset.bucket_name)
              .download(asset.storage_path)
            if (blob) {
              const bytes = new Uint8Array(await (blob as Blob).arrayBuffer())
              const mime = (asset.mime_type || "image/jpeg").toLowerCase()
              const img = mime.includes("png")
                ? await pdf.embedPng(bytes)
                : await pdf.embedJpg(bytes)
              const fit = img.scaleToFit(cellW, cellH - captionH)
              page.drawImage(img, { x: x + (cellW - fit.width) / 2, y: y + captionH, width: fit.width, height: fit.height })
            }
          } catch (_) {
            page.drawRectangle({ x, y: y + captionH, width: cellW, height: cellH - captionH, color: rgb(0.9, 0.9, 0.9) })
            page.drawText("image unavailable", { x: x + 8, y: y + captionH + 6, size: 8, font, color: rgb(0.5, 0.5, 0.5) })
          }
          const caption = asset.captured_at
            ? new Date(asset.captured_at).toISOString().replace("T", " ").slice(0, 16)
            : "—"
          page.drawText(`#${asset.verification_code || "—"}`, { x, y: y + 12, size: 8, font: fontBold, color: rgb(0.15, 0.2, 0.3) })
          page.drawText(caption, { x, y: y, size: 8, font, color: rgb(0.3, 0.3, 0.3) })
        }
      }

      // ── Appendix (verification codes + hashes) ─
      const appendix = pdf.addPage([612, 792])
      appendix.drawText("Verification Appendix", { x: margin, y: 720, size: 18, font: fontBold })
      appendix.drawText("Each photo's SHA-256 hash and verification code are listed below for chain-of-custody audit.", {
        x: margin, y: 700, size: 9, font, color: rgb(0.4, 0.4, 0.4), maxWidth: 540, lineHeight: 12,
      })
      let ay = 672
      for (const asset of tenantAssets) {
        if (ay < 54) {
          const next = pdf.addPage([612, 792])
          ay = 760
          next.drawText("Verification Appendix (cont.)", { x: margin, y: 780, size: 11, font: fontBold })
        }
        const captured = asset.captured_at
          ? new Date(asset.captured_at).toISOString().replace("T", " ").slice(0, 19) + " UTC"
          : "time unknown"
        const gps = asset.gps_lat && asset.gps_lng
          ? `${(asset.gps_lat as number).toFixed(5)}, ${(asset.gps_lng as number).toFixed(5)}`
          : "no GPS"
        appendix.drawText(`#${asset.verification_code || "—"}   ${captured}   ${gps}`, {
          x: margin, y: ay, size: 9, font: fontBold, color: rgb(0.1, 0.15, 0.25),
        })
        appendix.drawText(`sha256 ${asset.sha256_hash || "—"}`, {
          x: margin, y: ay - 11, size: 7.5, font, color: rgb(0.4, 0.4, 0.4),
        })
        ay -= 26
      }

      const pdfBytes = await pdf.save()

      // Upload to the `reports` bucket under the tenant's folder.
      const pdfId = crypto.randomUUID()
      const storagePath = `${userRecord.company_id}/${new Date().toISOString().slice(0, 10)}/${pdfId}.pdf`
      const { error: uploadError } = await (supabaseAdmin as any).storage
        .from("reports")
        .upload(storagePath, pdfBytes, { contentType: "application/pdf", upsert: false })
      if (uploadError) throw uploadError

      // Register as a media_asset for auditability + reuse from the UI.
      const { data: mediaAsset, error: mediaError } = await supabaseAdmin
        .from("media_assets")
        .insert({
          id: pdfId,
          company_id: userRecord.company_id,
          job_id: resolvedJobId,
          uploaded_by: userRecord.id,
          kind: "report_pdf",
          bucket_name: "reports",
          storage_path: storagePath,
          mime_type: "application/pdf",
          file_size_bytes: pdfBytes.length,
          // `processed` is the terminal state for server-side generated artifacts.
          sync_status: "processed",
          metadata: { report_type, photo_count: tenantAssets.length, gallery_id: gallery_id || null },
        })
        .select("id")
        .single()
      if (mediaError) throw mediaError

      const { data: signed } = await (supabaseAdmin as any).storage
        .from("reports")
        .createSignedUrl(storagePath, 3600)

      await supabaseAdmin.from("export_artifacts").insert({
        id: crypto.randomUUID(),
        company_id: userRecord.company_id,
        job_id: resolvedJobId,
        generated_by: user.id,
        export_kind: report_type,
        status: "completed",
        generated_at: new Date().toISOString(),
        metadata: { media_asset_id: mediaAsset.id, photo_count: tenantAssets.length },
      })

      logRequestResult(ENDPOINT, requestId, 200, { op: "photo_report", type: report_type, photos: tenantAssets.length })
      return jsonResponse({
        status: "success",
        media_asset_id: mediaAsset.id,
        signed_url: signed?.signedUrl || null,
        photo_count: tenantAssets.length,
        request_id: requestId,
      }, 200, requestId)
    }

    return errorResponse(requestId, 400, "INVALID_PAYLOAD", "report_type must be 'job_report', 'timesheet', or one of: photo_insurance_claim, photo_daily_log, photo_before_after")
  } catch (error) {
    console.error("reports error:", error)
    return errorResponse(requestId, 500, "INTERNAL_ERROR", error.message || "Internal server error")
  }
})

// ─── Helper: compute worker hours from clock events ──────────
function computeWorkerHours(events: any[]) {
  const sessions: Record<string, { worker: string; clock_in: string; clock_out: string | null }[]> = {}

  for (const event of events) {
    const workerId = event.user_id
    const workerName = event.users?.full_name || "Unknown"

    if (!sessions[workerId]) sessions[workerId] = []

    if (event.event_subtype === "clock_in") {
      sessions[workerId].push({
        worker: workerName,
        clock_in: event.occurred_at,
        clock_out: null,
      })
    } else if (event.event_subtype === "clock_out") {
      // .findLast() is ES2023 — not available in all Deno versions.
      // Use .slice().reverse().find() for broad compatibility.
      const openSession = sessions[workerId].slice().reverse().find((s: any) => s.clock_out === null)
      if (openSession) {
        openSession.clock_out = event.occurred_at
      }
    }
  }

  const result: any[] = []
  for (const [, workerSessions] of Object.entries(sessions)) {
    let totalMinutes = 0
    for (const session of workerSessions) {
      if (session.clock_in && session.clock_out) {
        const diff = new Date(session.clock_out).getTime() - new Date(session.clock_in).getTime()
        totalMinutes += diff / 60000
      }
    }
    if (workerSessions.length > 0) {
      const regularMinutes = Math.min(totalMinutes, 480) // 8 hours
      const otMinutes = Math.max(totalMinutes - 480, 0)
      result.push({
        worker: workerSessions[0].worker,
        sessions: workerSessions.length,
        total_hours: +(totalMinutes / 60).toFixed(2),
        regular_hours: +(regularMinutes / 60).toFixed(2),
        ot_hours: +(otMinutes / 60).toFixed(2),
      })
    }
  }
  return result
}

// ─── Helper: build timesheet rows from clock events ──────────
function buildTimesheetRows(events: any[], filterJobId?: string) {
  // Pair clock_in with clock_out per worker per job
  const pairs: any[] = []
  const openSessions: Record<string, any> = {}

  for (const event of events) {
    if (filterJobId && event.job_id !== filterJobId) continue

    const key = `${event.user_id}_${event.job_id}`
    const workerName = event.users?.full_name || "Unknown"
    const jobCode = event.jobs?.code || "N/A"

    if (event.event_subtype === "clock_in") {
      openSessions[key] = {
        worker: workerName,
        job_code: jobCode,
        cost_code: event.cost_code || "",
        clock_in: event.occurred_at,
      }
    } else if (event.event_subtype === "clock_out" && openSessions[key]) {
      const session = openSessions[key]
      const inTime = new Date(session.clock_in)
      const outTime = new Date(event.occurred_at)
      const totalMinutes = (outTime.getTime() - inTime.getTime()) / 60000
      const regularMinutes = Math.min(totalMinutes, 480)
      const otMinutes = Math.max(totalMinutes - 480, 0)

      // Round to nearest 15 minutes
      const roundTo15 = (mins: number) => +(Math.round(mins / 15) * 15 / 60).toFixed(2)

      pairs.push({
        worker: session.worker,
        date: inTime.toISOString().split("T")[0],
        job_code: session.job_code,
        cost_code: session.cost_code || "",
        clock_in: inTime.toISOString(),
        clock_out: outTime.toISOString(),
        regular_hours: roundTo15(regularMinutes),
        ot_hours: roundTo15(otMinutes),
        total_hours: roundTo15(totalMinutes),
      })
      delete openSessions[key]
    }
  }

  return pairs
}
