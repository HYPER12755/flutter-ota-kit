/// Faithful port of hot-updater `plugins/postgres/src/postgres.ts` mapper
/// (the `mapRowToBundle` / `bundleToRowValues` / `bundleToPatchRows` helpers).
library;

import 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart'
    show
        Bundle,
        BundleMetadata,
        BundlePatchArtifact,
        defaultRolloutCohortCount,
        getAssetBaseStorageUri,
        getBundlePatches,
        getManifestFileHash,
        getManifestStorageUri,
        stripBundleArtifactMetadata;

import 'package:flutter_ota_kit_plugin_core/flutter_ota_kit_plugin_core.dart'
    show buildBundlePatchId, normalizeMetadata;

import 'postgres_types.dart';

/// Map a Postgres bundle row + optional patch rows to a [Bundle].
Bundle mapRowToBundle(
  PostgresBundleRow data, [
  List<PostgresBundlePatchRow> patchRows = const [],
]) {
  final rawMetadata = normalizeMetadata(data.metadata);
  final patches = patchRows.toList()
    ..sort((a, b) {
      final cmp = a.orderIndex.compareTo(b.orderIndex);
      if (cmp != 0) return cmp;
      return a.baseBundleId.compareTo(b.baseBundleId);
    });

  final patchArtifacts = patches
      .map((p) => BundlePatchArtifact(
            baseBundleId: p.baseBundleId,
            baseFileHash: p.baseFileHash,
            patchFileHash: p.patchFileHash,
            patchStorageUri: p.patchStorageUri,
          ))
      .toList();

  final primaryPatch = patchArtifacts.isNotEmpty ? patchArtifacts.first : null;

  return Bundle(
    id: data.id,
    channel: data.channel,
    enabled: data.enabled,
    shouldForceUpdate: data.shouldForceUpdate,
    fileHash: data.fileHash,
    gitCommitHash: data.gitCommitHash,
    message: data.message,
    platform: data.platform,
    targetAppVersion: data.targetAppVersion,
    fingerprintHash: data.fingerprintHash,
    storageUri: data.storageUri,
    metadata:
        rawMetadata != null ? BundleMetadata.fromJson(rawMetadata) : null,
    manifestStorageUri: data.manifestStorageUri,
    manifestFileHash: data.manifestFileHash,
    assetBaseStorageUri: data.assetBaseStorageUri,
    patches: patchArtifacts,
    patchBaseBundleId: primaryPatch?.baseBundleId,
    patchBaseFileHash: primaryPatch?.baseFileHash,
    patchFileHash: primaryPatch?.patchFileHash,
    patchStorageUri: primaryPatch?.patchStorageUri,
    rolloutCohortCount: data.rolloutCohortCount ?? defaultRolloutCohortCount,
    targetCohorts: data.targetCohorts,
  );
}

/// Map a [Bundle] to a `bundles` row for insert/update (snake_case columns).
Map<String, dynamic> bundleToRowValues(Bundle bundle) => {
      'id': bundle.id,
      'enabled': bundle.enabled,
      'should_force_update': bundle.shouldForceUpdate,
      'file_hash': bundle.fileHash,
      'git_commit_hash': bundle.gitCommitHash,
      'message': bundle.message,
      'platform': bundle.platform.value,
      'target_app_version': bundle.targetAppVersion,
      'channel': bundle.channel,
      'storage_uri': bundle.storageUri,
      'fingerprint_hash': bundle.fingerprintHash,
      'metadata': stripBundleArtifactMetadata(bundle.metadata?.toJson()) ?? {},
      'manifest_storage_uri': getManifestStorageUri(bundle),
      'manifest_file_hash': getManifestFileHash(bundle),
      'asset_base_storage_uri': getAssetBaseStorageUri(bundle),
      'rollout_cohort_count': bundle.rolloutCohortCount,
      'target_cohorts': bundle.targetCohorts,
    };

/// Map a [Bundle] to its `bundle_patches` rows for insert.
List<Map<String, dynamic>> bundleToPatchRows(Bundle bundle) {
  final patchArtifacts = getBundlePatches(bundle);
  return [
    for (var i = 0; i < patchArtifacts.length; i++)
      PostgresBundlePatchRow(
        id: buildBundlePatchId(bundle.id, patchArtifacts[i].baseBundleId),
        bundleId: bundle.id,
        baseBundleId: patchArtifacts[i].baseBundleId,
        baseFileHash: patchArtifacts[i].baseFileHash,
        patchFileHash: patchArtifacts[i].patchFileHash,
        patchStorageUri: patchArtifacts[i].patchStorageUri,
        orderIndex: i,
      ).toJson(),
  ];
}
