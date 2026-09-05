// flutter_ota_kit_plugin_core example
//
// `flutter_ota_kit_plugin_core` provides the shared abstractions that
// every backend plugin is built on top of: `DatabasePlugin`,
// `StoragePlugin`, `Bundle` filtering, storage-URI parsing, pagination,
// and the "blob database" factory used by the AWS, Cloudflare, and
// PocketBase backends.
//
// Most apps don't import this package directly; the SDK's update
// pipeline does. This file shows the standalone helpers so you can
// use them while writing a custom backend or a CLI tool.
//
// Run: `dart run example/main.dart`

import 'package:flutter_ota_kit_plugin_core/flutter_ota_kit_plugin_core.dart';

void main() {
  // ── 1. Storage URI parser. ───────────────────────────────────────
  // `parseStorageUri` validates the protocol and returns the bucket +
  // key. Throws on unknown protocols so misuse is caught early.
  const supabaseUri =
      'supabase-storage://flutter-ota-bundles/'
      '01a059a6/patch.zip';
  final parsed = parseStorageUri(supabaseUri, 'supabase-storage');
  print('Parsed protocol: ${parsed.protocol}');
  print('Parsed bucket:   ${parsed.bucket}');
  print('Parsed key:      ${parsed.key}');

  // ── 2. Bundle storage keys. ──────────────────────────────────────
  // `createBundleStorageKey` returns a flat key for the patch blob
  // inside a storage bucket. The default layout is `{id}/patch.zip`;
  // for assets it's `{id}/assets/{path}`.
  final patchKey = createBundleStorageKey('01a059a6');
  print('Patch key: $patchKey');

  final assetKey = createBundleStorageKey('01a059a6', [
    'assets',
    'images',
    'logo.png',
  ]);
  print('Asset key: $assetKey');

  // ── 3. Patch ID helper. ──────────────────────────────────────────
  // The device SDK reports the currently-installed patch id back to
  // the server (so the server can compute diffs). For patches with a
  // base, the id is `{currentId}-h{patchCount}`; for standalone
  // patches, the id is the current id.
  final patchId = buildBundlePatchId(
    '01a059a6-7d3c-4f3e-8a2c-9c2e3a4b5d6e',
    '00000000-0000-0000-0000-000000000000',
  );
  print('Patch id: $patchId');

  // ── 4. Pagination math. ──────────────────────────────────────────
  // `calculatePagination` returns total/page/hasNext/hasPrev info
  // used by the CLI's `bundle list` command.
  final p = calculatePagination(247, limit: 20, offset: 40);
  print('Page ${p.currentPage} of ${p.totalPages} (${p.total} items)');
  print('  hasNextPage:     ${p.hasNextPage}');
  print('  hasPreviousPage: ${p.hasPreviousPage}');
}
