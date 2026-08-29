/// Per-asset diff descriptors — hot-updater `ChangedAsset*`.
library;

class ChangedAssetFile {
  /// "br" or null.
  final String? compression;
  final String url;

  const ChangedAssetFile({required this.url, this.compression});

  factory ChangedAssetFile.fromJson(Map<String, dynamic> j) =>
      ChangedAssetFile(url: j['url'] as String, compression: j['compression'] as String?);

  Map<String, dynamic> toJson() => {'url': url, 'compression': compression};
}

class ChangedAssetPatch {
  final String baseBundleId;
  final String baseFileHash;
  final String patchFileHash;
  final String patchUrl;

  /// Always "bsdiff" in hot-updater; kept for wire compatibility.
  final String algorithm;

  const ChangedAssetPatch({
    required this.baseBundleId,
    required this.baseFileHash,
    required this.patchFileHash,
    required this.patchUrl,
    this.algorithm = 'bsdiff',
  });

  factory ChangedAssetPatch.fromJson(Map<String, dynamic> j) =>
      ChangedAssetPatch(
        baseBundleId: j['baseBundleId'] as String,
        baseFileHash: j['baseFileHash'] as String,
        patchFileHash: j['patchFileHash'] as String,
        patchUrl: j['patchUrl'] as String,
        algorithm: j['algorithm'] as String? ?? 'bsdiff',
      );

  Map<String, dynamic> toJson() => {
        'algorithm': algorithm,
        'baseBundleId': baseBundleId,
        'baseFileHash': baseFileHash,
        'patchFileHash': patchFileHash,
        'patchUrl': patchUrl,
      };
}

class ChangedAsset {
  /// SHA256 hex of the asset file.
  final String fileHash;
  final ChangedAssetFile? file;
  final ChangedAssetPatch? patch;

  const ChangedAsset({required this.fileHash, this.file, this.patch});

  factory ChangedAsset.fromJson(Map<String, dynamic> j) => ChangedAsset(
        fileHash: j['fileHash'] as String,
        file: j['file'] == null
            ? null
            : ChangedAssetFile.fromJson(
                (j['file'] as Map).cast<String, dynamic>()),
        patch: j['patch'] == null
            ? null
            : ChangedAssetPatch.fromJson(
                (j['patch'] as Map).cast<String, dynamic>()),
      );

  Map<String, dynamic> toJson() => {
        'fileHash': fileHash,
        'file': file?.toJson(),
        'patch': patch?.toJson(),
      };
}
