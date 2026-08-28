import 'dart:convert' show jsonEncode;

import 'package:flutter_patcher_core/flutter_patcher_core.dart'
    show Bundle, BundleMetadata, BundlePatchArtifact, Platform;
import 'package:flutter_patcher_cloudflare/flutter_patcher_cloudflare.dart'
    show
        buildBundlePatchId,
        bundleToPatchRows,
        parseMetadata,
        transformRowToBundle;
import 'package:test/test.dart';

void main() {
  group('d1 bundle mapper', () {
    test('transformRowToBundle rebuilds derived patch fields', () {
      final row = {
        'id': 'b1',
        'channel': 'production',
        'enabled': 1,
        'should_force_update': 0,
        'file_hash': 'h1',
        'git_commit_hash': null,
        'message': 'msg',
        'platform': 'android',
        'target_app_version': '1.0.0',
        'storage_uri': 's3://b1',
        'fingerprint_hash': null,
        'metadata': jsonEncode({'app_version': '1.2.3'}),
        'manifest_storage_uri': null,
        'manifest_file_hash': null,
        'asset_base_storage_uri': null,
        'rollout_cohort_count': 100,
        'target_cohorts': jsonEncode(['c1', 'c2']),
      };
      final patchRows = [
        {
          'id': 'b1:base1',
          'bundle_id': 'b1',
          'base_bundle_id': 'base1',
          'base_file_hash': 'bf1',
          'patch_file_hash': 'pf1',
          'patch_storage_uri': 's3://p1',
          'order_index': 0,
        },
      ];

      final bundle = transformRowToBundle(row, patchRows);

      expect(bundle.id, 'b1');
      expect(bundle.enabled, isTrue);
      expect(bundle.shouldForceUpdate, isFalse);
      expect(bundle.platform, Platform.android);
      expect(bundle.targetAppVersion, '1.0.0');
      expect(bundle.targetCohorts, ['c1', 'c2']);
      expect(bundle.patches, hasLength(1));
      expect(bundle.patches!.first.baseBundleId, 'base1');
      expect(bundle.patchFileHashLegacy, 'pf1');
      expect(bundle.patchStorageUri, 's3://p1');
      expect(bundle.rolloutCohortCount, 100);
      expect(bundle.metadata, isA<BundleMetadata>());
      expect(bundle.metadata!.appVersion, '1.2.3');
    });

    test('bundleToPatchRows builds compound ids in order', () {
      final bundle = Bundle(
        id: 'b1',
        channel: 'production',
        enabled: true,
        shouldForceUpdate: false,
        fileHash: 'h1',
        platform: Platform.android,
        targetAppVersion: '1.0.0',
        storageUri: 's3://b1',
        patches: [
          BundlePatchArtifact(
            baseBundleId: 'base1',
            baseFileHash: 'bf1',
            patchFileHash: 'pf1',
            patchStorageUri: 's3://p1',
          ),
          BundlePatchArtifact(
            baseBundleId: 'base2',
            baseFileHash: 'bf2',
            patchFileHash: 'pf2',
            patchStorageUri: 's3://p2',
          ),
        ],
      );

      final rows = bundleToPatchRows(bundle);

      expect(rows, hasLength(2));
      expect(rows[0]['id'], buildBundlePatchId('b1', 'base1'));
      expect(rows[0]['order_index'], 0);
      expect(rows[1]['id'], buildBundlePatchId('b1', 'base2'));
      expect(rows[1]['order_index'], 1);
    });

    test('parseMetadata handles string, object and null', () {
      expect(parseMetadata(null), isNull);
      expect(parseMetadata(jsonEncode({'a': 1})), {'a': 1});
      expect(parseMetadata({'a': 1}), {'a': 1});
      expect(parseMetadata('not-json'), isNull);
    });
  });
}
