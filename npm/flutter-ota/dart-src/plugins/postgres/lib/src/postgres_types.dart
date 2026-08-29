import 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart'
    show Platform;

/// Database row for the `bundles` table (snake_case columns).
///
/// Faithful port of hot-updater `postgres/src/types.ts` `PostgresBundleRow`.
class PostgresBundleRow {
  const PostgresBundleRow({
    required this.id,
    required this.channel,
    required this.enabled,
    required this.shouldForceUpdate,
    required this.fileHash,
    this.gitCommitHash,
    this.message,
    required this.platform,
    this.targetAppVersion,
    required this.storageUri,
    this.fingerprintHash,
    this.metadata,
    this.manifestStorageUri,
    this.manifestFileHash,
    this.assetBaseStorageUri,
    this.rolloutCohortCount,
    this.targetCohorts,
  });

  factory PostgresBundleRow.fromJson(Map<String, dynamic> json) {
    return PostgresBundleRow(
      id: json['id'] as String,
      channel: json['channel'] as String,
      enabled: json['enabled'] as bool,
      shouldForceUpdate: json['should_force_update'] as bool,
      fileHash: json['file_hash'] as String,
      gitCommitHash: json['git_commit_hash'] as String?,
      message: json['message'] as String?,
      platform: Platform.fromValue(json['platform'] as String),
      targetAppVersion: json['target_app_version'] as String?,
      storageUri: json['storage_uri'] as String,
      fingerprintHash: json['fingerprint_hash'] as String?,
      metadata: json['metadata'],
      manifestStorageUri: json['manifest_storage_uri'] as String?,
      manifestFileHash: json['manifest_file_hash'] as String?,
      assetBaseStorageUri: json['asset_base_storage_uri'] as String?,
      rolloutCohortCount: json['rollout_cohort_count'] as int?,
      targetCohorts: (json['target_cohorts'] as List?)?.cast<String>(),
    );
  }

  final String id;
  final String channel;
  final bool enabled;
  final bool shouldForceUpdate;
  final String fileHash;
  final String? gitCommitHash;
  final String? message;
  final Platform platform;
  final String? targetAppVersion;
  final String storageUri;
  final String? fingerprintHash;
  final dynamic metadata;
  final String? manifestStorageUri;
  final String? manifestFileHash;
  final String? assetBaseStorageUri;
  final int? rolloutCohortCount;
  final List<String>? targetCohorts;

  Map<String, dynamic> toJson() => {
        'id': id,
        'channel': channel,
        'enabled': enabled,
        'should_force_update': shouldForceUpdate,
        'file_hash': fileHash,
        'git_commit_hash': gitCommitHash,
        'message': message,
        'platform': platform.name,
        'target_app_version': targetAppVersion,
        'storage_uri': storageUri,
        'fingerprint_hash': fingerprintHash,
        'metadata': metadata ?? const {},
        'manifest_storage_uri': manifestStorageUri,
        'manifest_file_hash': manifestFileHash,
        'asset_base_storage_uri': assetBaseStorageUri,
        'rollout_cohort_count': rolloutCohortCount,
        'target_cohorts': targetCohorts,
      };
}

/// Database row for the `bundle_patches` table (snake_case columns).
///
/// Faithful port of hot-updater `postgres/src/types.ts` `PostgresBundlePatchRow`.
class PostgresBundlePatchRow {
  const PostgresBundlePatchRow({
    required this.id,
    required this.bundleId,
    required this.baseBundleId,
    required this.baseFileHash,
    required this.patchFileHash,
    required this.patchStorageUri,
    required this.orderIndex,
  });

  factory PostgresBundlePatchRow.fromJson(Map<String, dynamic> json) {
    return PostgresBundlePatchRow(
      id: json['id'] as String,
      bundleId: json['bundle_id'] as String,
      baseBundleId: json['base_bundle_id'] as String,
      baseFileHash: json['base_file_hash'] as String,
      patchFileHash: json['patch_file_hash'] as String,
      patchStorageUri: json['patch_storage_uri'] as String,
      orderIndex: json['order_index'] as int,
    );
  }

  final String id;
  final String bundleId;
  final String baseBundleId;
  final String baseFileHash;
  final String patchFileHash;
  final String patchStorageUri;
  final int orderIndex;

  Map<String, dynamic> toJson() => {
        'id': id,
        'bundle_id': bundleId,
        'base_bundle_id': baseBundleId,
        'base_file_hash': baseFileHash,
        'patch_file_hash': patchFileHash,
        'patch_storage_uri': patchStorageUri,
        'order_index': orderIndex,
      };
}
