"use client";

import { getSupabase } from "@/lib/supabase";
import { reportError } from "@/lib/observability";

type QueryValue = string | number | boolean | null | undefined;

function buildFunctionUrl(path: string, query?: Record<string, QueryValue>) {
  const baseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL || "";
  if (!baseUrl) {
    throw new Error("Missing NEXT_PUBLIC_SUPABASE_URL environment variable.");
  }

  const normalizedPath = path.replace(/^\/+/, "");
  const url = new URL(`functions/v1/${normalizedPath}`, baseUrl.endsWith("/") ? baseUrl : `${baseUrl}/`);

  if (query) {
    for (const [key, value] of Object.entries(query)) {
      if (value === null || value === undefined || value === "") continue;
      url.searchParams.set(key, String(value));
    }
  }

  return url.toString();
}

async function parseJsonSafely(response: Response) {
  const rawBody = await response.text();
  if (!rawBody) return null;

  try {
    return JSON.parse(rawBody) as unknown;
  } catch {
    return null;
  }
}

export async function callFunctionJson<T>(
  path: string,
  options: RequestInit & { query?: Record<string, QueryValue> } = {},
): Promise<T> {
  const { query, headers, ...init } = options;
  const supabase = getSupabase();
  const { data: sessionData } = await supabase.auth.getSession();
  const token = sessionData.session?.access_token;

  if (!token) {
    throw new Error("Missing session");
  }

  let response: Response;
  try {
    response = await fetch(buildFunctionUrl(path, query), {
      ...init,
      headers: {
        ...headers,
        Authorization: `Bearer ${token}`,
      },
    });
  } catch (networkErr) {
    // Central choke point: every edge-function call in the app flows through
    // here, so one capture covers them all. Callers still get the throw and
    // render their inline error UI as before.
    reportError(networkErr, {
      source: "callFunctionJson.network",
      extra: { fn: path, method: init.method ?? "GET" },
    });
    throw networkErr;
  }

  const payload = await parseJsonSafely(response);
  if (!response.ok) {
    const message =
      payload && typeof payload === "object" && "message" in payload && typeof payload.message === "string"
        ? payload.message
        : `Request failed for ${path}`;
    // 4xx auth/validation noise is worth seeing too, but only 5xx and 404
    // (missing function = deploy drift) page a human via alert rules.
    reportError(new Error(`[edge:${path}] ${response.status} ${message}`), {
      source: "callFunctionJson.response",
      extra: {
        fn: path,
        method: init.method ?? "GET",
        status: response.status,
        request_id:
          payload && typeof payload === "object" && "request_id" in payload
            ? (payload as { request_id?: string }).request_id
            : undefined,
      },
    });
    throw new Error(message);
  }

  return payload as T;
}
