"use client";

import { useEffect, useState } from "react";
import { Bell } from "lucide-react";
import { getSupabase } from "@/lib/supabase";
import { useCurrentUser } from "@/lib/use-role";
import { isSupervisorOrAbove } from "@/lib/roles";
import { useI18n } from "@/lib/i18n";

/**
 * Persistent bell icon for the sidebar brand row.
 *
 * Counts `alert_events` with status='open' for the current company and
 * keeps the count live via Supabase Realtime on INSERT/UPDATE of the
 * partitioned alert_events table. Clicking routes to /alerts.
 *
 * Rendered only for supervisors and above — workers/foremen don't act on
 * operational alerts.
 */
export function AlertBell({ compact = false }: { compact?: boolean }) {
  const { t } = useI18n();
  const { role, companyId, loading } = useCurrentUser();
  const canSee = isSupervisorOrAbove(role);
  const [count, setCount] = useState(0);

  useEffect(() => {
    if (loading || !canSee || !companyId) return;

    let cancelled = false;
    const supabase = getSupabase();

    async function loadCount() {
      const { count: c } = await supabase
        .from("alert_events")
        .select("id", { count: "exact", head: true })
        .eq("company_id", companyId)
        .eq("status", "open");
      if (!cancelled) setCount(c ?? 0);
    }

    loadCount();

    // Subscribe to INSERT (new alert) + UPDATE (status change) for this company's alerts.
    // Unique channel name per effect run prevents collisions with a still-alive
    // subscription from a previous mount (React 18 StrictMode / fast refresh).
    const channel = supabase
      .channel(`alert-bell-${companyId}-${Math.random().toString(36).slice(2)}`)
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "alert_events",
          filter: `company_id=eq.${companyId}`,
        },
        () => {
          loadCount();
        },
      )
      .subscribe();

    return () => {
      cancelled = true;
      supabase.removeChannel(channel);
    };
  }, [loading, canSee, companyId]);

  if (!canSee) return null;

  const displayCount = count > 99 ? "99+" : String(count);
  const hasOpen = count > 0;
  const label = hasOpen
    ? t("shell.alertBellWithCount", { count: displayCount })
    : t("shell.alertBellNone");

  return (
    <a
      href="/alerts"
      title={label}
      aria-label={label}
      className={`relative flex items-center justify-center rounded-md text-slate-500 transition-colors hover:bg-stone-100 hover:text-slate-700 dark:text-slate-400 dark:hover:bg-slate-800 dark:hover:text-slate-200 ${
        compact ? "h-7 w-7" : "h-8 w-8"
      }`}
    >
      <Bell size={compact ? 14 : 16} />
      {hasOpen && (
        <span
          className="absolute -right-0.5 -top-0.5 flex min-w-[16px] items-center justify-center rounded-full bg-red-500 px-1 text-[9px] font-bold leading-none text-white"
          style={{ height: 16 }}
        >
          {displayCount}
        </span>
      )}
    </a>
  );
}
