"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import { Clock, Coffee, AlertCircle } from "lucide-react";
import { useI18n } from "@/lib/i18n";

type WorkerFilter = "all" | "working" | "break" | "over8";

interface ActiveWorker {
  id: string;
  full_name: string;
  status: "working" | "break";
  hours: number;
}

function initials(name: string): string {
  const parts = name.trim().split(/\s+/);
  if (parts.length >= 2)
    return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
  return (parts[0]?.[0] ?? "?").toUpperCase();
}

const MAX_VISIBLE = 10;

export function ActiveWorkersTable({ workers }: { workers: ActiveWorker[] }) {
  const { t } = useI18n();
  const [filter, setFilter] = useState<WorkerFilter>("all");

  const counts = useMemo(() => {
    const c: Record<WorkerFilter, number> = {
      all: workers.length,
      working: 0,
      break: 0,
      over8: 0,
    };
    for (const w of workers) {
      if (w.status === "working") c.working++;
      if (w.status === "break") c.break++;
      if (w.hours >= 8) c.over8++;
    }
    return c;
  }, [workers]);

  const filtered = useMemo(() => {
    const rows =
      filter === "all"
        ? workers
        : filter === "over8"
          ? workers.filter((w) => w.hours >= 8)
          : workers.filter((w) => w.status === filter);
    // Stable sort: most-hours-first so long shifts surface.
    return [...rows].sort((a, b) => b.hours - a.hours);
  }, [workers, filter]);

  const visible = filtered.slice(0, MAX_VISIBLE);
  const overflow = Math.max(0, filtered.length - MAX_VISIBLE);

  if (workers.length === 0) return null;

  return (
    <div className="mb-6">
      <div className="mb-3 flex flex-wrap items-center justify-between gap-2">
        <h2 className="text-sm font-semibold text-slate-600 dark:text-slate-300">
          {t("activeWorkers.heading")}
        </h2>
        <div className="flex flex-wrap gap-1.5">
          {(["all", "working", "break", "over8"] as WorkerFilter[]).map((f) => {
            const active = filter === f;
            return (
              <button
                key={f}
                onClick={() => setFilter(f)}
                className={`rounded-full px-2.5 py-0.5 text-[11px] font-semibold transition-colors ${
                  active
                    ? "bg-slate-900 text-white dark:bg-slate-100 dark:text-slate-900"
                    : "bg-stone-100 text-slate-600 hover:bg-stone-200 dark:bg-slate-800 dark:text-slate-300 dark:hover:bg-slate-700"
                }`}
              >
                {t(`activeWorkers.filter.${f}`)} ·{" "}
                <span className="tabular-nums">{counts[f]}</span>
              </button>
            );
          })}
        </div>
      </div>

      {filtered.length === 0 ? (
        <div className="rounded-xl border border-dashed border-stone-200 bg-white p-6 text-center text-xs text-slate-400 dark:border-slate-700 dark:bg-slate-900 dark:text-slate-400">
          {t("activeWorkers.empty")}
        </div>
      ) : (
        <div className="overflow-hidden rounded-xl border border-stone-200 bg-white shadow-sm dark:border-slate-800 dark:bg-slate-900">
          <table className="min-w-full divide-y divide-stone-100 dark:divide-slate-800">
            <thead className="bg-stone-50 dark:bg-slate-950">
              <tr className="text-left text-[10px] font-semibold uppercase tracking-widest text-slate-400 dark:text-slate-400">
                <th className="px-3 py-2">{t("activeWorkers.col.worker")}</th>
                <th className="px-3 py-2">{t("activeWorkers.col.status")}</th>
                <th className="px-3 py-2 text-right tabular-nums">
                  {t("activeWorkers.col.hours")}
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-stone-100 dark:divide-slate-800">
              {visible.map((w) => {
                const over8 = w.hours >= 8;
                const over10 = w.hours >= 10;
                const StatusIcon =
                  w.status === "break"
                    ? Coffee
                    : over10
                      ? AlertCircle
                      : Clock;
                return (
                  <tr
                    key={w.id}
                    className="text-sm text-slate-700 hover:bg-stone-50 dark:text-slate-300 dark:hover:bg-slate-800/60"
                  >
                    <td className="px-3 py-2">
                      <div className="flex items-center gap-2.5">
                        <div className="flex h-7 w-7 items-center justify-center rounded-full bg-slate-800 text-[10px] font-bold text-white dark:bg-slate-700">
                          {initials(w.full_name)}
                        </div>
                        <span className="truncate font-medium text-slate-900 dark:text-slate-100">
                          {w.full_name}
                        </span>
                      </div>
                    </td>
                    <td className="px-3 py-2">
                      <span
                        className={`inline-flex items-center gap-1.5 rounded-full px-2 py-0.5 text-[11px] font-semibold ${
                          w.status === "break"
                            ? "bg-amber-50 text-amber-700 dark:bg-amber-950/40 dark:text-amber-300"
                            : over10
                              ? "bg-rose-50 text-rose-700 dark:bg-rose-950/40 dark:text-rose-300"
                              : "bg-emerald-50 text-emerald-700 dark:bg-emerald-950/40 dark:text-emerald-300"
                        }`}
                      >
                        <StatusIcon size={11} />
                        {w.status === "break"
                          ? t("activeWorkers.status.break")
                          : over10
                            ? t("activeWorkers.status.over10")
                            : t("activeWorkers.status.working")}
                      </span>
                    </td>
                    <td
                      className={`px-3 py-2 text-right tabular-nums text-sm ${
                        over10
                          ? "font-semibold text-rose-700 dark:text-rose-400"
                          : over8
                            ? "font-semibold text-amber-700 dark:text-amber-400"
                            : "text-slate-600 dark:text-slate-300"
                      }`}
                    >
                      {w.hours}h
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
          {overflow > 0 && (
            <div className="border-t border-stone-100 bg-stone-50 px-3 py-2 text-center text-[11px] dark:border-slate-800 dark:bg-slate-950">
              <Link
                href="/workers?filter=active"
                className="font-semibold text-slate-500 hover:text-slate-800 dark:text-slate-400 dark:hover:text-slate-200"
              >
                {t("activeWorkers.viewAll", { count: overflow })} →
              </Link>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
