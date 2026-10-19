import * as Sentry from "@sentry/nextjs";
import { SENTRY_DSN } from "./src/lib/observability";

Sentry.init({
  dsn: SENTRY_DSN,
  tracesSampleRate: process.env.NODE_ENV === "production" ? 0.1 : 1.0,
  environment: process.env.NODE_ENV ?? "development",
  initialScope: { tags: { app: "web", runtime: "browser" } },
  // Session replay only when an error occurs — worth its weight in repro
  // steps for "it broke when I clicked X" beta reports, negligible volume.
  integrations: [
    Sentry.replayIntegration({ maskAllText: true, blockAllMedia: true }),
  ],
  replaysSessionSampleRate: 0,
  replaysOnErrorSampleRate: 1.0,
});

export const onRouterTransitionStart = Sentry.captureRouterTransitionStart;
