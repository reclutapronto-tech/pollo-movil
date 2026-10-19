"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";

/**
 * Global keyboard shortcut layer.
 *
 * Pattern: GitHub/Linear-style "g <letter>" sequences for navigation, plus
 * "?" to open the shortcut help modal. Shortcuts are ignored when the user
 * is typing in an input, textarea, or contenteditable element.
 *
 * Cmd-K is handled separately by the existing CommandPalette component —
 * this hook intentionally does not bind it.
 */

const NAV_TARGETS: Record<string, string> = {
  d: "/",
  m: "/map",
  w: "/workers",
  t: "/timeline",
  s: "/schedule",
  p: "/photos",
  r: "/reports",
  a: "/alerts",
  c: "/timecards",
};

/** Window in which a key press after "g" counts as a sequence. */
const SEQUENCE_WINDOW_MS = 1500;

function isTypingTarget(target: EventTarget | null): boolean {
  if (!(target instanceof HTMLElement)) return false;
  const tag = target.tagName;
  if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT") return true;
  if (target.isContentEditable) return true;
  return false;
}

interface UseKeyboardShortcutsOptions {
  onOpenHelp: () => void;
}

export function useKeyboardShortcuts({ onOpenHelp }: UseKeyboardShortcutsOptions) {
  const router = useRouter();
  const gActiveRef = useRef(false);
  const gTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const resetG = useCallback(() => {
    gActiveRef.current = false;
    if (gTimerRef.current) {
      clearTimeout(gTimerRef.current);
      gTimerRef.current = null;
    }
  }, []);

  useEffect(() => {
    function onKeyDown(e: KeyboardEvent) {
      // Skip when the user is typing.
      if (isTypingTarget(e.target)) return;
      // Skip when modifier keys are held (those are reserved for other shortcuts).
      if (e.metaKey || e.ctrlKey || e.altKey) return;

      const key = e.key.toLowerCase();

      // "?" opens the help modal. (Shift+/ on US keyboards.)
      if (e.key === "?" || (e.shiftKey && key === "/")) {
        e.preventDefault();
        resetG();
        onOpenHelp();
        return;
      }

      // First press of "g": arm the sequence.
      if (!gActiveRef.current && key === "g") {
        e.preventDefault();
        gActiveRef.current = true;
        gTimerRef.current = setTimeout(resetG, SEQUENCE_WINDOW_MS);
        return;
      }

      // Second press while armed: navigate or cancel.
      if (gActiveRef.current) {
        const target = NAV_TARGETS[key];
        resetG();
        if (target) {
          e.preventDefault();
          router.push(target);
        }
      }
    }

    window.addEventListener("keydown", onKeyDown);
    return () => {
      window.removeEventListener("keydown", onKeyDown);
      resetG();
    };
  }, [router, onOpenHelp, resetG]);
}

/** Public list of shortcuts — used by the help modal so the two stay in sync. */
export const SHORTCUTS = [
  { keys: ["⌘", "K"], label: "shortcuts.openCommandPalette" },
  { keys: ["/", null], label: "shortcuts.focusSearch" },
  { keys: ["g", "d"], label: "shortcuts.goDashboard" },
  { keys: ["g", "m"], label: "shortcuts.goMap" },
  { keys: ["g", "w"], label: "shortcuts.goWorkers" },
  { keys: ["g", "t"], label: "shortcuts.goTimeline" },
  { keys: ["g", "s"], label: "shortcuts.goSchedule" },
  { keys: ["g", "p"], label: "shortcuts.goPhotos" },
  { keys: ["g", "r"], label: "shortcuts.goReports" },
  { keys: ["g", "a"], label: "shortcuts.goAlerts" },
  { keys: ["g", "c"], label: "shortcuts.goTimecards" },
  { keys: ["?", null], label: "shortcuts.showHelp" },
] as const;

interface ShortcutRow {
  keys: readonly (string | null)[];
  label: string;
}
export type { ShortcutRow };

interface SetState<T> {
  (value: T | ((prev: T) => T)): void;
}

/** Convenience hook: wraps useKeyboardShortcuts with built-in open/close state. */
export function useShortcutsHelp(): {
  shortcutsOpen: boolean;
  openShortcuts: () => void;
  closeShortcuts: () => void;
  setShortcutsOpen: SetState<boolean>;
} {
  const [shortcutsOpen, setShortcutsOpen] = useState(false);
  const openShortcuts = useCallback(() => setShortcutsOpen(true), []);
  const closeShortcuts = useCallback(() => setShortcutsOpen(false), []);

  useKeyboardShortcuts({ onOpenHelp: openShortcuts });

  return { shortcutsOpen, openShortcuts, closeShortcuts, setShortcutsOpen };
}
