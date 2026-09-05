// flutter_ota_kit_client example
//
// `flutter_ota_kit_client` is a thin Dart server that speaks the
// hot-updater-compatible update-check HTTP contract. The device SDK
// (running on the user's phone) POSTs device fingerprint info to it;
// it queries the configured backend for an update and returns a
// `ServerUpdateResult` that the SDK can install.
//
// Most apps don't run this server themselves — `flutter_ota_kit_cli`
// already does. This example shows the request/response shape if you
// need to wire one up in a custom server (e.g. Dart Frog or shelf).
//
// Run: `dart run example/main.dart`

import 'package:flutter_ota_kit_client/flutter_ota_kit_client.dart';
import 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart';

void main() {
  // A real server wires `performServerUpdateCheck` into a shelf
  // handler. Here we just demonstrate the request/response shape.

  // ── 1. The request body the device sends. ─────────────────────────
  const requestBody = {
    'platform': 'android',
    'deviceId': 'd4f5e2b1-a3c8-4f0e-9b1d-8c2a3b4c5d6e',
    'appVersion': '1.0.0',
    'minBundleId': '00000000-0000-0000-0000-000000000000',
    'bundleId': '01a059a5-7d3c-4f3e-8a2c-9c2e3a4b5d6e',
    'channel': 'production',
    'abi': 'arm64-v8a',
  };
  print('Device update-check request: $requestBody');

  // ── 2. The response shape (a `ServerUpdateResult`). ────────────────
  // The common case: no update available, device proceeds with the
  // installed version.
  final noUpdate = ServerUpdateResult.upToDate();
  print('Up-to-date response: $noUpdate');

  // ── 3. The shape when an update is available. ─────────────────────
  // When `isUpToDate=false` and `status=AppUpdateStatus.update`, the
  // device downloads the patch from `patch.artifactUrl`, verifies its
  // MD5 against `patch.fileHash`, and (optionally) verifies the
  // Ed25519 `signature` against your public key.
  final rollout = ServerUpdateResult(
    isUpToDate: false,
    status: AppUpdateStatus.update,
    shouldForceUpdate: false,
    id: '01a059a6-7d3c-4f3e-8a2c-9c2e3a4b5d6e',
    patch: const PatchInfo(
      version: '01a059a6-7d3c-4f3e-8a2c-9c2e3a4b5d6e',
      patchUrl:
          'https://your-bucket.supabase.co/storage/v1/object/'
          'sign/flutter-ota-bundles/01a059a6/patch.zip',
      md5: '7c4a8d09ca3762af61e59520943dc26494f8941b',
      signature: 'ed25519:9f86d081884c7d659a2feaa0c55ad015a3bf4f1b',
    ),
  );
  print('Rollout response: $rollout');
}
