# Architecture

How `flutter_ota_kit` actually works — the patch lifecycle, the data model,
the signing protocol, the boot-time loader, the crash rollback, the
asset-overlay synthesis, and the things that are not portable across
the Flutter / Android boundary.

This doc is for people who need to:
- Debug a failed update
- Host their own update endpoint or CDN
- Add a new storage backend
- Modify the signing / verification logic
- Decide whether flutter_ota_kit fits their security model

For "how to set it up and deploy", see [Getting Started](getting-started.md).
For the public SDK surface, see [API Reference](api-reference.md).

---

## Backends

The SDK is **backend-agnostic** at the device side. The device talks to a
plugin-agnostic interface, and each backend plugin implements that
interface over its cloud's native API.

```
┌────────────────────┐  HTTP   ┌────────────────────┐
│   The app          │ ──────▶ │   Your backend     │
│                    │         │                    │
│  SupabaseUpdateCfg │         │  supabaseDatabase()│  PostgREST + Storage signed URL
│  PostgresUpdateCfg │         │  postgresDatabase()│  pgwire + bytea download URL
│  CloudflareUpdateCfg│        │  d1Database()      │  REST /d1/query + R2 presigned URL
│  AwsUpdateCfg      │         │  s3Database()      │  S3 list/get + presigned URL
│  PocketBaseUpdateCfg│        │  pocketbaseDatabase()│ REST /records + /files token
│                    │         │                    │
└────────────────────┘         └────────────────────┘
```

Five built-in backends, all first-class. Adding a sixth is "implement
two methods: `getUpdateInfo()` and `getDownloadUrl()`" — the SDK core
doesn't know or care which one you pick.

Each backend has a `RuntimeStorageProfile.getDownloadUrl(storageUri)`
that returns an HTTP URL the device's native `applyPatch` can stream from.
The native side just needs bytes — the protocol, auth, and signing
happen in the plugin.

---

## How it works

### Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  Server side:                   Device side:                    │
│  ─────────                      ───────────                     │
│                                                                 │
│  ┌────────────┐                ┌──────────────────────┐         │
│  │ patch.zip  │ ─── HTTP ───▶ │ checkForUpdate()      │         │
│  │ (in S3/R2/ │                │   ├─ getUpdateInfo    │         │
│  │  bucket)   │                │   └─ getDownloadUrl  │         │
│  └────────────┘                │        ↓             │         │
│       ▲                        │  PatchInfo(url, md5) │         │
│       │                        │        ↓             │         │
│  ┌────────────┐                │  applyPatch()        │         │
│  │ manifest   │                │   ├─ download       │         │
│  │ (metadata) │                │   ├─ verify MD5     │         │
│  └────────────┘                │   ├─ verify sig (opt) │       │
│       ▲                        │   └─ atomic rename    │         │
│       │                        │        ↓             │         │
│  ┌────────────┐                │  next cold start     │         │
│  │ bundles   │                │   └─ loader hook     │         │
│  │ table      │                │      applies patch   │         │
│  └────────────┘                │      if boot ok:     │         │
│                                │        keep          │         │
│                                │      if boot fail:   │         │
│                                │        auto-rollback │         │
│                                └──────────────────────┘         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

Three logical pieces: a **bundle store** (the `bundles` table — one row
per OTA release), a **payload store** (the `patch.zip` blob in
S3/R2/Supabase Storage), and the **client** (your app + the SDK).

### Patch lifecycle

A patch goes through these states:

```
       CLI                     server                  device
       ───                     ──────                  ──────
  1.  build APK ──>
  2.  pack      ──> stores  patch.zip
                 ──> writes  bundles row
  3.                                  check-update <──
  4.                              ──> PatchInfo(url,md5)
  5.  download  patch.zip <─────────────────
  6.  verify    MD5 + sig
  7.  stage     atomic rename to patch dir
  8.  cold start
  9.  loader hook reads patched libapp.so
  10. app boots
      ok ──> mark patch success, no-op next time
      fail ──> auto-rollback + blacklist
```

Two things to notice:

- Steps 5–7 are all on the device. The server's only job after step 2 is to
  serve the bytes (and respond to the check-update query). The device
  does everything else locally.
- The patch is **never swapped into the running process**. It loads on
  the next cold start. This is enforced at the loader-hook level — see
  "Atomic install" below.

### VersionCode binding

Each patch has a `targetVersionCode` (the `versionCode` of the host APK
the user must have installed for the patch to apply). The SDK filters
at update-check time:

```
client.appVersionCode  →  patch.targetVersionCode
```

