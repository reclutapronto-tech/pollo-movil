"use client";

import { X } from "lucide-react";

interface BulkAction {
  label: string;
  tone?: "primary" | "danger" | "neutral";
  onClick: () => void;
  disabled?: boolean;
}

/**
 * Sticky action bar shown when rows are selected in a list.
 *
 * Used on /overtime for bulk approve/reject and on /timecards for bulk
 * CSV export. Actions are looped through the existing single-row endpoints
 * — the bar is purely UI coordination.
 */
export function BulkActionBar({
  count,
  onClear,
  actions,
  selectedLabel,
}: {
  count: number;
  onClear: () => void;
  actions: BulkAction[];
  selectedLabel: string;
}) {
  if (count === 0) return null;

  const toneClass = (tone?: BulkAction["tone"]) => {
    if (tone === "primary")
      return "bg-slate-900 text-white hover:bg-slate-800 dark:bg-slate-100 dark:text-slate-900 dark:hover:bg-card";
    if (tone === "danger")
      return "bg-red-600 text-white hover:bg-red-700 dark:bg-red-600 dark:hover:bg-red-500";
    return "bg-stone-100 text-slate-700 hover:bg-stone-200 dark:bg-slate-800 dark:text-slate-200 dark:hover:bg-slate-700";
  };

  return (
    <div
      className="sticky top-2 z-30 mb-4 flex flex-wrap items-center gap-3 rounded-xl border border-slate-200 bg-card/95 px-4 py-2.5 shadow-md backdrop-blur dark:border-slate-800 dark:bg-slate-900/95"
      role="region"
      aria-label="Bulk actions"
    >
      <button
        onClick={onClear}
        aria-label="Clear selection"
        className="flex h-6 w-6 items-center justify-center rounded-md text-slate-500 hover:bg-stone-100 hover:text-slate-700 dark:hover:bg-slate-800 dark:hover:text-slate-200"
      >
        <X size={14} />
      </button>
      <span className="text-sm font-semibold text-slate-700 dark:text-slate-200">
        {selectedLabel}
      </span>
      <div className="ml-auto flex flex-wrap gap-2">
        {actions.map((a) => (
          <button
            key={a.label}
            onClick={a.onClick}
            disabled={a.disabled}
            className={`rounded-lg px-3 py-1.5 text-xs font-semibold transition-colors disabled:bg-stone-100 disabled:text-slate-500 ${toneClass(
              a.tone,
            )}`}
          >
            {a.label}
          </button>
        ))}
      </div>
    </div>
  );
}
