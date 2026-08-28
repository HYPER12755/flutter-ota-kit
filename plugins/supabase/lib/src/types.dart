/// Faithful port of hot-updater `plugins/supabase/src/types.ts`.
library;

/// Row type from Supabase `bundles` table.
class SupabaseBundleRow {
  final String id;
  final String channel;
  final bool enabled;
  final bool shouldForceUpdate;
  final String fileHash;
  final String? gitCommitHash;
  final String? message;
  final String platform;
  final String? targetAppVersion;
  final String? fingerprintHash;
  final String storageUri;
  final Map<String, Object?>? metadata;
  final String? manifestStorageUri;
  final String? manifestFileHash;
  final String? assetBaseStorageUri;
  final int? rolloutCohortCount;
  final List<String>? targetCohorts;

  const SupabaseBundleRow({
    required this.id,
    required this.channel,
    required this.enabled,
    required this.shouldForceUpdate,
    required this.fileHash,
    this.gitCommitHash,
    this.message,
    required this.platform,
    this.targetAppVersion,
    this.fingerprintHash,
    required this.storageUri,
    this.metadata,
    this.manifestStorageUri,
    this.manifestFileHash,
    this.assetBaseStorageUri,
    this.rolloutCohortCount,
    this.targetCohorts,
  });

  factory SupabaseBundleRow.fromJson(Map<String, dynamic> j) =>
      SupabaseBundleRow(
        id: j['id'] as String,
        channel: j['channel'] as String,
        enabled: j['enabled'] as bool,
        shouldForceUpdate: j['should_force_update'] as bool,
        fileHash: j['file_hash'] as String,
        gitCommitHash: j['git_commit_hash'] as String?,
        message: j['message'] as String?,
        platform: j['platform'] as String,
        targetAppVersion: j['target_app_version'] as String?,
        fingerprintHash: j['fingerprint_hash'] as String?,
        storageUri: j['storage_uri'] as String,
        metadata: j['metadata'] is Map
            ? (j['metadata'] as Map).cast<String, Object?>()
            : null,
        manifestStorageUri: j['manifest_storage_uri'] as String?,
        manifestFileHash: j['manifest_file_hash'] as String?,
        assetBaseStorageUri: j['asset_base_storage_uri'] as String?,
        rolloutCohortCount: j['rollout_cohort_count'] as int?,
        targetCohorts: (j['target_cohorts'] as List?)
            ?.map((e) => e as String)
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'channel': channel,
        'enabled': enabled,
        'should_force_update': shouldForceUpdate,
        'file_hash': fileHash,
        'git_commit_hash': gitCommitHash,
        'message': message,
        'platform': platform,
        'target_app_version': targetAppVersion,
        'fingerprint_hash': fingerprintHash,
        'storage_uri': storageUri,
        'metadata': metadata,
        'manifest_storage_uri': manifestStorageUri,
        'manifest_file_hash': manifestFileHash,
        'asset_base_storage_uri': assetBaseStorageUri,
        'rollout_cohort_count': rolloutCohortCount,
        'target_cohorts': targetCohorts,
      };
}

/// Row type from Supabase `bundle_patches` table.
class SupabaseBundlePatchRow {
  final String id;
  final String bundleId;
  final String baseBundleId;
  final String baseFileHash;
  final String patchFileHash;
  final String patchStorageUri;
  final int orderIndex;

  const SupabaseBundlePatchRow({
    required this.id,
    required this.bundleId,
    required this.baseBundleId,
    required this.baseFileHash,
    required this.patchFileHash,
    required this.patchStorageUri,
    required this.orderIndex,
  });

  factory SupabaseBundlePatchRow.fromJson(Map<String, dynamic> j) =>
      SupabaseBundlePatchRow(
        id: j['id'] as String,
        bundleId: j['bundle_id'] as String,
        baseBundleId: j['base_bundle_id'] as String,
        baseFileHash: j['base_file_hash'] as String,
        patchFileHash: j['patch_file_hash'] as String,
        patchStorageUri: j['patch_storage_uri'] as String,
        orderIndex: j['order_index'] as int,
      );

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
