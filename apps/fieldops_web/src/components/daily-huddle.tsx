"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Users as UsersIcon, CheckCircle2, AlertTriangle } from "lucide-react";
import { getSupabase } from "@/lib/supabase";
import { useI18n } from "@/lib/i18n";

/**
 * Daily huddle widget — supervisor's 7am "who's on deck?" check.
 *
 * Answers three numbers for today:
 *   scheduled  = workers with a published schedule_shift for today
 *   clockedIn  = workers who've logged a clock_in today
 *   missing    = scheduled ∖ clockedIn (names shown when expanded)
 *
 * Visibility:
 *   - Always visible between 06:00 and 10:00 local time.
 *   - After 10:00 local, visible only when `missing > 0`.
 *   - Auto-refresh every 2 minutes during the 06:00-10:00 window.
 */

interface ScheduledShift {
  worker_id: string;
  worker_name: string;
}

interface HuddleState {
  scheduled: ScheduledShift[];
  clockedInIds: Set<string>;
}

function isHuddleWindow(now = new Date()): boolean {
  const hours = now.getHours();
  return hours >= 6 && hours < 10;
}

export function DailyHuddle({ companyId }: { companyId: string | null }) {
  const { t } = useI18n();
  const [state, setState] = useState<HuddleState>({
    scheduled: [],
    clockedInIds: new Set(),
  });
  const [expanded, setExpanded] = useState(false);
  const [loading, setLoading] = useState(true);
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const load = useCallback(async () => {
    if (!companyId) {
      setLoading(false);
      return;
    }
    const supabase = getSupabase();
    const todayStr = new Date().toISOString().slice(0, 10);
    const todayStartIso = `${todayStr}T00:00:00Z`;

    const [shiftsRes, clockRes] = await Promise.all([
      supabase
        .from("schedule_shifts")
        .select("worker_id, users:users!schedule_shifts_worker_id_fkey(full_name)")
        .eq("company_id", companyId)
        .eq("shift_date", todayStr)
        .eq("status", "published"),
      supabase
        .from("clock_events")
        .select("user_id")
        .eq("company_id", companyId)
        .eq("event_subtype", "clock_in")
        .gte("occurred_at", todayStartIso),
    ]);

    const scheduledMap = new Map<string, ScheduledShift>();
    for (const row of shiftsRes.data ?? []) {
      const r = row as unknown as {
        worker_id: string;
        users: { full_name: string | null } | { full_name: string | null }[] | null;
      };
      const userObj = Array.isArray(r.users) ? r.users[0] : r.users;
      if (!scheduledMap.has(r.worker_id)) {
        scheduledMap.set(r.worker_id, {
          worker_id: r.worker_id,
          worker_name: userObj?.full_name ?? "—",
        });
      }
    }

    const clockedIds = new Set<string>();
    for (const row of clockRes.data ?? []) {
      clockedIds.add((row as { user_id: string }).user_id);
    }

    setState({
      scheduled: Array.from(scheduledMap.values()),
      clockedInIds: clockedIds,
    });
    setLoading(false);
  }, [companyId]);

  // Initial load + auto-refresh every 2 min during the huddle window.
  useEffect(() => {
    load();
    const startInterval = () => {
      if (intervalRef.current) clearInterval(intervalRef.current);
      if (!isHuddleWindow()) return;
      intervalRef.current = setInterval(load, 2 * 60 * 1000);
    };
    startInterval();

    return () => {
      if (intervalRef.current) clearInterval(intervalRef.current);
    };
  }, [load]);

  const scheduled = state.scheduled.length;
  const clockedIn = useMemo(
    () =>
      state.scheduled.filter((s) => state.clockedInIds.has(s.worker_id)).length,
    [state],
  );
  const missingList = useMemo(
    () =>
      state.scheduled.filter((s) => !state.clockedInIds.has(s.worker_id)),
    [state],
  );
  const missing = missingList.length;

  const inWindow = isHuddleWindow();
  // Hide entirely outside huddle window when there's nothing missing.
  if (loading) return null;
  if (!inWindow && missing === 0) return null;
  // Don't show the widget at all when there's nothing scheduled today.
  if (scheduled === 0) return null;

  const allShowed = missing === 0;

  return (
    <div
      className={`mb-6 rounded-xl border p-4 ${
        allShowed
          ? "border-emerald-200 bg-emerald-50 dark:border-emerald-900/40 dark:bg-emerald-950/20"
          : "border-amber-200 bg-amber-50 dark:border-amber-900/40 dark:bg-amber-950/20"
      }`}
    >
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          {allShowed ? (
            <CheckCircle2 size={18} className="text-emerald-600" />
          ) : (
            <AlertTriangle size={18} className="text-amber-600" />
          )}
          <div>
            <h3 className="text-sm font-semibold text-slate-900 dark:text-slate-100">
              {t("dailyHuddle.title")}
            </h3>
            <p className="mt-0.5 text-xs text-slate-600 dark:text-slate-400">
              {allShowed
                ? t("dailyHuddle.allPresent", { count: scheduled })
                : t("dailyHuddle.summary", {
                    scheduled,
                    clockedIn,
                    missing,
                  })}
            </p>
          </div>
        </div>
        <div className="flex items-center gap-4">
          <Metric
            label={t("dailyHuddle.scheduled")}
            value={scheduled}
            icon={<UsersIcon size={14} className="text-slate-500" />}
          />
          <Metric
            label={t("dailyHuddle.clockedIn")}
            value={clockedIn}
            icon={<CheckCircle2 size={14} className="text-emerald-500" />}
          />
          <Metric
            label={t("dailyHuddle.missing")}
            value={missing}
            tone={missing > 0 ? "warn" : undefined}
            icon={
              <AlertTriangle
                size={14}
                className={missing > 0 ? "text-amber-500" : "text-slate-400"}
              />
            }
          />
          {missing > 0 && (
            <button
              onClick={() => setExpanded((e) => !e)}
              className="text-[11px] font-semibold text-amber-700 underline underline-offset-2 hover:text-amber-800 dark:text-amber-400 dark:hover:text-amber-300"
            >
              {expanded ? t("dailyHuddle.hide") : t("dailyHuddle.seeMissing")}
            </button>
          )}
        </div>
      </div>

      {expanded && missing > 0 && (
        <ul className="mt-3 grid grid-cols-2 gap-1 border-t border-amber-200 pt-3 sm:grid-cols-3 lg:grid-cols-4 dark:border-amber-900/40">
          {missingList.map((m) => (
            <li
              key={m.worker_id}
              className="truncate text-xs text-slate-700 dark:text-slate-300"
            >
              · {m.worker_name}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

function Metric({
  label,
  value,
  icon,
  tone,
}: {
  label: string;
  value: number;
  icon: React.ReactNode;
  tone?: "warn";
}) {
  return (
    <div className="flex items-center gap-1.5">
      {icon}
      <div className="flex items-baseline gap-1">
        <span
          className={`text-lg font-bold tabular-nums ${
            tone === "warn"
              ? "text-amber-700 dark:text-amber-400"
              : "text-slate-900 dark:text-slate-100"
          }`}
        >
          {value}
        </span>
        <span className="text-[10px] font-semibold uppercase tracking-widest text-slate-400 dark:text-slate-400">
          {label}
        </span>
      </div>
    </div>
  );
}
