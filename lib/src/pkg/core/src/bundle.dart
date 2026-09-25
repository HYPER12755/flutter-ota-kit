import 'metadata.dart';
import 'bundle_patch_artifact.dart';
import 'platform.dart';
import 'uuid.dart' show nilUuid;

/// hot-updater `Bundle` — the central database row / manifest object.
///
/// Wire format is camelCase; database rows are snake_case. [Bundle.fromJson]
/// tolerates both so one model works against PostgREST rows and API payloads.
class Bundle {
  final String id; // uuidv7

  final Platform platform;
  final bool shouldForceUpdate;
  final bool enabled;

  /// MD5 hex of the artifact blob. The device SDK verifies the downloaded
  /// file against this value (see [SignatureVerifier]). When the bundle is
  /// signed, the Ed25519 signature lives in [BundleMetadata.signature]
  /// (carried in the update-check `signature` field), not here.
  final String fileHash;

  /// Protocol URI, e.g. `supabase-storage://bucket/bundles/{id}/patch.zip`.
  final String storageUri;
  final String? gitCommitHash;
  final String? message;

  /// Default "production".
  final String channel;

  /// Semver range; XOR with [fingerprintHash] per DB CHECK constraint.
  final String? targetAppVersion;
  final String? fingerprintHash;
  final BundleMetadata? metadata;
  final String? manifestStorageUri;
  final String? manifestFileHash;
  final String? assetBaseStorageUri;

  /// Binary patch artifacts, array order = precedence.
  final List<BundlePatchArtifact>? patches;

  // Deprecated single-patch fields (kept for wire compatibility).
  final String? patchBaseBundleId;
  final String? patchBaseFileHash;
  final String? patchFileHashLegacy;
  final String? patchStorageUri;

  /// Per-mille 0..1000; null = full rollout.
  final int? rolloutCohortCount;

  /// Stored in DB, never returned to update-check clients.
  final List<String>? targetCohorts;

  const Bundle({
    required this.id,
    required this.platform,
    required this.shouldForceUpdate,
    required this.enabled,
    required this.fileHash,
    required this.storageUri,
    required this.channel,
    this.gitCommitHash,
    this.message,
    this.targetAppVersion,
    this.fingerprintHash,
    this.metadata,
    this.manifestStorageUri,
    this.manifestFileHash,
    this.assetBaseStorageUri,
    this.patches,
    this.patchBaseBundleId,
    this.patchBaseFileHash,
    String? patchFileHash,
    this.patchStorageUri,
    this.rolloutCohortCount,
    this.targetCohorts,
  }) : patchFileHashLegacy = patchFileHash;

  static T? _s<T>(Map<String, dynamic> j, String camel, String snake) {
    final v = j[camel] ?? j[snake];
    return v == null ? null : v as T;
  }

  factory Bundle.fromJson(Map<String, dynamic> j) => Bundle(
    id: (j['id'] ?? nilUuid) as String,
    platform: Platform.fromValue(j['platform'] as String),
    shouldForceUpdate:
        (j['shouldForceUpdate'] ?? j['should_force_update'] ?? false) as bool,
    enabled: (j['enabled'] ?? false) as bool,
    fileHash: (j['fileHash'] ?? j['file_hash']) as String,
    storageUri: (j['storageUri'] ?? j['storage_uri']) as String,
    gitCommitHash: _s<String>(j, 'gitCommitHash', 'git_commit_hash'),
    message: j['message'] == null ? null : j['message'] as String,
    channel: (j['channel'] ?? 'production') as String,
    targetAppVersion: _s<String>(j, 'targetAppVersion', 'target_app_version'),
    fingerprintHash: _s<String>(j, 'fingerprintHash', 'fingerprint_hash'),
    metadata: j['metadata'] is Map
        ? BundleMetadata.fromJson(
            (j['metadata'] as Map).cast<String, dynamic>(),
          )
        : null,
    manifestStorageUri: _s<String>(
      j,
      'manifestStorageUri',
      'manifest_storage_uri',
    ),
    manifestFileHash: _s<String>(j, 'manifestFileHash', 'manifest_file_hash'),
    assetBaseStorageUri: _s<String>(
      j,
      'assetBaseStorageUri',
      'asset_base_storage_uri',
    ),
    patches: (j['patches'] as List?)
        ?.map(
          (e) =>
              BundlePatchArtifact.fromJson((e as Map).cast<String, dynamic>()),
        )
        .toList(),
    patchBaseBundleId: _s<String>(
      j,
      'patchBaseBundleId',
      'patch_base_bundle_id',
    ),
    patchBaseFileHash: _s<String>(
      j,
      'patchBaseFileHash',
      'patch_base_file_hash',
    ),
    patchFileHash: _s(j, 'patchFileHash', 'patch_file_hash'),
    patchStorageUri: _s<String>(j, 'patchStorageUri', 'patch_storage_uri'),
    rolloutCohortCount: _s<int>(
      j,
      'rolloutCohortCount',
      'rollout_cohort_count',
    ),
    targetCohorts: (j['targetCohorts'] as List? ?? j['target_cohorts'] as List?)
        ?.map((e) => e as String)
        .toList(),
  );

