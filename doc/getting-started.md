# Getting Started

This guide covers local development workflows for flutter_patcher. For production deployment, see the [Production Playbook](production-playbook.md).

---

## Local mock server

If you want to try the HTTP `checkUpdate → applyPatch` flow without building a backend, run the bundled mock server. It is for local development only, not production patch distribution.

```bash
# Rebuild the release APK after editing Dart code
flutter build apk --release

# Build the patch package
dart run flutter_patcher:pack \
  --apk build/app/outputs/flutter-apk/app-release.apk \
  --version dev-1 \
  --target-version-code 100

# Serve dist/patch.zip and dist/manifest.json on 0.0.0.0:8080
dart run flutter_patcher:mock_server --dist dist
```

Then call it from a phone on the same Wi-Fi network:

```dart
final check = await FlutterPatcher.checkUpdate(
  'http://<your-computer-ip>:8080/check',
);

if (check.hasUpdate) {
  await FlutterPatcher.applyPatch(check.patch!);
}
```

The plugin also ships with an optional minimal check-update JSON protocol, intended for quick onboarding, the example, and local testing. In production, if you already have your own update / staging / auth protocol, parse the response yourself and construct `PatchInfo` directly. The protocol format and `checkUpdate` usage live in the [API Reference](https://pub.dev/documentation/flutter_patcher/latest/topics/API-reference-topic.html) and [Architecture](https://pub.dev/documentation/flutter_patcher/latest/topics/Architecture-topic.html).

---

## Skipping MD5

`PatchInfo.md5` is optional. If your server doesn't ship md5 (or you only want HTTPS-level integrity), leave it out:

```dart
PatchInfo(version: 'fix-1', patchUrl: '...', targetVersionCode: 100); // md5 defaults to ''
```

Download integrity checks are skipped. **Note that signature verification is also skipped** in this case (the Ed25519 input is the md5 hex string — without md5 there is no message to sign over). To keep signature verification you must also ship md5.

---

## Multi-ABI setup

The server must distribute a different `patch.zip` per ABI (each patch embeds one `lib/<abi>/libapp.so`). The client can read the current device ABI via `FlutterPatcher.deviceAbi` and include it in your update request.

---

## Multi-flavor setup

The server should track patches by `flavor × ABI × versionCode`. Different flavors typically have different configs, package names, resources, and business logic — never share a patch across flavors.

---

## Advanced `--assets` syntax

For long asset lists, point `--assets` at a text file prefixed with `@` — one path per line, `#` starts a comment, inline and `@file` can be mixed:

```bash
# patch-assets.txt
assets/hero.png
assets/strings/zh.json
assets/illustrations/onboarding-1.png
```

```bash
dart run flutter_patcher:pack \
  --apk build/app/outputs/flutter-apk/app-release.apk \
  --version 1.0.1 \
  --target-version-code 100 \
  --assets @patch-assets.txt,assets/last-minute.png
```

---

## Crash protection tuning

If you need to tune crash protection, pass parameters explicitly to `init`:

```dart
await FlutterPatcher.init(
  maxCrashCount: 1,
  verifyAfter: const Duration(seconds: 5),
);
```

| Parameter | Default | Description |
|---|---|---|
| `maxCrashCount` | `1` | Number of consecutive failures before the patch is tripped |
| `verifyAfter` | `5 seconds` | Window during which post-first-frame Dart error hooks keep watching |

Android 11+ uses `ApplicationExitInfo` to distinguish crashes, ANRs, user dismissal, and system reclaim more accurately. Android 10 and below have weaker signals; pair the SDK with your own crash monitoring and a server-side kill switch.

Full design: [Crash protection docs](https://pub.dev/documentation/flutter_patcher/latest/topics/Crash-protection-topic.html).
