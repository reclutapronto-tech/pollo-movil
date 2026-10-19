import * as Sentry from "@sentry/nextjs";
import { SENTRY_DSN } from "./src/lib/observability";

Sentry.init({
  dsn: SENTRY_DSN,
  tracesSampleRate: process.env.NODE_ENV === "production" ? 0.1 : 1.0,
  environment: process.env.NODE_ENV ?? "development",
  initialScope: { tags: { app: "web", runtime: "edge" } },
});
