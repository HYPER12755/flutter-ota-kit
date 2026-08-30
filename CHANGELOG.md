> Chinese version: [CHANGELOG-zh.md](CHANGELOG-zh.md)

## 0.1.9

### Changed

- **Shared the update-check orchestration across all backends.** The
  (previously copy-pasted) `check()` body in `SupabaseUpdateSource`,
  `PostgresUpdateSource`, `CloudflareUpdateSource` and `AwsUpdateSource` is now
  a single backend-agnostic `performSharedUpdateCheck()` in
  `lib/src/shared_update_check.dart`. Each backend keeps only its own config
  building + plugin factory calls; everything else (bundle-id normalization,
  `appVersion`/fingerprint argument building, the `getUpdateInfo` call,
  download-URL resolution and `ServerUpdateResult` mapping) lives in exactly one
  place. Behavior is unchanged. Added `flutter_ota_kit_plugin_core` as a direct
  dependency (for the shared `DatabasePlugin` / `StoragePlugin` types).

### Fixed

- **Runtime `appVersion` auto-detection now applies to Postgres, Cloudflare and
  AWS too, not just Supabase.** Those three sources had the same silent-failure
  bug described in 0.1.8 (they reported a hardcoded/empty `APP_VERSION` and the
  backend dropped the bundle), but only the Supabase source was fixed in 0.1.8.
  `resolveAppVersion()` (in `lib/src/app_version_resolver.dart`) is now the
  single shared resolver used by all four sources.
- **`resolveAppVersion()` no longer caches an empty detection forever.** A
  transient `PackageInfo.fromPlatform()` failure previously cached `''` and
  permanently pinned the reported version to empty, silently breaking
  `appVersion`-strategy targeting on every later check. It now only caches a
  successful, non-empty detection and retries on the next check.

## 0.1.8

### Fixed

- **Clients now auto-detect their real app version, so OTA updates no longer
  silently fail.** Previously the generated `flutter_ota_kit_setup.dart`
  defaulted `APP_VERSION` to the hardcoded string `'1.0.0'`. When a bundle was
  deployed with a different `--target-app-version` (e.g. `1.0.1`), the client
  reported `1.0.0`, the backend's `filterCompatibleAppVersions` dropped the
  bundle (`semverSatisfies('1.0.1','1.0.0')` is false), and the app stayed
  "up to date" forever — no update, no error. `SupabaseUpdateSource` now
  resolves the version from the host app's `versionName` via
  `package_info_plus` whenever `SupabaseUpdateConfig.appVersion` is null or
  empty, and the `flutter-ota init` generator now writes an empty default
  (which triggers detection) instead of `'1.0.0'`. An explicit
  `--dart-define=APP_VERSION=…` / `SupabaseUpdateConfig.appVersion` still wins.

## 0.1.7

### Fixed

- Added the missing `android.os.Process` / `kotlin.system.exitProcess`
  imports for the forced-update restart (`Process.killProcess`,
  `Process.myPid`, `exitProcess`). The 0.1.6 upload missed these, so the
  Android native build failed to compile.

## 0.1.6

### Fixed

- **Forced-update restart now works reliably on modern Android.** The previous
  `AlarmManager`-based relaunch is deferred or dropped in Doze / battery-saver
  modes, so the app stayed closed. It now uses `startActivity` with
  `FLAG_ACTIVITY_NEW_TASK | FLAG_ACTIVITY_CLEAR_TASK` followed by a
  `Handler.postDelayed(200ms)` + `Process.killProcess`, which is the same
  mechanism used by `restart_app` (`RestartMode.process`) and is not affected
  by Doze. The developer does not need to change any Dart code — forced updates
  restart automatically during `checkAndApplyUpdates` / `init`.

## 0.1.5

### Fixed

- **Forced updates now actually relaunch the app.** `handleRestartApp` used to
  `startActivity(NEW_TASK)` and then `killProcess(myPid())` after 200ms — but a
  NEW_TASK launch still runs in the same process, so the kill took down the
  just-launched activity and the patched native lib never loaded. It now
  schedules the relaunch via `AlarmManager` (outside the process) and then
  `System.exit(0)`, so the app reopens automatically with the update applied.

