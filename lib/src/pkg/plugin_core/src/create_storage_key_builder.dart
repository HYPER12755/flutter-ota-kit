/// Create a curried storage key builder that prepends an optional base path.
///
/// ```dart
/// final getKey = createStorageKeyBuilder('bundles');
/// getKey('v1', 'patch.zip'); // → 'bundles/v1/patch.zip'
/// ```
///
/// Faithful port of hot-updater `createStorageKeyBuilder.ts`.
String Function(String, [String, String, String]) createStorageKeyBuilder(
  String? basePath,
) {
  return (String a, [String b = '', String c = '', String d = '']) {
    return [basePath ?? '', a, b, c, d].where((s) => s.isNotEmpty).join('/');
  };
}
