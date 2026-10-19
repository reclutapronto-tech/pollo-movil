"use client";

import type { Job, ViewMode } from "@/lib/schedule/types";
import { VIEW_MODES } from "@/lib/schedule/types";
import { projectColor } from "@/lib/schedule/colors";

interface Props {
  rangeLabel: string;
  viewMode: ViewMode;
  onViewModeChange: (mode: ViewMode) => void;
  onPrev: () => void;
  onNext: () => void;
  onToday: () => void;
  jobs: Job[];
  selectedJobIds: Set<string>;
  onToggleJob: (id: string) => void;
  onClearJobs: () => void;
  workerSearch: string;
  onWorkerSearchChange: (v: string) => void;
  onAddShift: () => void;
  onPublish: () => void;
  onCopyPrev: () => void;
  draftCount: number;
  busyAction: string | null;
  labels: {
    addShift: string;
    publish: string;
    publishing: string;
    copyPrev: string;
    today: string;
    prev: string;
    next: string;
    searchWorkers: string;
    jobs: string;
    clear: string;
    viewModes: Record<ViewMode, string>;
    drafts: (n: number) => string;
  };
}

export function ScheduleToolbar(props: Props) {
  const {
    rangeLabel,
    viewMode,
    onViewModeChange,
    onPrev,
    onNext,
    onToday,
    jobs,
    selectedJobIds,
    onToggleJob,
    onClearJobs,
    workerSearch,
    onWorkerSearchChange,
    onAddShift,
    onPublish,
    onCopyPrev,
    draftCount,
    busyAction,
    labels,
  } = props;

  return (
    <div className="space-y-3 rounded-2xl border border-stone-200 bg-white p-4 shadow-sm">
      <div className="flex flex-wrap items-center gap-3">
        <div className="flex items-center gap-1">
          <button
            type="button"
            onClick={onPrev}
            className="rounded-lg border border-stone-200 px-2.5 py-1.5 text-sm font-medium text-stone-700 hover:bg-stone-50"
            aria-label={labels.prev}
          >
            ←
          </button>
          <button
            type="button"
            onClick={onToday}
            className="rounded-lg border border-stone-200 px-3 py-1.5 text-sm font-medium text-stone-700 hover:bg-stone-50"
          >
            {labels.today}
          </button>
          <button
            type="button"
            onClick={onNext}
            className="rounded-lg border border-stone-200 px-2.5 py-1.5 text-sm font-medium text-stone-700 hover:bg-stone-50"
            aria-label={labels.next}
          >
            →
          </button>
        </div>

        <div className="text-base font-semibold text-stone-900">{rangeLabel}</div>

        <div className="ml-auto flex flex-wrap items-center gap-2">
          <div className="inline-flex rounded-lg border border-stone-200 bg-stone-50 p-0.5">
            {VIEW_MODES.map((mode) => (
              <button
                key={mode}
                type="button"
                onClick={() => onViewModeChange(mode)}
                className={`rounded-md px-3 py-1.5 text-xs font-semibold transition-colors ${
                  viewMode === mode
                    ? "bg-white text-stone-900 shadow-sm"
                    : "text-stone-600 hover:text-stone-900"
                }`}
              >
                {labels.viewModes[mode]}
              </button>
            ))}
          </div>

          <button
            type="button"
            onClick={onCopyPrev}
            disabled={busyAction === "copy"}
            className="rounded-lg border border-stone-200 px-3 py-1.5 text-xs font-semibold text-stone-700 hover:bg-stone-50 disabled:bg-stone-100 disabled:text-slate-400"
          >
            {labels.copyPrev}
          </button>

          <button
            type="button"
            onClick={onAddShift}
            className="rounded-lg bg-amber-500 px-3 py-1.5 text-xs font-semibold text-white shadow-sm hover:bg-amber-600"
          >
            + {labels.addShift}
          </button>

          <button
            type="button"
            onClick={onPublish}
            disabled={draftCount === 0 || busyAction === "publish"}
            className="rounded-lg bg-stone-900 px-3 py-1.5 text-xs font-semibold text-white shadow-sm hover:bg-stone-800 disabled:cursor-not-allowed disabled:bg-stone-100 disabled:text-slate-400"
          >
            {busyAction === "publish"
              ? labels.publishing
              : `${labels.publish}${draftCount > 0 ? ` (${draftCount})` : ""}`}
          </button>
        </div>
      </div>

      <div className="flex flex-wrap items-center gap-2">
        <input
          type="search"
          value={workerSearch}
          onChange={(e) => onWorkerSearchChange(e.target.value)}
          placeholder={labels.searchWorkers}
          className="w-56 rounded-lg border border-stone-200 px-3 py-1.5 text-sm focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30"
        />
        <span className="text-xs font-medium uppercase tracking-wide text-stone-500">
          {labels.jobs}:
        </span>
        <div className="flex flex-1 flex-wrap items-center gap-1.5">
          {jobs.length === 0 && (
            <span className="text-xs text-stone-400">—</span>
          )}
          {jobs.map((job) => {
            const active = selectedJobIds.size === 0 || selectedJobIds.has(job.id);
            const color = projectColor(job.id);
            return (
              <button
                key={job.id}
                type="button"
                onClick={() => onToggleJob(job.id)}
                className={`inline-flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-xs font-medium transition-opacity ${
                  active
                    ? `${color.bg} ${color.border} ${color.text}`
                    : "border-stone-200 bg-white text-stone-400"
                }`}
                title={job.name}
              >
                <span className={`h-1.5 w-1.5 rounded-full ${color.dot}`} />
                {job.code || job.name}
              </button>
            );
          })}
          {selectedJobIds.size > 0 && (
            <button
              type="button"
              onClick={onClearJobs}
              className="ml-1 rounded-full border border-stone-200 px-2 py-1 text-xs text-stone-500 hover:bg-stone-50"
            >
              {labels.clear}
            </button>
          )}
        </div>
        {draftCount > 0 && (
          <span className="rounded-full bg-amber-50 px-2.5 py-1 text-xs font-medium text-amber-700">
            {labels.drafts(draftCount)}
          </span>
        )}
      </div>
    </div>
  );
}
