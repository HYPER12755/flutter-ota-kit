# Getting Started (5 minutes)

This walks through taking a fresh Flutter app from zero to a live OTA update using
`flutter_ota_kit` + the `flutter-ota` CLI. Pick **one** backend — Supabase, Postgres,
Cloudflare, or AWS.

## 1. Install the SDK + CLI
```bash
# Flutter package — the OTA runtime your app depends on
flutter pub add flutter_ota_kit

# CLI — builds patches and deploys them to your backend
npm install -g @_nazmiforreal/flutter-ota
flutter-ota --help
```

## 2. Scaffold your project
From the root of your Flutter app, choose your backend:
```bash
flutter-ota init supabase      # also: postgres | cloudflare | aws
```
This:
- writes `.flutter_ota_kit/config.json` (git-ignored, may contain secrets),
- ensures `flutter_ota_kit:` is present in `pubspec.yaml` (you can also add it manually with `flutter pub add flutter_ota_kit`),
- adds the `INTERNET` permission to `android/app/src/main/AndroidManifest.xml`,
- generates `lib/flutter_ota_kit_setup.dart` (wires your backend + forced auto-restart).

```bash
flutter pub get
```

## 2b. Fill in `.env`

`init` also wrote a `.env` scaffold at your project root. Put your backend
secrets there (e.g. `SUPABASE_URL`, `SUPABASE_ANON_KEY`) — it is git-ignored
automatically. The app reads them at build time via `--dart-define-from-file=.env`:

```bash
# dev
flutter run --dart-define-from-file=.env

# release APK for device / E2E
flutter build apk --release --target-platform android-x64 \
  --dart-define-from-file=.env
```

All configurable values resolve as: **environment (`.env` / `--dart-define`) →
`.flutter_ota_kit/config.json` → built-in defaults**. Environment wins, so
secrets never get committed. Full reference: [configuration.md](configuration.md).

## 3. Wire `main.dart`
```dart
import 'package:flutter/material.dart';
import 'package:flutter_ota_kit/flutter_ota_kit.dart';
import 'flutter_ota_kit_setup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupFlutterOta();          // configures backend + forced auto-restart
  runApp(const MyApp());
}
```

## 4. Provision the backend
`init` wrote your backend choice; now provision it.

- **Supabase** — fully automated:
  ```bash
  flutter-ota migrate supabase
  ```
- **Postgres** — prints SQL to run against your database:
  ```bash
  flutter-ota migrate postgres
  ```
- **Cloudflare** — prints `wrangler` commands (D1 + R2):
  ```bash
  flutter-ota migrate cloudflare
  ```
- **AWS** — prints S3 + DB setup (AWS CLI / Terraform):
  ```bash
  flutter-ota migrate aws
  ```

Per-backend credentials, env vars, and device-side `configureX` snippets are in
[backends.md](backends.md).

## 5. Build a patch
```bash
flutter build apk --release
flutter-ota build --name 1.0.1 --platform android --arch x86_64
# -> dist/patch.zip
```

## 6. Deploy it
```bash
# Non-forced: staged, applies on next launch
flutter-ota deploy --backend supabase --source dist/patch.zip \
  --channel production --platform android --target-app-version 1.0.0

# Forced: applies + auto-restarts the app immediately (zero clicks)
flutter-ota deploy --backend supabase --source dist/patch.zip \
  --channel production --platform android --target-app-version 1.0.0 --force
```
(Replace `supabase` with your chosen backend. Short flags also work:
`-b` backend, `-c` channel, `-f` force, `-s` source, `-k` key.)

## 7. Watch it land
- **Non-forced**: the next time the user opens the app (cold start) the new code is active.
- **Forced**: `init(autoApplyUpdates: true)` (set by `setupFlutterOta`) checks on launch,
  downloads, and restarts the process automatically — no button required.

## Next
- Full reference: [developer-guide.md](developer-guide.md)
- Per-backend details: [backends.md](backends.md)
