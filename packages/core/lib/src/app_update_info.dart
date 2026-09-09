import 'changed_asset.dart' show ChangedAsset;
import 'status.dart';

/// Database-layer update decision — hot-updater `UpdateInfo`.
///
/// This is the raw result from the database query before the storage
/// resolver converts URIs to download URLs. Not directly sent to devices.
class UpdateInfo {
  /// Bundle UUID.
  final String id;

  /// Whether the device must install this update before proceeding.
  final bool shouldForceUpdate;

  /// Optional message to display to the user during the update.
  final String? message;

  /// Deployment status (`update` or `rollback`).
  final UpdateStatus status;

  /// Protocol URI for the artifact in storage (e.g. `s3://bucket/key`).
  final String? storageUri;

  /// MD5 hex of the artifact for verification.
  final String? fileHash;

  /// Git commit hash of the build, if available.
  final String? gitCommitHash;

  /// Internal rollout metadata; never serialized to update-check clients.
  final int? rolloutCohortCount;

  /// Cohort identifiers for targeted rollouts; never sent to devices.
  final List<String>? targetCohorts;

  const UpdateInfo({
    required this.id,
    required this.shouldForceUpdate,
    required this.message,
    required this.status,
    required this.storageUri,
    required this.fileHash,
    this.gitCommitHash,
    this.rolloutCohortCount,
    this.targetCohorts,
  });
}

/// Device-facing payload for an available update —
/// hot-updater `AppUpdateAvailableInfo`.
///
/// This is the resolved update info sent to the device SDK after the
/// storage resolver converts URIs to signed download URLs.
class AppUpdateAvailableInfo extends AppUpdateInfo {
  @override
  final String id;

  @override
  final bool shouldForceUpdate;

  @override
  final String? message;

  @override
  final UpdateStatus status;

  /// Signed download URL for the artifact.
  final String? fileUrl;

  /// MD5 hex of the artifact for download verification.
  final String? fileHash;

  /// Ed25519 (base64) signature over the artifact MD5 hex string. Consumed by
  /// the device SDK to verify the patch (`PatchInfo.signature`).
  final String? signature;

  /// Signed URL for the asset manifest (if asset-based patch).
  final String? manifestUrl;

  /// MD5 hex of the manifest file for verification.
  final String? manifestFileHash;

  /// Map of asset path to diff descriptor for incremental asset updates.
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
///
/// Returned when the device is already on the latest bundle for its
/// channel/platform. All fields are empty/null defaults.
class AppUpToDateInfo extends AppUpdateInfo {
  const AppUpToDateInfo();

  @override
  String get id => '';

  @override
  bool get shouldForceUpdate => false;

  @override
  String? get message => null;

  @override
  UpdateStatus get status => UpdateStatus.update;

  @override
  Map<String, dynamic> toJson() => {'status': 'UP_TO_DATE'};
}

/// Sealed union: hot-updater `AppUpdateInfo`.
///
/// Pattern-match on [AppUpdateAvailableInfo] or [AppUpToDateInfo] to
/// handle the two possible outcomes of an update check.
sealed class AppUpdateInfo {
  const AppUpdateInfo();

  /// Bundle UUID (empty string for up-to-date).
  String get id;

  /// Whether the device must install this update.
  bool get shouldForceUpdate;

  /// Optional message to display during the update.
  String? get message;

  /// Deployment status.
  UpdateStatus get status;

  /// Serialize to JSON for device SDK consumption.
  Map<String, dynamic> toJson();

  /// Deserialize from JSON. Returns [AppUpToDateInfo] if status is
  /// `"UP_TO_DATE"`, otherwise [AppUpdateAvailableInfo].
  factory AppUpdateInfo.fromJson(Map<String, dynamic> j) {
    final raw = j['status'];
    if (raw == 'UP_TO_DATE') return const AppUpToDateInfo();
    return AppUpdateAvailableInfo.fromJson(j);
  }
}