## 0.1.4

### Fixed

- Fixed the Android build failing on host apps that use AGP 9 built-in
  Kotlin, with `Failed to apply plugin 'kotlin-android'` followed by
  `project ':flutter_ota_kit' does not specify compileSdk`. This affects
  projects created with or migrated to Flutter 3.44, which ship AGP 9.
  `android/build.gradle` now checks whether built-in Kotlin is actually
  active on the host and applies the Kotlin Gradle Plugin, plus the
  matching jvmTarget DSL, only where that DSL exists: `kotlinOptions` when
  KGP is applied, `kotlin { compilerOptions }` under built-in Kotlin.

  The switch is built-in Kotlin, not the AGP major version. AGP 9 hosts
  that opt out with `android.builtInKotlin=false` (the default the Flutter
  3.44 template generates) still need the plugin to bring its own KGP,
  exactly like AGP 8 hosts, and keep the previous code path unchanged.

  This is a build-time only change, with no runtime behavior change.
  Patches remain fully compatible: payloads produced by or for 0.1.3
  install and boot identically on 0.1.4, and no repack is required.

- No change to the minimum supported Flutter or AGP version. Existing
  hosts on AGP 8 build exactly as before.

### Known issues

- On AGP 9 hosts, Flutter still prints `WARNING: Your app uses the
  following plugins that apply Kotlin Gradle Plugin (KGP):
  flutter_ota_kit`. The Flutter Gradle Plugin decides this by text-matching
  `android/build.gradle`, so it cannot see that the `apply plugin` line is
  guarded. The warning is safe to ignore, and the literal has to stay:
  when the Flutter Gradle Plugin finds no KGP declaration in a plugin, it
  applies `kotlin-android` to that plugin itself, which fails the build
  under built-in Kotlin.
- Flutter 3.44's own Gradle plugin does not support `android.newDsl=true`
  and fails to apply before any plugin is evaluated. Keep the template
  default `android.newDsl=false`.

## 0.1.3

### Added

- Added Android cold-start Flutter asset hot updates. Assets (images,
  fonts, JSON, anything reachable via `Image.asset(...)` or
  `rootBundle.load(...)`) can be patched together with Dart code through
  the same `patch.zip` payload.
- Added `--assets` to `dart run flutter_ota_kit:pack`. Pass paths inline
  (`--assets a,b`) or read them from a UTF-8 text file with the `@` prefix
  (`--assets @patch-assets.txt`, one path per line, `#` starts a comment);
  inline paths and `@file` references can be mixed in the same flag.
  Each path must already be registered under `assets:` in the new APK's
  `pubspec.yaml`; `--assets` only tells `pack` which of those assets to
  ship inside `patch.zip`. The runtime overlays them on top of the APK's
  Flutter asset bundle at install time.

### Changed

- `dart run flutter_ota_kit:pack` now always emits `dist/patch.zip` +
  `dist/manifest.json` (outer `schemaVersion: 2`, `payload: patch.zip`),
  whether or not `--assets` is passed. A Dart-only `patch.zip` contains
  just `manifest.json` + `lib/<abi>/libapp.so`; its inner manifest omits
  the `assets` block. The previous bare-`.so` output mode is gone.
- Android runtime detects ZIP payloads, installs overlay asset packages,
  builds a private `flutter_assets.apk`, and starts Flutter through a
  patched `FlutterJNI` AssetManager when assets are present. Dart-only
  `patch.zip` payloads short-circuit the asset overlay pipeline and
  behave like code-only patches at install time.
- `mock_server --dist` reads `manifest.payload` and serves the declared
  file.

### Compatibility

- Bare-`.so` patches produced by 0.1.0-0.1.2 still install on 0.1.3
  devices (the runtime keeps a quiet legacy install path); the producer
  CLI no longer emits that format. Server operators should ship
  `patch.zip` for any new patch built against a 0.1.3+ host APK.

## 0.1.2

### Added

