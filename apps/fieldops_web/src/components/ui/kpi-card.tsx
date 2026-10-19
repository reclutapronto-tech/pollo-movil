"use client";

import * as React from "react";

import { cn } from "@/lib/utils";

interface KpiCardProps {
  title: string;
  value: number | string;
  icon?: React.ReactNode;
  subtitle?: string;
  href?: string;
  className?: string;
  /** Tone for the value digits. Color carries state (threshold crossed),
   *  not category. Default is neutral. */
  valueClassName?: string;
}

function KpiCard({
  title,
  value,
  icon,
  subtitle,
  href,
  className,
  valueClassName,
}: KpiCardProps) {
  const content = (
    <div
      data-slot="kpi-card"
      className={cn(
        "rounded-2xl border border-stone-200 bg-card p-5 shadow-sm transition hover:border-stone-300 hover:shadow-md dark:border-slate-800 dark:hover:border-slate-700",
        className,
      )}
    >
      <div className="flex items-center gap-2 text-xs font-medium text-slate-500 dark:text-slate-400">
        {icon && <span className="shrink-0">{icon}</span>}
        <span>{title}</span>
      </div>
      <span
        className={cn(
          "mt-1 block font-heading text-3xl font-bold tracking-tight tabular-nums text-slate-900 dark:text-slate-100",
          valueClassName,
        )}
      >
        {value}
      </span>
      {subtitle && (
        <div className="mt-1 text-xs text-slate-500 dark:text-slate-400">{subtitle}</div>
      )}
    </div>
  );

  if (href) {
    return <a href={href}>{content}</a>;
  }

  return content;
}

export { KpiCard };
export type { KpiCardProps };
