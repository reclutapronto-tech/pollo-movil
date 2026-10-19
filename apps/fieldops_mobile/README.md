# FieldOps Mobile

Worker mobile app for FieldOps AI.

## Hosted staging setup

This app reads Supabase config from Dart defines. The repo now generates those
defines from the root [`.env`](/Users/seancheick/FieldsOps_ai/.env) so web and mobile
stay on the same backend.

1. Put your hosted Supabase values in the repo root `.env`
2. Run:

```bash
cd /Users/seancheick/FieldsOps_ai
python3 scripts/sync_runtime_env.py
```

3. Start the app:

```bash
cd /Users/seancheick/FieldsOps_ai/apps/fieldops_mobile
flutter run --dart-define-from-file=env/staging.json
```

Optional:

```bash
flutter run --dart-define-from-file=env/staging.json --dart-define=SENTRY_DSN=...
```

## iPhone

1. Install Xcode and Flutter
2. Connect your iPhone with a cable
3. Open `ios/Runner.xcworkspace` in Xcode
4. Set your Apple Team under `Runner > Signing & Capabilities`
5. Run:

```bash
flutter devices
flutter run --dart-define-from-file=env/staging.json
```

## Android

1. Install Android Studio and the Android SDK
2. Enable Developer Options and USB debugging
3. Connect your Android phone
4. Run:

```bash
flutter devices
flutter run --dart-define-from-file=env/staging.json
```
