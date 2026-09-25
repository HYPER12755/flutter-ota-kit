/// Binary patch artifact — hot-updater `BundlePatchArtifact`.
///
/// Represents a single binary diff between two bundles. The device SDK uses
/// [patchStorageUri] to download the patch, verifies it against [patchFileHash],
/// then applies it on top of the base bundle identified by [baseBundleId].
library;

/// A binary diff artifact that patches an older bundle into a newer one.
///
/// Patch artifacts are stored in [Bundle.patches] as an ordered list. The
/// device SDK tries each patch in order and applies the first one whose base
/// matches the installed bundle.
class BundlePatchArtifact {
  /// UUID of the bundle this patch transforms from.
  final String baseBundleId;

  /// MD5 hex of the base bundle's artifact (for verification).
  final String baseFileHash;

  /// MD5 hex of the patch artifact (for download verification).
  final String patchFileHash;

  /// Protocol URI pointing to the patch artifact in storage.
  final String patchStorageUri;

  const BundlePatchArtifact({
    required this.baseBundleId,
    required this.baseFileHash,
    required this.patchFileHash,
    required this.patchStorageUri,
  });

  factory BundlePatchArtifact.fromJson(
    Map<String, dynamic> j,
  ) => BundlePatchArtifact(
    baseBundleId: j['baseBundleId'] as String? ?? j['base_bundle_id'] as String,
    baseFileHash: j['baseFileHash'] as String? ?? j['base_file_hash'] as String,
    patchFileHash:
        j['patchFileHash'] as String? ?? j['patch_file_hash'] as String,
    patchStorageUri:
        j['patchStorageUri'] as String? ?? j['patch_storage_uri'] as String,
  );

  Map<String, dynamic> toJson() => {
    'baseBundleId': baseBundleId,
    'baseFileHash': baseFileHash,
    'patchFileHash': patchFileHash,
    'patchStorageUri': patchStorageUri,
  };

  @override
  bool operator ==(Object o) =>
      o is BundlePatchArtifact &&
      o.baseBundleId == baseBundleId &&
      o.baseFileHash == baseFileHash &&
      o.patchFileHash == patchFileHash &&
      o.patchStorageUri == patchStorageUri;

  @override
  int get hashCode =>
      Object.hash(baseBundleId, baseFileHash, patchFileHash, patchStorageUri);
}
