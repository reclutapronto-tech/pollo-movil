# Pre-Pilot Fixes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close 6 pre-pilot gaps so the product works correctly and safely before the first real worker touches it.

**Architecture:** Six independent fixes across Flutter mobile, Next.js web, and Supabase Edge Functions. Each task can be executed independently and committed separately. Do them in order — observability first so you have visibility while doing the rest.

**Tech Stack:** Flutter + sentry_flutter | Next.js 15 + @sentry/nextjs + posthog-js | Deno Edge Functions + EdgeRuntime.waitUntil | Supabase Realtime (postgres_changes) | Supabase Storage signed URLs

---

## File Map

| File | Change |
|------|--------|
| `apps/fieldops_mobile/pubspec.yaml` | Add `sentry_flutter` dependency |
| `apps/fieldops_mobile/lib/app/bootstrap.dart` | Init Sentry, replace TODO error handlers |
| `apps/fieldops_web/package.json` | Add `@sentry/nextjs`, `posthog-js` |
| `apps/fieldops_web/sentry.client.config.ts` | CREATE — Sentry browser init |
| `apps/fieldops_web/sentry.server.config.ts` | CREATE — Sentry server init |
| `apps/fieldops_web/next.config.ts` | Wrap with `withSentryConfig` |
| `apps/fieldops_web/src/lib/posthog.ts` | CREATE — PostHog init helper |
| `apps/fieldops_web/src/app/providers.tsx` | CREATE — client-side providers wrapper |
| `apps/fieldops_web/src/app/layout.tsx` | Add `<Providers>` wrapper |
| `infra/supabase/functions/media_finalize/index.ts` | Add `EdgeRuntime.waitUntil` stamp trigger |
| `apps/fieldops_web/src/app/photos/page.tsx` | Add signed URL rendering + Realtime subscription |
| `apps/fieldops_web/src/app/timeline/page.tsx` | Add Realtime subscription |
| `apps/fieldops_web/src/components/auth-guard.tsx` | Remove hardcoded test credentials |

---

## Task 1: Sentry Crash Reporting — Flutter

**Files:**
- Modify: `apps/fieldops_mobile/pubspec.yaml`
- Modify: `apps/fieldops_mobile/lib/app/bootstrap.dart`

**Context:** `bootstrap.dart` already has `FlutterError.onError` and `PlatformDispatcher.instance.onError` handlers with `// TODO: Forward to crash reporting` comments. The package just needs to be added and wired in.

- [ ] **Step 1.1: Add sentry_flutter to pubspec.yaml**

In `apps/fieldops_mobile/pubspec.yaml`, under `dependencies:` after `connectivity_plus`:

```yaml
  sentry_flutter: ^8.11.0
```

- [ ] **Step 1.2: Run pub get**

```bash
cd apps/fieldops_mobile && flutter pub get
```

Expected: `Resolving dependencies... sentry_flutter 8.x.x` in output. No errors.

- [ ] **Step 1.3: Replace bootstrap.dart with Sentry-wired version**

Full replacement of `apps/fieldops_mobile/lib/app/bootstrap.dart`:

```dart
import 'dart:async';

import 'package:fieldops_mobile/app/app.dart';
import 'package:fieldops_mobile/core/config/fieldops_environment.dart';
import 'package:fieldops_mobile/core/data/sync_engine.dart';
import 'package:fieldops_mobile/core/observability/fieldops_provider_observer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  final environment = FieldOpsEnvironment.fromDartDefine();

  if (environment.isConfigured) {
    await Supabase.initialize(
      url: environment.supabaseUrl,
      anonKey: environment.supabaseAnonKey,
    );
  }

  final container = ProviderContainer(
    overrides: [fieldOpsEnvironmentProvider.overrideWithValue(environment)],
    observers: [FieldOpsProviderObserver()],
  );

  if (environment.isConfigured) {
    container.read(syncEngineProvider).start();
  }

  const sentryDsn = String.fromEnvironment('SENTRY_DSN', defaultValue: '');

  if (sentryDsn.isNotEmpty) {
    await SentryFlutter.init(
      (options) {
        options.dsn = sentryDsn;
        options.tracesSampleRate = kReleaseMode ? 0.2 : 1.0;
        options.environment = kReleaseMode ? 'production' : 'development';
        options.attachScreenshot = true;
        options.attachViewHierarchy = true;
      },
      appRunner: () => runApp(
        UncontrolledProviderScope(
          container: container,
          child: const FieldOpsApp(),
        ),
      ),
    );
  } else {
    // Local dev without Sentry DSN — still wire up error printing
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('Flutter error: ${details.exceptionAsString()}');
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      debugPrint('Platform error: $error\n$stack');
      return true;
    };

    runApp(
      UncontrolledProviderScope(
        container: container,
        child: const FieldOpsApp(),
      ),
    );
  }
}
```

