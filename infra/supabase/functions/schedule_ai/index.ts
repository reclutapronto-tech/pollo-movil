import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.4";
import { corsHeaders } from "../_shared/api.ts";

interface AiRequest {
  workers: string[];
  jobs: string[];
  anchorDate: string;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders(req) });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing Authorization header" }), {
        status: 401,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey);

    const jwt = authHeader.replace("Bearer ", "");
    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Invalid auth token" }), {
        status: 401,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    // Resolve the caller's company from the DB (never trust the request body for
    // tenant scope). All shift queries below MUST be scoped to this company —
    // supabaseAdmin bypasses RLS, so this is the only tenant guard.
    const { data: userRecord, error: userError } = await supabaseAdmin
      .from("users")
      .select("id, company_id, is_active")
      .eq("id", user.id)
      .single();
    if (userError || !userRecord) {
      return new Response(JSON.stringify({ error: "User record not found" }), {
        status: 401,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }
    if (!userRecord.is_active) {
      return new Response(JSON.stringify({ error: "User is inactive" }), {
        status: 403,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    const body: AiRequest = await req.json();
    const { anchorDate, jobs } = body;

    if (!anchorDate || !jobs?.length) {
      return new Response(JSON.stringify({ error: "anchorDate and jobs are required" }), {
        status: 400,
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
      });
    }

    // Build 4-week lookback range
    const anchor = new Date(`${anchorDate}T12:00:00Z`);
    const lookbackEnd = new Date(anchor);
    lookbackEnd.setUTCDate(lookbackEnd.getUTCDate() - 1);
    const lookbackStart = new Date(lookbackEnd);
    lookbackStart.setUTCDate(lookbackStart.getUTCDate() - 27);

    // Fetch historical published shifts with worker names
    const { data: historicalShifts, error: histError } = await supabaseAdmin
      .from("schedule_shifts")
      // Disambiguate the embed: schedule_shifts has 3 FKs to users
      // (worker_id, created_by, published_by) — name the worker FK explicitly.
      .select("worker_id, job_id, start_time, end_time, users!schedule_shifts_worker_id_fkey!inner(id, full_name)")
      .eq("company_id", userRecord.company_id)
      .in("job_id", jobs)
      .gte("shift_date", lookbackStart.toISOString().slice(0, 10))
      .lte("shift_date", lookbackEnd.toISOString().slice(0, 10))
      .eq("status", "published");

    if (histError) throw histError;

    // Build frequency map: job_id → { worker_id: { count, full_name, start_time, end_time } }
    const freq: Record<string, Record<string, { count: number; full_name: string; start_time: string; end_time: string }>> = {};

    for (const shift of (historicalShifts ?? [])) {
      const workerRecord = Array.isArray(shift.users) ? shift.users[0] : shift.users;
      const workerName = (workerRecord as { full_name?: string } | null)?.full_name ?? "Unknown";
      if (!freq[shift.job_id]) freq[shift.job_id] = {};
      if (!freq[shift.job_id][shift.worker_id]) {
        freq[shift.job_id][shift.worker_id] = {
          count: 0,
          full_name: workerName,
          start_time: shift.start_time,
          end_time: shift.end_time,
        };
      }
      freq[shift.job_id][shift.worker_id].count += 1;
    }

    // For each job, pick top 3 workers by frequency
    const ghost_shifts = [];
    for (const jobId of jobs) {
      const jobWorkers = freq[jobId];
      if (!jobWorkers) continue;
      const sorted = Object.entries(jobWorkers)
        .sort(([, a], [, b]) => b.count - a.count)
        .slice(0, 3);

      for (const [workerId, info] of sorted) {
        ghost_shifts.push({
          id: `ghost-${crypto.randomUUID()}`,
          worker_id: workerId,
          worker_name: info.full_name,
          job_id: jobId,
          date: anchorDate,
          start_time: info.start_time,
          end_time: info.end_time,
          status: "ghost",
          notes: `[AI] Based on ${info.count} historical shift${info.count !== 1 ? "s" : ""} on this job.`,
        });
      }
    }

    return new Response(
      JSON.stringify({
        message: `AI recommendations based on ${(historicalShifts ?? []).length} historical shifts.`,
        ghost_shifts,
      }),
      {
        headers: { ...corsHeaders(req), "Content-Type": "application/json" },
        status: 200,
      },
    );
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : "Unknown error";
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...corsHeaders(req), "Content-Type": "application/json" },
    });
  }
});
