/// Faithful port of hot-updater `plugins/supabase/src/supabaseBundleMapper.ts`.
library;

import 'dart:convert';

import 'package:flutter_patcher_core/flutter_patcher_core.dart';

import 'types.dart';

const String bundleSelectColumns =
    'id, channel, enabled, platform, should_force_update, file_hash, '
    'git_commit_hash, message, fingerprint_hash, target_app_version, '
    'storage_uri, metadata, manifest_storage_uri, manifest_file_hash, '
    'asset_base_storage_uri, rollout_cohort_count, target_cohorts';

/// Normalize metadata from various shapes to a plain map.
Map<String, Object?>? _normalizeMetadata(Object? value) {
  if (value == null) return null;

  if (value is String) {
    try {
      final parsed = jsonDecode(value);
      return _normalizeMetadata(parsed);
    } catch (_) {
      return null;
    }
  }

  if (value is Map) return value.cast<String, Object?>();

  return null;
}

/// Build the compound primary key for a patch row.
String _buildBundlePatchId(String bundleId, String baseBundleId) =>
    '$bundleId:$baseBundleId';

/// Map a Supabase bundle row + optional patch rows to a [Bundle].
Bundle mapRowToBundle(
  SupabaseBundleRow row, [
  List<SupabaseBundlePatchRow> patchRows = const [],
]) {
  final rawMetadata = _normalizeMetadata(row.metadata);
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

  final primaryPatch =
      patchArtifacts.isNotEmpty ? patchArtifacts.first : null;

  return Bundle(
    id: row.id,
    channel: row.channel,
    enabled: row.enabled,
    shouldForceUpdate: row.shouldForceUpdate,
    fileHash: row.fileHash,
    gitCommitHash: row.gitCommitHash,
    message: row.message,
    platform: Platform.fromValue(row.platform),
    targetAppVersion: row.targetAppVersion,
    fingerprintHash: row.fingerprintHash,
    storageUri: row.storageUri,
    metadata:
        rawMetadata != null ? BundleMetadata.fromJson(rawMetadata) : null,
    manifestStorageUri: row.manifestStorageUri,
    manifestFileHash: row.manifestFileHash,
    assetBaseStorageUri: row.assetBaseStorageUri,
    patches: patchArtifacts,
    patchBaseBundleId: primaryPatch?.baseBundleId,
    patchBaseFileHash: primaryPatch?.baseFileHash,
    patchFileHash: primaryPatch?.patchFileHash,
    patchStorageUri: primaryPatch?.patchStorageUri,
    rolloutCohortCount:
        row.rolloutCohortCount ?? defaultRolloutCohortCount,
    targetCohorts: row.targetCohorts,
  );
}

/// Map a [Bundle] to a Supabase row for upsert.
SupabaseBundleRow bundleToRow(Bundle bundle) => SupabaseBundleRow(
      id: bundle.id,
      channel: bundle.channel,
      enabled: bundle.enabled,
      shouldForceUpdate: bundle.shouldForceUpdate,
      fileHash: bundle.fileHash,
      gitCommitHash: bundle.gitCommitHash,
      message: bundle.message,
      platform: bundle.platform.value,
      targetAppVersion: bundle.targetAppVersion,
      fingerprintHash: bundle.fingerprintHash,
      storageUri: bundle.storageUri,
      metadata: stripBundleArtifactMetadata(bundle.metadata?.toJson()),
      manifestStorageUri: getManifestStorageUri(bundle),
      manifestFileHash: getManifestFileHash(bundle),
      assetBaseStorageUri: getAssetBaseStorageUri(bundle),
      rolloutCohortCount:
          bundle.rolloutCohortCount ?? defaultRolloutCohortCount,
      targetCohorts: bundle.targetCohorts,
    );

/// Map a [Bundle] to its patch rows for upsert.
List<SupabaseBundlePatchRow> bundleToPatchRows(Bundle bundle) {
  final patchArtifacts = getBundlePatches(bundle);
  return [
    for (var i = 0; i < patchArtifacts.length; i++)
      SupabaseBundlePatchRow(
        id: _buildBundlePatchId(
            bundle.id, patchArtifacts[i].baseBundleId),
        bundleId: bundle.id,
        baseBundleId: patchArtifacts[i].baseBundleId,
        baseFileHash: patchArtifacts[i].baseFileHash,
        patchFileHash: patchArtifacts[i].patchFileHash,
        patchStorageUri: patchArtifacts[i].patchStorageUri,
        orderIndex: i,
      ),
  ];
}