- [ ] **Step 1.4: Verify it compiles**

```bash
cd apps/fieldops_mobile && flutter analyze
```

Expected: No errors. Warnings about unused imports are OK.

- [ ] **Step 1.5: Commit**

```bash
cd apps/fieldops_mobile
git add pubspec.yaml pubspec.lock lib/app/bootstrap.dart
git commit -m "feat(mobile): wire Sentry crash reporting in bootstrap"
```

---

## Task 2: Sentry + PostHog — Next.js Web

**Files:**
- Modify: `apps/fieldops_web/package.json`
- Create: `apps/fieldops_web/sentry.client.config.ts`
- Create: `apps/fieldops_web/sentry.server.config.ts`
- Modify: `apps/fieldops_web/next.config.ts`
- Create: `apps/fieldops_web/src/lib/posthog.ts`
- Create: `apps/fieldops_web/src/app/providers.tsx`
- Modify: `apps/fieldops_web/src/app/layout.tsx`

- [ ] **Step 2.1: Install packages**

```bash
cd apps/fieldops_web && npm install @sentry/nextjs posthog-js
```

Expected: Both packages added to `package.json` dependencies. No peer dep errors.

- [ ] **Step 2.2: Create sentry.client.config.ts**

Create `apps/fieldops_web/sentry.client.config.ts`:

```typescript
import * as Sentry from "@sentry/nextjs";

Sentry.init({
  dsn: process.env.NEXT_PUBLIC_SENTRY_DSN,
  tracesSampleRate: process.env.NODE_ENV === "production" ? 0.1 : 1.0,
  environment: process.env.NODE_ENV ?? "development",
  enabled: !!process.env.NEXT_PUBLIC_SENTRY_DSN,
});
```

- [ ] **Step 2.3: Create sentry.server.config.ts**

Create `apps/fieldops_web/sentry.server.config.ts`:

```typescript
import * as Sentry from "@sentry/nextjs";

Sentry.init({
  dsn: process.env.NEXT_PUBLIC_SENTRY_DSN,
  tracesSampleRate: process.env.NODE_ENV === "production" ? 0.1 : 1.0,
  environment: process.env.NODE_ENV ?? "development",
  enabled: !!process.env.NEXT_PUBLIC_SENTRY_DSN,
});
```

- [ ] **Step 2.4: Update next.config.ts**

Replace `apps/fieldops_web/next.config.ts`:

```typescript
import type { NextConfig } from "next";
import { withSentryConfig } from "@sentry/nextjs";

const nextConfig: NextConfig = {};

export default withSentryConfig(nextConfig, {
  silent: true,
  org: process.env.SENTRY_ORG,
  project: process.env.SENTRY_PROJECT,
  widenClientFileUpload: true,
  hideSourceMaps: true,
  disableLogger: true,
});
```

- [ ] **Step 2.5: Create src/lib/posthog.ts**

Create `apps/fieldops_web/src/lib/posthog.ts`:

```typescript
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
```

- [ ] **Step 2.6: Create src/app/providers.tsx**

Create `apps/fieldops_web/src/app/providers.tsx`:

```tsx
"use client";

import { useEffect } from "react";
import { initPostHog } from "@/lib/posthog";

export function Providers({ children }: { children: React.ReactNode }) {
  useEffect(() => {
    initPostHog();
  }, []);

  return <>{children}</>;
}
```

- [ ] **Step 2.7: Add Providers to layout.tsx**

Replace `apps/fieldops_web/src/app/layout.tsx`:

