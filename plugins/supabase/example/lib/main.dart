// flutter_ota_kit_supabase example
//
// `flutter_ota_kit_supabase` is a Supabase backend for `flutter_ota_kit`.
// It provides two factories — `supabaseDatabase` and `supabaseStorage` —
// that read/write the `bundles` table and patch files in a Supabase
// Storage bucket.
//
// Most apps don't import this package directly; they wire it through
// `flutter_ota_kit.configureSupabase(...)` in their app boot path. This
// file shows the low-level config types in case you're writing a custom
// server, a migration script, or a CLI extension.
//
// Run: `dart run example/main.dart`

import 'package:flutter_ota_kit_supabase/flutter_ota_kit_supabase.dart';

void main() {
  // ── 1. Database config (PostgREST + service-role key). ─────────────
  // The `supabaseServiceRoleKey` is server-side only — never ship it in
  // a Flutter app. Use `supabaseAnonKey` + RLS policies instead.
  const dbConfig = SupabaseServiceRoleConfig(
    supabaseUrl: 'https://your-project.supabase.co',
    supabaseServiceRoleKey: 'eyJ...', // server-side only
  );
  print('Supabase URL: ${dbConfig.supabaseUrl}');

  // ── 2. Storage config (adds bucket + base path). ──────────────────
  // The `basePath` is the prefix inside the bucket where bundles live.
  // The default convention is `bundles/{id}/patch.zip`.
  const storageConfig = SupabaseStorageConfig(
    supabaseUrl: 'https://your-project.supabase.co',
    supabaseServiceRoleKey: 'eyJ...',
    bucketName: 'flutter-ota-bundles',
    basePath: 'bundles',
  );
  print('Bucket: ${storageConfig.bucketName}');
  print('Base path: ${storageConfig.basePath}');

  // ── 3. Row-to-Bundle mapping (server-side helper). ────────────────
  // Use this when reading bundles from PostgREST and passing them to
  // the SDK's `PatchInfo.fromJson`. The mapper handles both camelCase
  // and snake_case column names.
  const row = SupabaseBundleRow(
    id: '01a059a6-7d3c-4f3e-8a2c-9c2e3a4b5d6e',
    channel: 'production',
    enabled: true,
    shouldForceUpdate: false,
    fileHash: '7c4a8d09ca3762af61e59520943dc26494f8941b',
    platform: 'android',
    storageUri: 'supabase-storage://flutter-ota-bundles/'
        '01a059a6/patch.zip',
    targetAppVersion: '1.0.0',
    rolloutCohortCount: 100,
  );
  final bundle = mapRowToBundle(row);
  print('Mapped bundle: ${bundle.id} (${bundle.storageUri})');

  // ── 4. URL parsing helpers. ───────────────────────────────────────
  final uri = parseSupabaseStorageUri(bundle.storageUri);
  print('Bucket: ${uri.bucket}');
  print('Key:    ${uri.key}');
}
