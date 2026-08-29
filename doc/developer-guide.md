# flutter_ota_kit — Developer Guide

`flutter_ota_kit` is a server-driven **over-the-air (OTA) hot-update toolkit for Flutter**
(Android). It lets you ship new Dart/Flutter code (`libapp.so` or a v2 `patch.zip`)
to installed apps without going through the store, with built-in crash protection,
rollback, and **zero-click forced updates** that restart the app automatically.

The toolkit has three layers:

1. **SDK** (`flutter_ota_kit`) — the Dart API your app calls.
2. **CLI** (`flutter-ota`, npm `@_nazmiforreal/flutter-ota`) — build patches, deploy
   them, provision backends, and scaffold projects.
3. **Backend plugins** — Supabase, Postgres, Cloudflare (D1+R2), and AWS (S3).
   The CLI talks to these directly; no separate server process is required.

---

## Table of Contents
- [Installation](#installation)
- [Project setup with `flutter-ota init`](#project-setup-with-flutter-ota-init)
- [Provisioning the backend (`flutter-ota migrate`)](#provisioning-the-backend)
- [Building a patch](#building-a-patch)
- [Deploying a patch](#deploying-a-patch)
- [The SDK API](#the-sdk-api)
- [Zero-click forced updates](#zero-click-forced-updates)
- [Update targeting (channel / platform / strategy)](#update-targeting)
- [Crash protection, rollback & blacklist](#crash-protection-rollback--blacklist)
- [Troubleshooting](#troubleshooting)
- [Configuration](configuration.md)

---

## Installation

### CLI
```bash
npm install -g @_nazmiforreal/flutter-ota
# gives you the `flutter-ota` command
flutter-ota --help
```
The CLI ships a prebuilt Linux x64 binary and falls back to compiling the bundled
Dart source (`dart compile exe`) on other platforms/architectures (macOS, Windows, arm64)
when no prebuilt matches.

### SDK
Add it to your app's `pubspec.yaml` (the `flutter-ota init` command does this for you):
```yaml
dependencies:
  flutter_ota_kit: ^0.1.4
```

---

## Project setup with `flutter-ota init`

`init` does **not** generate a full app template. It scaffolds the exact files your
project needs to talk to a backend, and stores all CLI state under a single `.flutter_ota_kit/`
directory (so you can git-ignore it as one unit).

```bash
flutter-ota init supabase
# also: postgres | cloudflare | aws
# positional backend is equivalent to --provider supabase
```

For each backend, `init`:

1. writes `.flutter_ota_kit/config.json` (the CLI's working state — including the
   service-role / management keys `migrate` and `deploy` need — so it is
   git-ignored automatically),
2. writes a `.env` scaffold at the project root (git-ignored) holding the **app-side
   secrets** (anon key, DB password, R2/AWS keys, tokens). Fill these in — the app
   reads them at build time via `--dart-define-from-file=.env`. See
   [Configuration](configuration.md),
3. adds `flutter_ota_kit:` to `pubspec.yaml` if missing,
4. adds the `INTERNET` permission to `android/app/src/main/AndroidManifest.xml`
   (the auto-init `ContentProvider` is merged in automatically by the plugin — you
   do **not** need to edit `Application`),
5. generates `lib/flutter_ota_kit_setup.dart` that wires your backend (from
   environment) and enables zero-click forced updates.

> The Android native package id stays `com.flutter_patcher...` — that is the plugin's
> own package and is intentionally unchanged.

### Wire it into `main()`
Call the generated `setupFlutterOta()` once, after
`WidgetsFlutterBinding.ensureInitialized()` and **before** `runApp()`:

```dart
import 'package:flutter_ota_kit/flutter_ota_kit.dart';
import 'flutter_ota_kit_setup.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupFlutterOta(); // configures backend + enables forced auto-restart
  runApp(const MyApp());
}
```

The generated `lib/flutter_ota_kit_setup.dart` looks like this for Supabase:

```dart
import 'dart:io' show Platform;
import 'package:flutter_ota_kit/flutter_ota_kit.dart';

Future<void> setupFlutterOta() async {
  FlutterPatcher.configureSupabase(SupabaseUpdateConfig(
    supabaseUrl: const String.fromEnvironment('SUPABASE_URL', defaultValue: ''),
    anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: ''),
    bucket: const String.fromEnvironment('SUPABASE_BUCKET', defaultValue: 'bundles'),
    channel: const String.fromEnvironment('CHANNEL', defaultValue: 'production'),
    platform: Platform.android,
    updateStrategy: UpdateStrategy.appVersion,
    appVersion: const String.fromEnvironment('APP_VERSION', defaultValue: '1.0.0'),
    sdkVersion: const String.fromEnvironment('SDK_VERSION', defaultValue: '1.0.0'),
  ));
  await FlutterPatcher.init(autoApplyUpdates: true);
}
```

> The setup file contains **only** `String.fromEnvironment` reads — no secrets. Put
> the real values in `.env` and build/run with `--dart-define-from-file=.env` (or
> let `init` + the SDK auto-detect them). Full list of variables per backend:
> [Configuration](configuration.md).

---

## Provisioning the backend

```bash
flutter-ota migrate supabase
```

| Backend     | What `migrate` does                                                                 |
|-------------|-------------------------------------------------------------------------------------|
| `supabase`  | **Full setup**: runs all SQL migrations, creates the `bundles` table + RPCs, and creates the public `bundles` storage bucket. |
| `postgres`  | Prints the SQL you must run against your Postgres database.                          |
| `cloudflare`| Prints the `wrangler` commands to create the D1 database and R2 bucket.             |
| `aws`       | Prints the AWS CLI / Terraform steps for the S3 bucket + DB.                        |

For Supabase the command reads credentials from `.flutter_ota_kit/config.json` (or
`SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` env vars) and performs the full
migration. The other backends only emit the commands you run manually because
they require cloud-provider credentials/CLIs the CLI cannot safely drive.

---

## Building a patch

A patch is built from a **Flutter build** of your app and then diffed into a
`patch.zip`:

```bash
# 1. Build the APK / app bundle for the target ABI
flutter build apk --release

# 2. Pack it into a patch (uses the current app version as the patch version)
flutter-ota build --name 1.0.1 --platform android --arch x86_64
# outputs dist/patch.zip
```

You can also use the SDK helper directly:

```bash
dart run flutter_ota_kit:pack --name 1.0.1 --platform android --arch x86_64 --source build/app/outputs/flutter-apk/
```

The build artifacts are written to `dist/` by default (configurable via the
`source` field in `.flutter_ota_kit/config.json`).

---

## Deploying a patch

```bash
flutter-ota deploy \
  --backend supabase \
  --source dist/patch.zip \
  --channel production \
  --platform android \
  --target-app-version 1.0.0 \
  --force \
  --message "critical fix"
```

Flags:
- `--channel` — which channel the bundle belongs to (e.g. `production`, `staging`).
- `--platform` — `android` (currently the only supported platform).
- `--target-app-version` — the native app version this bundle applies to.
- `--force` — mark the bundle as **forced** (the app must apply + restart immediately).
- `--message` — human-readable note stored alongside the bundle.

Deploying without `--force` still publishes the bundle; the SDK will stage it and
apply it on the **next cold start** (non-forced).

---

## The SDK API

All calls go through the `FlutterPatcher` class.

```dart
// 1. Configure a backend (once, before init / checkForUpdate)
FlutterPatcher.configureSupabase(SupabaseUpdateConfig(/* ... */));

// 2. Initialize (idempotent; sets up crash protection)
await FlutterPatcher.init();

// 3. Check for an update
final result = await FlutterPatcher.checkForUpdate();
if (result.hasUpdate) {
  // 4. Apply it. auto-restarts ONLY when result.shouldForceUpdate is true.
  final applied = await FlutterPatcher.applyUpdate(result);
}

// Lower-level primitives
await FlutterPatcher.applyPatch(patchInfo);   // stage a payload
await FlutterPatcher.restart();               // restart the process now
final v = await FlutterPatcher.currentVersion;// installed patch version
await FlutterPatcher.rollback();              // delete current patch
final list = await FlutterPatcher.blacklist;  // bad-patch blacklist
```

`applyUpdate(result)` is sugar for `applyPatch(result.patch)` followed by
`restart()` **only if** `result.shouldForceUpdate`. Non-forced updates are staged
and take effect on the next normal launch.

---

## Zero-click forced updates

A **forced** bundle should apply and restart with **no user tap**. Two ways to wire it:

### Option A — `init(autoApplyUpdates: true)` (recommended)
```dart
await FlutterPatcher.init(autoApplyUpdates: true);
```
After boot protection is set up, the SDK fires `checkAndApplyUpdates()` in the
background: it checks for an update and, if a forced one exists, downloads, stages,
and restarts the process automatically.

### Option B — call `checkAndApplyUpdates()` yourself
```dart
await FlutterPatcher.checkAndApplyUpdates(
  onProgress: (p) => print('[${p.phase.name}]'),
);
```
Call this once at startup (e.g. right after `init`).

### Loop guard
`checkAndApplyUpdates()` **skips** an update when the returned patch version already
equals `FlutterPatcher.currentVersion`. This prevents the app from re-downloading and
re-restarting on every launch once it is already on the latest bundle.

> Note: the backend's `get_update_info` RPC always returns the latest *enabled*
> bundle for the channel/platform. The loop guard is what keeps a forced update from
> re-applying forever.

---

## Update targeting

Bundles are selected by:
- **channel** (`production`, `staging`, …)
- **platform** (`android`)
- **update strategy**:
  - `UpdateStrategy.appVersion` — target by the host app's `appVersion`
    (e.g. `1.0.0`). Bundles carry a `targetAppVersion`.
  - `UpdateStrategy.fingerprint` — target by a build fingerprint hash baked at
    build time (`kBuildFingerprintHash`).
- **cohort** — optional subset of users.

The `checkForUpdate()` call passes the device's current patch version (used by the
loop guard) and the configured targeting, and returns the newest matching enabled
bundle. `shouldForceUpdate` is true only when that bundle was deployed with `--force`.

---

## Crash protection, rollback & blacklist

- **Crash protection**: after `init`, the SDK watches the first frame. If a freshly
  loaded patch crashes during early boot (or fails md5/signature checks), the SDK
  rolls back to the previous state and blacklists that payload (`maxCrashCount`,
  default `1`).
- **Rollback**: `FlutterPatcher.rollback()` removes the current patch; the next cold
  start uses the APK's built-in code. This is a manual rollback and does **not**
  blacklist.
- **Blacklist**: `FlutterPatcher.blacklist` exposes the entries recorded for early
  boot failures, cold-start md5 mismatches, and cold-start signature failures.

---

## Troubleshooting

- **Update never applies** → ensure `INTERNET` permission is present and
  `setupFlutterOta()` / `configureX()` runs before `runApp()`.
- **Forced update doesn't restart** → you must call `init(autoApplyUpdates: true)` or
  `checkAndApplyUpdates()`. A forced update only auto-restarts through `applyUpdate` /
  `checkAndApplyUpdates`; a plain `applyPatch` only stages.
- **App re-downloads the same forced bundle repeatedly** → the loop guard compares
  patch *version*; make sure each deployed bundle has a distinct `--name`/version.
- **"No update available"** → verify the backend was provisioned (`flutter-ota migrate`
  for Supabase does the full setup; others need the printed commands run manually),
  the channel/platform/targetAppVersion match, and the bundle is `enabled`.
- **CLI can't find config** → `flutter-ota` reads `.flutter_ota_kit/config.json` in the current
  directory (or `~/.flutter_ota_kit/config.json` with `--global`).
- **pub.dev publish fails on name** → the published package name is `flutter_ota_kit`
  (the npm CLI command remains `flutter-ota`).
