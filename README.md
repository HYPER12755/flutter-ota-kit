# flutter_ota_kit

**English** | [简体中文](README-zh.md)

[![pub package](https://img.shields.io/pub/v/flutter_ota_kit.svg)](https://pub.dev/packages/flutter_ota_kit)
[![Platform](https://img.shields.io/badge/platform-Android-brightgreen)](https://flutter.dev)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Open-source code push for Flutter Android.**

Ship Dart code and asset hotfixes over the air — no store release, no
forced vendor lock-in, no per-month fees. Patches live on **your** backend
(Supabase, Postgres, Cloudflare, AWS, or your own object storage) and load
on the next cold start.

If you've used [Shorebird](https://shorebird.dev/),
[CodePush](https://learn.microsoft.com/en-us/appcenter/distribution/codepush/),
or [Expo EAS Update](https://docs.expo.dev/eas-update/introduction/) —
flutter_ota_kit is the same OTA update model for Flutter Android, MIT-licensed,
with your choice of cloud backend.

![Feature demo: apply a patch, cold restart, and rollback](doc/feature-presentation.gif)

---

## How it compares

|                       | flutter_ota_kit                                 | Shorebird                     | CodePush (React Native)       |
|-----------------------|--------------------------------------------------|-------------------------------|-------------------------------|
| **Framework**         | Flutter                                         | Flutter                       | React Native                  |
| **Platforms**         | Android                                         | Android + iOS                 | Android + iOS (retired 2025)  |
| **Hosting**           | Your backend or your own CDN — see [Backends](doc/backends.md) | Shorebird cloud (managed)     | AppCenter cloud (deprecated)  |
| **Update scope**      | Dart AOT + Flutter assets                        | Dart code (engine-level diff) | JS bundle                     |
| **Takes effect**      | Next cold start                                  | Next restart                  | Next restart                  |
| **Cost**              | Free (MIT)                                      | Free tier + paid plans        | —                             |
| **Backend flexibility** | Supabase / Postgres / Cloudflare / AWS / bring-your-own | Cloud-managed only            | —                             |
| **Forced updates**     | Yes — built-in progress UI                       | Yes                           | Yes                           |
| **Crash rollback**     | Automatic + bad-patch blacklist                  | Yes                           | Yes                           |
| **Signing**            | Ed25519 (Android 13+) + MD5                      | Yes                           | —                             |

**Choose Shorebird** if you need iOS support today or want a fully managed cloud.

**Choose flutter_ota_kit** if you need OTA on infrastructure you control —
enterprise apps, regional distribution, air-gapped deployments, or non-Play
distribution channels. Bring your own backend, your own CDN, your own auth.

> Google Play and some stores restrict downloading executable code at runtime.
> flutter_ota_kit targets self-controlled, enterprise, or permissive
> distribution channels. Verify your channel's policy before shipping.

---

## Features

- **OTA code push** — replace the Dart AOT `libapp.so` and Flutter assets on the
  next cold start, with MD5 + Ed25519 integrity checks.
- **Five cloud backends** — Supabase (fully automated), Postgres, Cloudflare (D1 + R2),
  AWS (S3), **PocketBase** (single-binary self-hosted). Or bring your own CDN.
- **Crash rollback** — automatic on boot failure with a bad-patch blacklist.
  Configurable via `maxCrashCount` and `verifyAfter`.
- **Forced updates with built-in UI** — opt into zero-click updates with
  `autoApplyUpdates: true`; the SDK shows a download spinner, progress bar, and
  the server's OTA message during the install. No UI code from you.
- **Staged rollout** — server-side cohort math (per-mille, target-cohorts) lets
  you ship 1% → 5% → 20% → 50% → 100% safely.
- **Tooling included** — `pack` CLI (builds patches from release APKs),
  `flutter_ota_kit console` (web-based admin UI for the sidecar server),
  runtime diagnostics, sample app.
- **No native plugin churn** — the patch system uses the Android
  `ContentProvider` to stage files; no platform channel gymnastics, no
  per-vendor SDKs to upgrade.

---

## Try it in 5 minutes (no server needed)

```bash
git clone https://github.com/HYPER12755/flutter-ota-kit.git
cd flutter_ota_kit/example
flutter pub get
flutter build apk --release
flutter install
```

1. Launch the app — it shows the **original** `assets/patch_demo.png`.
2. Tap **Apply patch**.
3. Swipe the app away from recents and reopen.
4. The image has changed — the asset patch took effect.
5. Tap **Rollback** → restart → original image is back.

The example bundles a precompiled `patch.zip`. Everything runs offline on
the device. For HTTP-based testing with a real backend, see
[Getting Started](doc/getting-started.md) or the
[Beginner Guide](doc/beginner-guide.md) (the human-narrated walkthrough).

---

## Requirements

| Item                       | Requirement                                                        |
|----------------------------|--------------------------------------------------------------------|
| **Platform**               | Android only (iOS / macOS / Windows / Linux / Web are no-op)         |
| **Dart SDK**               | `>=3.13.0 <4.0.0`                                                  |
| **Flutter**                | `>=3.47.0`                                                          |
| **Android `minSdk`**       | 24                                                                  |
| **Android `compileSdk`**   | 36                                                                  |
| **ABI**                    | `armeabi-v7a` / `arm64-v8a` / `x86_64`                              |
| **NDK**                    | 27.0.12077973+                                                      |
| **AGP**                    | 8.11.1+ (including AGP 9.x)                                         |
| **Kotlin**                 | 2.2.20+ (or AGP 9 built-in Kotlin)                                  |
| **Java / JVM**             | 17                                                                  |

On iOS / macOS / Windows / Linux / Web, every API is safe to call but is a
**no-op** — the plugin logs a one-time warning and returns safe defaults.
This makes it safe to ship `flutter_ota_kit` in cross-platform code without
guarding every call site.

---

## Quick start

### 1. Install

```yaml
# pubspec.yaml
dependencies:
  flutter_ota_kit: ^0.1.10
```

### 2. Initialize

Call `setupFlutterOta()` (or the bare `FlutterPatcher.init()`) before `runApp()`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_ota_kit/flutter_ota_kit.dart';
import 'flutter_ota_kit_setup.dart';   // generated by `flutter-ota init <backend>`

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupFlutterOta();              // configures the backend + zero-click forced updates
  runApp(const FlutterOtaApp(child: MyApp()));
}
```

`FlutterOtaApp` is the zero-code wrapper that gives the SDK an
`Overlay` to render the built-in forced-update progress UI into. The user
sees a download spinner + progress bar + the server's OTA message during
the install — no UI from you.

Disable the overlay app-wide with `FlutterPatcher.showUpdateUi = false`
(or `FlutterOtaApp(showUpdateUi: false)`), or host it yourself by
assigning `MaterialApp.navigatorKey = FlutterPatcher.navigatorKey`.

### 3. Build a patch

Rebuild the release APK, then run `pack` against the new APK to produce
`dist/patch.zip` and `dist/manifest.json`:

```bash
dart run flutter_ota_kit:pack \
  --apk build/app/outputs/flutter-apk/app-release.apk \
  --version 1.0.0-h1 \
  --target-version-code 100
```

To include assets (since 0.1.3), append `--assets`:

```bash
dart run flutter_ota_kit:pack \
  --apk build/app/outputs/flutter-apk/app-release.apk \
  --version 1.0.1 \
  --target-version-code 100 \
  --assets assets/hero.png,assets/strings/zh.json
```

Each asset must be registered in the new APK's `pubspec.yaml`. Upload
`patch.zip` to your backend (or CDN) and have your update endpoint return
a `PatchInfo` pointing at it.

### 4. Apply a patch (most apps just do this)

```dart
final result = await FlutterPatcher.applyPatch(
  PatchInfo(
    version: 'fix-1',
    patchUrl: 'https://your-cdn.com/v100/patch.zip',
    md5: '0123456789abcdef0123456789abcdef',
    targetVersionCode: 100,
  ),
);

if (result.ok) {
  // Patch takes effect on the next cold start.
}
```

If you manage the download yourself, use `applyPatchBytes`:

```dart
final bytes = await loadPatchFromYourSource();
final result = await FlutterPatcher.applyPatchBytes(
  bytes,
  version: '1.0.0-h1',
  targetVersionCode: 100,
);
```

### 5. Roll back

```dart
await FlutterPatcher.rollback();
```

Deletes the current patch. The app reverts to the APK's built-in version on
the next cold start. This is **not** the same as a server-side rollback —
this deletes the local patch, it doesn't change what's in your backend.

---

## How it works

```text
  ┌─────────────────┐
  │  Your backend    │  Supabase / Postgres / Cloudflare / AWS / PocketBase / your CDN
  │  (or CDN)        │  stores: patch.zip (the diff) + manifest.json (the metadata)
  └────────▲────────┘
           │  1. check-for-update on launch
           │  2. server returns PatchInfo (url, md5, signature, version, shouldForceUpdate)
           │
  ┌────────┴────────┐
  │   The app       │
  │                 │  3. download patch.zip
  │                 │  4. verify MD5 + Ed25519 signature
  │                 │  5. write to local patch dir (atomic rename)
  │                 │  6. cold-restart (forced) OR next cold start (staged)
  │                 │  7. loader hook reads patched libapp.so + asset overlays
  │                 │  8. boot succeeds → keep patch
  │                 │     boot fails    → auto-rollback + blacklist
  └─────────────────┘
```

A patch is a **byte-for-byte diff** of the new APK's `libapp.so` against the
old one (the versionCode the user has installed). Asset patches overlay
`flutter_assets/` files by path. The patch never ships inside the running
process — it loads on the next cold start. The cold-restart for forced
updates goes through `restart_app` (with `RestartMode.process`, which
actually exits the process so the new code reloads).

Full internals: [Architecture](doc/architecture.md).

---

## What can and can't be patched

| ✅ Hot-patchable                                                | ❌ Not hot-patchable                                                  |
|-----------------------------------------------------------------|-----------------------------------------------------------------------|
| Anything in `lib/` — widgets, logic, routes, constants, tests  | Native code (Kotlin / Java / C++ in `android/src/main/`)              |
| Pure-Dart package upgrades (same native side)                  | `AndroidManifest.xml` changes                                       |
| Flutter asset files (registered in `pubspec.yaml`)            | APK `res/` (icons, layouts, strings.xml)                            |
| New `Image.asset()` / `rootBundle.load()` calls pick up new bytes | Flutter Engine upgrades                                            |
|                                                                 | Adding or removing native plugins                                   |
|                                                                 | Removing assets that exist in the base APK                           |
|                                                                 | `pubspec.yaml` font registration changes                              |

For edge cases (ProGuard/R8, multi-ABI / flavors, state migrations, asset
overlay quirks), see [API Reference → What can be patched](doc/api-reference.md#what-can-and-cannot-be-patched).

---

## Safety

### Crash protection (on by default)

The plugin is **fail-fast**: if a patch causes a boot failure, it auto-rolls
back and blacklists the offending version so it won't be retried. Tunable
via `maxCrashCount` (default 1) and `verifyAfter` (default 5s).

Design and Android version differences:
[Crash Protection](doc/crash-protection.md).

### Integrity & signing

- **MD5** verification is strongly recommended; omit only for quick testing.
- **Ed25519 signature** verification is available on Android 13+ (API 33).
  Falls back to MD5-only on older Android (with a warning).
- Patches are bound to the host APK's `versionCode` — old patches expire
  after an APK upgrade and the server stops serving them.
- Always download over HTTPS. Keep private signing keys on the server only,
  never in the app bundle.

### Production tips

- **Stage your rollout** (1% → 5% → 20% → 50% → 100%) and monitor crash
  rate at each stage. The SDK records `lastBootDiagnostic` per device.
- **Report diagnostics** to your analytics pipeline so you can spot a bad
  patch before users hit the app.
- **Prepare for emergency rollback** — stop returning the bad patch from
  your endpoint; devices that already tripped crash protection have
  rolled back locally and won't re-download.

Full release workflow + diagnostic-reporting code:
[Production Playbook](doc/production-playbook.md).

---

## FAQ

**Q: Must the patch and base APK use the same Flutter version?**
A: Yes. `libapp.so` is tightly coupled to the Flutter Engine ABI.
After upgrading the SDK, ship a new release.

**Q: Why doesn't a patch take effect immediately?**
A: Once `libapp.so` is loaded by the current process, it can't be swapped
at runtime. The patch is written to disk and loaded on the next cold
start. Forced updates trigger a process restart so the new code loads
immediately.

**Q: Why does each patch need a `targetVersionCode`?**
A: Two reasons: (1) old patches expire after an APK upgrade (so a user on
v2 doesn't accidentally load a v1-targeted patch), and (2) the server
won't ship a patch built for v1 to a user on v2 (the SDK filters them
out at update-check time).

**Q: How does the client report its app version, and why must it match `--target-app-version`?**
A: The client reports an `appVersion` that the backend matches against
each bundle's `target_app_version`. By default this is **auto-detected at
runtime** from the host app's `versionName` via `package_info_plus` — no
build flag needed. You can override it explicitly with
`--dart-define=APP_VERSION=1.2.3` or `SupabaseUpdateConfig.appVersion`.
The backend keeps only bundles whose `target_app_version` is
semver-compatible with the reported version. **If they don't match, the
backend returns no bundle and the app silently stays "up to date"** — so
always deploy with `--target-app-version` equal to the app's real
`versionName` (e.g. `1.0.1` for a `version: 1.0.1+2` pubspec). A mismatched
version is the most common cause of "the update never arrives".

More questions: [Full FAQ](doc/faq.md).

---

## Documentation

**Guides** (narrative, in reading order)

- [Beginner Guide](doc/beginner-guide.md) — zero-to-first-OTA walkthrough, as a human would do it
- [Getting Started](doc/getting-started.md) — scaffold → build → deploy in 5 minutes
- [Developer Guide](doc/developer-guide.md) — full workflow reference (init, migrate, build, deploy, SDK API, targeting, troubleshooting)
- [Configuration](doc/configuration.md) — every env var, `.env`, resolution order, secrets policy
- [Backends](doc/backends.md) — Supabase / Postgres / Cloudflare / AWS / PocketBase setup, env vars, CLI snippets
- [Production Playbook](doc/production-playbook.md) — staged rollout, diagnostics, emergency rollback

**Reference**

- [API Reference](doc/api-reference.md) — `FlutterPatcher` methods, error codes, asset patching
- [Architecture](doc/architecture.md) — internals, server protocol, signing, advanced config
- [CLI Reference](doc/cli-reference.md) — every command, subcommand, and flag
- [Crash Protection](doc/crash-protection.md) — auto-rollback, blacklist, Android version differences
- [Golden Testing](doc/golden-testing.md) — how Flutter's pixel-perfect test system works (and how this project uses it)

**Other**

- [FAQ](doc/faq.md) — versioning, cold start, store policy
- [CHANGELOG.md](CHANGELOG.md) — release notes

中文文档: [README-zh.md](README-zh.md) · [api-reference-zh](doc/api-reference-zh.md) ·
[architecture-zh](doc/architecture-zh.md) · [crash-protection-zh](doc/crash-protection-zh.md) ·
[getting-started-zh](doc/getting-started-zh.md) · [production-playbook-zh](doc/production-playbook-zh.md) ·
[faq-zh](doc/faq-zh.md)

---

## Who's using it?

If you run flutter_ota_kit in production, [open an issue](https://github.com/HYPER12755/flutter-ota-kit/issues) and tell us about your use case — we'd love to list you here.

---

## Contributing

Issues and PRs are welcome.

Before submitting, please make sure:

- `flutter analyze` reports no warnings
- `flutter test` is fully green
- If you touched native code, you've run a real-device end-to-end patch / rollback flow
- If you added a new public API, you've documented it on `dartdoc_options.yaml` topics (the doc appears on pub.dev)

---

## License

MIT
