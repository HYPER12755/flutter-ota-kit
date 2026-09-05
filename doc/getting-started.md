# Getting Started — 5 minutes to a working OTA

This is the **fast path**: the smallest possible set of commands to get a
real OTA update working end-to-end. If you get stuck, the
[Beginner Guide](beginner-guide.md) has the same flow with every step
explained.

**Prerequisites:** Flutter 3.47+, an Android device or emulator, a
backend of your choice (Supabase / Postgres / Cloudflare / AWS /
PocketBase). The example below uses Supabase — substitute your backend's
creds and command names for the others.

---

## 1. Install

```bash
# Runtime SDK (the package your app depends on)
flutter pub add flutter_ota_kit

# CLI (builds patches + deploys to your backend)
npm install -g @_nazmiforreal/flutter-ota

flutter-ota --version
```

**Troubleshoot:** if `flutter-ota` says "command not found", your
`npm bin -g` isn't on `$PATH`. The `npm install` output prints the
exact export line.

---

## 2. Scaffold your project

From your Flutter app root:

```bash
flutter-ota init supabase      # also: postgres | cloudflare | aws | pocketbase
```

This writes `.flutter_ota_kit/config.json`, `.env` (git-ignored), and
`lib/flutter_ota_kit_setup.dart`. Adds `INTERNET` to your
`AndroidManifest.xml`. Adds `.flutter_ota_kit/` and `.env` to
`.gitignore`.

---

## 3. Fill in `.env`

```bash
# .env  (git-ignored)
SUPABASE_URL=https://your-project-ref.supabase.co
SUPABASE_ANON_KEY=sb_publishable_xxxxxxxxxxxxxxxxxxxxxxxxxxxx
CHANNEL=production
APP_VERSION=1.0.0
```

Every value is read via `String.fromEnvironment(...)` in the generated
`lib/flutter_ota_kit_setup.dart`. Build with `--dart-define-from-file=.env`
so they reach the compiled app.

**The service-role key is CLI-only.** Never put it in `.env`. Export it
in your shell when you run `migrate` / `deploy`:

```bash
export SUPABASE_SERVICE_ROLE_KEY=sb_secret_xxxxxxxx
```

---

## 4. Wire `main.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_ota_kit/flutter_ota_kit.dart';
import 'flutter_ota_kit_setup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupFlutterOta();
  runApp(const FlutterOtaApp(child: MyApp()));
}
```

`setupFlutterOta()` calls `FlutterPatcher.configureSupabase(...)` (or
whichever backend you picked) with the values from `.env` /
`--dart-define`, then `FlutterPatcher.init(autoApplyUpdates: true)`.
`FlutterOtaApp` is the zero-code wrapper that lets the SDK show the
forced-update progress overlay.

Disable the overlay with `FlutterPatcher.showUpdateUi = false` if you
want to draw your own UI.

---

## 5. Provision the backend

```bash
# Supabase: fully automated
SUPABASE_SERVICE_ROLE_KEY=sb_secret_xxx flutter-ota migrate supabase

# Postgres: prints SQL
flutter-ota migrate postgres

# Cloudflare: prints wrangler commands
flutter-ota migrate cloudflare

# AWS: prints S3 + DynamoDB / RDS commands
flutter-ota migrate aws

# PocketBase: downloads PB + installs schema
flutter-ota pocketbase install
flutter-ota pocketbase serve --admin-email a@b.c --admin-password pw
```

**Troubleshoot:** `flutter-ota doctor` prints the channel list when
the backend is reachable. If it says "unreachable", your env vars
are wrong or the network blocked the connection.

---

## 6. Build, pack, deploy

```bash
# 1. Build the release APK with secrets injected
flutter build apk --release --target-platform android-x64 \
  --dart-define-from-file=.env

# 2. Pack the diff against the baseline (versionCode is from pubspec.yaml)
flutter-ota build --name 1.0.1 --platform android --arch x86_64

# 3. Push to your backend
export SUPABASE_SERVICE_ROLE_KEY=sb_secret_xxx   # CLI only
flutter-ota deploy -b supabase -s dist -c production -p android \
  --target-app-version 1.0.0 --force -m "first hot fix"
```

The `--force` flag makes it apply + auto-restart the app on the user's
device (zero clicks). Drop it for staged rollouts where you want the
update to land organically on the next cold start.

---

## 7. Watch it land

Open the app on the device. You'll see:

1. The current version (e.g. `1.0.0`).
2. The SDK checks for an update on launch (no UI).
3. It finds `1.0.1` as a forced bundle, downloads, stages.
4. The app restarts automatically — no button press.
5. The new code is now active.

**Verify on the device:**

```bash
adb logcat | grep -i flutter
```

You should see something like:

```
[FlutterPatcher] checkForUpdate: forced update available (1.0.1)
[FlutterPatcher] applyUpdate: patch 1.0.1 staged, restarting…
```

If you see "no update" instead, the most common reason is
`--target-app-version` not matching the user's `pubspec.yaml` `version:`
field. See [FAQ](faq.md#how-does-the-client-report-its-app-version-and-why-must-it-match---target-app-version-).

---

## Next

- **Stuck?** → [Beginner Guide](beginner-guide.md) has the same flow with
  every step explained + a "mistakes Sam made" section.
- **Reference** → [Developer Guide](developer-guide.md) covers the full
  workflow with troubleshooting.
- **Per-backend** → [Backends](backends.md) has setup for Supabase /
  Postgres / Cloudflare / AWS / PocketBase side-by-side.
- **Production** → [Production Playbook](production-playbook.md) covers
  staged rollouts, diagnostic reporting, and emergency rollback.
- **API** → [API Reference](api-reference.md) for every `FlutterPatcher`
  method, error codes, and asset-patching syntax.
