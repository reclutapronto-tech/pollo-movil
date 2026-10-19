"use client";

import { useEffect } from "react";
import { initPostHog } from "@/lib/posthog";
import { LocaleProvider } from "@/lib/i18n";
import { ThemeProvider } from "@/lib/theme";

export function Providers({ children }: { children: React.ReactNode }) {
  useEffect(() => {
    initPostHog();
  }, []);

  return (
    <ThemeProvider>
      <LocaleProvider>{children}</LocaleProvider>
    </ThemeProvider>
  );
}
