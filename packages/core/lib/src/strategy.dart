/// Update targeting strategy — hot-updater `UpdateStrategy`.
///
/// Determines how the server matches bundles to devices during update checks.
library;

/// Strategy for targeting bundles to devices.
enum UpdateStrategy {
  /// Match by device fingerprint hash. The server compares the hash against
  /// bundles' `targetCohorts` list.
  fingerprint('fingerprint'),

  /// Match by app version semver range. The server compares the version
  /// against bundles' `targetAppVersion` range.
  appVersion('appVersion');

  /// String value used in API payloads.
  final String value;

  const UpdateStrategy(this.value);
}
