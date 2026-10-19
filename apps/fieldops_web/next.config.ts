import type { NextConfig } from "next";
import { withSentryConfig } from "@sentry/nextjs";
import path from "node:path";

const nextConfig: NextConfig = {
  outputFileTracingRoot: path.join(__dirname, "../.."),
  eslint: {
    // Next.js still runs its legacy internal lint path during build.
    // Use the explicit ESLint CLI gate from package.json as the source of truth.
    ignoreDuringBuilds: true,
  },
  // FullCalendar ships ESM-only — Next.js must transpile it to avoid
  // "module not found" errors and ensure CSS is bundled correctly.
  transpilePackages: [
    "@fullcalendar/react",
    "@fullcalendar/interaction",
    "@fullcalendar/resource-timeline",
    "@fullcalendar/core",
  ],
};

export default withSentryConfig(nextConfig, {
  silent: true,
  org: process.env.SENTRY_ORG,
  project: process.env.SENTRY_PROJECT,
  widenClientFileUpload: true,
  sourcemaps: {
    filesToDeleteAfterUpload: [".next/static/**/*.map"],
  },
});
