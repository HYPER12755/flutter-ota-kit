import 'dart:convert' show jsonDecode;

import 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart'
    show Bundle, BundleMetadata, BundlePatchArtifact, Platform, getBundlePatches;

/// Default rollout cohort count — full rollout in the Dart port's per-mille
/// scale (matches core's `defaultRolloutCohortCount` = `numericCohortSize`).
const int defaultRolloutCohortCount = 1000;

/// Compound patch id `${bundleId}:${baseBundleId}` (matches D1 schema).
String buildBundlePatchId(String bundleId, String baseBundleId) =>
    '$bundleId:$baseBundleId';

/// Parse `target_cohorts` which is stored as a JSON string (or already a list).
List<String>? parseTargetCohorts(dynamic value) {
  if (value == null) return null;
  if (value is List) {
    return [
      for (final v in value)
        if (v is String) v,
    ];
  }
  if (value is String) {
    try {
      final parsed = jsonDecode(value);
      if (parsed is List) {
        return [
          for (final v in parsed)
            if (v is String) v,
        ];
      }
    } catch (_) {
      return null;
    }
  }
  return null;
}

/// Parse `metadata` which may be a JSON string or an already-decoded object.
Map<String, Object?>? parseMetadata(dynamic value) {
  if (value == null) return null;
  if (value is String) {
    try {
      return parseMetadata(jsonDecode(value));
    } catch (_) {
      return null;
    }
  }
  if (value is Map) {
    return value.cast<String, Object?>();
  }
  return null;
}

/// Convert a [Bundle] into the rows inserted into `bundle_patches`.
List<Map<String, dynamic>> bundleToPatchRows(Bundle bundle) =>
    getBundlePatches(bundle).asMap().entries.map((entry) {
      final patch = entry.value;
      return {
        'id': buildBundlePatchId(bundle.id, patch.baseBundleId),
        'bundle_id': bundle.id,
        'base_bundle_id': patch.baseBundleId,
        'base_file_hash': patch.baseFileHash,
        'patch_file_hash': patch.patchFileHash,
        'patch_storage_uri': patch.patchStorageUri,
        'order_index': entry.key,
      };
    }).toList();

/// Rebuild a [Bundle] from a D1 `bundles` row plus its `bundle_patches` rows.
Bundle transformRowToBundle(
  Map<String, dynamic> row, [
  List<Map<String, dynamic>> patchRows = const [],
]) {
  final rawMetadata = parseMetadata(row['metadata']);
  final metadata = rawMetadata == null
      ? null
      : BundleMetadata.fromJson(rawMetadata.cast<String, dynamic>());
  final patches = patchRows
      .toList()
    ..sort(
      (left, right) =>
          (left['order_index'] as num? ?? 0)
              .compareTo(right['order_index'] as num? ?? 0) +
          (left['base_bundle_id'] as String? ?? '')
              .compareTo(right['base_bundle_id'] as String? ?? ''),
    );

  final bundlePatches = patches.map((patch) {
    return BundlePatchArtifact(
      baseBundleId: patch['base_bundle_id'] as String,
      baseFileHash: patch['base_file_hash'] as String,
      patchFileHash: patch['patch_file_hash'] as String,
      patchStorageUri: patch['patch_storage_uri'] as String,
    );
  }).toList();

  final primaryPatch = bundlePatches.isNotEmpty ? bundlePatches.first : null;

  final enabled = row['enabled'];
  final shouldForceUpdate = row['should_force_update'];

  return Bundle(
    id: row['id'] as String,
    channel: row['channel'] as String,
    enabled: enabled is bool ? enabled : (enabled as num? ?? 0) != 0,
    shouldForceUpdate: shouldForceUpdate is bool
        ? shouldForceUpdate
        : (shouldForceUpdate as num? ?? 0) != 0,
    fileHash: row['file_hash'] as String,
    gitCommitHash: row['git_commit_hash'] as String?,
    message: row['message'] as String?,
    platform: Platform.fromValue(row['platform'] as String),
    targetAppVersion: row['target_app_version'] as String?,
    storageUri: row['storage_uri'] as String,
    fingerprintHash: row['fingerprint_hash'] as String?,
    metadata: metadata,
    manifestStorageUri: row['manifest_storage_uri'] as String?,
    manifestFileHash: row['manifest_file_hash'] as String?,
    assetBaseStorageUri: row['asset_base_storage_uri'] as String?,
    patches: bundlePatches,
    patchBaseBundleId: primaryPatch?.baseBundleId,
    patchBaseFileHash: primaryPatch?.baseFileHash,
    patchFileHash: primaryPatch?.patchFileHash,
    patchStorageUri: primaryPatch?.patchStorageUri,
    rolloutCohortCount:
        (row['rollout_cohort_count'] as num? ?? defaultRolloutCohortCount)
            .toInt(),
    targetCohorts: parseTargetCohorts(row['target_cohorts']),
  );
}