  /// camelCase wire format (server API payloads).
  Map<String, dynamic> toJson() => {
    'id': id,
    'platform': platform.value,
    'shouldForceUpdate': shouldForceUpdate,
    'enabled': enabled,
    'fileHash': fileHash,
    'storageUri': storageUri,
    if (gitCommitHash != null) 'gitCommitHash': gitCommitHash,
    if (message != null) 'message': message,
    'channel': channel,
    if (targetAppVersion != null) 'targetAppVersion': targetAppVersion,
    if (fingerprintHash != null) 'fingerprintHash': fingerprintHash,
    if (metadata != null) 'metadata': metadata!.toJson(),
    if (manifestStorageUri != null) 'manifestStorageUri': manifestStorageUri,
    if (manifestFileHash != null) 'manifestFileHash': manifestFileHash,
    if (assetBaseStorageUri != null) 'assetBaseStorageUri': assetBaseStorageUri,
    if (patches != null) 'patches': patches!.map((p) => p.toJson()).toList(),
    if (patchBaseBundleId != null) 'patchBaseBundleId': patchBaseBundleId,
    if (patchBaseFileHash != null) 'patchBaseFileHash': patchBaseFileHash,
    if (patchFileHashLegacy != null) 'patchFileHash': patchFileHashLegacy,
    if (patchStorageUri != null) 'patchStorageUri': patchStorageUri,
    if (rolloutCohortCount != null) 'rolloutCohortCount': rolloutCohortCount,
    if (targetCohorts != null) 'targetCohorts': targetCohorts,
  };

  /// snake_case row format (Postgres/Supabase columns).
  Map<String, dynamic> toSqlJson() => {
    'id': id,
    'platform': platform.value,
    'should_force_update': shouldForceUpdate,
    'enabled': enabled,
    'file_hash': fileHash,
    'storage_uri': storageUri,
    'channel': channel,
    if (gitCommitHash != null) 'git_commit_hash': gitCommitHash,
    if (message != null) 'message': message,
    if (targetAppVersion != null) 'target_app_version': targetAppVersion,
    if (fingerprintHash != null) 'fingerprint_hash': fingerprintHash,
    if (metadata != null) 'metadata': metadata!.toJson(),
    if (manifestStorageUri != null) 'manifest_storage_uri': manifestStorageUri,
    if (manifestFileHash != null) 'manifest_file_hash': manifestFileHash,
    if (assetBaseStorageUri != null)
      'asset_base_storage_uri': assetBaseStorageUri,
    if (patches != null) 'patches': patches!.map((p) => p.toJson()).toList(),
    if (patchBaseBundleId != null) 'patch_base_bundle_id': patchBaseBundleId,
    if (patchBaseFileHash != null) 'patch_base_file_hash': patchBaseFileHash,
    if (patchFileHashLegacy != null) 'patch_file_hash': patchFileHashLegacy,
    if (patchStorageUri != null) 'patch_storage_uri': patchStorageUri,
    if (rolloutCohortCount != null) 'rollout_cohort_count': rolloutCohortCount,
    if (targetCohorts != null) 'target_cohorts': targetCohorts,
  };

  @override
  bool operator ==(Object o) =>
      o is Bundle &&
      o.id == id &&
      o.platform == platform &&
      o.shouldForceUpdate == shouldForceUpdate &&
      o.enabled == enabled &&
      o.fileHash == fileHash &&
      o.storageUri == storageUri &&
      o.channel == channel &&
      o.gitCommitHash == gitCommitHash &&
      o.message == message &&
      o.targetAppVersion == targetAppVersion &&
      o.fingerprintHash == fingerprintHash &&
      o.metadata == metadata &&
      o.manifestStorageUri == manifestStorageUri &&
      o.manifestFileHash == manifestFileHash &&
      o.assetBaseStorageUri == assetBaseStorageUri &&
      o.patchBaseBundleId == patchBaseBundleId &&
      o.patchBaseFileHash == patchBaseFileHash &&
      o.patchFileHashLegacy == patchFileHashLegacy &&
      o.patchStorageUri == patchStorageUri &&
      o.rolloutCohortCount == rolloutCohortCount;

  @override
  int get hashCode => Object.hash(
    id,
    platform,
    shouldForceUpdate,
    enabled,
    fileHash,
    storageUri,
    channel,
    gitCommitHash,
    message,
    targetAppVersion,
    fingerprintHash,
    metadata,
    manifestStorageUri,
    manifestFileHash,
    assetBaseStorageUri,
    patchBaseBundleId,
    patchBaseFileHash,
    patchFileHashLegacy,
    patchStorageUri,
    rolloutCohortCount,
  );
}
