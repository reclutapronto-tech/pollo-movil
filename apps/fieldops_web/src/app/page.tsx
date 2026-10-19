"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import {
  Users,
  Settings,
  BarChart3,
  ShieldCheck,
  Clock,
  CalendarDays,
  CircleDot,
  FileText,
  CalendarOff,
  Receipt,
  CreditCard,
  HelpCircle,
} from "lucide-react";
import { useI18n } from "@/lib/i18n";
import { useCurrentUser } from "@/lib/use-role";
import { getSupabase } from "@/lib/supabase";
import { KpiCard } from "@/components/ui/kpi-card";
import { SkeletonCard } from "@/components/ui/skeleton";
import { DailyHuddle } from "@/components/daily-huddle";
import { ActiveWorkersTable } from "@/components/active-workers-table";
import {
  DashboardWelcome,
  dashboardWelcomeSeen,
  markDashboardWelcomeSeen,
} from "@/components/dashboard-welcome";
import type { JobSummary } from "@/lib/types";

interface DashboardStats {
  totalJobs: number;
  activeWorkers: number;
  photosToday: number;
  pendingOT: number;
}

interface ActiveWorker {
  id: string;
  full_name: string;
  status: "working" | "break";
  hours: number;
}

interface JobTaskCount {
  job_id: string;
  total: number;
  completed: number;
}

const QUICK_ACTIONS: Record<string, { label: string; href: string; icon: React.ElementType }[]> = {
  admin: [
    { label: "dashboard.manageStaff", href: "/settings/staff", icon: Users },
    { label: "dashboard.companySettings", href: "/settings", icon: Settings },
    { label: "dashboard.viewReports", href: "/reports", icon: BarChart3 },
    { label: "dashboard.alerts", href: "/alerts", icon: ShieldCheck },
  ],
  supervisor: [
    { label: "dashboard.approveOt", href: "/overtime", icon: Clock },
    { label: "dashboard.scheduleWorkers", href: "/schedule", icon: CalendarDays },
    { label: "dashboard.viewReports", href: "/reports", icon: BarChart3 },
    { label: "dashboard.approvePto", href: "/pto", icon: CalendarOff },
  ],
  worker: [
    { label: "dashboard.mySchedule", href: "/schedule", icon: CalendarDays },
    { label: "dashboard.submitExpense", href: "/expenses", icon: Receipt },
    { label: "dashboard.requestPto", href: "/pto", icon: FileText },
    { label: "dashboard.myTimecards", href: "/timecards", icon: CreditCard },
  ],
};
QUICK_ACTIONS.foreman = QUICK_ACTIONS.worker;

