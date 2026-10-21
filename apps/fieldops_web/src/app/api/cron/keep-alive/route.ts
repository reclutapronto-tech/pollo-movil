const REQUEST_TIMEOUT_MS = 10_000;

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

export async function GET(request: Request): Promise<Response> {
  const cronSecret = process.env.CRON_SECRET;
  if (!cronSecret) {
    console.error("keep-alive cron is not configured: CRON_SECRET is missing");
    return Response.json({ error: "Cron job is not configured" }, { status: 500 });
  }

  if (request.headers.get("authorization") !== `Bearer ${cronSecret}`) {
    return Response.json({ error: "Unauthorized" }, { status: 401 });
  }

  const backendUrl = process.env.RENDER_BACKEND_URL;
  if (!backendUrl) {
    console.error("keep-alive cron is not configured: RENDER_BACKEND_URL is missing");
    return Response.json({ error: "Backend URL is not configured" }, { status: 500 });
  }

  let target: URL;
  try {
    target = new URL(backendUrl);
    if (target.protocol !== "https:" || target.username || target.password) {
      return Response.json({ error: "RENDER_BACKEND_URL must be a credential-free HTTPS URL" }, { status: 500 });
    }
  } catch {
    return Response.json({ error: "RENDER_BACKEND_URL must be a valid HTTPS URL" }, { status: 500 });
  }

  try {
    const upstream = await fetch(target, {
      method: "GET",
      cache: "no-store",
      redirect: "error",
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
      headers: { "user-agent": "pollo-movil-staging-keep-alive/1.0" },
    });

    if (!upstream.ok) {
      console.error("keep-alive backend returned a non-success status", { status: upstream.status });
      return Response.json({ error: "Backend health request failed", status: upstream.status }, { status: 502 });
    }

    return Response.json({ ok: true, backendStatus: upstream.status }, {
      headers: { "Cache-Control": "no-store" },
    });
  } catch (error) {
    const reason = error instanceof Error ? error.name : "UnknownError";
    console.error("keep-alive backend request failed", { reason });
    return Response.json({ error: "Backend health request failed", reason }, { status: 502 });
  }
}
