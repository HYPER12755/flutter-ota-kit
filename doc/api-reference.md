# API Reference

Every public API in `flutter_ota_kit` is a static member of the `FlutterPatcher`
class, plus the config classes and the overlay widgets — all from a **single
import**:

```dart
import 'package:flutter_ota_kit/flutter_ota_kit.dart';
```

> **One package.** As of v0.2.0 the device SDK and all five backends live in
> `flutter_ota_kit`. There are no separate `flutter_ota_kit_supabase` /
> `_postgres` / `_cloudflare` / `_aws` / `_pocketbase` / `_core` /
> `_plugin_core` packages to import.

The plugin only executes patch logic on **Android**. On iOS, Web, macOS,
Windows, and Linux every API is a **no-op** — it never throws, prints a one-time
warning on first call, and returns safe defaults.

For internals (how a patch loads, the signing protocol, the boot-time loader
hook) see [Architecture](architecture.md). For setup see
[Getting Started](getting-started.md).

---

## Table of contents

- [Initialization](#initialization)
- [Configure a backend](#configure-a-backend)
- [Check for updates](#check-for-updates)
- [Apply a patch](#apply-a-patch)
- [Apply update (full server-driven flow)](#apply-update-full-server-driven-flow)
- [The forced-update overlay](#the-forced-update-overlay)
- [Handle the result](#handle-the-result)
- [Error codes](#error-codes)
- [Listen to progress](#listen-to-progress)
- [Roll back](#roll-back)
- [Boot diagnostics](#boot-diagnostics)
- [Query state](#query-state)
- [Blacklist](#blacklist)
- [Asset patching](#asset-patching)
- [What can and cannot be patched](#what-can-and-cannot-be-patched)
- [Custom update source](#custom-update-source)
- [PatchInfo](#patchinfo)
- [Enums](#enums)
- [Version compatibility](#version-compatibility)

---

## Initialization

### `FlutterPatcher.init`

Configures the patch loader, crash protection, and boot diagnostics. **Call once
before `runApp()`.** Idempotent — repeated calls are safe no-ops.

```dart
Future<void> init({
  String publicKeyBase64 = '',
  int maxCrashCount = 1,
  bool strictSignature = true,
  List<String> loaderFieldCandidates = const ['flutterLoader'],
  bool loaderFallbackHeuristic = false,
  Duration verifyAfter = const Duration(seconds: 5),
  bool autoApplyUpdates = false,
  int maxPatchHistory = 4,
  int maxAssetHistory = 4,
})
```

| Parameter | Default | What it does |
|-----------|---------|--------------|
| `publicKeyBase64` | `''` | Ed25519 public key (X.509 SubjectPublicKeyInfo, base64) for signature verification. Empty disables signing. |
| `maxCrashCount` | `1` | Fail-fast: after this many early boot failures with a patch, auto-rollback + blacklist. `0` disables. |
| `strictSignature` | `true` | Reject signed patches on Android API < 33 (platform Ed25519 is unreliable there). `false` allows signed patches on older Android (MD5-only fallback). |
| `loaderFieldCandidates` | `['flutterLoader']` | Field names the native loader hook looks for. **Don't change** unless adapting a new Flutter version. |
| `loaderFallbackHeuristic` | `false` | Fallback loader path for unusual Flutter embedders. **Don't enable** unless instructed. |
| `verifyAfter` | `5s` | Post-first-frame Dart error watch window. Uncaught errors here trigger crash rollback. |
| `autoApplyUpdates` | `false` | Zero-click forced updates: after boot protection, runs `checkAndApplyUpdates` in the background. |
| `maxPatchHistory` | `4` | How many previous patches to keep for local rollback. `0` disables history. |
| `maxAssetHistory` | `4` | How many asset archives to keep (deduplicated; only asset-changing patches add one). |

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterPatcher.configureSupabase(/* … */);   // configure BEFORE init
  await FlutterPatcher.init(autoApplyUpdates: true);
  runApp(const FlutterOtaApp(child: MyApp()));
}
```

The backend must be configured (via a `configureX(...)` call, the generated
`setupFlutterOta()`, or env-var auto-detection) **before** `init()` for
`autoApplyUpdates` to have something to check.

---

## Configure a backend

Pick the one backend you use. Each takes a config object and stores it for
`checkForUpdate` / `checkAndApplyUpdates`.

```dart
static void configureSupabase(SupabaseUpdateConfig config);
static void configurePostgres(PostgresUpdateConfig config);
static void configureCloudflare(CloudflareUpdateConfig config);
static void configureAws(AwsUpdateConfig config);
static void configurePocketBase(PocketBaseUpdateConfig config);
```

Common fields across every config (all optional): `appVersion` (String? — when
omitted the SDK auto-detects the host `versionName`), `fingerprintHash`
(String?), `sdkVersion` (String, default `'1.0.0'`), `cohort` (String?),
`minBundleId` (String, default the nil UUID). `channel`, `platform`, and
`updateStrategy` are **required** on all of them.

### SupabaseUpdateConfig

```dart
FlutterPatcher.configureSupabase(SupabaseUpdateConfig(
  supabaseUrl: 'https://<ref>.supabase.co',   // required
  bucket: 'bundles',                           // required
  channel: 'production',                       // required
  platform: Platform.android,                  // required
  updateStrategy: UpdateStrategy.appVersion,   // required
  anonKey: '<anon-key>',        // optional — public, RLS-protected reads
  serviceRoleKey: null,          // optional — only if the device must write (rare)
  appVersion: '1.0.0',
));
```

### PostgresUpdateConfig

```dart
FlutterPatcher.configurePostgres(PostgresUpdateConfig(
  host: 'db.example.com',                      // required
  database: 'app',                             // required
  channel: 'production', platform: Platform.android,
  updateStrategy: UpdateStrategy.appVersion,   // required trio
  port: 5432, username: 'readonly', password: '…', sslMode: 'require',
  servingBaseUrl: 'https://patches.example.com', // proxies the bytea artifact table
));
```

### CloudflareUpdateConfig

```dart
FlutterPatcher.configureCloudflare(CloudflareUpdateConfig(
  databaseId: '<d1-id>', accountId: '<acct>', cloudflareApiToken: '<token>', // required
  bucketName: '<r2-bucket>', accessKeyId: '<r2-key>', secretAccessKey: '<r2-secret>', // required
  channel: 'production', platform: Platform.android,
  updateStrategy: UpdateStrategy.appVersion,
  basePath: 'bundles', region: 'auto', endpoint: null,
));
```

### AwsUpdateConfig

```dart
FlutterPatcher.configureAws(AwsUpdateConfig(
  bucketName: '<bucket>', region: 'us-east-1',
  accessKeyId: '<key>', secretAccessKey: '<secret>', // required
  channel: 'production', platform: Platform.android,
  updateStrategy: UpdateStrategy.appVersion,
  basePath: 'bundles', endpoint: null, sessionToken: null,
  cloudfrontDistributionId: null,
));
```

### PocketBaseUpdateConfig

```dart
FlutterPatcher.configurePocketBase(PocketBaseUpdateConfig(
  url: 'https://pb.example.com',               // required
  adminEmail: 'admin@example.com',             // required
  adminPassword: '<password>',                 // required
  bundlesCollection: 'bundles',                // required
  bundlesBucket: 'bundles',                    // required
  channel: 'production', platform: Platform.android,
  updateStrategy: UpdateStrategy.appVersion,
));
```

> **Secrets on the device.** Only Supabase's anon key is designed to be shipped
> in an app (public, RLS-protected). For Cloudflare / AWS / PocketBase /
> Postgres, embedding full credentials in a public APK exposes them. For
> public-store apps, front those backends with your own server. See
> [Backends](backends.md).

---

## Check for updates

### `FlutterPatcher.checkForUpdate({timeout})`

The primary check. Uses whichever backend you configured.

```dart
Future<ServerUpdateResult> checkForUpdate({
  Duration timeout = const Duration(seconds: 10),
})
```

```dart
final result = await FlutterPatcher.checkForUpdate();
if (result.hasUpdate) {
  await FlutterPatcher.applyPatch(result.patch!);
}
```

`timeout` bounds the two HTTP round-trips (DB query + signed-URL mint); on
timeout a `TimeoutException` is thrown and the in-flight request cancelled.
Throws `PatcherException` if no backend was configured.

`ServerUpdateResult` fields:

| Field | Type | Meaning |
|-------|------|---------|
| `hasUpdate` | `bool` | `true` when not up-to-date **and** a patch is present |
| `patch` | `PatchInfo?` | The downloadable patch (null when `!hasUpdate`) |
| `status` | `AppUpdateStatus` | `update`, `rollback`, or `upToDate` |
| `shouldForceUpdate` | `bool` | Apply even on a normal cold start |
| `id` | `String?` | Bundle id (often the version string) |
| `message` | `String?` | "What's new" text — shown in the forced-update overlay |
| `gitCommitHash` | `String?` | Commit the bundle was built from |
| `raw` | `Map<String,dynamic>` | Original backend response |

### `FlutterPatcher.checkUpdate(url)`

A minimal HTTP check for bring-your-own-endpoint setups. Returns a
`PatchCheckResult` you parse yourself.

```dart
Future<PatchCheckResult> checkUpdate(
  String url, {
  Map<String, String>? headers,
  Duration timeout = const Duration(seconds: 10),
})
```

The endpoint must return:

```json
{
  "hasUpdate": true,
  "patch": {
    "version": "1.0.1",
    "patchUrl": "https://your-cdn.com/v100/patch.zip",
    "md5": "0123456789abcdef0123456789abcdef",
    "signature": "ed25519-sig-base64",
    "targetVersionCode": 100
  },
  "shouldForceUpdate": false,
  "message": "New onboarding flow"
}
```

Both `hasUpdate`/`has_update` and camel/snake `patchUrl` are accepted.

---

## Apply a patch

### Option 1 — let the SDK download it

```dart
Future<PatchApplyResult> applyPatch(
  PatchInfo patchInfo, {
  void Function(PatchApplyProgress)? onProgress,
})
```

```dart
final result = await FlutterPatcher.applyPatch(
  PatchInfo(
    version: '1.0.1',
    patchUrl: 'https://your-cdn.com/v100/patch.zip',
    md5: '0123456789abcdef0123456789abcdef',
    signature: 'ed25519-sig-base64',   // optional
    targetVersionCode: 100,
  ),
  onProgress: (p) => print('${p.phase.name}: ${(p.fraction ?? 0) * 100}%'),
);

if (result.ok) {
  // Staged. Takes effect on next cold start.
}
```

`patchUrl` may be `https://` (recommended), `http://` (Android 9+ blocks
cleartext by default), or `file:///…/patch.zip` (bundled patches). Downloads
follow cross-origin/scheme redirects (e.g. presigned S3/R2/CDN URLs) and retry
transient/corrupted transfers with backoff.

### Option 2 — apply bytes directly

```dart
Future<PatchApplyResult> applyPatchBytes(
  Uint8List bytes, {
  required String version,
  String signature = '',
  int? targetVersionCode,
  void Function(PatchApplyProgress)? onProgress,
})
```

Use when you've already fetched the bytes (FFI isolate, secure element,
in-memory cache) or the patch comes from a non-HTTP source.

---

## Apply update (full server-driven flow)

The common path: check, apply, auto-restart when forced.

```dart
Future<PatchApplyResult> applyUpdate(
  ServerUpdateResult result, {
  void Function(PatchApplyProgress)? onProgress,
})
```

Behavior:

- When `result.shouldForceUpdate` **and** `FlutterPatcher.showUpdateUi`
  (default `true`), the SDK shows the built-in terminal overlay during install.
- When forced, on success the SDK calls `restart()` after a short dwell so the
  new code loads immediately.
- On failure the overlay shows the error briefly; the app keeps running the old
  code. Only **deterministic** failures (`md5Mismatch`, `signatureInvalid`,
  `assetPackageInvalid`, `unsupportedAbi`, `invalidArgs`) blacklist the patch —
  transient failures (`network`, `ioError`, `unknown`) are simply retried next
  check.

### `checkAndApplyUpdates`

```dart
Future<PatchApplyResult?> checkAndApplyUpdates({
  void Function(PatchApplyProgress)? onProgress,
})
```

`checkForUpdate()` + `applyUpdate()` with guards: skips if the device is already
on the target version or if the bundle is blacklisted, and handles a
server-signaled `rollback`. This is what `init(autoApplyUpdates: true)` fires in
the background.

```dart
// From a "Check for updates" button or a background task:
await FlutterPatcher.checkAndApplyUpdates();
```

---

## The forced-update overlay

When a **forced** update installs and `showUpdateUi` is on, the SDK renders a
full-screen, terminal-style progress screen — you write no UI. It has:

- a **title bar** with a status pill (`RUNNING` / `FAILED`),
- a **META** block (channel, `current → target` version, bundle hash, size),
- a **STEPS** list — Initialize → Download → Verify → Install → Finalize — each
  with a live braille spinner / ✓ / ✗,
- a **PROGRESS** block — a monospace bar plus speed / ETA / phase,
- a scrolling **LOG** feed, and
- a **footer** (deploy message, or an error hint + `[ retry ]`).

### Wiring it

The zero-code path is `FlutterOtaApp` + `FlutterPatcher.navigatorKey`:

```dart
runApp(const FlutterOtaApp(child: MyApp()));

MaterialApp(
  navigatorKey: FlutterPatcher.navigatorKey,
  // …
);
```

Controls:

- `FlutterPatcher.showUpdateUi = false` (or `FlutterOtaApp(showUpdateUi: false)`)
  disables it — forced updates still apply silently.
- Setting `MaterialApp.navigatorKey = FlutterPatcher.navigatorKey` alone is
  enough; `FlutterOtaApp` is a convenience wrapper.

### Driving it yourself (advanced)

`OtaProgressOverlay` is a plain widget driven by a
`ValueNotifier<OtaOverlayState>`, and `OtaOverlayManager.instance` +
`OtaOverlayHandle` let you show/update/end it manually if you're building a
custom flow. Most apps never touch these directly.

---

## Handle the result

`applyPatch` / `applyPatchBytes` / `applyUpdate` return `PatchApplyResult`:

```dart
class PatchApplyResult {
  final bool ok;
  final PatchApplyError? error;   // set when !ok
  final String? message;          // developer-facing; don't show to users
}
```

`ok == true` means the patch is staged for the next cold start.

---

## Error codes

`PatchApplyError` (exhaustive):

| Value | When |
|-------|------|
| `invalidArgs` | Missing version/URL, malformed MD5, target-version mismatch, unsupported mode. |
| `blacklisted` | The `(version, md5)` payload is in the local bad-patch blacklist. |
| `network` | Download failed after retries with backoff. (Transient — not blacklisted.) |
| `md5Mismatch` | Downloaded bytes' MD5 ≠ `PatchInfo.md5` after retries. Corruption or tampering. |
| `signatureInvalid` | Ed25519 check failed. Tampering or wrong public key. |
| `unsupportedAbi` | No `libapp.so` for this device's ABI in the patch. |
| `assetPackageInvalid` | Bad zip/schema/manifest, unsafe path, missing asset entry. |
| `ioError` | Filesystem, disk-space, copy, fsync, or rename failure. (Transient.) |
| `unknown` | Unclassified native/channel error. Check `logcat`. |

---

## Listen to progress

`FlutterPatcher.applyProgress` is a broadcast `Stream<PatchApplyProgress>`.
Subscribe before calling apply, or use the `onProgress` callback.

`PatchApplyProgress` fields:

| Field | Type | Meaning |
|-------|------|---------|
| `phase` | `PatchApplyPhase` | `downloading`, `verifying`, or `finalizing` |
| `bytesReceived` | `int` | Bytes downloaded (during `downloading`) |
| `totalBytes` | `int` | Content-Length; `-1` if the server didn't send one |
| `fraction` | `double?` | 0.0–1.0, or `null` when unknown |

---

## Roll back

```dart
Future<void> rollback()                     // delete current patch → base APK next boot
Future<RollbackOutcome> rollbackToPrevious()// restore the previous non-blacklisted patch
Future<void> restart()                      // cold-restart the process now
```

`rollback()` is a **local** operation — it doesn't touch your backend. To also
remove the bundle server-side, run `flutter-ota rollback --channel <c>` or
`flutter-ota bundle delete --id <id>`.

`rollbackToPrevious()` returns a `RollbackOutcome`: `success`,
`skippedBlacklisted`, or `fallbackToBase`. Call `restart()` afterward to
activate it.

---

## Boot diagnostics

### `FlutterPatcher.lastBootDiagnostic`

```dart
Future<PatchBootDiagnostic?> get lastBootDiagnostic
```

Describes what happened to the patch on the most recent cold start. Ship it to
your analytics to catch a bad patch early.

```dart
class PatchBootDiagnostic {
  final PatchBootStatus status;
  final DateTime recordedAt;
  final String? patchVersion;
  final int? patchTargetVersionCode;
  final int? appVersionCode;
  final int? crashCount;
  final List<String>? attemptedLoaderFields;
  final String? message;
  bool get isHealthy;   // true when status is patched or noPatch
}
```

`PatchBootStatus` values: `noPatch`, `patched`, `droppedVersionCodeMismatch`,
`droppedMd5Mismatch`, `droppedSignatureInvalid`, `droppedMetaCorrupted`,
`droppedCircuitBreaker`, `hookInstallFailed`, `unknown`.

### `FlutterPatcher.reportBootSuccess()`

Called automatically after the first frame. Call it earlier (e.g. from a
`postFrameCallback` after a long splash) to close the crash-verification window
sooner.

---

## Query state

```dart
static Future<int?>    get appVersionCode  // current APK versionCode
static Future<String>  get deviceAbi       // current device ABI
static Future<String?> get currentVersion  // installed patch version (null = none)
static Future<List<BlacklistEntry>> get blacklist
static Future<void>    clearBlacklist()
static Future<bool>    isVersionBlacklisted(String version, {String md5 = ''})
```

---

## Blacklist

A local list of patch payloads the SDK refuses to retry, populated by
deterministic failures and boot crashes. Each `BlacklistEntry` has `version`,
`md5`, `reason` (`BOOT_CRASH`, `MD5_MISMATCH`, `SIGNATURE_INVALID`, or
`APPLY_FAILED`), and `blacklistedAt`. It is **not** cleared on app upgrade — an
operator must call `clearBlacklist()` (or the device rolls onto a new
`versionCode`). A re-cut patch with a **new md5** is not blocked, so shipping a
fixed build under a new version bypasses a prior blacklist naturally.

---

## Asset patching

Include Flutter assets in a patch by rebuilding the APK with the new assets
registered, then packing with `--assets`:

```bash
flutter build apk --release
flutter-ota build \
  --apk build/app/outputs/flutter-apk/app-release.apk \
  --version 1.0.1 \
  --target-version-code 100 \
  --assets assets/hero.png,assets/strings/zh.json
```

The patch's `assets/` tree overlays the base APK's `flutter_assets/` at install
time — existing `Image.asset()` / `rootBundle.load()` calls pick up the new
bytes with no code change.

### Payload layout (`patch.zip`, v2)

```
patch.zip
├── lib/<abi>/libapp.so
├── assets/AssetManifest.json
├── assets/AssetManifest.bin
├── assets/<your-file-1>
├── manifest.json
└── version.json
```

### Asset path rules

| Path | OK? |
|------|-----|
| `assets/hero.png` | ✅ relative to project root |
| `assets/icons/home.svg` | ✅ nested |
| `/abs/path/x.png` | ❌ absolute |
| `assets/*` | ❌ glob — list each file, or use `--assets @list.txt` |

Every listed asset must exist in the rebuilt APK's `flutter_assets/` and be
registered in `pubspec.yaml`. Asset patches inherit the same MD5 + Ed25519
verification as `libapp.so`.

---

## What can and cannot be patched

| ✅ Hot-patchable | ❌ Not hot-patchable |
|------------------|----------------------|
| Anything in `lib/` — widgets, logic, routes, constants | Native code (Kotlin / Java / C++) |
| Pure-Dart package upgrades (same native side) | `AndroidManifest.xml` changes |
| Flutter assets registered in `pubspec.yaml` | APK `res/` (icons, layouts, strings.xml) |
| New `Image.asset()` / `rootBundle.load()` calls | Flutter Engine upgrades |
| | Adding/removing native plugins |
| | Removing assets that exist in the base APK |

A patch is byte-coupled to a specific host APK + Flutter Engine. After a store
release or a Flutter SDK upgrade, ship a fresh build before deploying more
patches — old patches expire against the new `versionCode`.

---

## Custom update source

The five built-in backends cover most needs. For anything else you can:

1. **Adapt a built-in source** by passing a custom client to its config's
   `clientFactory` seam (e.g. an S3-compatible endpoint, or a mock for tests).
2. **Call `performSharedUpdateCheck` directly** with your own `DatabasePlugin` /
   `StoragePlugin` implementations (both types come from the same single
   `flutter_ota_kit` import):

```dart
final result = await performSharedUpdateCheck(
  db: myCustomDb,
  storage: myCustomStorage,
  channel: 'production',
  platform: Platform.android,
  updateStrategy: UpdateStrategy.appVersion,
  appVersion: '1.0.0',
  fingerprintHash: null,
  minBundleId: /* nil uuid */ '00000000-0000-0000-0000-000000000000',
);
```

3. **Skip the SDK's check entirely** — build a `ServerUpdateResult` from your own
   response and call `applyUpdate(result)`.

---

## PatchInfo

```dart
class PatchInfo {
  final String version;          // unique id, e.g. "1.0.1"
  final String patchUrl;         // https:// | http:// | file://
  final String md5;              // 32-char lowercase hex; "" disables MD5 (test only)
  final String signature;        // Ed25519 sig, base64; "" disables sig check
  final int? targetVersionCode;  // host APK versionCode; null = any
  final Map<String, dynamic> raw;

  factory PatchInfo.fromJson(Map<String, dynamic> json);
  Map<String, dynamic> toJson();
}
```

`fromJson` accepts camelCase and snake_case (`patchUrl`/`patch_url`,
`targetVersionCode`/`target_version_code`). The signature is computed over the
**MD5 hex string**, not the raw bytes. An empty `md5` skips both MD5 and
signature verification and logs a warning (never do this in production).

---

## Enums

| Enum | Values |
|------|--------|
| `PatchApplyPhase` | `downloading`, `verifying`, `finalizing` |
| `PatchApplyError` | `invalidArgs`, `blacklisted`, `network`, `md5Mismatch`, `signatureInvalid`, `unsupportedAbi`, `assetPackageInvalid`, `ioError`, `unknown` |
| `AppUpdateStatus` | `upToDate`, `rollback`, `update` |
| `UpdateStrategy` | `appVersion`, `fingerprint` |
| `Platform` | `android`, `ios` (only `android` is functional) |
| `PatchBootStatus` | `noPatch`, `patched`, `droppedVersionCodeMismatch`, `droppedMd5Mismatch`, `droppedSignatureInvalid`, `droppedMetaCorrupted`, `droppedCircuitBreaker`, `hookInstallFailed`, `unknown` |
| `RollbackOutcome` | `success`, `fallbackToBase`, `skippedBlacklisted` |

---

## Version compatibility

| flutter_ota_kit | Dart SDK | Flutter | Notes |
|-----------------|----------|---------|-------|
| **0.2.0** | ≥ 3.13.2 | ≥ 3.47.2 | Current — single-package release (all backends bundled) |
| 0.1.x | ≥ 3.13.0 | ≥ 3.32.0 | Multi-package era (separate backend packages) |

Upgrading `flutter_ota_kit` or Flutter itself means shipping a new app release
before deploying more patches — the loader hook is native and each patch is
byte-coupled to the host binary + engine.

---

## See also

- [Architecture](architecture.md) — internals, server protocol, signing
- [Crash Protection](crash-protection.md) — auto-rollback, blacklist, boot window
- [Configuration](configuration.md) — env vars, `.env`, resolution order
- [Backends](backends.md) — per-backend setup
- [Production Playbook](production-playbook.md) — staged rollout, diagnostics, rollback
