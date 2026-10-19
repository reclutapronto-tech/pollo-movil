"use client";

import { Camera, Check, Circle, Clock } from "lucide-react";
import { ReportCharts } from "./ReportCharts";

const STATUS_PRESENTATION: Record<
  string,
  { Icon: typeof Check; tone: string; bg: string }
> = {
  completed: {
    Icon: Check,
    tone: "text-emerald-700 dark:text-emerald-300",
    bg: "bg-emerald-50 dark:bg-emerald-950/40",
  },
  in_progress: {
    Icon: Clock,
    tone: "text-amber-700 dark:text-amber-300",
    bg: "bg-amber-50 dark:bg-amber-950/40",
  },
};
const DEFAULT_STATUS = {
  Icon: Circle,
  tone: "text-slate-600 dark:text-slate-400",
  bg: "bg-stone-50 dark:bg-slate-800",
} as const;

export function JobReportView({
  report,
  t,
}: {
  report: Record<string, unknown>;
  t: (key: string, vars?: Record<string, string | number>) => string;
}) {
  const job = report.job as Record<string, string>;
  const summary = report.summary as Record<string, number>;
  const workerHours = report.worker_hours as Array<Record<string, unknown>>;
  const tasks = report.tasks as Array<Record<string, unknown>>;
  const photos = report.photos as Array<Record<string, unknown>>;

  return (
    <div className="space-y-6">
      {/* Job header */}
      <div className="rounded-2xl border border-stone-200 bg-card p-6 shadow-sm dark:border-slate-800">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <h3 className="text-xl font-bold tracking-tight text-slate-900 dark:text-slate-100">
              {job.name}
            </h3>
            <p className="mt-1 text-sm text-slate-600 dark:text-slate-400">
              <span className="tabular-nums">{job.code}</span> &middot; {job.status}{" "}
              &middot; {job.site_name || t("reports.noSite")}
            </p>
          </div>
          <span className="text-xs tabular-nums text-slate-500 dark:text-slate-400">
            {t("reports.generated", {
              time: new Date(report.generated_at as string).toLocaleString(),
            })}
          </span>
        </div>
      </div>

      {/* Summary stats — proof-grade voice (Manrope + tabular-nums). */}
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-5">
        {[
          { label: t("reports.clockEvents"), value: summary.total_clock_events },
          { label: t("reports.photos"), value: summary.total_photos },
          {
            label: t("reports.tasks"),
            value: `${summary.completed_tasks}/${summary.total_tasks}`,
          },
          { label: t("reports.otDecisions"), value: summary.total_ot_decisions },
        ].map((stat) => (
          <div
            key={stat.label}
            className="rounded-xl border border-stone-200 bg-card p-4 text-center dark:border-slate-800"
          >
            <div className="font-heading text-2xl font-bold tracking-tight tabular-nums text-slate-900 dark:text-slate-100">
              {stat.value}
            </div>
            <div className="mt-1 text-xs text-slate-500 dark:text-slate-400">
              {stat.label}
            </div>
          </div>
        ))}
      </div>

      {/* Visual Charts */}
      <ReportCharts
        workerHours={workerHours}
        tasks={tasks}
        summary={summary}
        t={t}
      />

      {/* Worker hours table */}
      {workerHours && workerHours.length > 0 && (
        <div className="rounded-2xl border border-stone-200 bg-card p-6 shadow-sm dark:border-slate-800">
          <h4 className="mb-4 font-heading font-bold tracking-tight text-slate-900 dark:text-slate-100">
            {t("reports.workerHours")}
          </h4>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-stone-200 text-left text-xs font-semibold uppercase tracking-widest text-slate-500 dark:border-slate-700 dark:text-slate-400">
                  <th className="pb-2">{t("reports.worker")}</th>
                  <th className="pb-2 tabular-nums">{t("reports.sessions")}</th>
                  <th className="pb-2 tabular-nums">{t("reports.regular")}</th>
                  <th className="pb-2 tabular-nums">{t("reports.ot")}</th>
                  <th className="pb-2 tabular-nums">{t("reports.total")}</th>
                </tr>
              </thead>
              <tbody>
                {workerHours.map((wh) => (
                  <tr
                    key={wh.worker as string}
                    className="border-b border-stone-100 text-slate-700 dark:border-slate-800 dark:text-slate-300"
                  >
                    <td className="py-2 font-medium text-slate-900 dark:text-slate-100">
                      {wh.worker as string}
                    </td>
                    <td className="py-2 tabular-nums">{wh.sessions as number}</td>
                    <td className="py-2 tabular-nums">
                      {wh.regular_hours as number}h
                    </td>
                    <td className="py-2 tabular-nums text-amber-700 dark:text-amber-400">
                      {wh.ot_hours as number}h
                    </td>
                    <td className="py-2 font-semibold tabular-nums text-slate-900 dark:text-slate-100">
                      {wh.total_hours as number}h
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Tasks — status paired with icon (no color-only). */}
      {tasks && tasks.length > 0 && (
        <div className="rounded-2xl border border-stone-200 bg-card p-6 shadow-sm dark:border-slate-800">
          <h4 className="mb-4 font-heading font-bold tracking-tight text-slate-900 dark:text-slate-100">
            {t("reports.tasks")}
          </h4>
          <ul className="space-y-2">
            {tasks.map((task, i) => {
              const status = task.status as string;
              const presentation =
                STATUS_PRESENTATION[status] ?? DEFAULT_STATUS;
              const { Icon, tone, bg } = presentation;
              return (
                <li
                  key={i}
                  className={`flex items-center justify-between gap-3 rounded-lg px-4 py-2 ${bg}`}
                >
                  <div className="flex min-w-0 items-center gap-2">
                    <Icon
                      className={`h-3.5 w-3.5 shrink-0 ${tone}`}
                      aria-hidden="true"
                    />
                    <span className="truncate text-sm text-slate-900 dark:text-slate-100">
                      {task.name as string}
                    </span>
                    {(task.requires_photo as boolean) && (
                      <Camera
                        className="h-3.5 w-3.5 shrink-0 text-amber-700 dark:text-amber-400"
                        aria-label={t("reports.requiresPhoto")}
                      />
                    )}
                  </div>
                  <span className={`text-xs font-medium ${tone}`}>
                    {status}
                  </span>
                </li>
              );
            })}
          </ul>
        </div>
      )}

      {/* Photos */}
      {photos && photos.length > 0 && (
        <div className="rounded-2xl border border-stone-200 bg-card p-6 shadow-sm dark:border-slate-800">
          <h4 className="mb-4 font-heading font-bold tracking-tight text-slate-900 dark:text-slate-100">
            {t("reports.photoProof", { count: photos.length })}
          </h4>
          <ul className="space-y-2">
            {photos.map((p, i) => (
              <li
                key={i}
                className="flex items-center justify-between gap-3 rounded-lg bg-stone-50 px-4 py-2 text-sm dark:bg-slate-800"
              >
                <span className="tabular-nums text-slate-700 dark:text-slate-300">
                  {new Date(p.occurred_at as string).toLocaleString()}
                  {(p.is_checkpoint as boolean) && ` ${t("reports.checkpoint")}`}
                </span>
                {(p.verification_code as string | null) && (
                  <code className="rounded bg-stone-200 px-2 py-0.5 font-mono text-xs text-slate-700 dark:bg-slate-700 dark:text-slate-200">
                    {p.verification_code as string}
                  </code>
                )}
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}
