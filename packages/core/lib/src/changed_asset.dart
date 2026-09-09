/// Per-asset diff descriptors — hot-updater `ChangedAsset*`.
///
/// Used by the CLI's asset diffing pipeline to describe how individual
/// assets changed between two bundles. The device SDK uses these descriptors
/// to apply incremental asset updates.
library;

/// A single asset file that changed between bundles.
class ChangedAssetFile {
  /// Compression format (e.g. `"br"` for Brotli), or null if uncompressed.
  final String? compression;

  /// Download URL for the full asset file.
  final String url;

  const ChangedAssetFile({required this.url, this.compression});

  factory ChangedAssetFile.fromJson(Map<String, dynamic> j) => ChangedAssetFile(
    url: j['url'] as String,
    compression: j['compression'] as String?,
  );

  Map<String, dynamic> toJson() => {'url': url, 'compression': compression};
}

/// A binary patch for a changed asset.
///
/// When an asset is modified between bundles, a bsdiff patch is generated
/// to avoid re-downloading the full file. The device SDK downloads [patchUrl],
/// verifies it against [patchFileHash], then applies the diff on top of
/// the base asset.
class ChangedAssetPatch {
  /// UUID of the bundle containing the original (unpatched) asset.
  final String baseBundleId;

  /// MD5 hex of the original asset file (for verification).
  final String baseFileHash;

  /// MD5 hex of the patch file (for verification).
  final String patchFileHash;

  /// Download URL for the binary patch file.
  final String patchUrl;

  /// Diff algorithm identifier. Always `"bsdiff"` in hot-updater;
  /// kept for wire compatibility with future algorithms.
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

/// Describes a single asset that changed between two bundles.
///
/// Exactly one of [file] or [patch] is non-null:
/// - [file] is set when the asset is new or replaced entirely.
/// - [patch] is set when the asset was modified and a binary diff is available.
class ChangedAsset {
  /// SHA-256 hex of the asset file content.
  final String fileHash;

  /// Full replacement file descriptor. Null if a patch is available instead.
  final ChangedAssetFile? file;

  /// Binary diff patch. Null if the asset is new (use [file] instead).
  final ChangedAssetPatch? patch;

  const ChangedAsset({required this.fileHash, this.file, this.patch});

  factory ChangedAsset.fromJson(Map<String, dynamic> j) => ChangedAsset(
    fileHash: j['fileHash'] as String,
    file: j['file'] == null
        ? null
        : ChangedAssetFile.fromJson((j['file'] as Map).cast<String, dynamic>()),
    patch: j['patch'] == null
        ? null
        : ChangedAssetPatch.fromJson(
            (j['patch'] as Map).cast<String, dynamic>(),
          ),
  );

  Map<String, dynamic> toJson() => {
    'fileHash': fileHash,
    'file': file?.toJson(),
    'patch': patch?.toJson(),
  };
}
