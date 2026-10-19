"use client";

import { useDroppable } from "@dnd-kit/core";
import { useMemo } from "react";
import type {
  ConflictFlags,
  PtoRequest,
  ScheduleEntry,
  Worker,
} from "@/lib/schedule/types";
import { asDateKey, isToday, isWeekend } from "@/lib/schedule/dates";
import {
  detectConflicts,
  workerHoursInRange,
  workerPtoDates,
} from "@/lib/schedule/hours";
import { ShiftBar } from "./ShiftBar";

interface Props {
  workers: Worker[];
  dates: Date[];
  entries: ScheduleEntry[];
  ptoRequests: PtoRequest[];
  rangeStart: string;
  rangeEnd: string;
  selectedJobIds: Set<string>;
  onShiftClick: (entry: ScheduleEntry) => void;
  onEmptyCellClick: (workerId: string, date: string) => void;
  labels: { hours: (h: number) => string; pto: string; today: string };
}

interface DayHeaderProps {
  date: Date;
  todayLabel: string;
}

function DayHeader({ date, todayLabel }: DayHeaderProps) {
  const today = isToday(date);
  const weekend = isWeekend(date);
  return (
    <div
      className={`flex flex-col items-center justify-center border-l border-stone-200 px-2 py-2 text-xs font-semibold ${
        today
          ? "bg-amber-50 text-amber-900"
          : weekend
            ? "bg-stone-50 text-stone-500"
            : "bg-white text-stone-700"
      }`}
    >
      <span className="uppercase tracking-wide">
        {date.toLocaleDateString(undefined, { weekday: "short" })}
      </span>
      <span className={`text-base ${today ? "font-bold" : "font-semibold"}`}>
        {date.getUTCDate()}
      </span>
      {today && (
        <span className="mt-0.5 rounded-full bg-amber-500 px-1.5 py-0.5 text-[9px] font-bold uppercase text-white">
          {todayLabel}
        </span>
      )}
    </div>
  );
}

interface CellProps {
  workerId: string;
  date: string;
  isPto: boolean;
  weekend: boolean;
  today: boolean;
  entries: ScheduleEntry[];
  conflictsFor: (entry: ScheduleEntry) => ConflictFlags;
  selectedJobIds: Set<string>;
  onShiftClick: (entry: ScheduleEntry) => void;
  onEmptyClick: () => void;
  ptoLabel: string;
}

function Cell({
  workerId,
  date,
  isPto,
  weekend,
  today,
  entries,
  conflictsFor,
  selectedJobIds,
  onShiftClick,
  onEmptyClick,
  ptoLabel,
}: CellProps) {
  const { isOver, setNodeRef } = useDroppable({
    id: `cell-${workerId}-${date}`,
    data: { kind: "cell", workerId, date },
  });

  return (
    <div
      ref={setNodeRef}
      onClick={entries.length === 0 ? onEmptyClick : undefined}
      className={`relative flex min-h-[72px] flex-col gap-1 border-l border-t border-stone-200 p-1 transition-colors ${
        today ? "bg-amber-50/40" : weekend ? "bg-stone-50/60" : "bg-white"
      } ${isOver ? "bg-amber-100/70 ring-1 ring-inset ring-amber-400" : ""} ${
        entries.length === 0 ? "cursor-pointer hover:bg-stone-50" : ""
      }`}
    >
      {isPto && (
        <div className="absolute inset-0 flex items-center justify-center bg-rose-50/80 text-[10px] font-semibold uppercase tracking-wide text-rose-600">
          {ptoLabel}
        </div>
      )}
      {entries.map((e) => (
        <ShiftBar
          key={e.id}
          entry={e}
          conflicts={conflictsFor(e)}
          dimmed={selectedJobIds.size > 0 && !selectedJobIds.has(e.job_id)}
          onClick={() => onShiftClick(e)}
        />
      ))}
    </div>
  );
}

export function WorkerGrid(props: Props) {
  const {
    workers,
    dates,
    entries,
    ptoRequests,
    rangeStart,
    rangeEnd,
    selectedJobIds,
    onShiftClick,
    onEmptyCellClick,
    labels,
  } = props;

  const hoursMap = useMemo(
    () => workerHoursInRange(entries, rangeStart, rangeEnd),
    [entries, rangeStart, rangeEnd],
  );
  const ptoMap = useMemo(() => workerPtoDates(ptoRequests), [ptoRequests]);

  const conflictsFor = (entry: ScheduleEntry) =>
    detectConflicts(entry, entries, ptoMap, hoursMap);

  // index entries by worker+date for fast lookup
  const grouped = useMemo(() => {
    const map = new Map<string, ScheduleEntry[]>();
    for (const e of entries) {
      const key = `${e.worker_id}|${e.date}`;
      const arr = map.get(key) ?? [];
      arr.push(e);
      map.set(key, arr);
    }
    return map;
  }, [entries]);

  const cols = dates.length;
  const gridTemplate = `220px repeat(${cols}, minmax(110px, 1fr))`;

  return (
    <div className="overflow-x-auto rounded-2xl border border-stone-200 bg-white shadow-sm">
      <div className="min-w-fit">
        <div
          className="sticky top-0 z-10 grid border-b border-stone-200 bg-white"
          style={{ gridTemplateColumns: gridTemplate }}
        >
          <div className="px-3 py-3 text-xs font-semibold uppercase tracking-wide text-stone-500">
            Worker
          </div>
          {dates.map((d) => (
            <DayHeader key={asDateKey(d)} date={d} todayLabel={labels.today} />
          ))}
        </div>

        {workers.length === 0 ? (
          <div className="px-6 py-10 text-center text-sm text-stone-500">
            No workers found.
          </div>
        ) : (
          workers.map((worker) => {
            const hours = Math.round((hoursMap.get(worker.id) ?? 0) * 10) / 10;
            const overtime = hours > 40;
            return (
              <div
                key={worker.id}
                className="grid border-b border-stone-100 last:border-b-0"
                style={{ gridTemplateColumns: gridTemplate }}
              >
                <div className="flex items-center justify-between gap-2 border-r border-stone-200 bg-stone-50/50 px-3 py-2">
                  <div className="min-w-0">
                    <div className="truncate text-sm font-semibold text-stone-900">
                      {worker.full_name}
                    </div>
                    <div className="truncate text-[11px] uppercase tracking-wide text-stone-500">
                      {worker.role}
                    </div>
                  </div>
                  <span
                    className={`shrink-0 rounded-full px-2 py-0.5 text-[11px] font-semibold ${
                      overtime
                        ? "bg-red-100 text-red-700"
                        : hours > 32
                          ? "bg-amber-100 text-amber-700"
                          : "bg-stone-100 text-stone-600"
                    }`}
                    title={overtime ? "Overtime" : ""}
                  >
                    {labels.hours(hours)}
                  </span>
                </div>
                {dates.map((d) => {
                  const dateKey = asDateKey(d);
                  const cellEntries = grouped.get(`${worker.id}|${dateKey}`) ?? [];
                  return (
                    <Cell
                      key={dateKey}
                      workerId={worker.id}
                      date={dateKey}
                      isPto={ptoMap.get(worker.id)?.has(dateKey) ?? false}
                      weekend={isWeekend(d)}
                      today={isToday(d)}
                      entries={cellEntries}
                      conflictsFor={conflictsFor}
                      selectedJobIds={selectedJobIds}
                      onShiftClick={onShiftClick}
                      onEmptyClick={() => onEmptyCellClick(worker.id, dateKey)}
                      ptoLabel={labels.pto}
                    />
                  );
                })}
              </div>
            );
          })
        )}
      </div>
    </div>
  );
}
