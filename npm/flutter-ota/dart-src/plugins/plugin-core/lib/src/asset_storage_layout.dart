import 'content_addressed_assets.dart' show getContentAddressedAssetStoragePath;
import 'legacy_asset_storage_layout.dart' show getLegacyManifestAssetStoragePath;

/// The two supported asset storage layout strategies.
typedef AssetStorageLayout = String;

const String assetLayoutContentAddressed = 'content-addressed';
const String assetLayoutLegacyFiles = 'legacy-files';

/// Whether [assetPath] is a brotli-compressed manifest path
/// (e.g. `index.android.bundle` → `index.android.bundle.br`).
bool isBrotliManifestAssetPath(String assetPath) {
  return RegExp(r'(^|/)index\.[^/]+\.bundle$')
      .hasMatch(assetPath.replaceAll('\\', '/'));
}

/// Append `.br` to brotli manifest asset paths, pass through otherwise.
String getManifestAssetDownloadPath(String assetPath) {
  return isBrotliManifestAssetPath(assetPath) ? '$assetPath.br' : assetPath;
}

/// Build a full storage URI by joining a base URI with a relative path.
///
/// Segments of [relativePath] are percent-encoded individually.
String createStorageUriWithRelativePath({
  required String baseStorageUri,
  required String relativePath,
}) {
  final storageUrl = Uri.parse(baseStorageUri);
  final normalizedBasePath =
      storageUrl.path.replaceAll(RegExp(r'/+$'), '');
  final normalizedRelativePath = relativePath
      .replaceAll('\\', '/')
      .split('/')
      .where((s) => s.isNotEmpty)
      .map(Uri.encodeComponent)
      .join('/');

  return storageUrl
      .replace(path: '$normalizedBasePath/$normalizedRelativePath')
      .toString();
}

/// Determine the asset storage layout from the base URI.
///
/// Returns `'content-addressed'` if the URI path ends with `/assets`,
/// otherwise `'legacy-files'`.
AssetStorageLayout getAssetStorageLayout(String assetBaseStorageUri) {
  final pathname =
      Uri.parse(assetBaseStorageUri).path.replaceAll(RegExp(r'/+$'), '');
  return pathname.endsWith('/assets') || pathname == '/assets'
      ? assetLayoutContentAddressed
      : assetLayoutLegacyFiles;
}

/// Convenience check: is the base URI using content-addressed layout?
bool isContentAddressedAssetBaseStorageUri(String assetBaseStorageUri) {
  return getAssetStorageLayout(assetBaseStorageUri) ==
      assetLayoutContentAddressed;
}

/// Compute the storage path for a manifest asset, dispatching on layout.
String getManifestAssetStoragePath({
  required String assetBaseStorageUri,
  required String assetPath,
  required String fileHash,
}) {
  final layout = getAssetStorageLayout(assetBaseStorageUri);

  if (layout == assetLayoutContentAddressed) {
    return getContentAddressedAssetStoragePath(
      assetPath: assetPath,
      fileHash: fileHash,
    );
  }

  return getLegacyManifestAssetStoragePath(assetPath: assetPath);
}

/// Build a full storage URI for a manifest asset.
String resolveManifestAssetStorageUri({
  required String assetBaseStorageUri,
  required String assetPath,
  required String fileHash,
}) {
  return createStorageUriWithRelativePath(
    baseStorageUri: assetBaseStorageUri,
    relativePath: getManifestAssetStoragePath(
      assetBaseStorageUri: assetBaseStorageUri,
      assetPath: assetPath,
      fileHash: fileHash,
    ),
  );
}
