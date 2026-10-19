"use client";

import { Suspense, useCallback, useEffect, useMemo, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import {
  Clock,
  Camera,
  CheckCircle2,
  FileText,
  Timer,
  PencilLine,
  FileQuestion,
  type LucideIcon,
} from "lucide-react";
import { useI18n } from "@/lib/i18n";
import { getSupabase } from "@/lib/supabase";
import { useCurrentUser } from "@/lib/use-role";
import type { TimelineEvent } from "@/lib/types";

interface EventGlyph {
  Icon: LucideIcon;
  tint: string; // bg + text tailwind classes for the 40×40 avatar
}

const EVENT_GLYPHS: Record<string, EventGlyph> = {
  clock_event: {
    Icon: Clock,
    tint: "bg-slate-100 text-slate-700 dark:bg-slate-800 dark:text-slate-200",
  },
  photo_event: {
    Icon: Camera,
    tint: "bg-blue-50 text-blue-700 dark:bg-blue-950/40 dark:text-blue-300",
  },
  task_event: {
    Icon: CheckCircle2,
    tint: "bg-emerald-50 text-emerald-700 dark:bg-emerald-950/40 dark:text-emerald-300",
  },
  note_event: {
    Icon: FileText,
    tint: "bg-amber-50 text-amber-700 dark:bg-amber-950/40 dark:text-amber-300",
  },
  ot_approval_event: {
    Icon: Timer,
    tint: "bg-orange-50 text-orange-700 dark:bg-orange-950/40 dark:text-orange-300",
  },
  correction_event: {
    Icon: PencilLine,
    tint: "bg-rose-50 text-rose-700 dark:bg-rose-950/40 dark:text-rose-300",
  },
};

const FALLBACK_GLYPH: EventGlyph = {
  Icon: FileQuestion,
  tint: "bg-stone-100 dark:bg-slate-800 text-slate-500 dark:text-slate-400",
};

const TIMELINE_SOURCE_TABLES = [
  "clock_events",
  "photo_events",
  "task_events",
  "note_events",
  "ot_approval_events",
  "correction_events",
] as const;

// Matches public.job_status enum (foundation_tables.sql):
// draft | active | in_progress | review | completed | archived.
// Timeline shows everything except archived.
const TIMELINE_JOB_STATUSES = [
  "draft",
  "active",
  "in_progress",
  "review",
  "completed",
] as const;

interface JobOption {
  id: string;
  name: string;
  code: string;
  status: string;
}

export default function TimelinePage() {
  const { t } = useI18n();
  return (
    <Suspense
      fallback={
        <div className="flex items-center gap-2 text-slate-500 dark:text-slate-400">
          <div className="h-4 w-4 animate-spin rounded-full border-2 border-slate-300 border-t-amber-500" />
          {t("timeline.loading")}
        </div>
      }
    >
      <TimelineContent />
    </Suspense>
  );
}

function TimelineContent() {
  const { t } = useI18n();
  const router = useRouter();
  const searchParams = useSearchParams();
  const currentUser = useCurrentUser();

  // Accept both `?job=<id>` (new) and `?job_id=<id>` (legacy) for backwards compat.
  const jobId = searchParams.get("job") ?? searchParams.get("job_id");
  // `?worker=<id>` narrows events to one worker (used by map popups and the
  // command palette). Works with or without a job selected.
  const workerId = searchParams.get("worker");

  const [jobs, setJobs] = useState<JobOption[]>([]);
  const [jobsLoading, setJobsLoading] = useState(true);
  const [jobsError, setJobsError] = useState<string | null>(null);
  const [filterText, setFilterText] = useState("");

  // Load jobs list scoped to current company.
  useEffect(() => {
    if (currentUser.loading) return;
    if (!currentUser.companyId) {
      setJobsLoading(false);
      return;
    }

    let cancelled = false;
    (async () => {
      setJobsLoading(true);
      setJobsError(null);
      const { data, error } = await getSupabase()
        .from("jobs")
        .select("id, name, code, status")
        .eq("company_id", currentUser.companyId)
        .is("deleted_at", null)
        .in("status", TIMELINE_JOB_STATUSES as unknown as string[])
        .order("name", { ascending: true })
        .limit(200);

      if (cancelled) return;

      if (error) {
        setJobsError(error.message);
        setJobs([]);
      } else {
        setJobs((data ?? []) as JobOption[]);
      }
      setJobsLoading(false);
    })();

    return () => {
      cancelled = true;
    };
  }, [currentUser.loading, currentUser.companyId]);

  // Auto-pick if exactly one job and no URL selection.
  useEffect(() => {
    if (jobsLoading) return;
    if (jobId) return;
    if (jobs.length !== 1) return;
    router.replace(`/timeline?job=${jobs[0].id}`);
  }, [jobsLoading, jobs, jobId, router]);

  const handleJobChange = useCallback(
    (nextId: string) => {
      if (!nextId) {
        router.replace("/timeline");
      } else {
        router.replace(`/timeline?job=${nextId}`);
      }
    },
    [router],
  );

  const filteredJobs = useMemo(() => {
    const q = filterText.trim().toLowerCase();
    if (!q) return jobs;
    return jobs.filter(
      (j) =>
        j.name.toLowerCase().includes(q) || j.code.toLowerCase().includes(q),
    );
  }, [jobs, filterText]);

  const selectedJob = useMemo(
    () => jobs.find((j) => j.id === jobId) ?? null,
    [jobs, jobId],
  );

  // ---- Render states ---------------------------------------------------

  if (currentUser.loading) {
    return (
      <div className="flex items-center gap-2 text-slate-500 dark:text-slate-400">
        <div className="h-4 w-4 animate-spin rounded-full border-2 border-slate-300 border-t-amber-500" />
        {t("timeline.loading")}
      </div>
    );
  }

  return (
    <div>
      <div className="mb-6">
        <a
          href="/"
          className="mb-2 inline-flex items-center gap-1 text-sm font-medium text-slate-500 dark:text-slate-400 hover:text-slate-900 dark:hover:text-slate-100"
        >
          <span>&larr;</span> {t("common.backToDashboard")}
        </a>
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-slate-900 dark:text-slate-100">
            {selectedJob
              ? t("timeline.titleWithJob", { jobName: selectedJob.name })
              : t("timeline.title")}
          </h1>
          <p className="mt-1 text-slate-600 dark:text-slate-400">{t("timeline.subtitle")}</p>
        </div>

        {/* Job picker */}
        {currentUser.companyId && jobs.length > 0 && (
          <div className="mt-4 flex flex-wrap items-center gap-3">
            {jobs.length > 8 && (
              <div className="relative min-w-[200px] flex-1 max-w-xs">
                <svg
                  className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-500 dark:text-slate-400"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth={2}
                    d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"
                  />
                </svg>
                <input
                  type="text"
                  value={filterText}
                  onChange={(e) => setFilterText(e.target.value)}
                  placeholder="Filter jobs…"
                  className="w-full rounded-lg border border-stone-300 bg-card dark:border-slate-700 dark:bg-slate-900 py-2 pl-10 pr-3 text-sm text-slate-900 dark:text-slate-100 placeholder:text-slate-500 dark:text-slate-400 focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30"
                />
              </div>
            )}
            <select
              value={jobId ?? ""}
              onChange={(e) => handleJobChange(e.target.value)}
              className="min-w-[240px] rounded-lg border border-stone-300 bg-card dark:border-slate-700 dark:bg-slate-900 px-3 py-2 text-sm text-slate-700 dark:text-slate-400 focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30"
            >
              <option value="">Select a job to view its timeline</option>
              {filteredJobs.map((j) => (
                <option key={j.id} value={j.id}>
                  {j.name}
                  {j.code ? ` (${j.code})` : ""}
                </option>
              ))}
            </select>
          </div>
        )}
      </div>

      {jobsError && (
        <div className="mb-4 rounded-lg bg-red-50 p-3 text-sm text-red-700 dark:bg-red-950/30 dark:text-red-300 dark:border-red-900/50 dark:bg-red-950/30 dark:text-red-300">
          {jobsError}
        </div>
      )}

      {/* No company resolved */}
      {!currentUser.companyId && !currentUser.loading && (
        <div className="rounded-xl border border-stone-200 bg-card dark:border-slate-800 dark:bg-slate-900 p-8 text-center text-slate-500 dark:text-slate-400">
          {t("timeline.noJob")}
        </div>
      )}

      {/* Company with zero jobs */}
      {currentUser.companyId && !jobsLoading && jobs.length === 0 && (
        <div className="rounded-xl border border-stone-200 bg-card dark:border-slate-800 dark:bg-slate-900 p-8 text-center">
          <p className="text-slate-500 dark:text-slate-400">
            No jobs in this company yet — create one from the Projects tab.
          </p>
        </div>
      )}

      {/* Worker deep-link banner */}
      {workerId && (
        <div className="mb-4 flex items-center gap-2 rounded-lg border border-blue-200 bg-blue-50 px-3 py-2 text-sm text-blue-700 dark:border-blue-900 dark:bg-blue-950/30 dark:text-blue-300">
          Showing events for one worker only.
          <a href={jobId ? `/timeline?job=${jobId}` : "/timeline"} className="font-semibold underline">
            Clear
          </a>
        </div>
      )}

      {/* Jobs exist but none selected */}
      {currentUser.companyId && jobs.length > 0 && !jobId && !workerId && (
        <div className="rounded-xl border border-stone-200 bg-card dark:border-slate-800 dark:bg-slate-900 p-8 text-center">
          <p className="text-slate-500 dark:text-slate-400">
            Select a job above to view its timeline.
          </p>
          <a
            href="/"
            className="mt-4 inline-block text-sm font-medium text-slate-500 dark:text-slate-400 underline hover:text-slate-900 dark:hover:text-slate-100"
          >
            {t("timeline.goToDashboard")}
          </a>
        </div>
      )}

      {/* Events list — job, worker, or both */}
      {currentUser.companyId && (jobId || workerId) && (
        <TimelineEventsList jobId={jobId} workerId={workerId} />
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Events list (unchanged fetching logic, extracted for readability)
// ---------------------------------------------------------------------------

interface TimelineEventsListProps {
  jobId: string | null;
  workerId?: string | null;
}

function TimelineEventsList({ jobId, workerId }: TimelineEventsListProps) {
  const { t } = useI18n();
  const [events, setEvents] = useState<TimelineEvent[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const loadTimeline = useCallback(async () => {
    setLoading(true);
    setError(null);

    let query = getSupabase()
      .from("job_timeline")
      .select("*")
      .order("occurred_at", { ascending: false })
      .limit(100);
    if (jobId) query = query.eq("job_id", jobId);
    if (workerId) query = query.eq("user_id", workerId);
    const { data, error: err } = await query;

    if (err) {
      setError(err.message);
    } else {
      setEvents(data ?? []);
    }
    setLoading(false);
  }, [jobId, workerId]);

  useEffect(() => {
    loadTimeline();

    // Live updates are keyed on job_id; a worker-only view (no job selected)
    // has no server-side filter to subscribe on, so it stays request/response.
    if (!jobId) return;

    const supabase = getSupabase();
    let channel = supabase.channel(
      `timeline-job-${jobId}-${Math.random().toString(36).slice(2)}`,
    );

    for (const table of TIMELINE_SOURCE_TABLES) {
      channel = channel.on(
        "postgres_changes",
        {
          event: "INSERT",
          schema: "public",
          table,
          filter: `job_id=eq.${jobId}`,
        },
        () => loadTimeline(),
      );
    }

    channel.subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [jobId, loadTimeline]);

  function formatTime(iso: string) {
    return new Date(iso).toLocaleString(undefined, {
      month: "short",
      day: "numeric",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
    });
  }

  function renderPayload(event: TimelineEvent) {
    const p = event.payload;

    switch (event.event_type) {
      case "clock_event": {
        const subtype = (p.subtype as string) ?? "unknown";
        const gpsLat = p.gps_lat as number | null;
        const gpsLng = p.gps_lng as number | null;
        const label =
          subtype === "clock_in"
            ? t("timeline.clockedIn")
            : t("timeline.clockedOut");
        return (
          <div>
            <span
              className={`inline-block rounded-full px-2 py-0.5 text-xs font-semibold ${
                subtype === "clock_in"
                  ? "bg-green-100 text-green-700"
                  : "bg-red-100 text-red-700"
              }`}
            >
              {label}
            </span>
            {gpsLat != null && gpsLng != null && (
              <span className="ml-2 text-xs text-slate-500 dark:text-slate-400">
                {t("timeline.gps", {
                  lat: gpsLat.toFixed(4),
                  lng: gpsLng.toFixed(4),
                })}
              </span>
            )}
          </div>
        );
      }
      case "photo_event":
        return (
          <span className="text-sm text-slate-600 dark:text-slate-400">
            {t("timeline.photoCaptured")}
            {p.is_checkpoint ? t("timeline.checkpoint") : ""}
          </span>
        );
      case "task_event":
        return (
          <span className="text-sm text-slate-600 dark:text-slate-400">
            {String(p.from_status ?? "—")} → {String(p.to_status ?? "—")}
            {p.note ? `: ${String(p.note)}` : ""}
          </span>
        );
      default:
        return (
          <span className="text-xs text-slate-500 dark:text-slate-400">
            {JSON.stringify(p).substring(0, 120)}
          </span>
        );
    }
  }

  if (loading) {
    return (
      <div className="flex items-center gap-2 text-slate-500 dark:text-slate-400">
        <div className="h-4 w-4 animate-spin rounded-full border-2 border-slate-300 border-t-amber-500" />
        {t("timeline.loading")}
      </div>
    );
  }

  if (error) {
    return (
      <div className="rounded-xl border border-red-200 bg-red-50 p-4 text-sm text-red-700 dark:border-red-900/50 dark:bg-red-950/30 dark:text-red-300 dark:border-red-900/50 dark:bg-red-950/30 dark:text-red-300">
        {error}
      </div>
    );
  }

  if (events.length === 0) {
    return (
      <div className="rounded-xl border border-stone-200 bg-card dark:border-slate-800 dark:bg-slate-900 p-8 text-center text-slate-500 dark:text-slate-400">
        {t("common.noData")}
      </div>
    );
  }

  return (
    <div className="space-y-3">
      {events.map((event) => {
        const glyph = EVENT_GLYPHS[event.event_type] ?? FALLBACK_GLYPH;
        const Icon = glyph.Icon;
        return (
        <div
          key={event.id}
          className="flex gap-4 rounded-xl border border-stone-200 bg-card dark:border-slate-800 dark:bg-slate-900 p-4 shadow-sm"
        >
          <div
            className={`flex h-10 w-10 flex-shrink-0 items-center justify-center rounded-full ${glyph.tint}`}
            aria-hidden="true"
          >
            <Icon size={18} strokeWidth={2} />
          </div>
          <div className="min-w-0 flex-1">
            <div className="flex items-center gap-2">
              <span className="text-sm font-semibold text-slate-900 dark:text-slate-100">
                {{
                  clock_event: t("timeline.clockEvent"),
                  photo_event: t("timeline.photoEvent"),
                  task_event: t("timeline.taskEvent"),
                  note_event: t("timeline.noteEvent"),
                  ot_approval_event: t("timeline.otApprovalEvent"),
                  correction_event: t("timeline.correctionEvent"),
                }[event.event_type] ?? event.event_type}
              </span>
              <span className="text-xs text-slate-500 dark:text-slate-400">
                {formatTime(event.occurred_at)}
              </span>
            </div>
            <div className="mt-1">{renderPayload(event)}</div>
          </div>
        </div>
        );
      })}
    </div>
  );
}
