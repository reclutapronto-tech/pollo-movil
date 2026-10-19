#!/bin/bash
# Build FieldOps Mobile for release distribution (TestFlight / Play Store)
# Usage:
#   ./scripts/build_release.sh ios      → builds .ipa for TestFlight
#   ./scripts/build_release.sh android  → builds .aab for Play Store
#   ./scripts/build_release.sh both     → builds both
#
# Prerequisites:
#   iOS:     Xcode + valid provisioning profile + Apple Developer account
#   Android: Java 17 + keystore configured in android/key.properties
#
# Set these env vars before running (or add to a local .env.release file):
#   SUPABASE_URL       - your Supabase project URL
#   SUPABASE_ANON_KEY  - your Supabase anon key
#   SENTRY_DSN         - your Sentry project DSN (optional but recommended)

set -e

export PATH="$PATH:/Users/seancheick/development/flutter/bin"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/../apps/fieldops_mobile"

# Load local env if it exists
if [ -f "$SCRIPT_DIR/../.env.release" ]; then
  set -a
  source "$SCRIPT_DIR/../.env.release"
  set +a
  echo "✓ Loaded .env.release"
fi

if [ -z "$SUPABASE_URL" ] || [ -z "$SUPABASE_ANON_KEY" ]; then
  echo "ERROR: SUPABASE_URL and SUPABASE_ANON_KEY must be set."
  echo "Create .env.release in project root (see .env.release.example)"
  exit 1
fi

cd "$PROJECT_DIR"
flutter pub get

DART_DEFINES="--dart-define=SUPABASE_URL=$SUPABASE_URL \
  --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY"

if [ -n "$SENTRY_DSN" ]; then
  DART_DEFINES="$DART_DEFINES --dart-define=SENTRY_DSN=$SENTRY_DSN"
fi

TARGET=${1:-ios}

build_ios() {
  echo ""
  echo "► Building iOS release (ipa)..."
  flutter build ipa \
    --release \
    $DART_DEFINES
  echo "✓ iOS build complete: build/ios/ipa/fieldops_mobile.ipa"
  echo ""
  echo "Next steps:"
  echo "  1. Open Xcode → Organizer → Distribute App → TestFlight"
  echo "  OR: xcrun altool --upload-app --type ios -f build/ios/ipa/*.ipa"
}

build_android() {
  echo ""
  echo "► Building Android release (aab)..."
  flutter build appbundle \
    --release \
    $DART_DEFINES
  echo "✓ Android build complete: build/app/outputs/bundle/release/app-release.aab"
  echo ""
  echo "Next steps:"
  echo "  Upload app-release.aab to Google Play Console → Internal Testing"
}

case "$TARGET" in
  ios)     build_ios ;;
  android) build_android ;;
  both)    build_ios && build_android ;;
  *)
    echo "Usage: $0 [ios|android|both]"
    exit 1
    ;;
esac