```tsx
import type { Metadata } from "next";
import "./globals.css";
import { AuthGuard } from "@/components/auth-guard";
import { Sidebar } from "@/components/sidebar";
import { Providers } from "./providers";

export const metadata: Metadata = {
  title: "FieldOps AI — Command Center",
  description:
    "Monitor field operations, worker activity, and proof timelines.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body className="bg-stone-50 text-slate-900 antialiased">
        <Providers>
          <AuthGuard>
            <div className="flex h-screen overflow-hidden">
              <Sidebar />
              <main className="flex-1 overflow-y-auto">
                <div className="mx-auto max-w-7xl px-6 py-6">{children}</div>
              </main>
            </div>
          </AuthGuard>
        </Providers>
      </body>
    </html>
  );
}
```

- [ ] **Step 2.8: Add env vars to .env.local.example**

Add to `apps/fieldops_web/.env.local.example` (or create if missing):

```
NEXT_PUBLIC_SENTRY_DSN=
NEXT_PUBLIC_POSTHOG_KEY=
NEXT_PUBLIC_POSTHOG_HOST=https://app.posthog.com
SENTRY_ORG=
SENTRY_PROJECT=
```

- [ ] **Step 2.9: Verify build succeeds**

```bash
cd apps/fieldops_web && npm run build
```

