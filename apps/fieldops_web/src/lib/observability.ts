import * as Sentry from "@sentry/nextjs";

/** Error reporting is opt-in and must point to the Pollo Móvil deployment. */
export const SENTRY_DSN = process.env.NEXT_PUBLIC_SENTRY_DSN || "";

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
