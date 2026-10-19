"use client";

import { useEffect } from "react";
import { X } from "lucide-react";
import { useI18n } from "@/lib/i18n";
import { SHORTCUTS } from "@/lib/use-keyboard-shortcuts";

interface ShortcutHelpModalProps {
  open: boolean;
  onClose: () => void;
}

export function ShortcutHelpModal({ open, onClose }: ShortcutHelpModalProps) {
  const { t } = useI18n();

  // ESC closes the modal.
  useEffect(() => {
    if (!open) return;
    const handleKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        e.stopPropagation();
        onClose();
      }
    };
    document.addEventListener("keydown", handleKey);
    return () => document.removeEventListener("keydown", handleKey);
  }, [open, onClose]);

  if (!open) return null;

  return (
    <>
      {/* Light scrim — click dismisses. */}
      <button
        type="button"
        aria-label={t("shortcuts.close")}
        onClick={onClose}
        className="fixed inset-0 z-40 bg-slate-900/20 backdrop-blur-[1px] dark:bg-slate-950/40"
      />
      <aside
        role="dialog"
        aria-labelledby="shortcut-help-title"
        aria-modal="true"
        className="fixed inset-y-0 right-0 z-50 flex w-full max-w-sm flex-col border-l border-stone-200 bg-card shadow-xl dark:border-slate-800"
      >
        <header className="flex items-start justify-between gap-3 border-b border-stone-200 p-6 dark:border-slate-800">
          <div>
            <p className="text-xs font-semibold uppercase tracking-widest text-slate-500 dark:text-slate-400">
              {t("shortcuts.kicker")}
            </p>
            <h2
              id="shortcut-help-title"
              className="mt-1 text-xl font-bold tracking-tight text-slate-900 dark:text-slate-100"
            >
              {t("shortcuts.title")}
            </h2>
          </div>
          <button
            type="button"
            onClick={onClose}
            aria-label={t("shortcuts.close")}
            className="flex h-11 w-11 shrink-0 items-center justify-center rounded-md text-slate-500 transition-colors hover:bg-stone-100 hover:text-slate-700 dark:hover:bg-slate-800 dark:hover:text-slate-200"
          >
            <X size={18} />
          </button>
        </header>
        <ul className="flex-1 divide-y divide-stone-100 overflow-y-auto dark:divide-slate-800">
          {SHORTCUTS.map((row) => (
            <li
              key={row.label}
              className="flex items-center justify-between gap-3 px-6 py-3"
            >
              <span className="text-sm text-slate-700 dark:text-slate-300">
                {t(row.label)}
              </span>
              <span className="flex items-center gap-1 font-mono text-xs">
                {row.keys.map((k, i) =>
                  k === null ? null : (
                    <kbd
                      key={i}
                      className="inline-flex h-6 min-w-[1.5rem] items-center justify-center rounded border border-stone-300 bg-stone-50 px-1.5 font-semibold text-slate-700 shadow-[0_1px_0_rgb(0_0_0/0.05)] dark:border-slate-700 dark:bg-slate-800 dark:text-slate-200"
                    >
                      {k}
                    </kbd>
                  ),
                )}
              </span>
            </li>
          ))}
        </ul>
        <footer className="border-t border-stone-200 p-6 dark:border-slate-800">
          <p className="text-xs text-slate-500 dark:text-slate-400">
            {t("shortcuts.footnote")}
          </p>
        </footer>
      </aside>
    </>
  );
}