- Added `dart run flutter_ota_kit:mock_server` for local
  `checkUpdate -> applyPatch` testing without maintaining an example-only
  helper script.

### Changed

- Improved README onboarding with a TL;DR, clearer fit / non-fit guidance,
  store policy warning, and local mock server instructions.
- Updated pub.dev package description and topics for better discoverability.
- Added a GitHub social preview image under `doc/social-preview.png`.

## 0.1.1+1

### Fixed

- Corrected the README install snippet version pin to `^0.1.1`
  (docs-only, no code change).
- Translated CHANGELOG to English so pub.dev's pana check no longer
  flags it for non-ASCII content. Chinese version preserved as
  `CHANGELOG-zh.md`.

## 0.1.1

### Changed

- **`PatchInfo.md5` is now optional.** An empty string means the caller
  explicitly opts out of download integrity verification and relies on
  HTTPS only. When `md5` is empty the Ed25519 signature check is also
  skipped (the signature input is the md5 hex, so no md5 means no
  signature input). `toJson` omits the `md5` key when it is empty.
- **`validatePatchArgs`**: blank `md5` is now accepted; non-blank `md5`
  is still required to be 32 lowercase hex chars.
- **Blacklist**: when the caller does not provide `md5`, the download
  pre-check falls back to version-only matching via the new
  `BlacklistStore.containsByVersion`. Blacklist entries are still
  recorded with the actual md5 computed after download.
- **`meta.json`**: `effectiveMd5` now always stores the md5 computed
  after download (previously it stored the server-declared md5). Boot
  checks and blacklist entries key on this stable hash.
- **Dependency constraints relaxed**: Dart SDK constraint changed from
  `^3.10.7` to `>=3.0.0 <4.0.0`; runtime dependencies switched to a
  lower bound plus an open upper bound; `archive` now supports both
  3.x and 4.x to reduce host-project conflicts.

## 0.1.0

First public release (Android-only beta).

### Core features

- **Cold-start hot updates**: replaces `FlutterLoader.findAppBundlePath`
  via reflection inside `Application.attachBaseContext`, before the
  Dart engine starts, enabling whole-file `libapp.so` replacement.
- **Signature verification**: built-in Ed25519 (X.509 SubjectPublicKey
  Info) plus MD5 dual verification, with `strictSignature` mode that
  prevents downgrade bypass on older devices.
- **Crash circuit breaker / auto rollback**: counts `REASON_CRASH`
  events from `ApplicationExitInfo` and hooks
  `PlatformDispatcher.onError` on the Dart side. Once `maxCrashCount`
  (default 1, fail-fast) is reached, the patch is deleted, added to
  the blacklist, and the host falls back to the bundled APK version.
- **First-frame verify clears the breaker**: after the patch loads,
  the app must stay alive in the foreground for `verifyAfter`
  (default 5s) before being marked verified, which resets the crash
  counter.
- **Local blacklist**: auto-blacklisted patches will never be
  reinstalled, preventing crash loops. Inspect or clear via
  `FlutterPatcher.blacklist` / `clearBlacklist`.
- **Progress event stream**: `FlutterPatcher.applyProgress` exposes
  `downloading` / `verifying` / `finalizing` phase events.
- **CLI packaging tool**: `dart run flutter_ota_kit:pack` extracts
  `libapp.so` from a release APK and produces the patch manifest.

### Known limitations

- **Android only**. On iOS / Web / desktop, all APIs are no-ops (the
  first call prints a warning).
- **Strict Ed25519 mode requires Android API 33+**. Below API 33 with
  `strictSignature: true` (the default), signed patches are rejected.
- **Only full-mode patches are supported**. Differential patching is
  not shipped in 0.1.0 to avoid exposing an unverified path.
- This initial release shipped the legacy lib-only payload path. Asset
  payloads were added later in 0.1.3.

### Documentation

- Repository README: use cases, 5-minute demo, integration steps.
- `doc/architecture.md`: native + Dart layered architecture and
  startup sequence.
- `doc/api-reference.md`: full API reference.
- `doc/crash-protection.md`: breaker and rollback strategy.
