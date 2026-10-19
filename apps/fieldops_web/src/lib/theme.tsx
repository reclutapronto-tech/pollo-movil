"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
} from "react";

type ThemePref = "light" | "dark" | "system";
type ResolvedTheme = "light" | "dark";

const STORAGE_KEY = "fieldops_theme";

interface ThemeContextValue {
  pref: ThemePref;
  resolved: ResolvedTheme;
  setPref: (p: ThemePref) => void;
  toggle: () => void;
}

const ThemeContext = createContext<ThemeContextValue | null>(null);

function resolvePref(pref: ThemePref): ResolvedTheme {
  if (pref === "system") {
    return typeof window !== "undefined" &&
      window.matchMedia("(prefers-color-scheme: dark)").matches
      ? "dark"
      : "light";
  }
  return pref;
}

function applyToDocument(theme: ResolvedTheme) {
  if (typeof document === "undefined") return;
  const root = document.documentElement;
  if (theme === "dark") {
    root.classList.add("dark");
    root.style.colorScheme = "dark";
  } else {
    root.classList.remove("dark");
    root.style.colorScheme = "light";
  }
}

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const [pref, setPrefState] = useState<ThemePref>("system");
  const [resolved, setResolved] = useState<ResolvedTheme>("light");

  // Load stored preference on mount.
  useEffect(() => {
    try {
      const stored = localStorage.getItem(STORAGE_KEY) as ThemePref | null;
      const initial: ThemePref =
        stored === "light" || stored === "dark" || stored === "system"
          ? stored
          : "system";
      setPrefState(initial);
    } catch {
      /* localStorage unavailable */
    }
  }, []);

  // Apply resolved theme whenever preference changes, and subscribe to system changes when on "system".
  useEffect(() => {
    const r = resolvePref(pref);
    setResolved(r);
    applyToDocument(r);

    if (pref !== "system") return;
    if (typeof window === "undefined") return;

    const mq = window.matchMedia("(prefers-color-scheme: dark)");
    const onChange = () => {
      const next = mq.matches ? "dark" : "light";
      setResolved(next);
      applyToDocument(next);
    };
    mq.addEventListener("change", onChange);
    return () => mq.removeEventListener("change", onChange);
  }, [pref]);

  const setPref = useCallback((p: ThemePref) => {
    setPrefState(p);
    try {
      localStorage.setItem(STORAGE_KEY, p);
    } catch {
      /* ignore */
    }
  }, []);

  const toggle = useCallback(() => {
    setPref(resolved === "dark" ? "light" : "dark");
  }, [resolved, setPref]);

  const value = useMemo<ThemeContextValue>(
    () => ({ pref, resolved, setPref, toggle }),
    [pref, resolved, setPref, toggle],
  );

  return <ThemeContext.Provider value={value}>{children}</ThemeContext.Provider>;
}

export function useTheme(): ThemeContextValue {
  const ctx = useContext(ThemeContext);
  if (!ctx) {
    // Safe fallback when used outside provider (e.g. in SSR snapshots).
    return {
      pref: "system",
      resolved: "light",
      setPref: () => {},
      toggle: () => {},
    };
  }
  return ctx;
}

/**
 * Inline script payload injected into <head> to apply the correct theme
 * before React hydrates — prevents a light→dark flash on first paint.
 */
export const THEME_INIT_SCRIPT = `
(function(){try{
  var s=localStorage.getItem('${STORAGE_KEY}');
  var m=window.matchMedia('(prefers-color-scheme: dark)').matches;
  var t=(s==='dark'||s==='light')?s:(m?'dark':'light');
  if(t==='dark'){document.documentElement.classList.add('dark');document.documentElement.style.colorScheme='dark';}
  else{document.documentElement.style.colorScheme='light';}
}catch(e){}})();
`;
