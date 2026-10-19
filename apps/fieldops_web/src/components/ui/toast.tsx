"use client";

import { useCallback, useRef, useState } from "react";

interface ToastState {
  message: string;
  tone: "success" | "error";
}

/**
 * Minimal toast: `const { toast, showToast } = useToast()` — render `{toast}`
 * once in the page, call `showToast("PTO approved")` after actions. Fixed
 * bottom-center, auto-dismisses. Deliberately not a provider/portal library;
 * three approval pages need feedback, not an abstraction.
 */
export function useToast() {
  const [state, setState] = useState<ToastState | null>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  const showToast = useCallback(
    (message: string, tone: "success" | "error" = "success") => {
      if (timer.current) clearTimeout(timer.current);
      setState({ message, tone });
      timer.current = setTimeout(() => setState(null), 3500);
    },
    [],
  );

  const toast = state ? (
    <div
      role="status"
      aria-live="polite"
      className={`fixed bottom-6 left-1/2 z-50 -translate-x-1/2 rounded-xl px-4 py-2.5 text-sm font-semibold text-white shadow-lg ${
        state.tone === "success" ? "bg-green-600" : "bg-red-600"
      }`}
    >
      {state.message}
    </div>
  ) : null;

  return { toast, showToast };
}
