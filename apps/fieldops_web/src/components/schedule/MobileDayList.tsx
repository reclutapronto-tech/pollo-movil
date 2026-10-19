"use client";

import { useMemo } from "react";
import type { ScheduleEntry, Worker } from "@/lib/schedule/types";
import { asDateKey, isToday } from "@/lib/schedule/dates";
import { projectColor } from "@/lib/schedule/colors";

interface Props {
  workers: Worker[];
  dates: Date[];
  entries: ScheduleEntry[];
  selectedJobIds: Set<string>;
  onShiftClick: (entry: ScheduleEntry) => void;
  onAddForDate: (date: string) => void;
}

export function MobileDayList({
  workers,
  dates,
  entries,
  selectedJobIds,
  onShiftClick,
  onAddForDate,
}: Props) {
  const workerName = useMemo(() => {
    const m = new Map<string, string>();
    workers.forEach((w) => m.set(w.id, w.full_name));
    return m;
  }, [workers]);

  const grouped = useMemo(() => {
    const map = new Map<string, ScheduleEntry[]>();
    for (const e of entries) {
      if (selectedJobIds.size > 0 && !selectedJobIds.has(e.job_id)) continue;
      const arr = map.get(e.date) ?? [];
      arr.push(e);
      map.set(e.date, arr);
    }
    return map;
  }, [entries, selectedJobIds]);

  return (
    <div className="space-y-3">
      {dates.map((d) => {
        const key = asDateKey(d);
        const dayEntries = (grouped.get(key) ?? []).sort((a, b) =>
          a.start_time.localeCompare(b.start_time),
        );
        const today = isToday(d);
        return (
          <div
            key={key}
            className={`overflow-hidden rounded-2xl border bg-white shadow-sm ${
              today ? "border-amber-300" : "border-stone-200"
            }`}
          >
            <div
              className={`flex items-center justify-between px-4 py-2 ${
                today ? "bg-amber-50 text-amber-900" : "bg-stone-50 text-stone-700"
              }`}
            >
              <div className="text-sm font-semibold">
                {d.toLocaleDateString(undefined, {
                  weekday: "short",
                  month: "short",
                  day: "numeric",
                })}
              </div>
              <button
                type="button"
                onClick={() => onAddForDate(key)}
                className="rounded-md border border-stone-200 bg-white px-2 py-1 text-xs font-semibold text-stone-700 hover:bg-stone-50"
              >
                + Add
              </button>
            </div>
            <div className="divide-y divide-stone-100">
              {dayEntries.length === 0 && (
                <div className="px-4 py-3 text-xs text-stone-400">No shifts</div>
              )}
              {dayEntries.map((e) => {
                const c = projectColor(e.job_id);
                return (
                  <button
                    key={e.id}
                    type="button"
                    onClick={() => onShiftClick(e)}
                    className="flex w-full items-center gap-3 px-4 py-2.5 text-left hover:bg-stone-50"
                  >
                    <span className={`h-8 w-1 rounded-full ${c.dot}`} />
                    <div className="min-w-0 flex-1">
                      <div className="truncate text-sm font-semibold text-stone-900">
                        {e.job_code ? `${e.job_code} — ` : ""}{e.job_name}
                      </div>
                      <div className="truncate text-xs text-stone-500">
                        {workerName.get(e.worker_id) ?? e.worker_name}
                      </div>
                    </div>
                    <div className="text-right font-mono text-xs text-stone-600">
                      {e.start_time.slice(0, 5)}
                      <br />
                      {e.end_time.slice(0, 5)}
                    </div>
                  </button>
                );
              })}
            </div>
          </div>
        );
      })}
    </div>
  );
}
