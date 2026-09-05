// flutter_ota_kit_core example
//
// `flutter_ota_kit_core` is the framework-agnostic data model shared by every
// backend plugin in the `flutter_ota_kit` family. It defines the canonical
// shapes for bundles, patches, and rollouts.
//
// Most apps don't import this package directly — they use `flutter_ota_kit`
// (the umbrella package) which re-exports it. This file shows the types you
// might encounter in API responses, in `flutter_ota_kit_cli` tool output, or
// while writing a custom backend.
//
// Run: `dart run example/main.dart`

import 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart';

void main() {
  // ── 1. Bundle: the central database row / manifest object. ─────────
  // Every backend stores this shape (Postgres, Supabase, Cloudflare D1,
  // AWS DynamoDB, PocketBase). The wire format is camelCase, the SQL
  // format is snake_case — `fromJson` tolerates both.
  final bundle = Bundle(
    id: '01a059a6-7d3c-4f3e-8a2c-9c2e3a4b5d6e',
    platform: Platform.android,
    shouldForceUpdate: false,
    enabled: true,
    fileHash: '7c4a8d09ca3762af61e59520943dc26494f8941b',
    storageUri: 'supabase-storage://flutter-ota-bundles/01a059a6/patch.zip',
    channel: 'production',
    targetAppVersion: '1.0.0',
    metadata: const BundleMetadata(
      appVersion: '1.0.1',
      signature:
          'ed25519:9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08',
    ),
    rolloutCohortCount: 100, // 10% of devices (per-mille 0..1000).
  );

  print('Bundle ${bundle.id} on ${bundle.platform.value}:');
  print('  storageUri          = ${bundle.storageUri}');
  print('  targetAppVersion    = ${bundle.targetAppVersion}');
  print('  metadata.appVersion = ${bundle.metadata?.appVersion}');

  // ── 2. Wire format conversion. ─────────────────────────────────────
  // `toJson()` produces the camelCase wire payload sent over the
  // hot-updater-compatible update-check HTTP contract.
  final wire = bundle.toJson();
  print('Wire payload keys: ${wire.keys.toList()}');

  // `toSqlJson()` produces the snake_case row format used by SQL
  // backends (Postgres / Supabase / D1 / DynamoDB).
  final sql = bundle.toSqlJson();
  print('SQL row keys: ${sql.keys.toList()}');

  // ── 3. Rollout: per-mille 0..1000 cohort bucketing. ────────────────
  // The same device fingerprint always lands in the same bucket across
  // cold starts, so a 10% rollout stays at 10% even as users churn.
  const bundleId = '01a059a6-7d3c-4f3e-8a2c-9c2e3a4b5d6e';
  const rolloutCohortCount = 100; // 10% (per-mille).

  for (final userId in const ['alice', 'bob', 'carol', 'dave', 'eve']) {
    final cohort = getDefaultNumericCohort(userId);
    final eligible = isCohortEligibleForUpdate(
      bundleId,
      cohort,
      rolloutCohortCount,
      null, // targetCohorts (null = percentage rollout)
    );
    print('user=$userId  cohort=$cohort  in 10% rollout? $eligible');
  }
}