Mismatch → backend returns no bundle. This protects against:

- **Stale patches after an APK upgrade**: A user who upgraded to
  `versionCode 100` should not accidentally load a patch built for
  `versionCode 99`. The server filters them out.
- **Wrong-channel patches**: A user on the `beta` channel should not
  receive a `production`-only patch. (Channel is a server-side filter.)

The CLI's `--target-app-version` flag must match the user's currently
installed `versionCode`, not the new APK's. This is the #1 cause of
"the update never arrives" — see [FAQ](faq.md#how-does-the-client-report-its-app-version-and-why-must-it-match---target-app-version-).

### Crash safety

The crash-protection state machine is the most safety-critical piece
of the SDK. It's documented separately in
[Crash Protection](crash-protection.md) — read that for the boot
window, the boot-error detection, the blacklist, and the Android
version differences.

Summary: if a patch causes a boot failure, the SDK auto-rolls back on
the **next** boot. Devices that tripped crash protection will not
re-download the offending patch. Configurable via `maxCrashCount`
(default 1) and `verifyAfter` (default 5s).

---

## Payload v2 (`patch.zip`)

A modern patch is a `patch.zip` archive with this layout:

```
patch.zip
├── lib/
│   └── <abi>/              # one entry per supported ABI
│       └── libapp.so       # the new AOT library
├── assets/                 # the overlay tree
│   ├── AssetManifest.json
│   ├── AssetManifest.bin
│   ├── fonts/
│   │   └── MaterialIcons-Regular.otf
│   ├── assets/
│   │   └── my_image.png
│   └── (… other registered assets …)
├── manifest.json           # metadata for the host
└── version.json
```

Two things the SDK does differently from a "naive patch":

1. **Only `lib/<abi>/libapp.so` is patched**, not the whole APK. A 50MB
   APK typically becomes a 5–15MB patch.
2. **Assets are overlaid on top of the base APK's `flutter_assets/`** at
   install time. New assets replace old ones; unchanged assets keep
   loading from the base APK.

### Atomic install

A patch is staged to a temp directory, then atomically renamed into
the patch slot. The boot-time loader hook never sees a partial patch.

```
stage/                      patch/
├── lib/                     ├── lib/
│   └── libapp.so   rename ▶│   └── libapp.so
├── assets/                  ├── assets/
│   └── …                    │   └── …
```

The rename is the atomic commit. If the device loses power mid-stage,
on the next boot the loader either sees the old patch (good) or no
patch (good — the user just runs the base APK). A partially-staged
patch is **impossible** because the rename happens as one syscall.

### Asset overlay synthesis (install phase)

When the patched `libapp.so` calls `rootBundle.load('assets/foo.png')`,
Flutter's asset bundle looks first in the patch's `flutter_assets/`,
then in the APK's `flutter_assets/`. This is transparent to the app —
existing `Image.asset()` and `rootBundle.load()` calls pick up new
bytes without code changes.

The SDK handles this by:

1. Walking the patch's `assets/` tree.
2. For each file, writing it into the patch slot under
   `flutter_assets/`.
3. Updating the `AssetManifest` entries to prefer the patch's copy.

### Download retry policy

`applyPatch` retries the download up to 3 times with exponential
backoff. The first failure is at t=0, the second at t≈1s, the third at
t≈3s. This handles transient network blips without overloading the
backend.

For production with rolling updates, this is critical: 1% of devices
will hit a transient network failure on the first try. Without retry,
those users get a "patch failed" toast for no good reason.

The SDK's timeout for each attempt is 30 seconds (the default for
`http.Client.get` in the underlying network stack). Tunable via the
`timeout` parameter on `FlutterPatcher.checkForUpdate` (in the SDK;
currently does not propagate to `applyPatch`'s HTTP calls — see
"Limitations" below).

### ABI fallback

The native loader hook picks the right `lib/<abi>/libapp.so` for the
device. If the patch has only `arm64-v8a` and the device is `x86_64`,
the loader skips the patch (base APK runs unchanged) and reports
`UNSUPPORTED_ABI`. The device keeps the patched assets but not the
patched code.

This is the only way to ship a patch to a mixed-ABI fleet without
splitting the channel by ABI.

### `file://` URL support

