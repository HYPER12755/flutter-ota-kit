// flutter_ota_kit_cloudflare example
//
// `flutter_ota_kit_cloudflare` provides Cloudflare D1 (database) + R2
// (storage) plugins for `flutter_ota_kit`. D1 is Cloudflare's SQLite-
// based serverless database; R2 is S3-compatible object storage. The
// combo is the cheapest self-hostable option for low-traffic apps.
//
// Most apps don't import this package directly; they wire it through
// `flutter_ota_kit.configureCloudflare(...)` in their app boot path.
// This file shows the low-level config types in case you're writing a
// custom server or a CLI extension.
//
// Run: `dart run example/main.dart`

import 'package:flutter_ota_kit_cloudflare/flutter_ota_kit_cloudflare.dart';

void main() {
  // ── 1. D1 database config (Cloudflare's SQLite). ─────────────────
  // `databaseId` is the UUID of the D1 database. `accountId` is your
  // Cloudflare account ID. `cloudflareApiToken` needs D1 read/write.
  const d1Config = D1DatabaseConfig(
    databaseId: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
    accountId: '0123456789abcdef0123456789abcdef',
    cloudflareApiToken: 'cf-token-...',
  );
  print('D1 database: ${d1Config.databaseId}');
  print('Account:     ${d1Config.accountId}');

  // ── 2. R2 storage config (S3-compatible object storage). ──────────
  // R2 is S3-compatible: same `accessKeyId`/`secretAccessKey` flow,
  // but the endpoint host is `{accountId}.r2.cloudflarestorage.com`.
  const r2Config = R2S3StorageConfig(
    accountId: '0123456789abcdef0123456789abcdef',
    bucketName: 'flutter-ota-bundles',
    accessKeyId: 'r2-access-key',
    secretAccessKey: 'r2-secret-key',
    basePath: 'bundles',
  );
  print('R2 bucket: ${r2Config.bucketName}');
  print('Region:    ${r2Config.region}');

  // ── 3. Resolving a custom client (test seam). ────────────────────
  // The `clientFactory` lets you inject a mock S3 client in tests or
  // use a custom S3-compatible client in production.
  // final client = resolveR2Client(r2Config);

  // ── 4. Row-to-Bundle mapping (server-side helper). ────────────────
  // Use this when reading bundles from a custom D1 query and passing
  // them to the SDK's `PatchInfo.fromJson`. The mapper handles both
  // camelCase and snake_case column names.
  // const row = {
  //   'id': '01a059a6-7d3c-4f3e-8a2c-9c2e3a4b5d6e',
  //   'channel': 'production',
  //   'enabled': true,
  //   'file_hash': '7c4a8d09ca3762af61e59520943dc26494f8941b',
  //   'storage_uri': 'r2://flutter-ota-bundles/01a059a6/patch.zip',
  //   'target_app_version': '1.0.0',
  //   'rollout_cohort_count': 100,
  // };
  // final bundle = transformRowToBundle(row);
  // print('Mapped bundle: ${bundle.id} (${bundle.storageUri})');
}
