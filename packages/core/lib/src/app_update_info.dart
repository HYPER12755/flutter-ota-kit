import 'changed_asset.dart' show ChangedAsset;
import 'status.dart';

/// hot-updater `UpdateInfo` — database-layer update decision.
class UpdateInfo {
  final String id;
  final bool shouldForceUpdate;
  final String? message;
  final UpdateStatus status;
  final String? storageUri;
  final String? fileHash;

  /// Internal rollout metadata; never serialized to update-check clients.
  final int? rolloutCohortCount;
  final List<String>? targetCohorts;

  const UpdateInfo({
    required this.id,
    required this.shouldForceUpdate,
    required this.message,
    required this.status,
    required this.storageUri,
    required this.fileHash,
    this.rolloutCohortCount,
    this.targetCohorts,
  });
}

/// Device-facing payload for an available update —
/// hot-updater `AppUpdateAvailableInfo`.
class AppUpdateAvailableInfo extends AppUpdateInfo {
  final String id;
  final bool shouldForceUpdate;
  final String? message;
  final UpdateStatus status;
  final String? fileUrl;
  final String? fileHash;

  /// Ed25519 (base64) signature over the artifact MD5 hex string. Consumed by
  /// the device SDK to verify the patch (`PatchInfo.signature`).
  final String? signature;

  final String? manifestUrl;
  final String? manifestFileHash;
  final Map<String, ChangedAsset>? changedAssets;

  const AppUpdateAvailableInfo({
    required this.id,
    required this.shouldForceUpdate,
    required this.message,
    required this.status,
    required this.fileUrl,
    required this.fileHash,
    this.signature,
    this.manifestUrl,
    this.manifestFileHash,
    this.changedAssets,
  });

  factory AppUpdateAvailableInfo.fromJson(Map<String, dynamic> j) =>
      AppUpdateAvailableInfo(
        id: j['id'] as String,
        shouldForceUpdate: (j['shouldForceUpdate'] ?? false) as bool,
        message: j['message'] as String?,
        status: UpdateStatus.fromValue(j['status'] as String),
        fileUrl: j['fileUrl'] as String?,
        fileHash: j['fileHash'] as String?,
        signature: j['signature'] as String?,
        manifestUrl: j['manifestUrl'] as String?,
        manifestFileHash: j['manifestFileHash'] as String?,
        changedAssets: (j['changedAssets'] as Map?)?.map(
          (k, v) => MapEntry(
            k as String,
            ChangedAsset.fromJson((v as Map).cast<String, dynamic>()),
          ),
        ),
      );

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'shouldForceUpdate': shouldForceUpdate,
    'message': message,
    'status': status.value,
    'fileUrl': fileUrl,
    'fileHash': fileHash,
    if (signature != null) 'signature': signature,
    if (manifestUrl != null) 'manifestUrl': manifestUrl,
    if (manifestFileHash != null) 'manifestFileHash': manifestFileHash,
    if (changedAssets != null) 'changedAssets': changedAssets,
  };
}

/// Device-facing "nothing to do" — hot-updater `AppUpToDateInfo`.
class AppUpToDateInfo extends AppUpdateInfo {
  const AppUpToDateInfo();

  @override
  Map<String, dynamic> toJson() => {'status': 'UP_TO_DATE'};
}

/// Sealed union: hot-updater `AppUpdateInfo`.
sealed class AppUpdateInfo {
  const AppUpdateInfo();

  Map<String, dynamic> toJson();

  factory AppUpdateInfo.fromJson(Map<String, dynamic> j) {
    final raw = j['status'];
    if (raw == 'UP_TO_DATE') return const AppUpToDateInfo();
    return AppUpdateAvailableInfo.fromJson(j);
  }
}
