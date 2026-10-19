import * as React from "react";

import { cn } from "@/lib/utils";

const STATUS_STYLES = {
  active: { dot: "bg-green-500", pill: "bg-green-100 text-green-700" },
  approved: { dot: "bg-green-500", pill: "bg-green-100 text-green-700" },
  break: { dot: "bg-amber-500", pill: "bg-amber-100 text-amber-700" },
  pending: { dot: "bg-amber-500", pill: "bg-amber-100 text-amber-700" },
  offline: { dot: "bg-stone-400", pill: "bg-stone-100 text-stone-500" },
  late: { dot: "bg-red-500", pill: "bg-red-100 text-red-700" },
  denied: { dot: "bg-red-500", pill: "bg-red-100 text-red-700" },
} as const;

type Status = keyof typeof STATUS_STYLES;

interface StatusBadgeProps {
  status: Status;
  size?: "sm" | "md";
  className?: string;
}

function StatusBadge({ status, size = "md", className }: StatusBadgeProps) {
  const styles = STATUS_STYLES[status];
  const label = status.charAt(0).toUpperCase() + status.slice(1);

  return (
    <span
      data-slot="status-badge"
      className={cn(
        "inline-flex items-center gap-1.5 rounded-full font-semibold",
        styles.pill,
        size === "sm"
          ? "px-2 py-0.5 text-[10px]"
          : "px-2.5 py-0.5 text-xs",
        className,
      )}
    >
      <span
        className={cn(
          "inline-block rounded-full",
          styles.dot,
          size === "sm" ? "h-1.5 w-1.5" : "h-2 w-2",
        )}
      />
      {label}
    </span>
  );
}

export { StatusBadge };
export type { StatusBadgeProps, Status };
