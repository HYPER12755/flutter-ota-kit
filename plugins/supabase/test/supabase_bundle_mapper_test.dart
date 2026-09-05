import 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart';
import 'package:flutter_ota_kit_supabase/src/supabase_bundle_mapper.dart';
import 'package:flutter_ota_kit_supabase/src/types.dart';
import 'package:test/test.dart';

Bundle _makeBundle({List<BundlePatchArtifact> patches = const []}) => Bundle(
  id: '018f0000-0000-7000-8000-000000000001',
  platform: Platform.android,
  shouldForceUpdate: false,
  enabled: true,
  fileHash: 'file-hash-1',
  gitCommitHash: 'git-1',
  message: 'hello',
  channel: 'production',
  storageUri: 'supabase-storage://updates/bundles/b1.zip',
  targetAppVersion: '1.0.0',
  fingerprintHash: 'fp-1',
  metadata: const BundleMetadata(appVersion: '1.2.3'),
  manifestStorageUri: 'supabase-storage://updates/manifests/m1.json',
  manifestFileHash: 'mf-1',
  assetBaseStorageUri: 'supabase-storage://updates/assets',
  rolloutCohortCount: 500,
  targetCohorts: ['team-a'],
  patches: patches,
  patchBaseBundleId: patches.isNotEmpty ? patches.first.baseBundleId : null,
  patchBaseFileHash: patches.isNotEmpty ? patches.first.baseFileHash : null,
  patchFileHash: patches.isNotEmpty ? patches.first.patchFileHash : null,
  patchStorageUri: patches.isNotEmpty ? patches.first.patchStorageUri : null,
);

void main() {
  group('bundleToRow / mapRowToBundle round-trip', () {
    test('preserves scalar fields and stripBundleArtifactMetadata', () {
      final bundle = _makeBundle();
      final row = bundleToRow(bundle);

      expect(row.id, bundle.id);
      expect(row.channel, 'production');
      expect(row.enabled, true);
      expect(row.shouldForceUpdate, false);
      expect(row.fileHash, 'file-hash-1');
      expect(row.gitCommitHash, 'git-1');
      expect(row.message, 'hello');
      expect(row.platform, 'android');
      expect(row.targetAppVersion, '1.0.0');
      expect(row.fingerprintHash, 'fp-1');
      expect(row.storageUri, 'supabase-storage://updates/bundles/b1.zip');
      expect(row.manifestStorageUri, bundle.manifestStorageUri);
      expect(row.manifestFileHash, 'mf-1');
      expect(row.assetBaseStorageUri, bundle.assetBaseStorageUri);
      expect(row.rolloutCohortCount, 500);
      expect(row.targetCohorts, ['team-a']);
      expect(row.metadata, {'app_version': '1.2.3'});
    });

    test('mapRowToBundle rebuilds derived patch fields', () {
      final baseBundleId = '018f0000-0000-7000-8000-000000000000';
      final bundle = _makeBundle(
        patches: [
          BundlePatchArtifact(
            baseBundleId: baseBundleId,
            baseFileHash: 'base-hash',
            patchFileHash: 'patch-hash',
            patchStorageUri: 'supabase-storage://updates/patches/p1.patch',
          ),
        ],
      );

      final row = bundleToRow(bundle);
      final patchRows = bundleToPatchRows(bundle);
      expect(patchRows, hasLength(1));
      expect(patchRows.first.id, '${bundle.id}:$baseBundleId');
      expect(patchRows.first.bundleId, bundle.id);
      expect(patchRows.first.baseBundleId, baseBundleId);
      expect(patchRows.first.orderIndex, 0);

      final back = mapRowToBundle(
        SupabaseBundleRow.fromJson(row.toJson()),
        patchRows
            .map((p) => SupabaseBundlePatchRow.fromJson(p.toJson()))
            .toList(),
      );

      expect(back.id, bundle.id);
      expect(back.patches, hasLength(1));
      expect(back.patchBaseBundleId, baseBundleId);
      expect(back.patchBaseFileHash, 'base-hash');
      expect(back.patches!.first.patchFileHash, 'patch-hash');
      expect(
        back.patchStorageUri,
        'supabase-storage://updates/patches/p1.patch',
      );
      expect(back.metadata?.appVersion, '1.2.3');
    });

    test('defaults when row fields are missing', () {
      final row = SupabaseBundleRow.fromJson({
        'id': 'id-1',
        'channel': 'production',
        'enabled': true,
        'platform': 'android',
        'should_force_update': false,
        'file_hash': 'fh',
        'storage_uri': 's',
        'target_app_version': '1.0.0',
        'metadata': {'app_version': '9.9.9'},
      });
      final bundle = mapRowToBundle(row);
      expect(bundle.rolloutCohortCount, 1000);
      expect(bundle.targetCohorts, isNull);
      expect(bundle.metadata?.appVersion, '9.9.9');
      expect(bundle.manifestStorageUri, isNull);
    });
  });
}
