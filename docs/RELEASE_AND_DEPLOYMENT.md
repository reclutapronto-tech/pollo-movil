# Release and deployment preparation

This guide describes a future release path. The repository workflows do not
deploy, and no production environment or credential is configured by CI.

## Environment variables

Never commit a real .env file, service token, private key, or service-account
JSON. Store deployment credentials in the destination platform's secret store.

- Next.js on Vercel: NEXT_PUBLIC_SUPABASE_URL and
  NEXT_PUBLIC_SUPABASE_ANON_KEY are browser-visible configuration. Optional
  public integrations are NEXT_PUBLIC_MAPTILER_KEY,
  NEXT_PUBLIC_SENTRY_DSN, NEXT_PUBLIC_POSTHOG_KEY, and
  NEXT_PUBLIC_POSTHOG_HOST. Do not put SUPABASE_SERVICE_ROLE_KEY or
  TIMEFOLD_SERVICE_TOKEN in a NEXT_PUBLIC_ variable or in Vercel's browser
  environment.
- Supabase Edge Functions: configure SUPABASE_URL, SUPABASE_ANON_KEY, and
  SUPABASE_SERVICE_ROLE_KEY as function runtime secrets. For restaurant
  assignment, also configure TIMEFOLD_SERVICE_URL and TIMEFOLD_SERVICE_TOKEN.
  CRON_SECRET, FIREBASE_SERVICE_ACCOUNT_JSON, and SENTRY_DSN are only needed by
  the corresponding enabled functions.
- Flutter Android/iOS: pass SUPABASE_URL and the public SUPABASE_ANON_KEY using
  --dart-define; optional error reporting uses SENTRY_DSN. The service-role key
  must never be included in a mobile build.
- Timefold on Render: configure TIMEFOLD_API_TOKEN as a private service
  environment variable. TIMEFOLD_SOLVER_TIME_LIMIT is optional and defaults
  in the service. The API listens on port 8080. If Supabase-hosted Edge
  Functions call a Render-hosted service, use its HTTPS endpoint and the bearer
  token; Render private networking is not automatically shared with Supabase.

## Vercel — web

1. Create a Vercel project from the private pollo-movil repository and set the
   project root to apps/fieldops_web.
2. Use the committed npm lockfile (npm ci) and the existing npm run build
   build command.
3. Add the required public Supabase URL and anon key for the target Supabase
   environment. Add optional public integration values only if enabled.
4. Deploy a preview first and verify login, protected restaurant routes, and
   live data access before promoting it. No Vercel project is linked by CI.

## Supabase — hosted backend

1. Provision a separate Supabase project for the intended environment.
2. Review migrations and environment settings, then link the local CLI to that
   project using its project reference and a separately stored access token.
3. Apply reviewed migrations and deploy only the required Edge Functions.
4. Set function secrets in the Supabase secret store, including the
   service-role key and Timefold token. Keep CI pointed at its local,
   disposable Supabase stack.
5. Verify Auth redirects, RLS, Storage policies, Realtime, and function-to-
   solver connectivity against the target environment before any production
   data is loaded.

## Render — Timefold service

1. Create a Docker-based service from the repository and use
   infra/timefold/Dockerfile.
2. Configure TIMEFOLD_API_TOKEN using Render's secret environment settings;
   never use the local compose default or commit a token.
3. Keep the service HTTPS-protected and ensure the Supabase Edge Function can
   reach it. The solver's bearer-token check remains enabled.
4. Configure TIMEFOLD_SERVICE_URL and the matching
   TIMEFOLD_SERVICE_TOKEN in the Supabase function secrets, then verify an
   authenticated assignment before routing operational traffic.

## Android

On a release workstation with the Android SDK and signing material configured:

    cd apps/fieldops_mobile
    flutter pub get --enforce-lockfile
    flutter build appbundle --release \
      --dart-define=SUPABASE_URL="$SUPABASE_URL" \
      --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"

Protect the Android signing key and its passwords in a release system, not in
GitHub Actions test jobs or the repository. The current CI builds a debug APK
and exercises the app on an emulator; it does not create a signed store bundle.

## iOS

On macOS with Xcode, an Apple developer signing setup, and the intended bundle
identifier configured:

    cd apps/fieldops_mobile
    flutter pub get --enforce-lockfile
    flutter build ipa --release \
      --dart-define=SUPABASE_URL="$SUPABASE_URL" \
      --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"

Keep certificates, provisioning profiles, and signing passwords in the release
system. Current CI builds an unsigned simulator app and runs its smoke test; it
does not sign or submit an App Store build.
