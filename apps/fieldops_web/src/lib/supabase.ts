import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { reportError } from "@/lib/observability";

let _client: SupabaseClient | null = null;

/**
 * Fetch wrapper: one central intercept for EVERY PostgREST / auth / storage
 * request the app makes. Failed responses (>=400) and network errors are
 * reported to Sentry with the endpoint path — pages keep their existing
 * inline `res.error` handling, but nothing fails silently anymore.
 *
 * Deliberately excluded from reporting:
 *  - /auth/v1/token 400s (wrong password — user error, not a bug)
 *  - request bodies and query strings (PII: filters can contain names)
 */
async function observedFetch(
  input: RequestInfo | URL,
  init?: RequestInit,
): Promise<Response> {
  const url = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
  const path = (() => {
    try {
      return new URL(url).pathname;
    } catch {
      return String(url);
    }
  })();

  let response: Response;
  try {
    response = await fetch(input, init);
  } catch (networkErr) {
    reportError(networkErr, {
      source: "supabase.network",
      extra: { path, method: init?.method ?? "GET" },
    });
    throw networkErr;
  }

  const isAuthTokenNoise =
    path.includes("/auth/v1/token") && response.status < 500;
  if (!response.ok && !isAuthTokenNoise) {
    // Read the error body from a clone so the caller's stream is untouched.
    let detail = "";
    try {
      detail = (await response.clone().text()).slice(0, 500);
    } catch {
      /* body already consumed or unreadable */
    }
    reportError(new Error(`[rest:${path}] ${response.status} ${detail}`), {
      source: "supabase.response",
      extra: { path, method: init?.method ?? "GET", status: response.status },
    });
  }
  return response;
}

export function getSupabase(): SupabaseClient {
  if (_client) return _client;

  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL || "";
  const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || "";

  if (!supabaseUrl || !supabaseAnonKey) {
    throw new Error(
      "Missing NEXT_PUBLIC_SUPABASE_URL or NEXT_PUBLIC_SUPABASE_ANON_KEY environment variables.",
    );
  }

  _client = createClient(supabaseUrl, supabaseAnonKey, {
    global: { fetch: observedFetch },
  });
  return _client;
}
