// flutter_ota_kit_pocketbase example
//
// `flutter_ota_kit_pocketbase` is a PocketBase backend for
// `flutter_ota_kit`. PocketBase is a single-binary, self-hostable
// backend (similar to Supabase) that gives you SQLite, auth, file
// storage, realtime, and an admin UI in one ~15MB Go binary. This
// plugin makes it a drop-in `DatabasePlugin` + `StoragePlugin`.
//
// Pair this with `flutter_ota_kit serve` (cli-tools) to start a local
// PocketBase instance with the flutter_ota_kit schema pre-installed,
// plus an admin UI at `http://localhost:8090/_/`.
//
// Run: `dart run example/main.dart`

import 'package:flutter_ota_kit_pocketbase/flutter_ota_kit_pocketbase.dart';

void main() {
  // ── 1. Database config (the `bundles` collection). ──────────────
  // `url` is the base URL of your PocketBase instance. `adminEmail` /
  // `adminPassword` are the superuser credentials — used only for
  // server-side reads/writes against the `bundles` and `channels`
  // collections.
  const dbConfig = PocketBaseConfig(
    url: 'http://localhost:8090',
    adminEmail: 'admin@example.com',
    adminPassword: 'super-secret',
  );
  print('PocketBase URL: ${dbConfig.url}');
  print('Bundles collection: ${dbConfig.bundlesCollection}');

  // ── 2. Storage config (the `bundles` file bucket). ───────────────
  // The `bundlesCollection` is the collection whose records carry the
  // patch file attachments. The `bundlesBucket` is the file-storage
  // bucket name within PocketBase.
  const storageConfig = PocketBaseStorageConfig(
    url: 'http://localhost:8090',
    adminEmail: 'admin@example.com',
    adminPassword: 'super-secret',
    bundlesCollection: 'bundles',
    bundlesBucket: 'bundles',
  );
  print('Bucket: ${storageConfig.bundlesBucket}');

  // ── 3. Storage URI helpers. ──────────────────────────────────────
  // Build a `pb://<bucket>/<recordId>/<file>` URI for a given
  // record+filename. The device SDK understands this format and
  // downloads via the PocketBase `/api/files/{collection}/{id}/{file}`
  // endpoint (with a short-lived token).
  final uri = buildPocketBaseStorageUri(
    '01a059a6-7d3c-4f3e-8a2c-9c2e3a4b5d6e',
    'patch.zip',
  );
  print('Storage URI: $uri');

  // Round-trip it:
  final parsed = parsePocketBaseStorageUri(uri);
  if (parsed != null) {
    print('Parsed bucket:   ${parsed.bucket}');
    print('Parsed recordId: ${parsed.recordId}');
    print('Parsed filename: ${parsed.filename}');
  }
}
