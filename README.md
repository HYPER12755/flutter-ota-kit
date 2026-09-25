# flutter_ota_kit

[![pub package](https://img.shields.io/pub/v/flutter_ota_kit.svg)](https://pub.dev/packages/flutter_ota_kit)
[![Platform](https://img.shields.io/badge/platform-Android-brightgreen)](https://flutter.dev)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

### Ship Dart & asset hotfixes over the air. Your backend. No store review. No monthly bill.

**flutter_ota_kit** is open-source code push for **Flutter Android**. Push a bug
fix or a new screen, and your users get it on the next cold start — no Play
Store round-trip, no vendor lock-in, no per-seat pricing. The patch lives on
**your** infrastructure (Supabase, Postgres, Cloudflare, AWS S3, PocketBase, or
your own CDN), signed and integrity-checked, with automatic crash rollback if
anything goes wrong.

If you've used [Shorebird](https://shorebird.dev/),
[CodePush](https://learn.microsoft.com/en-us/appcenter/distribution/codepush/),
or [Expo EAS Update](https://docs.expo.dev/eas-update/introduction/), this is the
same idea for Flutter Android — MIT-licensed, self-hosted, and yours to keep.

![Feature demo: apply a patch, cold restart, and rollback](doc/feature-presentation.gif)

```yaml
dependencies:
  flutter_ota_kit: ^0.2.0   # one package — every backend included
```

> **v0.2.0 is a single package.** Everything — the device SDK plus all five
> backends — now ships inside `flutter_ota_kit`. There are no more
> `flutter_ota_kit_supabase` / `_postgres` / `_cloudflare` / `_aws` /
> `_pocketbase` packages to add. One import, one dependency.

---

## Why teams pick it

- **You own the pipeline.** Patches sit in your Supabase project, your S3
  bucket, your Cloudflare account — not someone else's cloud. No third party
  sees your code or your users.
- **Zero recurring cost.** MIT-licensed. The only bill is your own storage,
  which for OTA payloads is pennies.
- **Ships in one dependency.** Add `flutter_ota_kit`, run `flutter-ota init`,
  deploy. Five backends are built in; you configure the one you use.
- **Safe by default.** MD5 + Ed25519 verification, automatic crash rollback,
  a bad-patch blacklist, and staged rollouts — all on by default.
- **Zero-code forced-update UI.** Opt in and the SDK renders a polished
  full-screen install progress screen for you. Write no UI.

---

## How it compares

|                          | flutter_ota_kit                                          | Shorebird                     | CodePush (React Native)      |
|--------------------------|----------------------------------------------------------|-------------------------------|------------------------------|
| **Framework**            | Flutter                                                  | Flutter                       | React Native                 |
| **Platforms**            | Android                                                  | Android + iOS                 | Android + iOS (retired 2025) |
| **Hosting**              | Your backend / your CDN — see [Backends](doc/backends.md) | Shorebird cloud (managed)     | AppCenter cloud (deprecated) |
| **Update scope**         | Dart AOT + Flutter assets                                | Dart code (engine-level diff) | JS bundle                    |
| **Takes effect**         | Next cold start                                          | Next restart                  | Next restart                 |
| **Cost**                 | Free (MIT) — you pay only your own storage               | Free tier + paid plans        | —                            |
| **Backend flexibility**  | Supabase / Postgres / Cloudflare / AWS / PocketBase / BYO CDN | Cloud-managed only       | —                            |
| **Forced updates**       | Yes — built-in progress UI                               | Yes                           | Yes                          |
| **Crash rollback**       | Automatic + bad-patch blacklist                          | Yes                           | Yes                          |
| **Signing**              | Ed25519 (Android 13+) + MD5                              | Yes                           | —                            |

**Choose Shorebird** if you need iOS today or want a fully managed cloud.

**Choose flutter_ota_kit** if you want OTA on infrastructure you control —
enterprise apps, regional distribution, air-gapped deployments, or non-Play
channels. Bring your own backend, CDN, and auth.

> Google Play and some stores restrict downloading executable code at runtime.
> flutter_ota_kit targets self-controlled, enterprise, or permissive
> distribution channels. Verify your channel's policy before shipping.

---

## Features

- **OTA code push** — replaces the Dart AOT `libapp.so` and Flutter assets on
  the next cold start, with MD5 + Ed25519 integrity checks.
- **Five backends, built in** — Supabase (fully automated), Postgres,
  Cloudflare (D1 + R2), AWS (S3 + optional CloudFront), and **PocketBase**
  (single-binary, self-hosted). Or point at your own CDN.
- **Automatic crash rollback** — a patch that fails to boot is rolled back and
  blacklisted so it's never retried. Tunable via `maxCrashCount` /
  `verifyAfter`. A runtime crash *hours* after a healthy boot no longer reverts
  a good patch (bounded crash-attribution window).
- **Forced updates with a built-in UI** — set `autoApplyUpdates: true` and wrap
  your app in `FlutterOtaApp`; the SDK shows a full-screen terminal-style
  install screen (steps, live progress bar, speed/ETA, server message) and
  cold-restarts into the new build. You write no UI.
- **Staged rollout** — server-side cohort math (per-mille + target cohorts) lets
  you ship 1% → 5% → 20% → 50% → 100% safely.
- **Batteries-included tooling** — the `flutter-ota` CLI (`init`, `build`,
  `deploy`, `bundle`, `channel`, `rollback`, `migrate`, `doctor`, and a bundled
  PocketBase manager), plus runtime diagnostics and a sample app.

---

## Try it in 5 minutes (no server needed)

```bash
git clone https://github.com/HYPER12755/flutter-ota-kit.git
cd flutter-ota-kit/example
flutter pub get
flutter build apk --release
flutter install
```

1. Launch the app — it shows the **original** demo screen.
2. Tap **Apply patch**.
3. Swipe the app away from recents and reopen.
4. The screen has changed — the patch took effect.
5. Tap **Rollback** → restart → the original is back.

The example bundles a precompiled patch; everything runs offline on the device.
For a full backend walkthrough, see the [Beginner Guide](doc/beginner-guide.md)
or [Getting Started](doc/getting-started.md).

---

## Requirements

| Item                     | Requirement                                              |
|--------------------------|----------------------------------------------------------|
| **Platform**             | Android only (iOS / macOS / Windows / Linux / Web are no-ops) |
| **Dart SDK**             | `>=3.13.2 <4.0.0`                                        |
| **Flutter**              | `>=3.47.2`                                               |
| **Android `minSdk`**     | 24                                                       |
| **Android `compileSdk`** | 36                                                       |
| **ABI**                  | `armeabi-v7a` / `arm64-v8a` / `x86_64`                   |
| **NDK**                  | 27.0.12077973+                                          |
| **Java / JVM**           | 17                                                       |

On non-Android platforms every API is safe to call but is a **no-op** — the
plugin logs a one-time warning and returns safe defaults, so you can ship
`flutter_ota_kit` in cross-platform code without guarding every call site.

---

## Quick start

### 1. Install

```yaml
dependencies:
  flutter_ota_kit: ^0.2.0
```

### 2. Scaffold your backend (CLI)

```bash
# installs the flutter-ota CLI globally
npm i -g @_nazmiforreal/flutter-ota

# scaffold config + a generated setup file for your backend
flutter-ota init supabase   # or: postgres | cloudflare | aws | pocketbase
```

`init` writes a `.flutter_ota_kit/config.json`, an `.env` template for secrets,
and a `lib/flutter_ota_kit_setup.dart` helper you call from `main()`.

### 3. Initialize in your app

Call the generated `setupFlutterOta()` (or wire it by hand) before `runApp`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_ota_kit/flutter_ota_kit.dart';
import 'flutter_ota_kit_setup.dart'; // generated by `flutter-ota init`

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupFlutterOta();               // configures the backend + forced updates
  runApp(const FlutterOtaApp(child: MyApp()));
}
```

`FlutterOtaApp` is the zero-code wrapper that lets the SDK render its built-in
forced-update screen. Disable it app-wide with
`FlutterPatcher.showUpdateUi = false` (or `FlutterOtaApp(showUpdateUi: false)`),
or host it yourself by setting `MaterialApp.navigatorKey =
FlutterPatcher.navigatorKey`.

Prefer wiring the backend directly? Every backend has a `configureX` helper:

```dart
FlutterPatcher.configureSupabase(SupabaseUpdateConfig(
  supabaseUrl: 'https://<ref>.supabase.co',
  anonKey: '<anon-key>',            // public, RLS-protected reads
  bucket: 'bundles',
  channel: 'production',
  platform: Platform.android,
  updateStrategy: UpdateStrategy.appVersion,
  appVersion: '1.0.0',              // or omit — auto-detected from versionName
));
await FlutterPatcher.init(autoApplyUpdates: true);
```

### 4. Build a patch

Rebuild the release APK, then pack it into a device-ready `patch.zip`:

```bash
flutter build apk --release
flutter-ota build \
  --apk build/app/outputs/flutter-apk/app-release.apk \
  --version 1.0.1 \
  --target-version-code 100
```

Every ABI in the APK is included, so one bundle serves all devices. Add
`--assets assets/hero.png,assets/strings/zh.json` to overlay updated assets.

### 5. Deploy

```bash
flutter-ota deploy \
  --source dist \
  --channel production \
  --target-app-version 1.0.0 \
  --force
```

That's it — devices pick up the patch on their next check.

### 6. Roll back (server side)

```bash
flutter-ota rollback --channel production
```

Or on the device, `FlutterPatcher.rollback()` deletes the local patch and
reverts to the APK's built-in version on the next cold start.

---

## How it works

```text
  ┌─────────────────┐  Supabase / Postgres / Cloudflare / AWS / PocketBase / CDN
  │  Your backend    │  stores: patch.zip (the diff) + manifest.json (metadata)
  └────────▲────────┘
           │  1. check-for-update on launch
           │  2. backend returns PatchInfo (url, md5, signature, force flag)
  ┌────────┴────────┐
  │   The app       │  3. download patch.zip
  │                 │  4. verify MD5 + Ed25519 signature
  │                 │  5. write to local patch dir (atomic rename)
  │                 │  6. cold-restart (forced) OR next cold start (staged)
  │                 │  7. loader hook reads patched libapp.so + asset overlays
  │                 │  8. boot ok → keep · boot fails → auto-rollback + blacklist
  └─────────────────┘
```

A patch is a byte-for-byte diff of the new APK's `libapp.so` against the
version the user has installed; asset patches overlay `flutter_assets/` by path.
Nothing is swapped into the running process — it loads on the next cold start.

Full internals: [Architecture](doc/architecture.md).

---

## What can and can't be patched

| ✅ Hot-patchable                                     | ❌ Not hot-patchable                                     |
|------------------------------------------------------|----------------------------------------------------------|
| Anything in `lib/` — widgets, logic, routes, constants | Native code (Kotlin / Java / C++ in `android/src/main/`) |
| Pure-Dart package upgrades (same native side)        | `AndroidManifest.xml` changes                            |
| Flutter asset files registered in `pubspec.yaml`     | APK `res/` (icons, layouts, strings.xml)                 |
| New `Image.asset()` / `rootBundle.load()` calls      | Flutter Engine upgrades                                  |
|                                                      | Adding or removing native plugins                        |
|                                                      | Removing assets that exist in the base APK               |

See [API Reference → What can be patched](doc/api-reference.md#what-can-and-cannot-be-patched)
for edge cases (ProGuard/R8, multi-ABI/flavors, state migrations).

---

## Safety

- **Crash protection (on by default).** If a patch fails to boot, the SDK
  auto-rolls back and blacklists the offending version. Tune with
  `maxCrashCount` (default 1) and `verifyAfter` (default 5s). Crash attribution
  is bounded to a boot window, so an unrelated crash long after a healthy boot
  won't revert a working patch. See [Crash Protection](doc/crash-protection.md).
- **Integrity & signing.** MD5 is strongly recommended; Ed25519 signature
  verification is available on Android 13+ (falls back to MD5-only below, with a
  warning). Patches are bound to the host APK's `versionCode`, so stale patches
  expire after an app upgrade. Keep private signing keys on your server, never
  in the app bundle.
- **Staged rollout.** Ship 1% → 5% → 20% → 50% → 100% and watch crash rate at
  each stage. The SDK records `lastBootDiagnostic` per device.

Full release workflow: [Production Playbook](doc/production-playbook.md).

---

## Documentation

**Guides**

- [Beginner Guide](doc/beginner-guide.md) — zero to first OTA, narrated
- [Getting Started](doc/getting-started.md) — scaffold → build → deploy
- [Developer Guide](doc/developer-guide.md) — full workflow reference
- [Configuration](doc/configuration.md) — env vars, `.env`, resolution order
- [Backends](doc/backends.md) — Supabase / Postgres / Cloudflare / AWS / PocketBase setup
- [Production Playbook](doc/production-playbook.md) — staged rollout, diagnostics, rollback

**Reference**

- [API Reference](doc/api-reference.md) — `FlutterPatcher`, configs, overlay, error codes
- [Architecture](doc/architecture.md) — internals, protocol, signing
- [CLI Reference](doc/cli-reference.md) — every command and flag
- [Crash Protection](doc/crash-protection.md) — rollback, blacklist, Android differences
- [FAQ](doc/faq.md) — versioning, cold start, store policy

---

## Contributing

Issues and PRs welcome. Before submitting:

- `flutter analyze` reports no issues
- `flutter test` is fully green
- If you touched native code, run a real-device patch / rollback end-to-end
- Document new public APIs (they surface on pub.dev)

---

## License

MIT
