// flutter_ota_kit_postgres example
//
// `flutter_ota_kit_postgres` is a Postgres backend for `flutter_ota_kit`.
// It provides a `postgresDatabase` factory and a `postgresStorage`
// factory that talk to a vanilla Postgres database (no Supabase, no
// Cloudflare — just `pg`).
//
// Most apps don't import this package directly; they wire it through
// `flutter_ota_kit.configurePostgres(...)` in their app boot path. This
// file shows the low-level config types in case you're writing a custom
// server, a migration script, or a CLI extension.
//
// Run: `dart run example/main.dart`

import 'package:flutter_ota_kit_postgres/flutter_ota_kit_postgres.dart';
import 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart';

void main() {
  // ── 1. Database config (vanilla Postgres connection). ─────────────
  // `PostgresConfig` is a thin wrapper around the `postgres` package
  // connection parameters. The `host`/`port`/`database` triple is the
  // canonical form; username/password are required for non-trust auth.
  const dbConfig = PostgresConfig(
    host: 'db.example.com',
    port: 5432,
    database: 'ota',
    username: 'ota',
    password: 'secret',
  );
  print('Postgres: ${dbConfig.host}:${dbConfig.port}/${dbConfig.database}');

  // ── 2. Storage config (for storing patch blobs). ──────────────────
  // The `servingBaseUrl` is the public-facing URL that the device SDK
  // can use to download patches. Omit it only if you proxy the
  // download through your own update-check endpoint.
  const storageConfig = PostgresStorageConfig(
    db: dbConfig,
    servingBaseUrl: 'https://cdn.example.com/flutter-ota',
  );
  print('Serving base URL: ${storageConfig.servingBaseUrl}');

  // ── 3. Row-to-Bundle mapping (server-side helper). ────────────────
  // Use this when reading bundles from a custom query and passing them
  // to the SDK's `PatchInfo.fromJson`. The mapper handles both
  // camelCase and snake_case column names.
  const row = PostgresBundleRow(
    id: '01a059a6-7d3c-4f3e-8a2c-9c2e3a4b5d6e',
    channel: 'production',
    enabled: true,
    shouldForceUpdate: false,
    fileHash: '7c4a8d09ca3762af61e59520943dc26494f8941b',
    platform: Platform.android,
    storageUri: 'postgres-blob://flutter-ota-bundles/'
        '01a059a6/patch.zip',
    targetAppVersion: '1.0.0',
    rolloutCohortCount: 100,
  );
  final bundle = mapRowToBundle(row);
  print('Mapped bundle: ${bundle.id} (${bundle.storageUri})');

  // ── 4. Bundle → SQL values (for inserts/updates). ────────────────
  // Returns snake_case column→value maps ready to feed to a `pg` query.
  final values = bundleToRowValues(bundle);
  print('SQL column count: ${values.length}');
  print('  file_hash = ${values['file_hash']}');
}
