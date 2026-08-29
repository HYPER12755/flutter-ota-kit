/// The top-level prefix for bundle storage keys.
const String bundleStoragePrefix = 'bundles';

/// Build a storage key for a bundle, e.g. `bundles/<bundleId>/patch.zip`.
String createBundleStorageKey(String bundleId, [List<String> relativePaths = const []]) {
  return [bundleStoragePrefix, bundleId, ...relativePaths]
      .where((s) => s.isNotEmpty)
      .join('/');
}

/// Replace the bundle-id segment in a storage URI with a relative path.
///
/// For example, given a storage URI containing `.../bundles/<bundleId>/patch.zip`
/// and a [relativePath] of `files/manifest.json`, this returns a URI pointing
/// to `.../files/manifest.json`.
String createStorageRootUriWithPath(
  String storageUri,
  String bundleId,
  String relativePath,
) {
  final storageUrl = Uri.parse(storageUri);
  final segments = storageUrl.path.split('/').where((s) => s.isNotEmpty).toList();
  final bundleIndex = segments.lastIndexOf(bundleId);
  if (bundleIndex < 0) {
    throw StateError(
      'Storage URI does not contain bundle id: $bundleId',
    );
  }

  final rootSegments = segments.sublist(0, bundleIndex);
  if (rootSegments.isNotEmpty && rootSegments.last == bundleStoragePrefix) {
    rootSegments.removeLast();
  }

  final relativeSegments = relativePath
      .split('/')
      .where((s) => s.isNotEmpty)
      .map(Uri.encodeComponent)
      .toList();

  return storageUrl
      .replace(path: '/${[...rootSegments, ...relativeSegments].join('/')}')
      .toString();
}
