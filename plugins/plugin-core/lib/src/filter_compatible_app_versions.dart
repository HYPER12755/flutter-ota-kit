import 'package:flutter_patcher_core/flutter_patcher_core.dart'
    show semverSatisfies;

/// Filter target app versions that are compatible with the current app version.
///
/// Returns only versions compatible per semver, sorted descending (newest first).
///
/// Faithful port of hot-updater `filterCompatibleAppVersions.ts`.
List<String> filterCompatibleAppVersions(
  List<String> targetAppVersionList,
  String currentVersion,
) {
  final compatible = targetAppVersionList
      .where((version) => semverSatisfies(version, currentVersion))
      .toList();
  compatible.sort((a, b) => b.compareTo(a));
  return compatible;
}
