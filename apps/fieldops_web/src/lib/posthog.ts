import posthog from "posthog-js";

let initialized = false;

export function initPostHog(): void {
  if (initialized || typeof window === "undefined") return;
  const key = process.env.NEXT_PUBLIC_POSTHOG_KEY;
  if (!key) return;

  posthog.init(key, {
    api_host: process.env.NEXT_PUBLIC_POSTHOG_HOST ?? "https://app.posthog.com",
    capture_pageview: true,
    capture_pageleave: true,
    loaded: () => {
      if (process.env.NODE_ENV === "development") posthog.debug();
    },
  });
  initialized = true;
}

export { posthog };
