/// Maps PocketBase bundle records to [Bundle] and back.
library;

import 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart';
import 'package:flutter_ota_kit_plugin_core/flutter_ota_kit_plugin_core.dart'
    show normalizeMetadata;

/// Row shape of a `bundles` record as stored in PocketBase.
class PocketBaseBundleRow {
  PocketBaseBundleRow({
    required this.id,
    required this.channel,
    required this.enabled,
    required this.platform,
    required this.shouldForceUpdate,
    required this.fileHash,
    required this.storageUri,
    required this.rolloutCohortCount,
    this.gitCommitHash,
    this.message,
    this.fingerprintHash,
    this.targetAppVersion,
    this.manifestStorageUri,
    this.manifestFileHash,
    this.assetBaseStorageUri,
    this.targetCohorts,
    this.metadata,
    this.created,
    this.updated,
  });

  factory PocketBaseBundleRow.fromJson(Map<String, dynamic> j) =>
      PocketBaseBundleRow(
        id: j['id'] as String? ?? '',
        channel: j['channel'] as String? ?? 'production',
        enabled: j['enabled'] as bool? ?? true,
        platform: j['platform'] as String? ?? 'android',
        shouldForceUpdate: j['should_force_update'] as bool? ?? false,
        fileHash: j['file_hash'] as String? ?? '',
        storageUri: j['storage_uri'] as String? ?? '',
        rolloutCohortCount: (j['rollout_cohort_count'] as num?)?.toInt() ?? 1000,
        gitCommitHash: j['git_commit_hash'] as String?,
        message: j['message'] as String?,
        fingerprintHash: j['fingerprint_hash'] as String?,
        targetAppVersion: j['target_app_version'] as String?,
        manifestStorageUri: j['manifest_storage_uri'] as String?,
        manifestFileHash: j['manifest_file_hash'] as String?,
        assetBaseStorageUri: j['asset_base_storage_uri'] as String?,
        targetCohorts: (j['target_cohorts'] as List?)?.cast<String>(),
        metadata: (j['metadata'] as Map?)?.cast<String, dynamic>(),
        created: j['created'] as String?,
        updated: j['updated'] as String?,
      );

  final String id;
  final String channel;
  final bool enabled;
  final String platform;
  final bool shouldForceUpdate;
  final String fileHash;
  final String storageUri;
  final int rolloutCohortCount;
  final String? gitCommitHash;
  final String? message;
  final String? fingerprintHash;
  final String? targetAppVersion;
  final String? manifestStorageUri;
  final String? manifestFileHash;
  final String? assetBaseStorageUri;
  final List<String>? targetCohorts;
  final Map<String, dynamic>? metadata;
  final String? created;
  final String? updated;

  Map<String, dynamic> toCreateJson() => {
        'id': id,
        'channel': channel,
        'enabled': enabled,
        'platform': platform,
        'should_force_update': shouldForceUpdate,
        'file_hash': fileHash,
        'storage_uri': storageUri,
        'rollout_cohort_count': rolloutCohortCount,
        if (gitCommitHash != null) 'git_commit_hash': gitCommitHash,
        if (message != null) 'message': message,
        if (fingerprintHash != null) 'fingerprint_hash': fingerprintHash,
        if (targetAppVersion != null) 'target_app_version': targetAppVersion,
        if (manifestStorageUri != null) 'manifest_storage_uri': manifestStorageUri,
        if (manifestFileHash != null) 'manifest_file_hash': manifestFileHash,
        if (assetBaseStorageUri != null) 'asset_base_storage_uri': assetBaseStorageUri,
        if (targetCohorts != null) 'target_cohorts': targetCohorts,
        if (metadata != null) 'metadata': metadata,
      };
}

/// Convert a [PocketBaseBundleRow] into a [Bundle].
Bundle mapRowToBundle(PocketBaseBundleRow row) {
  final rawMetadata = normalizeMetadata(row.metadata);
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
    patches: const [],
    rolloutCohortCount: row.rolloutCohortCount,
    targetCohorts: row.targetCohorts,
  );
}