export default function DashboardPage() {
  const { t } = useI18n();
  const { role, companyId } = useCurrentUser();
  const JOBS_PAGE_SIZE = 20;

  const [jobs, setJobs] = useState<JobSummary[]>([]);
  const [stats, setStats] = useState<DashboardStats>({
    totalJobs: 0,
    activeWorkers: 0,
    photosToday: 0,
    pendingOT: 0,
  });
  const [activeWorkersList, setActiveWorkersList] = useState<ActiveWorker[]>([]);
  const [jobTasks, setJobTasks] = useState<JobTaskCount[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [hasMoreJobs, setHasMoreJobs] = useState(false);
  const [loadingMoreJobs, setLoadingMoreJobs] = useState(false);
  const [welcomeOpen, setWelcomeOpen] = useState(false);

  // Auto-open the first-run briefing once per device.
  useEffect(() => {
    if (!dashboardWelcomeSeen()) setWelcomeOpen(true);
  }, []);

  const closeWelcome = useCallback(() => {
    setWelcomeOpen(false);
    markDashboardWelcomeSeen();
  }, []);

  const openWelcome = useCallback(() => setWelcomeOpen(true), []);

  const aiHints = useMemo(() => {
    const hints: string[] = [];
    if (stats.pendingOT > 0)
      hints.push(t("dashboard.pendingOtHint", { count: stats.pendingOT }));
    const otWorkers = activeWorkersList.filter((w) => w.hours > 7);
    if (otWorkers.length > 0)
      hints.push(t("dashboard.otThresholdHint", { count: otWorkers.length }));
    if (stats.photosToday === 0 && stats.activeWorkers > 0)
      hints.push(t("dashboard.noPhotosHint"));
    return hints;
  }, [stats, activeWorkersList, t]);

  const loadDashboard = useCallback(async () => {
    setLoading(true);
    setError(null);

    try {
      const supabase = getSupabase();
      const { data, error: rpcError } = await supabase.rpc(
        "get_dashboard_overview",
        { p_job_limit: JOBS_PAGE_SIZE },
      );

      if (rpcError) throw rpcError;

      const payload = (data ?? {}) as {
        stats?: Partial<DashboardStats>;
        jobs?: JobSummary[];
        activeWorkers?: Array<{
          user_id: string;
          full_name: string | null;
          status: "working" | "break";
          first_clock_in_at: string | null;
        }>;
        jobTaskCounts?: JobTaskCount[];
      };

      const jobsList = payload.jobs ?? [];
      setJobs(jobsList);
      setHasMoreJobs(jobsList.length === JOBS_PAGE_SIZE);
      setStats({
        totalJobs: payload.stats?.totalJobs ?? 0,
        activeWorkers: payload.stats?.activeWorkers ?? 0,
        photosToday: payload.stats?.photosToday ?? 0,
        pendingOT: payload.stats?.pendingOT ?? 0,
      });

      const now = Date.now();
      setActiveWorkersList(
        (payload.activeWorkers ?? []).map((w) => {
          const hours = w.first_clock_in_at
            ? Math.round((now - new Date(w.first_clock_in_at).getTime()) / 360000) / 10
            : 0;
          return {
            id: w.user_id,
            full_name: w.full_name ?? "?",
            status: w.status,
            hours,
          };
        }),
      );

      setJobTasks(payload.jobTaskCounts ?? []);
    } catch (e) {
      setError(e instanceof Error ? e.message : t("dashboard.failedToLoad"));
    } finally {
      setLoading(false);
    }
  }, [t]);

  const loadMoreJobs = useCallback(async () => {
    setLoadingMoreJobs(true);
    try {
      const supabase = getSupabase();
      const { data, error: err } = await supabase
        .from("jobs")
        .select("id, name, code, status, site_name, geofence_radius_m")
        .in("status", ["active", "in_progress"])
        .order("created_at", { ascending: false })
        .range(jobs.length, jobs.length + JOBS_PAGE_SIZE - 1);

      if (err) throw err;
      const newJobs = (data ?? []) as JobSummary[];
      setJobs((prev) => [...prev, ...newJobs]);
      setHasMoreJobs(newJobs.length === JOBS_PAGE_SIZE);
    } catch (e) {
      setError(e instanceof Error ? e.message : t("dashboard.failedToLoad"));
    } finally {
      setLoadingMoreJobs(false);
    }
  }, [jobs.length, t]);

  useEffect(() => {
    loadDashboard();
  }, [loadDashboard]);

  return (
    <div>
      {/* Header */}
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold tracking-tight text-slate-900 dark:text-slate-100">
            {t("dashboard.title")}
          </h1>
          <p className="mt-0.5 text-sm text-slate-500 dark:text-slate-400">
            {t("dashboard.subtitle")}
          </p>
        </div>
        <div className="flex gap-2">
          <button
            type="button"
            onClick={openWelcome}
            aria-label={t("dashboard.help")}
            className="flex h-11 w-11 items-center justify-center rounded-lg text-slate-500 transition-colors hover:bg-stone-100 hover:text-slate-700 dark:text-slate-400 dark:hover:bg-slate-800 dark:hover:text-slate-200"
          >
            <HelpCircle size={18} />
          </button>
          <button
            onClick={loadDashboard}
            className="inline-flex min-h-11 items-center rounded-lg bg-stone-100 px-4 text-sm font-semibold text-slate-700 transition-colors hover:bg-stone-200 dark:bg-slate-800 dark:text-slate-200 dark:hover:bg-slate-700"
          >
            {t("common.refresh")}
          </button>
          <a
            href="/reports"
            className="inline-flex min-h-11 items-center rounded-lg bg-slate-900 px-4 text-sm font-semibold text-white transition-colors hover:bg-slate-800 dark:bg-slate-100 dark:text-slate-900 dark:hover:bg-white"
          >
            {t("dashboard.generateReport")}
          </a>
        </div>
      </div>

      {/* Daily huddle (6am-10am or when missing>0) */}
      <DailyHuddle companyId={companyId ?? null} />

      {/* KPI Cards — color is reserved for state thresholds, not category. */}
      <div className="mb-6 grid grid-cols-2 gap-4 lg:grid-cols-4">
        <KpiCard
          title={t("dashboard.activeJobs")}
          value={stats.totalJobs.toString()}
          subtitle={t("dashboard.thisWeek")}
        />
        <KpiCard
          title={t("dashboard.workersClockedIn")}
          value={stats.activeWorkers.toString()}
          subtitle={t("dashboard.today")}
        />
        <KpiCard
          title={t("dashboard.photosToday")}
          value={stats.photosToday.toString()}
          subtitle={t("dashboard.proofCaptured")}
        />
        <KpiCard
          title={t("dashboard.pendingOt")}
          value={stats.pendingOT.toString()}
          subtitle={t("dashboard.awaitingApproval")}
          valueClassName={
            stats.pendingOT > 0
              ? "text-amber-600 dark:text-amber-400"
              : undefined
          }
          href={stats.pendingOT > 0 ? "/overtime" : undefined}
        />
      </div>

      {/* Role-aware quick-jump pills (compact secondary actions) */}
      {role && QUICK_ACTIONS[role] && (
        <div className="mb-6 flex flex-wrap gap-2">
          {QUICK_ACTIONS[role].map((action) => {
            const Icon = action.icon;
            return (
              <Link
                key={action.href}
                href={action.href}
                className="inline-flex min-h-11 items-center gap-1.5 rounded-full border border-stone-200 bg-card px-3.5 text-xs font-medium text-slate-700 transition-colors hover:border-slate-300 hover:bg-stone-50 dark:border-slate-800 dark:text-slate-200 dark:hover:border-slate-700 dark:hover:bg-slate-800"
              >
                <Icon className="h-3.5 w-3.5 flex-shrink-0 text-slate-500 dark:text-slate-400" />
                {t(action.label)}
              </Link>
            );
          })}
        </div>
      )}

      {loading && (
        <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
          <SkeletonCard />
          <SkeletonCard />
          <SkeletonCard />
          <SkeletonCard />
        </div>
      )}

      {error && (
        <div className="rounded-xl border border-red-100 bg-red-50 p-4 text-sm text-red-600">
          {error}
          <button
            onClick={loadDashboard}
            className="ml-3 font-semibold underline"
          >
            {t("common.retry")}
          </button>
        </div>
      )}

      {/* Active workers — exception-aware status table */}
      <ActiveWorkersTable workers={activeWorkersList} />

      {/* Today's flags (rule-based) */}
      {aiHints.length > 0 && (
        <div className="mb-6 rounded-xl border border-stone-200 border-l-4 border-l-amber-400 bg-card p-4 dark:border-slate-800">
          <h3 className="mb-2 text-xs font-semibold uppercase tracking-widest text-amber-700">
            {t("dashboard.todaysFlags")}
          </h3>
          <ul className="space-y-1">
            {aiHints.map((hint, i) => (
              <li key={i} className="text-xs text-slate-600 dark:text-slate-400">
                {hint}
              </li>
            ))}
          </ul>
        </div>
      )}

      {/* Jobs */}
      {!loading && !error && jobs.length === 0 && (
        <div className="rounded-2xl border border-dashed border-stone-200 bg-card p-10 text-center dark:border-slate-700">
          <p className="text-sm text-slate-600 dark:text-slate-300">{t("dashboard.noActiveJobs")}</p>
          <a
            href="/projects"
            className="mt-4 inline-flex min-h-11 items-center rounded-lg bg-slate-900 px-5 text-sm font-semibold text-white transition-colors hover:bg-slate-800 dark:bg-slate-100 dark:text-slate-900 dark:hover:bg-white"
          >
            {t("dashboard.createFirstJob")}
          </a>
        </div>
      )}

      {jobs.length > 0 && (
        <div className="mb-6">
          <h2 className="mb-3 text-sm font-semibold text-slate-700 dark:text-slate-300">
            {t("dashboard.jobsTable.heading")}
          </h2>

          {/* Mobile: card stack (no horizontal scroll, full 44pt actions). */}
          <ul className="space-y-3 md:hidden">
            {jobs.map((job) => {
              const tc = jobTasks.find((jt) => jt.job_id === job.id);
              const pct = tc && tc.total > 0 ? Math.round((tc.completed / tc.total) * 100) : 0;
              const inProgress = job.status === "in_progress";
              const StatusIcon = inProgress ? Clock : CircleDot;
              const statusTone = inProgress
                ? "text-emerald-600 dark:text-emerald-400"
                : "text-sky-600 dark:text-sky-400";
              const statusLabel = job.status.replace("_", " ");
              return (
                <li
                  key={job.id}
                  className="rounded-xl border border-stone-200 bg-card p-4 shadow-sm dark:border-slate-800"
                >
                  <div className="flex items-start justify-between gap-2">
                    <div className="flex min-w-0 flex-1 items-center gap-2">
                      <StatusIcon
                        className={`h-4 w-4 shrink-0 ${statusTone}`}
                        aria-label={statusLabel}
                      />
                      <div className="min-w-0">
                        <div className="truncate font-medium text-slate-900 dark:text-slate-100">
                          {job.name}
                        </div>
                        <div className="truncate text-xs font-medium tabular-nums text-slate-500 dark:text-slate-400">
                          {job.code}
                        </div>
                      </div>
                    </div>
                    <span className="shrink-0 text-xs tabular-nums text-slate-500 dark:text-slate-400">
                      {job.geofence_radius_m}m
                    </span>
                  </div>
                  {job.site_name && (
                    <div className="mt-2 text-sm text-slate-700 dark:text-slate-300">
                      {job.site_name}
                    </div>
                  )}
                  <div className="mt-3">
                    {tc && tc.total > 0 ? (
                      <>
                        <div className="flex items-center gap-2">
                          <div className="h-1.5 flex-1 overflow-hidden rounded-full bg-stone-100 dark:bg-slate-800">
                            <div
                              className="h-full rounded-full bg-emerald-500 transition-[width]"
                              style={{ width: `${pct}%` }}
                            />
                          </div>
                          <span className="text-xs font-semibold tabular-nums text-slate-700 dark:text-slate-300">
                            {pct}%
                          </span>
                        </div>
                        <div className="mt-1 text-xs tabular-nums text-slate-500 dark:text-slate-400">
                          {t("dashboard.tasksProgress", {
                            completed: tc.completed,
                            total: tc.total,
                          })}
                        </div>
                      </>
                    ) : (
                      <span className="text-xs text-slate-500">{t("dashboard.noTasks")}</span>
                    )}
                  </div>
                  <div className="mt-3 flex gap-2">
                    <a
                      href={`/timeline?job_id=${job.id}`}
                      className="inline-flex min-h-11 flex-1 items-center justify-center rounded-lg bg-stone-50 px-3 text-xs font-semibold text-slate-700 hover:bg-stone-100 dark:bg-slate-800 dark:text-slate-200 dark:hover:bg-slate-700"
                    >
                      {t("dashboard.timeline")}
                    </a>
                    <a
                      href={`/photos?job_id=${job.id}`}
                      className="inline-flex min-h-11 flex-1 items-center justify-center rounded-lg bg-stone-50 px-3 text-xs font-semibold text-slate-700 hover:bg-stone-100 dark:bg-slate-800 dark:text-slate-200 dark:hover:bg-slate-700"
                    >
                      {t("dashboard.photos")}
                    </a>
                  </div>
                </li>
              );
            })}
          </ul>

          {/* Desktop: dense table. */}
          <div className="hidden overflow-hidden rounded-xl border border-stone-200 bg-card shadow-sm md:block dark:border-slate-800">
            <div className="overflow-x-auto">
              <table className="min-w-full divide-y divide-stone-100 dark:divide-slate-800">
                <thead className="bg-stone-50 dark:bg-slate-950">
                  <tr className="text-left text-xs font-semibold uppercase tracking-widest text-slate-500 dark:text-slate-400">
                    <th scope="col" className="px-3 py-2 w-10">
                      <span className="sr-only">{t("dashboard.jobsTable.col.status")}</span>
                    </th>
                    <th scope="col" className="px-3 py-2">{t("dashboard.jobsTable.col.name")}</th>
                    <th scope="col" className="px-3 py-2">{t("dashboard.jobsTable.col.site")}</th>
                    <th scope="col" className="px-3 py-2">{t("dashboard.jobsTable.col.progress")}</th>
                    <th scope="col" className="px-3 py-2 text-right tabular-nums">{t("dashboard.jobsTable.col.geofence")}</th>
                    <th scope="col" className="px-3 py-2">
                      <span className="sr-only">{t("dashboard.timeline")} / {t("dashboard.photos")}</span>
                    </th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-stone-100 dark:divide-slate-800">
                  {jobs.map((job) => {
                    const tc = jobTasks.find((jt) => jt.job_id === job.id);
                    const pct = tc && tc.total > 0 ? Math.round((tc.completed / tc.total) * 100) : 0;
                    const inProgress = job.status === "in_progress";
                    const StatusIcon = inProgress ? Clock : CircleDot;
                    const statusTone = inProgress
                      ? "text-emerald-600 dark:text-emerald-400"
                      : "text-sky-600 dark:text-sky-400";
                    const statusLabel = job.status.replace("_", " ");
                    return (
                      <tr
                        key={job.id}
                        className="text-sm text-slate-700 transition-colors hover:bg-stone-50 dark:text-slate-300 dark:hover:bg-slate-800/40"
                      >
                        <td className="px-3 py-3 align-middle">
                          <StatusIcon
                            className={`h-4 w-4 ${statusTone}`}
                            aria-label={statusLabel}
                          />
                        </td>
                        <td className="px-3 py-3 align-middle">
                          <div className="font-medium text-slate-900 dark:text-slate-100">
                            {job.name}
                          </div>
                          <div className="mt-0.5 text-xs font-medium tabular-nums text-slate-500 dark:text-slate-400">
                            {job.code}
                          </div>
                        </td>
                        <td className="px-3 py-3 align-middle text-slate-700 dark:text-slate-300">
                          {job.site_name ?? "—"}
                        </td>
                        <td className="px-3 py-3 align-middle">
                          {tc && tc.total > 0 ? (
                            <div className="flex items-center gap-2">
                              <div className="h-1.5 w-24 overflow-hidden rounded-full bg-stone-100 dark:bg-slate-800">
                                <div
                                  className="h-full rounded-full bg-emerald-500 transition-[width]"
                                  style={{ width: `${pct}%` }}
                                />
                              </div>
                              <span className="text-xs font-semibold tabular-nums text-slate-700 dark:text-slate-300">
                                {pct}%
                              </span>
                              <span className="text-xs tabular-nums text-slate-500 dark:text-slate-400">
                                {t("dashboard.tasksProgress", {
                                  completed: tc.completed,
                                  total: tc.total,
                                })}
                              </span>
                            </div>
                          ) : (
                            <span className="text-xs text-slate-500">{t("dashboard.noTasks")}</span>
                          )}
                        </td>
                        <td className="px-3 py-3 align-middle text-right text-xs tabular-nums text-slate-500 dark:text-slate-400">
                          {job.geofence_radius_m}m
                        </td>
                        <td className="px-3 py-3 align-middle">
                          <div className="flex justify-end gap-1">
                            <a
                              href={`/timeline?job_id=${job.id}`}
                              className="inline-flex min-h-9 items-center rounded-md px-2 text-xs font-semibold text-slate-700 transition-colors hover:bg-stone-100 dark:text-slate-200 dark:hover:bg-slate-800"
                            >
                              {t("dashboard.timeline")}
                            </a>
                            <a
                              href={`/photos?job_id=${job.id}`}
                              className="inline-flex min-h-9 items-center rounded-md px-2 text-xs font-semibold text-slate-700 transition-colors hover:bg-stone-100 dark:text-slate-200 dark:hover:bg-slate-800"
                            >
                              {t("dashboard.photos")}
                            </a>
                          </div>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </div>
        </div>
      )}

      {hasMoreJobs && (
        <div className="mt-6 flex justify-center">
          <button
            onClick={loadMoreJobs}
            disabled={loadingMoreJobs}
            className="mx-auto mt-4 flex min-h-11 items-center gap-2 rounded-xl border border-stone-200 bg-white px-6 text-sm font-semibold text-slate-700 shadow-sm hover:bg-stone-50 disabled:bg-stone-100 disabled:text-slate-400 dark:border-slate-800 dark:bg-slate-900 dark:text-slate-200 dark:hover:bg-slate-800 dark:disabled:bg-slate-900 dark:disabled:text-slate-500"
          >
            {loadingMoreJobs ? t("common.loadingMore") : t("common.loadMore")}
          </button>
        </div>
      )}

      <DashboardWelcome open={welcomeOpen} onClose={closeWelcome} />
    </div>
  );
}

