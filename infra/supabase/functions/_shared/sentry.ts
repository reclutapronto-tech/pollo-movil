// Sentry for Supabase Edge Functions.
//
// Wired through logRequestError()/logRequestResult() in _shared/api.ts, so
// every function that uses the shared error helpers reports automatically —
// no per-function code. Uses the "fieldops-edge" DSN key on the shared
// bbr-technology Sentry project (DSNs are publishable; SENTRY_DSN env, set
// as a function secret, wins when present so it can be rotated without a
// redeploy).
//
// Design constraints:
//  - Lazy dynamic import: keeps cold-start cost off the happy path; the SDK
//    only loads the first time an error is captured in an isolate.
//  - Never throws: observability must not break a request.
//  - EdgeRuntime.waitUntil() when available so flushing outlives the
//    response without delaying it; falls back to awaiting a bounded flush.

const EDGE_DSN =
  "https://5eda5d1210e17a578bea900bb669fd69@o4511242297540608.ingest.us.sentry.io/4511242378018816"

// deno-lint-ignore no-explicit-any
type SentryModule = any

let sentryPromise: Promise<SentryModule | null> | null = null

function loadSentry(): Promise<SentryModule | null> {
  if (!sentryPromise) {
    sentryPromise = (async () => {
      try {
        const Sentry: SentryModule = await import("npm:@sentry/deno@8")
        Sentry.init({
          dsn: Deno.env.get("SENTRY_DSN") || EDGE_DSN,
          environment: Deno.env.get("SENTRY_ENVIRONMENT") || "production",
          // Edge functions are short-lived; default integrations that poll
          // or hook process lifetime are unnecessary weight.
          defaultIntegrations: false,
          initialScope: { tags: { app: "edge" } },
        })
        return Sentry
      } catch (loadErr) {
        console.error("[sentry] SDK load failed, continuing without:", loadErr)
        return null
      }
    })()
  }
  return sentryPromise
}

interface EdgeErrorContext {
  endpoint: string
  requestId: string
  status?: number
  metadata?: Record<string, unknown>
}

/** Fire-and-forget capture. Safe to call from any error path. */
export function captureEdgeError(error: unknown, ctx: EdgeErrorContext): void {
  const work = (async () => {
    try {
      const Sentry = await loadSentry()
      if (!Sentry) return
      Sentry.withScope((scope: SentryModule) => {
        scope.setTag("endpoint", ctx.endpoint)
        if (ctx.status) scope.setTag("status", String(ctx.status))
        scope.setContext("request", {
          request_id: ctx.requestId,
          ...ctx.metadata,
        })
        const err =
          error instanceof Error
            ? error
            : new Error(typeof error === "string" ? error : JSON.stringify(error))
        Sentry.captureException(err)
      })
      await Sentry.flush(2000)
    } catch (captureErr) {
      console.error("[sentry] capture failed:", captureErr)
    }
  })()

  // Keep the isolate alive until the event is flushed, without adding
  // latency to the response. EdgeRuntime exists on Supabase; guard for
  // local `deno test` runs.
  // deno-lint-ignore no-explicit-any
  const runtime = (globalThis as any).EdgeRuntime
  if (runtime && typeof runtime.waitUntil === "function") {
    runtime.waitUntil(work)
  }
}
