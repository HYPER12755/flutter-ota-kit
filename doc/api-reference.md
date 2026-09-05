# API Reference

**English** | [简体中文](api-reference-zh.md)

Every public API in `flutter_ota_kit` is exposed as a static member on
the `FlutterPatcher` class. The plugin only executes patch logic on
Android. On iOS, Web, macOS, Windows, and Linux, calling these APIs is
a **no-op** — they don't throw, they print a one-time warning on first
call, and they return safe defaults.

This is the reference for the **public SDK surface**. For internals
(how a patch actually loads, the signing protocol, the boot-time
loader hook), see [Architecture](architecture.md). For setup, see
[Getting Started](getting-started.md).

---

## Table of contents

- [Initialization](#initialization)
- [Check for updates](#check-for-updates)
- [Apply a patch](#apply-a-patch)
- [Apply update (full server-driven flow)](#apply-update-full-server-driven-flow)
- [Handle the result](#handle-the-result)
- [Error codes](#error-codes)
- [Listen to progress](#listen-to-progress)
- [Roll back](#roll-back)
- [Boot diagnostics](#boot-diagnostics)
- [Query state](#query-state)
- [Blacklist](#blacklist)
- [Asset patching](#asset-patching)
- [Custom update source](#custom-update-source)
- [PatchInfo](#patchinfo)
- [Version compatibility](#version-compatibility)

---

## Initialization

### `FlutterPatcher.init`

Configure patch loader, crash protection, and boot diagnostics.
**Call this once before `runApp()`**. Idempotent — repeated calls are
safe no-ops.

```dart
Future<void> init({
  String publicKeyBase64 = '',
  int maxCrashCount = 1,
  bool strictSignature = true,
  List<String> loaderFieldCandidates = const ['flutterLoader'],
  bool loaderFallbackHeuristic = false,
  Duration verifyAfter = const Duration(seconds: 5),
  bool autoApplyUpdates = false,
})
```

| Parameter | Default | What it does |
|-----------|---------|--------------|
| `publicKeyBase64` | `''` | Ed25519 public key (X.509 SubjectPublicKeyInfo, base64) for patch signature verification. Empty disables signing. |
| `maxCrashCount` | `1` | Fail-fast: after this many early boot failures with a patch, auto-rollback. Set to `0` to disable. |
| `strictSignature` | `true` | Reject signed patches on Android API < 33 (the platform Ed25519 implementation is unreliable there). Set `false` to allow signed patches on older Android. |
| `loaderFieldCandidates` | `['flutterLoader']` | Field names the native loader looks for when restoring. **Don't change** unless adapting a new Flutter version. |
| `loaderFallbackHeuristic` | `false` | Enable a fallback loader path for unusual Flutter embedders. **Don't enable** unless instructed. |
| `verifyAfter` | `5s` | Post-first-frame Dart error watch window. Errors during this window trigger crash rollback. |
| `autoApplyUpdates` | `false` | Zero-click forced updates: after boot protection, run `checkAndApplyUpdates` in the background. A forced update downloads, stages, and the process restarts automatically. |

```dart
import 'package:flutter_ota_kit/flutter_ota_kit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterPatcher.init();
  runApp(const MyApp());
}
```

For zero-click forced updates, also set `autoApplyUpdates: true` and wrap
your app in `FlutterOtaApp`:

```dart
await FlutterPatcher.init(autoApplyUpdates: true);
runApp(const FlutterOtaApp(child: MyApp()));
```

The backend must be configured (via `configureSupabase(...)` etc., or
auto-detected from env vars) before `init()` is called for
`autoApplyUpdates` to work.

---

## Check for updates

### `FlutterPatcher.checkUpdate(url)`

Built-in minimal HTTP check for the simplest deployments. Returns a
`PatchCheckResult` you parse yourself.

```dart
Future<PatchCheckResult> checkUpdate(
  String url, {
  Map<String, String>? headers,
  Duration timeout = const Duration(seconds: 10),
})
```

```dart
final result = await FlutterPatcher.checkUpdate(
  'https://your-cdn.com/api/check-update?v=1.0.0',
  headers: {'Authorization': 'Bearer <token>'},
);

if (result.hasUpdate && result.patch != null) {
  await FlutterPatcher.applyPatch(result.patch!);
}
```

The endpoint must return this JSON:

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

The SDK accepts both `hasUpdate` and `has_update` (snake_case). The
`patch` object may be a top-level map or nested under a `patch` key.

### `FlutterPatcher.checkForUpdate({timeout})`

The richer check. Uses whichever backend you configured via
`configureSupabase` / `configurePostgres` / etc. (or auto-detected
from env vars).

```dart
Future<ServerUpdateResult> checkForUpdate({
  Duration timeout = const Duration(seconds: 10),
})
```

```dart
final result = await FlutterPatcher.checkForUpdate();

if (result.hasUpdate) {
  // result.patch is non-null when hasUpdate is true
  await FlutterPatcher.applyPatch(result.patch!);
}
```

The `timeout` parameter bounds the two HTTP round-trips (DB query + signed-URL
mint). On timeout, a `TimeoutException` with a clear message is thrown
and the in-flight HTTP request is cancelled.

`ServerUpdateResult` fields:

| Field | Type | Meaning |
|-------|------|---------|
| `hasUpdate` | `bool` | `true` if a patch is available |
| `patch` | `PatchInfo?` | The downloadable patch (null when `!hasUpdate`) |
| `status` | `AppUpdateStatus` | `update`, `rollback`, or `upToDate` |
| `shouldForceUpdate` | `bool` | Server wants the patch applied even on a normal cold start |
| `id` | `String?` | The bundle id (often the version string) |
| `message` | `String?` | Human-readable "what's new" text — shown in the forced-update overlay |
| `raw` | `Map<String, dynamic>` | The original backend response, in case you need extra fields |

---

## Apply a patch

### Option 1: let the SDK download the patch

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
  onProgress: (p) {
    print('${p.phase.name}: ${(p.fraction ?? 0) * 100}%');
  },
);

if (result.ok) {
  // Patch is staged. Takes effect on next cold start.
  // For forced updates, FlutterPatcher.restart() is called automatically
  // when you used applyUpdate() instead.
}
```

`patchUrl` may be:
- `https://your-cdn.com/...` — standard, recommended
- `http://...` — works but not recommended (Android 9+ blocks cleartext
  by default)
- `file:///data/data/<pkg>/files/patch.zip` — for bundled patches
  (e.g. the example app's `assets/patch_demo.zip` style)

### Option 2: apply patch bytes directly

```dart
Future<PatchApplyResult> applyPatchBytes(
  Uint8List bytes, {
  required String version,
  String signature = '',
  int? targetVersionCode,
  void Function(PatchApplyProgress)? onProgress,
})
```

```dart
// For example, fetch the bytes yourself and apply them.
final bytes = await loadPatchFromIsolate();
final result = await FlutterPatcher.applyPatchBytes(
  bytes,
  version: '1.0.1',
  targetVersionCode: 100,
);
```

Use this when:
- You've already downloaded the bytes (for example, in a FFI isolate)
- The patch comes from a non-HTTP source (asset bundle, secure element,
  in-memory cache)
- You need full control over the IO

---

## Apply update (full server-driven flow)

The most common path: check, apply, auto-restart if forced.

```dart
Future<PatchApplyResult> applyUpdate(
  ServerUpdateResult result, {
  void Function(PatchApplyProgress)? onProgress,
})
```

```dart
final result = await FlutterPatcher.checkForUpdate();
if (result.hasUpdate && result.patch != null) {
  await FlutterPatcher.applyUpdate(result, onProgress: (p) {
    print('${p.phase.name}: ${(p.fraction ?? 0) * 100}%');
  });
}
```

Behavior:

- If `result.shouldForceUpdate` is `true` and `FlutterPatcher.showUpdateUi`
  is `true` (the default), the SDK shows the built-in progress overlay
  during the install.
- If `result.shouldForceUpdate` is `true`, the SDK calls `FlutterPatcher.restart()`
  after a successful install. This restarts the process so the new code
  loads immediately.
- If the install fails, the SDK shows the error in the overlay for 6
  seconds, then the overlay is removed. The app keeps running on the
  old code.

The convenience wrapper:

```dart
Future<PatchApplyResult?> checkAndApplyUpdates({
  void Function(PatchApplyProgress)? onProgress,
})
```

does `checkForUpdate() + applyUpdate()` with one extra guard: if the
device is already on the same version as the new patch, it skips the
install (no infinite restart loops). This is the method `init(autoApplyUpdates: true)`
fires in the background.

```dart
// From your background task or a "Check for updates" button:
await FlutterPatcher.checkAndApplyUpdates();
```

---

## Handle the result

Both `applyPatch` and `applyPatchBytes` return a `PatchApplyResult`:

```dart
class PatchApplyResult {
  final bool ok;
  final PatchApplyError? error;
  final String? message;
}
```

| Field | Meaning |
|-------|---------|
| `ok` | `true` if the patch is staged and ready for the next cold start. |
| `error` | A `PatchApplyError` enum value when `ok` is `false`. |
| `message` | Developer-facing error description. Don't show directly to users. |

---

## Error codes

`PatchApplyError` is an exhaustive enum:

| Value | When |
|-------|------|
| `invalidArgs` | Missing version/URL, malformed MD5, target version mismatch, unsupported mode. |
| `blacklisted` | The same `(version, md5)` payload is in the local bad-patch blacklist. Auto-recovered by crash protection. |
| `network` | Download failed after 3 retries with exponential backoff. |
| `md5Mismatch` | The downloaded bytes' MD5 didn't match `PatchInfo.md5`. Possible CDN corruption or tampering. |
| `signatureInvalid` | Ed25519 signature check failed. Possible tampering or wrong public key. |
| `unsupportedAbi` | The patch has no `libapp.so` for this device's ABI. |
| `assetPackageInvalid` | Bad zip/schema/manifest, unsafe path, missing asset entry. |
| `ioError` | Filesystem, disk space, copy, fsync, or rename failure. |
| `unknown` | Unclassified native / channel error. Check `logcat`. |

```dart
if (!result.ok && result.error == PatchApplyError.network) {
  // The user's network is bad. Tell them to retry on Wi-Fi.
}
```

---

## Listen to progress

### `FlutterPatcher.applyProgress`

A broadcast `Stream<PatchApplyProgress>` that emits during `applyPatch`
and `applyPatchBytes`. Subscribe before calling apply to receive
events.

```dart
Stream<PatchApplyProgress> get applyProgress
```

`PatchApplyProgress` fields:

| Field | Type | Meaning |
|-------|------|---------|
| `phase` | `PatchApplyPhase` | `downloading`, `verifying`, or `finalizing` |
| `bytesReceived` | `int` | Bytes downloaded (only meaningful during `downloading`) |
| `totalBytes` | `int` | Content-Length from the server; `-1` if not provided |
| `fraction` | `double?` | Download progress 0.0–1.0, or `null` if unknown |

```dart
final sub = FlutterPatcher.applyProgress.listen((p) {
  if (p.phase == PatchApplyPhase.downloading && p.fraction != null) {
    // update your custom progress bar
  }
});

try {
  await FlutterPatcher.applyPatch(patch);
} finally {
  await sub.cancel();
}
```

Or use the convenience `onProgress` parameter on `applyPatch` /
`applyUpdate` / `checkAndApplyUpdates` for a one-off callback.

---

## Roll back

```dart
Future<void> rollback()
```

Deletes the current patch. The app reverts to the base APK on the next
cold start. Does **not** clear the blacklist — blacklisted patches
stay blacklisted until you explicitly call `clearBlacklist()`.

```dart
// Emergency: kill the patch and force a restart
await FlutterPatcher.rollback();
// The user reopens the app — they get the base APK's code.
```

This is a **local** operation. It does not change your backend. The
server still has the bad bundle; the device just stops trying to apply
it. To also remove the bundle from the server, run
`flutter-ota bundle delete <id>` on the CLI.

---

## Boot diagnostics

### `FlutterPatcher.lastBootDiagnostic`

```dart
Future<PatchBootDiagnostic?> get lastBootDiagnostic async
```

Returns a `PatchBootDiagnostic?` describing what happened on the most
recent cold start. Send this to your analytics pipeline to spot a bad
patch before users hit the app.

```dart
class PatchBootDiagnostic {
  final String? version;            // patch version that was loaded
  final BootOutcome outcome;         // success | md5Mismatch | signatureFailure | crashRollback | loaderFailure | unknown
  final DateTime? timestamp;
}
```

`outcome` values:

| Value | Meaning |
|-------|---------|
| `success` | Patched `libapp.so` loaded cleanly. |
| `md5Mismatch` | The loader found the patch but its MD5 didn't match. The patch was auto-rolled back. |
| `signatureFailure` | The signature didn't match. Auto-rolled back. |
| `crashRollback` | The patch loaded but the app crashed within `verifyAfter`. Auto-rolled back. |
| `loaderFailure` | The Flutter loader hook couldn't load the patch. Auto-rolled back. |
| `unknown` | The diagnostic wasn't recorded (e.g. no patch was installed). |

---

### `FlutterPatcher.reportBootSuccess()`

Normally called automatically by the SDK after the first frame. If
you want to call it earlier (e.g. after a critical async init), you can:

```dart
Future<void> reportBootSuccess()
```

Once the SDK has called this, the boot window closes. Subsequent
crashes don't trigger auto-rollback. If your app's first frame is
delayed (e.g. a splash screen that takes 10s), call this from a
`postFrameCallback` to short-circuit the boot window.

---

## Query state

```dart
static Future<int?>    get appVersionCode async   // current APK versionCode
static Future<String>  get deviceAbi async         // current device ABI
static Future<String?> get currentVersion async    // installed patch version
static Future<List<BlacklistEntry>> get blacklist async
static Future<void>     clearBlacklist()            // for tests / ops
```

Example: ship a debug overlay that shows the current state:

```dart
final v = await FlutterPatcher.currentVersion;
final code = await FlutterPatcher.appVersionCode;
final abi = await FlutterPatcher.deviceAbi;
print('patch=$v versionCode=$code abi=$abi');
```

---

## Blacklist

A local list of patch versions the SDK has refused to retry. Caused
by:

- **Cold-start MD5 mismatch** — the patch was installed but its bytes
  on disk don't match the expected MD5. This usually means disk
  corruption, not tampering.
- **Cold-start signature failure** — the signature didn't match.
  Either a wrong public key in the build, or a tampered patch.
- **Boot crash** — the patch loaded but the app crashed within
  `verifyAfter`. The most common cause is an actually-broken patch.

Each entry has a `version`, an `md5`, a `reason` (one of
`md5Mismatch`, `signatureFailure`, `crashRollback`), and a
`timestamp`. The SDK reads this list at update-check time and
excludes matching bundles.

```dart
// In a debug overlay:
for (final entry in await FlutterPatcher.blacklist) {
  print('${entry.version} blacklisted: ${entry.reason}');
}
```

To clear (for tests or after fixing the root cause):

```dart
await FlutterPatcher.clearBlacklist();
```

---

## Asset patching

Since 0.1.3, you can include Flutter assets in your patch. The
workflow is:

```bash
# 1. Rebuild your APK with the NEW assets registered
flutter build apk --release

# 2. Pack with --assets. Each path is relative to the project root.
flutter-ota build --name 1.0.1 --platform android --arch x86_64 \
  --assets assets/hero.png,assets/strings/zh.json
```

The patch's `assets/` tree is overlaid on the base APK's
`flutter_assets/` at install time. Existing `Image.asset()` and
`rootBundle.load()` calls in the new Dart code pick up the new bytes
**without any code changes**.

### Payload layout (`patch.zip`, v2)

```
patch.zip
├── lib/<abi>/libapp.so
├── assets/AssetManifest.json
├── assets/AssetManifest.bin
├── assets/<your-file-1>
├── assets/<your-file-2>
├── manifest.json
└── version.json
```

The two manifests are required by Flutter's asset bundle loader. They
describe which assets the new APK declares. The SDK writes both from
the new APK's `flutter_assets/` automatically.

### Asset path requirements

| Path format | OK? |
|-------------|-----|
| `assets/hero.png` | ✅ Relative to project root |
| `assets/icons/home.svg` | ✅ Nested |
| `/Users/me/project/assets/x.png` | ❌ Absolute |
| `*.png` | ❌ Glob (you must list each file) |
| `assets/*` | ❌ Glob (use `@file` syntax) |

To list a file from a separate file:

```bash
flutter-ota build --assets @asset_list.txt
# asset_list.txt:
#   assets/hero.png
#   assets/icons/home.svg
#   assets/strings/zh.json
```

### ABI handling

The patch contains `lib/<abi>/libapp.so` for every ABI you built
(default: `arm64-v8a`, `armeabi-v7a`, `x86_64`). Each ABI is patched
independently. If you ship to a single ABI only:

```bash
flutter-ota build --abi arm64-v8a
```

the resulting patch is ~3× smaller and applies only to ARM64 devices.
Mixed-ABI fleets need to deploy one bundle per ABI per release.

### Validation errors

The pack command fails fast on these:

- **Asset not in the new APK**: The path you passed to `--assets`
  doesn't exist in `build/app/outputs/flutter-apk/app-release.apk`'s
  `flutter_assets/`. Re-run `flutter build apk` after adding the asset.
- **Path outside the project root**: rejected with a clear error.
- **Asset not registered in pubspec.yaml**: Flutter will silently
  exclude the asset from the bundle. The patch installs but the asset
  is still loaded from the base APK.

### Security

Asset patches inherit the patch's MD5 + Ed25519 signature verification.
A tampered `patch.zip` is rejected at install time the same way a
tampered `libapp.so` is.

---

## Custom update source

The five built-in backends (Supabase / Postgres / Cloudflare / AWS /
PocketBase) cover most production needs. For anything else, you can
either:

1. **Adapt the built-in `XxxUpdateSource`** by passing a custom client
   to its `config.clientFactory`. For example, a `MockSupabaseClient`
   for tests, or a custom `S3Client` for S3-compatible storage.
2. **Implement your own** by calling `performSharedUpdateCheck`
   directly:

```dart
import 'package:flutter_ota_kit/flutter_ota_kit.dart';
import 'package:flutter_ota_kit_plugin_core/flutter_ota_kit_plugin_core.dart';

final result = await performSharedUpdateCheck(
  db: myCustomDb,
  storage: myCustomStorage,
  channel: 'production',
  platform: Platform.android,
  updateStrategy: UpdateStrategy.appVersion,
  appVersion: '1.0.0',
  fingerprintHash: null,
  minBundleId: nilUuid,
);
```

You supply any `DatabasePlugin` and `StoragePlugin` that implement the
plugin-core interfaces. See
[Plugin core](https://pub.dev/packages/flutter_ota_kit_plugin_core) for
the contract.

3. **Skip the SDK's check entirely** and parse the response yourself
   into a `ServerUpdateResult`, then call `applyUpdate(result)`:

```dart
final response = await myCustomHttpGet(...);
final result = ServerUpdateResult(
  isUpToDate: response.upToDate,
  patch: response.hasPatch
      ? PatchInfo(version: response.version, patchUrl: response.url, md5: response.md5)
      : null,
  shouldForceUpdate: response.forceUpdate,
  message: response.message,
);
if (result.hasUpdate) {
  await FlutterPatcher.applyUpdate(result);
}
```

---

## PatchInfo

```dart
class PatchInfo {
  final String version;          // unique id, e.g. "1.0.1" or "fix-2024-01-15"
  final String patchUrl;         // https://, http://, or file://
  final String md5;              // hex; "" disables MD5 check (test only)
  final String signature;        // Ed25519 sig, base64; "" disables sig check
  final int? targetVersionCode;  // host APK versionCode; null = any
  final String? message;         // human-readable "what's new"

  factory PatchInfo.fromJson(Map<String, dynamic> json);
  Map<String, dynamic> toJson();
}
```

`fromJson` accepts both `patchUrl` (camelCase) and `patch_url`
(snake_case) for cross-language backend compatibility. Same for
`targetVersionCode` / `target_version_code`.

`md5` must be lowercase hex, 32 chars (128 bits). The empty string is
allowed for test deployments but produces a warning at runtime.

`signature` must be a base64-encoded Ed25519 signature (88 chars
unpadded, or 88 with padding). The signature is over the **MD5 hex
string**, not the raw bytes — this is what the SDK computes at
verification time.

`targetVersionCode` is required when you want to prevent a patch
from applying to the wrong host APK. The backend should set it, but
the client also rejects mismatches as a defense-in-depth measure.

---

## Version compatibility

`flutter_ota_kit` follows [semver](https://semver.org/). Compatibility
matrix (last verified):

| flutter_ota_kit | Dart SDK | Flutter  | Status                                  |
|----------------|----------|----------|-----------------------------------------|
| 0.1.10         | ≥ 3.13.0 | ≥ 3.47.0 | Current; recommended                   |
| 0.1.9          | ≥ 3.13.0 | ≥ 3.32.0 | Previous release; auto-update safe     |
| 0.1.5          | ≥ 3.0.0  | ≥ 3.19.0 | Legacy; loader hook stable              |
| 0.1.0 – 0.1.4  | ≥ 3.0.0  | ≥ 3.0.0  | Pre-`autoApplyUpdates`; no UI          |

If you upgrade flutter_ota_kit, expect to need a new app release (the
loader hook is part of the native plugin and the patch is bound to
the host binary).

If you upgrade Flutter itself, **you must ship a new app release**
before shipping more patches. Old patches are byte-coupled to the
old Flutter Engine.

---

## See also

- [Architecture](architecture.md) — internals, server protocol,
  signing, advanced config
- [Crash Protection](crash-protection.md) — auto-rollback, blacklist,
  Android version differences
- [Configuration](configuration.md) — env vars, `.env`, resolution order
- [Backends](backends.md) — per-backend setup, env vars, CLI snippets
- [Production Playbook](production-playbook.md) — staged rollout,
  diagnostic reporting, emergency rollback
- [Golden Testing](golden-testing.md) — how Flutter's pixel-perfect
  test system works (and how this project uses it for the forced-update
  overlay)
