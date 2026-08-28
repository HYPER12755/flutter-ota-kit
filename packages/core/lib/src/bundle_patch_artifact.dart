/// Binary patch artifact — hot-updater `BundlePatchArtifact`.
library;

class BundlePatchArtifact {
  final String baseBundleId;
  final String baseFileHash;
  final String patchFileHash;
  final String patchStorageUri;

  const BundlePatchArtifact({
    required this.baseBundleId,
    required this.baseFileHash,
    required this.patchFileHash,
    required this.patchStorageUri,
  });

  factory BundlePatchArtifact.fromJson(Map<String, dynamic> j) =>
      BundlePatchArtifact(
        baseBundleId:
            j['baseBundleId'] as String? ?? j['base_bundle_id'] as String,
        baseFileHash:
            j['baseFileHash'] as String? ?? j['base_file_hash'] as String,
        patchFileHash:
            j['patchFileHash'] as String? ?? j['patch_file_hash'] as String,
        patchStorageUri: j['patchStorageUri'] as String? ??
            j['patch_storage_uri'] as String,
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
