"use client";

import { useEffect } from "react";
import { X } from "lucide-react";
import { useI18n } from "@/lib/i18n";

/**
 * First-run briefing for the dashboard.
 *
 * Slide-in side panel (not a modal scrim that hijacks the page). Persists
 * "seen" in localStorage so it shows once. Re-openable via the ? button in
 * the dashboard header. Content reads as a *briefing*, not a *demo* —
 * matches the proof-grade brand voice.
 */

const STORAGE_KEY = "dashboard-welcome-dismissed";

export function dashboardWelcomeSeen(): boolean {
  if (typeof window === "undefined") return true; // SSR: assume seen
  try {
    return localStorage.getItem(STORAGE_KEY) === "true";
  } catch {
    return true;
  }
}

export function markDashboardWelcomeSeen(): void {
  try {
    localStorage.setItem(STORAGE_KEY, "true");
  } catch {
    /* localStorage unavailable */
  }
}

interface DashboardWelcomeProps {
  open: boolean;
  onClose: () => void;
}

const SURFACES = [
  { titleKey: "welcome.huddle.title", bodyKey: "welcome.huddle.body" },
  { titleKey: "welcome.kpis.title", bodyKey: "welcome.kpis.body" },
  { titleKey: "welcome.workers.title", bodyKey: "welcome.workers.body" },
  { titleKey: "welcome.jobs.title", bodyKey: "welcome.jobs.body" },
  { titleKey: "welcome.nav.title", bodyKey: "welcome.nav.body" },
] as const;

export function DashboardWelcome({ open, onClose }: DashboardWelcomeProps) {
  const { t } = useI18n();

  // ESC closes the panel. Focus restoration handled by the browser when
  // the trigger button receives focus after dismiss.
  useEffect(() => {
    if (!open) return;
    const handleKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    document.addEventListener("keydown", handleKey);
    return () => document.removeEventListener("keydown", handleKey);
  }, [open, onClose]);

  if (!open) return null;

  return (
    <>
      {/* Light scrim — subtle, not aggressive. Click dismisses. */}
      <button
        type="button"
        aria-label={t("welcome.close")}
        onClick={onClose}
        className="fixed inset-0 z-40 bg-slate-900/20 backdrop-blur-[1px] dark:bg-slate-950/40"
      />
      {/* Side panel. Slides in from the right; full width on mobile. */}
      <aside
        role="dialog"
        aria-labelledby="dashboard-welcome-title"
        aria-modal="true"
        className="fixed inset-y-0 right-0 z-50 flex w-full max-w-md flex-col border-l border-stone-200 bg-card shadow-xl dark:border-slate-800"
      >
        <header className="flex items-start justify-between gap-3 border-b border-stone-200 p-6 dark:border-slate-800">
          <div className="min-w-0">
            <p className="text-xs font-semibold uppercase tracking-widest text-amber-700 dark:text-amber-400">
              {t("welcome.kicker")}
            </p>
            <h2
              id="dashboard-welcome-title"
              className="mt-1 text-2xl font-bold tracking-tight text-slate-900 dark:text-slate-100"
            >
              {t("welcome.title")}
            </h2>
            <p className="mt-2 text-sm text-slate-600 dark:text-slate-300">
              {t("welcome.subtitle")}
            </p>
          </div>
          <button
            type="button"
            onClick={onClose}
            aria-label={t("welcome.close")}
            className="flex h-11 w-11 shrink-0 items-center justify-center rounded-md text-slate-500 transition-colors hover:bg-stone-100 hover:text-slate-700 dark:hover:bg-slate-800 dark:hover:text-slate-200"
          >
            <X size={18} />
          </button>
        </header>
        <ol className="flex-1 space-y-5 overflow-y-auto p-6">
          {SURFACES.map((surface, i) => (
            <li key={surface.titleKey} className="flex gap-3">
              <span className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full border border-stone-200 bg-stone-50 text-xs font-bold tabular-nums text-slate-700 dark:border-slate-700 dark:bg-slate-800 dark:text-slate-200">
                {i + 1}
              </span>
              <div className="min-w-0">
                <h3 className="text-sm font-semibold text-slate-900 dark:text-slate-100">
                  {t(surface.titleKey)}
                </h3>
                <p className="mt-1 text-sm text-slate-600 dark:text-slate-300">
                  {t(surface.bodyKey)}
                </p>
              </div>
            </li>
          ))}
        </ol>
        <footer className="border-t border-stone-200 p-6 dark:border-slate-800">
          <button
            type="button"
            onClick={onClose}
            className="inline-flex min-h-11 w-full items-center justify-center rounded-lg bg-slate-900 px-5 text-sm font-semibold text-white transition-colors hover:bg-slate-800 dark:bg-slate-100 dark:text-slate-900 dark:hover:bg-white"
          >
            {t("welcome.cta")}
          </button>
          <p className="mt-3 text-xs text-slate-500 dark:text-slate-400">
            {t("welcome.replayHint")}
          </p>
        </footer>
      </aside>
    </>
  );
}
