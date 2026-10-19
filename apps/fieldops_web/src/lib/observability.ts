import * as Sentry from "@sentry/nextjs";

/**
 * Sentry DSN for the web app ("fieldops-web" key on the shared
 * bbr-technology/fieldops-mobile project). DSNs are publishable
 * identifiers — safe to commit. NEXT_PUBLIC_SENTRY_DSN still wins when set
 * so staging/self-hosted can point elsewhere without a code change.
 */
export const SENTRY_DSN =
  process.env.NEXT_PUBLIC_SENTRY_DSN ||
  "https://ecd82d398110ddd62deec395a3a50147@o4511242297540608.ingest.us.sentry.io/4511242378018816";

interface ReportContext {
  /** Where it happened, e.g. "permits.loadJobs" or "workers.loadWorkers". */
  source: string;
  /** Any extra structured context (job_id, filter values, …). No PII. */
  extra?: Record<string, unknown>;
}

/**
 * Report a HANDLED error — one we caught and turned into inline UI state.
 *
 * Pages in this app almost never crash; they catch, `setError(message)`,
 * and render the message. That's good UX and total observability blindness:
 * the user sees "column jobs.permit_required does not exist" and Sentry sees
 * nothing. Call this in every catch / `res.error` branch so handled errors
 * still reach Sentry, tagged `handled:yes` so they're distinguishable from
 * crashes.
 */
export function reportError(error: unknown, ctx: ReportContext): void {
  try {
    const err =
      error instanceof Error
        ? error
        : new Error(
            typeof error === "string" ? error : JSON.stringify(error),
          );
    Sentry.withScope((scope) => {
      scope.setTag("handled", "yes");
      scope.setTag("source", ctx.source);
      if (ctx.extra) scope.setContext("details", ctx.extra);
      Sentry.captureException(err);
    });
  } catch {
    // Observability must never break the page.
  }
}

/**
 * Convenience for PostgREST results: call with `res.error` and it no-ops on
 * null, so `reportSupabaseError(res.error, {...})` can sit right above the
 * existing `if (res.error)` UI handling.
 */
export function reportSupabaseError(
  error: { message: string; code?: string; details?: string | null } | null,
  ctx: ReportContext,
): void {
  if (!error) return;
  reportError(new Error(`[supabase] ${error.message}`), {
    ...ctx,
    extra: { ...ctx.extra, pg_code: error.code, pg_details: error.details },
  });
}
