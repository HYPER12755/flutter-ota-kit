import 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart'
    show Bundle, BundleMetadata, BundlePatchArtifact, Platform;
import 'package:flutter_ota_kit_postgres/flutter_ota_kit_postgres.dart';
import 'package:test/test.dart';

void main() {
  group('postgres bundle mapper', () {
    test('bundleToRowValues emits snake_case columns', () {
      final bundle = Bundle(
        id: '018f0000-0000-7000-8000-000000000001',
        platform: Platform.android,
        shouldForceUpdate: true,
        enabled: true,
        fileHash: 'hash-1',
        gitCommitHash: 'abc',
        message: 'hello',
        channel: 'production',
        storageUri: 'file:///b1',
        targetAppVersion: '1.2.3',
        fingerprintHash: null,
        metadata: const BundleMetadata(appVersion: '1.2.3'),
        manifestStorageUri: 'file:///m1',
        manifestFileHash: 'mh1',
        assetBaseStorageUri: 'file:///a1',
        patches: const [
          BundlePatchArtifact(
            baseBundleId: '018f0000-0000-7000-8000-000000000000',
            baseFileHash: 'base-hash',
            patchFileHash: 'patch-hash',
            patchStorageUri: 'file:///p1',
          ),
        ],
        patchBaseBundleId: '018f0000-0000-7000-8000-000000000000',
        patchBaseFileHash: 'base-hash',
        patchFileHash: 'patch-hash',
        patchStorageUri: 'file:///p1',
        rolloutCohortCount: 1000,
        targetCohorts: const ['team-a'],
      );

      final row = bundleToRowValues(bundle);
      expect(row['id'], bundle.id);
      expect(row['should_force_update'], true);
      expect(row['file_hash'], 'hash-1');
      expect(row['target_app_version'], '1.2.3');
      expect(row['platform'], 'android');
      expect(row['manifest_storage_uri'], 'file:///m1');
      expect(row['rollout_cohort_count'], 1000);
      expect(row['target_cohorts'], const ['team-a']);
      expect(row['metadata'], isA<Map>());
    });

    test('mapRowToBundle rebuilds derived patch fields', () {
      final bundle = Bundle(
        id: '018f0000-0000-7000-8000-000000000001',
        platform: Platform.android,
        shouldForceUpdate: false,
        enabled: true,
        fileHash: 'hash-1',
        channel: 'production',
        storageUri: 'file:///b1',
        targetAppVersion: '1.2.3',
        message: null,
        fingerprintHash: null,
        metadata: const BundleMetadata(appVersion: '1.2.3'),
        manifestStorageUri: null,
        manifestFileHash: null,
        assetBaseStorageUri: null,
        patches: const [
          BundlePatchArtifact(
            baseBundleId: '018f0000-0000-7000-8000-000000000000',
            baseFileHash: 'base-hash',
            patchFileHash: 'patch-hash',
            patchStorageUri: 'file:///p1',
          ),
        ],
        patchBaseBundleId: null,
        patchBaseFileHash: null,
        patchFileHash: null,
        patchStorageUri: null,
        rolloutCohortCount: 1000,
        targetCohorts: null,
      );

      final row = bundleToRowValues(bundle);
      final patchRows = bundleToPatchRows(bundle);
      final back = mapRowToBundle(
        PostgresBundleRow.fromJson(row),
        [PostgresBundlePatchRow.fromJson(patchRows.first)],
      );

      expect(back.id, bundle.id);
      expect(back.fileHash, 'hash-1');
      expect(back.patches, hasLength(1));
      expect(back.patches!.first.patchFileHash, 'patch-hash');
      expect(back.patchStorageUri, 'file:///p1');
      expect(back.rolloutCohortCount, 1000);
      expect(back.metadata?.appVersion, '1.2.3');
    });

    test('bundleToPatchRows builds compound ids', () {
      final bundle = Bundle(
        id: 'bid',
        platform: Platform.android,
        shouldForceUpdate: false,
        enabled: true,
        fileHash: 'h',
        channel: 'production',
        storageUri: 's',
        message: null,
        fingerprintHash: null,
        metadata: null,
        manifestStorageUri: null,
        manifestFileHash: null,
        assetBaseStorageUri: null,
        patches: const [
          BundlePatchArtifact(
            baseBundleId: 'base',
            baseFileHash: 'bh',
            patchFileHash: 'ph',
            patchStorageUri: 'ps',
          ),
        ],
        patchBaseBundleId: null,
        patchBaseFileHash: null,
        patchFileHash: null,
        patchStorageUri: null,
        rolloutCohortCount: 1000,
        targetCohorts: null,
      );

      final rows = bundleToPatchRows(bundle);
      expect(rows, hasLength(1));
      expect(rows.first['id'], 'bid:base');
      expect(rows.first['bundle_id'], 'bid');
      expect(rows.first['base_bundle_id'], 'base');
      expect(rows.first['order_index'], 0);
    });
  });
}
