const String contentAddressedAssetPrefix = 'assets';

/// Build a content-addressed storage path for an asset.
///
/// Format: `sha256/{hash[:2]}/{hash}.{ext}`
/// Preserves `.br` brotli extension from the original asset path.
///
/// Faithful port of hot-updater `contentAddressedAssets.ts`.
String getContentAddressedAssetStoragePath({
  required String assetPath,
  required String fileHash,
}) {
  String extension;
  if (assetPath.endsWith('.br')) {
    extension = '.br';
  } else if (assetPath.contains('.')) {
    extension = '.${assetPath.split('.').last}';
  } else {
    extension = '';
  }
  return 'sha256/${fileHash.substring(0, 2)}/$fileHash$extension';
}