For bundled patches (the example app's `assets/patch_demo.zip` style),
the SDK accepts `file://` URLs in `patchUrl`. The native side reads
the file directly without going through the HTTP stack. This is how
the example app demonstrates a full patch → restart → rollback flow
with no server at all.

`applyPatchBytes(Uint8List bytes, ...)` is the equivalent for in-memory
patches (useful for FFI, isolate-based loaders, or test harnesses).

---

## Self-hosting

The "server" in `flutter_ota_kit` is just an HTTP endpoint that returns
a `PatchInfo` and a static file server that serves the `patch.zip`. No
serverless functions, no databases you can't see, no special runtime.

### Check-update protocol (optional)

The SDK has a built-in minimal JSON protocol for the most basic
self-hosting. The `checkUpdate(url)` method on `FlutterPatcher` does a
GET to `url` and expects:

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

`patchUrl` may be `https://`, `http://` (not recommended), or `file://`
(bundled). `md5` is required for non-test deployments.
`signature` is optional — required only if you've configured a
`publicKeyBase64` on `init()`. `targetVersionCode` is required; the
client rejects patches with a mismatched `versionCode`.

If you want a richer protocol (signed requests, A/B test cohort
assignment, server-side rate limiting), use `ServerUpdateResult` and
`performSharedUpdateCheck` directly — see
[API Reference → Building a custom update source](api-reference.md#building-a-custom-update-source).

### Hosting the patch file

Any static file server will do. The SDK only does a single GET with a
`Range` header, so:
- **Cloudflare R2 / AWS S3 / GCS** — point `patchUrl` at the public
  URL. CDN in front is recommended.
- **Nginx / Caddy** — drop the `patch.zip` in a directory served with
  `gzip` and a 1-year `Cache-Control: public, max-age=31536000`.
- **GitHub Releases** — works for low-traffic / open-source projects.
- **Your own CDN** — any URL that returns 200 with the right bytes.

HTTPS is strongly recommended. Plain HTTP works but is rejected by
Android 9+ by default for `cleartextTrafficPermitted=false` (which the
plugin does not set).

### ABI routing

The server doesn't need to know the device's ABI — `patch.zip` includes
all supported ABIs (`lib/<abi>/libapp.so`). The native loader picks
the right one. This means:
- One `bundles` row per release, not one per ABI.
- Simpler deployment — no per-ABI channel split.
- Larger patch size (~3× the single-ABI patch), but typically the
  storage cost is trivial.

For very large apps (>100MB) where patch size matters, the
`pack` CLI accepts a `--abi` filter to produce single-ABI patches.
You then deploy one bundle per ABI per release.

### Patch signing

For non-test deployments, you **must sign** your patches. The
verification flow:

```
┌──────────────────┐                                ┌──────────────────┐
│  pack CLI         │                                │  The app          │
│  ───────────       │                                │  ───────          │
│                    │                                │                  │
│  --signing-key  ─▶│  Ed25519 over md5 hex     ───▶ │  init(           │
│  <private key>     │  base64-encoded signature      │    publicKeyB64: │
│                    │                                │    <public key>)  │
│                    │                                │                  │
│  patches          │                                │  applyPatch:     │
│  manifest.json     │                                │   1. download    │
│  with signature    │                                │   2. verify md5  │
│                    │                                │   3. verify ed25519
│                    │                                │   4. stage       │
└──────────────────┘                                └──────────────────┘
```

The signing key is **separate** from any code-signing key. It's a 32-byte
Ed25519 seed; the public half goes into your app at build time
(`init(publicKeyBase64: ...)`); the private half stays on the CI/build
machine that runs `pack`.

The signature is over the **MD5 hex string** (not the raw bytes), which
matches what the SDK verifies at install time. This is intentional:
`md5_hex` is what the SDK already computes, so the signing adds zero
extra cryptographic operations on the device.

### strictSignature

`init(strictSignature: true)` (the default) **rejects signed patches on
Android 12 and below** (API < 33), because the platform's bundled
`Signature` class is unreliable on those versions. On Android 13+, the
default uses Android's Ed25519 implementation. Set to `false` if you
need to sign patches that work on Android 12 — but be aware the
verification is weaker (falls back to MD5-only with a warning).

If you're shipping a brand-new app and you can require Android 13+
(API 33, released October 2022), leave `strictSignature: true`. The
MD5-only fallback on API < 33 is still secure against casual
tampering, just not against a determined attacker with access to your
CDN.

#### Skipping MD5 entirely (optional)

For test deployments, you can set `md5` to an empty string in
`PatchInfo`. The SDK will skip the MD5 check and log a warning. The
signature check (if any) is still enforced. **Don't do this in
production** — MD5 is the cheap first line of defense that catches
accidental corruption and CDN misconfigurations.

### Recommended backend practices

For production deployments:

- **Pin `Cache-Control`** on the patch URL to a long max-age with
  content-hash in the URL. ETag-based cache busting is fine but URL
  hashing is simpler.
- **Sign every patch** with a key that's stored outside the
  deployment machine. Use a CI secret, not a developer's laptop.
- **Serve over HTTPS** with HSTS. Don't use the SDK's HTTP fallback
  in production.
- **Rate-limit** the check-update endpoint per `appVersionCode +
  channel` to prevent a single misbehaving device from hammering
  your backend.
- **Log every check-update** with `appVersionCode`, `channel`, and
  the device's `deviceAbi`. This gives you rollout visibility.

---

## Advanced configuration

### Manual Android initialization

If you need to initialize the plugin before `WidgetsFlutterBinding` (e.g.
in a custom Flutter embedder), you can call the underlying MethodChannel
directly:

```kotlin
// In your MainActivity.onCreate, before super.onCreate:
FlutterPatcherPlugin.markBooting()
```

This is only needed for exotic setups. The normal `FlutterPatcher.init()`
does the right thing in the Dart isolate.

### Flutter compatibility

The patch system relies on the Flutter Engine's loader hook. The hook
contract has been stable since Flutter 3.0, but minor version changes
sometimes require a new release. The SDK verifies compatibility at
boot time — if the loader hook doesn't match the current engine
version, the patch is rejected and the base APK runs.

Compatibility matrix (last verified):

| Flutter | SDK  | Notes                                      |
|---------|------|--------------------------------------------|
| 3.19.x  | 0.1.5+| Loader hook stable                          |
| 3.27.x  | 0.1.5+| Loader hook stable, Material 3 recommended |
| 3.32.x  | 0.1.7+| Verified end-to-end                         |
| 3.47.x  | 0.1.9+| Current                                     |

If you upgrade Flutter, expect to need a new release. Old patches
expire after the upgrade.

---

## Limitations

### Android only

The native loader hook is Android-specific. iOS doesn't allow
downloading executable code at runtime per App Store policy, and
desktop platforms don't have an equivalent "patch the running app"
mechanism. The SDK's public API is callable on all platforms (returns
no-op safe defaults) so cross-platform code can `await setupFlutterOta()`
without `#ifdef`s.

If you need iOS OTA, [Shorebird](https://shorebird.dev/) uses a different
mechanism (engine-level diff) and may be a better fit. flutter_ota_kit
will not add iOS support.

### APK or Flutter Engine upgrades invalidate old patches

A `1.0.0+100` patch cannot apply to a `1.1.0+101` host (the loader
hook is byte-different) or to a `1.0.0+100` host built with a newer
Flutter Engine. This is by design — a patch is bound to a specific
binary. After an APK upgrade, the new build starts fresh on the new
base.

Forced APK upgrades do not auto-pull pending patches. The user must
install the new APK from the store, then the SDK's `checkForUpdate`
will see the new `versionCode` and look for a `targetVersionCode` patch
that matches.

### Reliance on Flutter internals

The patch system uses Flutter's loader hook to swap `libapp.so`. This
is a private API that has been stable for years but is not contractually
guaranteed. If Google changes the loader hook signature in a future
Flutter release, patches from before the change will be rejected.

The SDK's auto-init `ContentProvider` is the more fragile piece — it
runs before `Application.onCreate` and depends on Android's
`ContentProvider` lifecycle. Some Android vendors (Xiaomi MIUI,
Huawei EMUI) are known to kill background ContentProviders on memory
pressure, which can break init. This is a known Android fragmentation
issue, not a bug in the SDK.

### App-store policies and compliance

- **Google Play**: Distributing executable code at runtime is
  technically against Play Store policy (Section 4.5 of the Developer
  Distribution Agreement), but the policy has been loosely enforced
  for years. Enterprise apps distributed via Managed Google Play
  have more flexibility.
- **Samsung Galaxy Store, Huawei AppGallery, Xiaomi GetApps**: Each
  has its own policy. Self-distribution via MDM is the safest channel.
- **Apple App Store**: Disallowed. The SDK's iOS API is a no-op.

Verify your distribution channel's policy before shipping.

---

## See also

- [Crash Protection](crash-protection.md) — auto-rollback, blacklist,
  Android version differences
- [API Reference](api-reference.md) — public SDK surface, error codes
- [Backends](backends.md) — per-backend setup
- [Configuration](configuration.md) — env vars, `.env`, resolution order
- [Production Playbook](production-playbook.md) — staged rollout,
  diagnostic reporting, emergency rollback
