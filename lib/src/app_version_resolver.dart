import 'package:package_info_plus/package_info_plus.dart';

/// Resolves the app version used for `appVersion`-strategy targeting.
///
/// If [configured] is non-empty it is honored (explicit override via
/// `XxxUpdateConfig.appVersion` / `--dart-define=APP_VERSION`). Otherwise the
/// real version is detected at runtime from the host app's `versionName` via
/// `package_info_plus`. This prevents the silent failure where a missing or
/// incorrect `APP_VERSION` made the client report a wrong version and the
/// backend return no compatible bundle (`filterCompatibleAppVersions` then drops
/// it).
///
/// Cached after the first successful detection so repeated update checks don't
/// re-read `PackageInfo`.
Future<String> resolveAppVersion(String? configured) async {
  if (configured != null && configured.trim().isNotEmpty) return configured;
  if (_cachedAppVersion != null) return _cachedAppVersion!;
  var detected = '';
  try {
    final info = await PackageInfo.fromPlatform();
    detected = info.version;
  } catch (_) {
    detected = '';
  }
  // Only cache a successful, non-empty detection. Caching '' would permanently
  // pin the version to empty after a transient failure and silently break
  // `appVersion`-strategy targeting forever. Callers retry on the next check.
  if (detected.isNotEmpty) _cachedAppVersion = detected;
  return detected;
}

String? _cachedAppVersion;

/// Resets the cached detected app version. Intended for tests that need to
/// re-run detection against a different [PackageInfo] (or simulate a failure).
void resetAppVersionCache() => _cachedAppVersion = null;