Expected: Build completes. Sentry may warn about missing DSN — this is OK (it's guarded by `enabled: !!dsn`).

- [ ] **Step 2.10: Commit**

```bash
cd apps/fieldops_web
git add sentry.client.config.ts sentry.server.config.ts next.config.ts \
  src/lib/posthog.ts src/app/providers.tsx src/app/layout.tsx \
  package.json package-lock.json
git commit -m "feat(web): add Sentry crash reporting and PostHog analytics"
```

---

## Task 3: Auto-Trigger Photo Stamping from media_finalize

**Files:**
- Modify: `infra/supabase/functions/media_finalize/index.ts`

**Context:** `media_finalize` creates the `photo_event` and stores idempotency but never calls `media_stamp`. Workers upload photos, photos are stored, but the proof stamp (SHA-256 + verification code + SVG overlay) never runs. This task adds a non-blocking `EdgeRuntime.waitUntil` call so stamping happens automatically after every successful finalize.

- [ ] **Step 3.1: Add the waitUntil stamp trigger**

In `infra/supabase/functions/media_finalize/index.ts`, find the line:

```typescript
    return jsonResponse(responseBody, 200, requestId, rateLimit.headers)
```

Replace it with:

```typescript
    // Trigger photo stamping asynchronously — non-blocking, does not affect response latency
    const stampUrl = `${supabaseUrl}/functions/v1/media_stamp`
    EdgeRuntime.waitUntil(
      fetch(stampUrl, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${supabaseServiceKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ media_asset_id }),
      }).then(async (res) => {
        if (!res.ok) {
          const body = await res.text()
          console.error(`media_stamp trigger failed (${res.status}): ${body}`)
        }
      }).catch((e) => {
        console.error("media_stamp trigger error:", e)
      })
    )

    return jsonResponse(responseBody, 200, requestId, rateLimit.headers)
```

- [ ] **Step 3.2: Test locally with supabase functions serve**

```bash
cd infra && supabase start && supabase functions serve
```

In a separate terminal, run the regression suite:

```bash
cd execution && python3 run_backend_regression_suite.py
```

Expected: All existing tests pass. No new failures.

- [ ] **Step 3.3: Verify stamp is created after finalize**

After the regression suite runs, check that `stamped_photo` records exist:

```bash
cd infra && supabase db connect --local
```

```sql
SELECT id, kind, verification_code, sync_status
FROM media_assets
WHERE kind = 'stamped_photo'
LIMIT 5;
```

Expected: Rows with `kind = 'stamped_photo'` and non-null `verification_code`.

- [ ] **Step 3.4: Commit**

```bash
git add infra/supabase/functions/media_finalize/index.ts
git commit -m "feat(backend): auto-trigger media_stamp after successful media_finalize"
```

---

## Task 4: Render Actual Photos with Signed URLs

**Files:**
- Modify: `apps/fieldops_web/src/app/photos/page.tsx`

**Context:** The photos page fetches `photo_events` with `media_assets` join but displays a `📸` emoji placeholder. Supabase Storage requires signed URLs to render private images. This task generates a signed URL for each raw photo after the initial fetch and replaces the placeholder with an `<img>` element.

- [ ] **Step 4.1: Add signedUrls state and generation to PhotoFeedContent**

In `apps/fieldops_web/src/app/photos/page.tsx`, find the `useState` declarations inside `PhotoFeedContent` and add:

```typescript
  const [signedUrls, setSignedUrls] = useState<Record<string, string>>({});
```

- [ ] **Step 4.2: Generate signed URLs after photos load**

In the `loadPhotos` function, after `setPhotos((data as unknown as PhotoEntry[]) ?? []);`, add:

```typescript
      // Generate signed URLs for actual photo display (1-hour expiry)
      const urlMap: Record<string, string> = {};
      const photoData = (data as unknown as PhotoEntry[]) ?? [];
      await Promise.allSettled(
        photoData.map(async (photo) => {
          const asset = photo.media_assets;
          if (!asset?.storage_path || !asset?.bucket_name) return;
          const { data: urlData } = await supabase.storage
            .from(asset.bucket_name)
            .createSignedUrl(asset.storage_path, 3600);
          if (urlData?.signedUrl) {
            urlMap[photo.id] = urlData.signedUrl;
          }
        })
      );
      setSignedUrls(urlMap);
```

- [ ] **Step 4.3: Replace the emoji placeholder with actual img**

Find the photo placeholder block:

```tsx
                <div className="relative bg-slate-100 p-6">
                  <div className="flex h-40 items-center justify-center text-4xl">
                    📸
                  </div>
```

Replace with:

```tsx
                <div className="relative bg-slate-100">
                  {signedUrls[photo.id] ? (
                    <img
                      src={signedUrls[photo.id]}
                      alt={`Photo by ${workerName}`}
                      className="h-48 w-full object-cover"
                      loading="lazy"
                    />
                  ) : (
                    <div className="flex h-48 items-center justify-center text-4xl bg-slate-100">
                      📸
                    </div>
                  )}
```

- [ ] **Step 4.4: Start dev server and verify photos render**

```bash
cd apps/fieldops_web && npm run dev
```

Open `http://localhost:3000/photos?job_id=<a-real-job-id>` in a browser.

Expected: Actual photo images render (not emoji). Photos without a signed URL (e.g. if storage is empty) fall back to emoji gracefully.

- [ ] **Step 4.5: Commit**

```bash
cd apps/fieldops_web
git add src/app/photos/page.tsx
git commit -m "feat(web): render actual photos via Supabase Storage signed URLs"
```

---

## Task 5: Replace Polling with Supabase Realtime

**Files:**
- Modify: `apps/fieldops_web/src/app/photos/page.tsx`
- Modify: `apps/fieldops_web/src/app/timeline/page.tsx`

**Context:** `photos/page.tsx` uses `setInterval(loadPhotos, 10000)` — polling every 10 seconds. `timeline/page.tsx` has no live updates at all. Both should use Supabase Realtime `postgres_changes` subscriptions so the supervisor sees events as they happen.

### 5a — Photos page Realtime

- [ ] **Step 5.1: Replace setInterval with Realtime subscription in photos/page.tsx**

Find and remove the current `useEffect` in `PhotoFeedContent`:

```typescript
  useEffect(() => {
    loadPhotos();
    const interval = setInterval(loadPhotos, 10000);
    return () => clearInterval(interval);
  }, [loadPhotos]);
```

Replace it with:

```typescript
  useEffect(() => {
    if (!jobId) return;

    loadPhotos();

    const supabase = getSupabase();
    const channel = supabase
      .channel(`photos-job-${jobId}`)
      .on(
        "postgres_changes",
        {
          event: "INSERT",
          schema: "public",
          table: "photo_events",
          filter: `job_id=eq.${jobId}`,
        },
        () => {
          loadPhotos();
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [jobId, loadPhotos]);
```

Also update the auto-refresh indicator text. Find:

```tsx
        {photos.length > 0 && (
          <p className="mt-1 text-sm text-slate-400">
            {photos.length} photos · Auto-refreshes every 10s
          </p>
        )}
```

Replace with:

```tsx
        {photos.length > 0 && (
          <p className="mt-1 text-sm text-slate-400">
            {photos.length} photos · Live updates enabled
          </p>
        )}
```

### 5b — Timeline page Realtime

- [ ] **Step 5.2: Add Realtime subscription to timeline/page.tsx**

Find the `useEffect` in `TimelineContent`:

```typescript
  useEffect(() => {
    loadTimeline();
  }, [jobId]);
```

Replace with:

```typescript
  useEffect(() => {
    if (!jobId) return;

    loadTimeline();

    const supabase = getSupabase();
    const channel = supabase
      .channel(`timeline-job-${jobId}`)
      .on(
        "postgres_changes",
        {
          event: "INSERT",
          schema: "public",
          table: "clock_events",
          filter: `job_id=eq.${jobId}`,
        },
        () => loadTimeline()
      )
      .on(
        "postgres_changes",
        {
          event: "INSERT",
          schema: "public",
          table: "photo_events",
          filter: `job_id=eq.${jobId}`,
        },
        () => loadTimeline()
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [jobId]);
```

- [ ] **Step 5.3: Verify Realtime works locally**

```bash
cd infra && supabase start
cd apps/fieldops_web && npm run dev
```

Open two browser tabs:
1. Tab 1: `http://localhost:3000/timeline?job_id=<job-id>`
2. Tab 2: Run a test clock-in via the regression suite or curl:

```bash
curl -X POST http://localhost:54321/functions/v1/sync_events \
  -H "Authorization: Bearer <worker-jwt>" \
  -H "Content-Type: application/json" \
  -H "Idempotency-Key: $(uuidgen)" \
  -d '{"batch_id":"test-1","clock_events":[{"id":"<uuid>","event_subtype":"clock_in","job_id":"<job-id>","occurred_at":"<iso-timestamp>","gps_lat":37.7749,"gps_lng":-122.4194,"gps_accuracy_m":5}]}'
```

Expected: Timeline in Tab 1 updates within 1–2 seconds without a page refresh.

- [ ] **Step 5.4: Commit**

```bash
cd apps/fieldops_web
git add src/app/photos/page.tsx src/app/timeline/page.tsx
git commit -m "feat(web): replace polling with Supabase Realtime subscriptions"
```

---

## Task 6: Remove Hardcoded Test Credentials from AuthGuard

**Files:**
- Modify: `apps/fieldops_web/src/components/auth-guard.tsx`

**Context:** `auth-guard.tsx` lines 12–13 have `supervisor@test.com` and `password123` as default field values. A supervisor visiting the production URL would see those pre-filled. Ship with empty fields.

- [ ] **Step 6.1: Clear default credential values**

In `apps/fieldops_web/src/components/auth-guard.tsx`, find:

```typescript
  const [email, setEmail] = useState("supervisor@test.com");
  const [password, setPassword] = useState("password123");
```

Replace with:

```typescript
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
```

- [ ] **Step 6.2: Verify login form still works**

```bash
cd apps/fieldops_web && npm run dev
```

Open `http://localhost:3000`, verify login form appears with empty fields. Sign in with `supervisor@test.com` / `password123` manually — should succeed.

- [ ] **Step 6.3: Commit**

```bash
cd apps/fieldops_web
git add src/components/auth-guard.tsx
git commit -m "fix(web): remove hardcoded test credentials from AuthGuard login form"
```

---

## Self-Review Checklist

**Spec coverage:**
- [x] Sentry in Flutter → Task 1
- [x] Sentry in Next.js → Task 2
- [x] PostHog in Next.js → Task 2
- [x] media_stamp auto-triggered → Task 3
- [x] Photos rendering with actual images → Task 4
- [x] Realtime for photos → Task 5a
- [x] Realtime for timeline → Task 5b
- [x] Remove hardcoded credentials → Task 6

**Placeholder scan:** No TBD, TODO, or "similar to above" patterns. All code blocks are complete.

**Type consistency:** `PhotoEntry`, `TimelineEvent`, `getSupabase()` are used as-is from existing code — no new types introduced, no renames.

**Gaps found during review:**
- Supabase Realtime requires tables to be in the `realtime` publication. Supabase hosted projects have this enabled by default for all tables. If running locally and Realtime doesn't fire, run: `ALTER PUBLICATION supabase_realtime ADD TABLE clock_events, photo_events;` as a migration.

---

## Environment Variables Summary

Before running in production, ensure these are set:

**Flutter (--dart-define):**
```
SENTRY_DSN=https://xxx@xxx.ingest.sentry.io/xxx
```

**Next.js (.env.local):**
```
NEXT_PUBLIC_SENTRY_DSN=https://xxx@xxx.ingest.sentry.io/xxx
NEXT_PUBLIC_POSTHOG_KEY=phc_xxxxx
NEXT_PUBLIC_POSTHOG_HOST=https://app.posthog.com
SENTRY_ORG=your-org
SENTRY_PROJECT=fieldops-web
```
