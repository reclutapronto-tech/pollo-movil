"use client";

import { useDraggable } from "@dnd-kit/core";
import type { ConflictFlags, ScheduleEntry } from "@/lib/schedule/types";
import { projectColor } from "@/lib/schedule/colors";

interface Props {
  entry: ScheduleEntry;
  conflicts: ConflictFlags;
  dimmed: boolean;
  onClick: () => void;
}

export function ShiftBar({ entry, conflicts, dimmed, onClick }: Props) {
  const { attributes, listeners, setNodeRef, isDragging } = useDraggable({
    id: `shift-${entry.id}`,
    data: { kind: "shift", entryId: entry.id },
  });

  const color = projectColor(entry.job_id);
  const hasConflict = conflicts.pto || conflicts.doubleBooked || conflicts.overtime;
  const isDraft = entry.status === "draft";

  const conflictTitle = [
    conflicts.pto && "PTO conflict",
    conflicts.doubleBooked && "Double-booked",
    conflicts.overtime && "Overtime (>40h)",
  ]
    .filter(Boolean)
    .join(" • ");

  return (
    <button
      ref={setNodeRef}
      type="button"
      onClick={onClick}
      {...listeners}
      {...attributes}
      title={conflictTitle || `${entry.job_name} • ${entry.start_time}-${entry.end_time}`}
      className={`group relative w-full cursor-grab rounded-md border px-2 py-1 text-left text-[11px] leading-tight shadow-sm transition-all hover:shadow-md active:cursor-grabbing ${
        color.bg
      } ${color.border} ${color.text} ${
        isDragging ? "opacity-30" : "opacity-100"
      } ${dimmed ? "opacity-30" : ""} ${
        hasConflict ? "ring-2 ring-red-400 ring-offset-1" : ""
      } ${isDraft ? "border-dashed" : ""}`}
    >
      <div className="flex items-center justify-between gap-1">
        <span className="truncate font-semibold">
          {entry.job_code || entry.job_name}
        </span>
        {hasConflict && (
          <span className="text-red-600" aria-label="conflict">!</span>
        )}
      </div>
      <div className="truncate font-mono text-[10px] opacity-80">
        {entry.start_time.slice(0, 5)}–{entry.end_time.slice(0, 5)}
      </div>
    </button>
  );
}
