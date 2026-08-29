import 'semver_range.dart' show satisfies;
import 'semver_version.dart';

export 'semver_range.dart' show satisfies;
export 'semver_version.dart' show SemVer;

/// hot-updater `semverSatisfies(targetAppVersion, currentVersion)`
/// (plugins/plugin-core/src/semverSatisfies.ts):
///
/// 1. `coerce(currentVersion)` — extract a version from loose input
///    ("v1.2", "version 2.3.4", "1a2b3c" → 1.0.0, junk → null).
/// 2. `satisfies(coerced, range)` against the raw target range.
bool semverSatisfies(String targetAppVersion, String currentVersion) {
  final coerced = semverCoerce(currentVersion);
  if (coerced == null) {
    return false;
  }
  return satisfies(coerced, targetAppVersion);
}

/// verkit `coerce` with default options: find the first plausible
/// major[.minor[.patch]] run; prerelease/build are dropped; anything after
/// the run (including stray dots/digits like "1.2.3.4") is ignored.
SemVer? semverCoerce(String value) {
  var input = value.trim();
  if (input.isEmpty) return null;
  final m = RegExp(
    r'(?<![0-9.])'
    r'(0|[1-9]\d*)'
    r'(?:\.(0|[1-9]\d*))?'
    r'(?:\.(0|[1-9]\d*))?',
  ).firstMatch(input);
  if (m == null) return null;

  // Overflow guard mirroring verkit: a digit run too large for a safe
  // integer is skipped and scanning resumes right after it, allowing a
  // leading dot. e.g. "99999999999999999999.1.1" -> "1.1.0".
  var majorStr = m.group(1)!;
  if (majorStr.length > 15) {
    return semverCoerceLoose(input.substring(m.start + majorStr.length));
  }

  return SemVer(
    int.parse(majorStr),
    int.tryParse(m.group(2) ?? '') ?? 0,
    int.tryParse(m.group(3) ?? '') ?? 0,
  );
}

/// Retry scan that allows a preceding dot (used after skipping an
/// oversized digit run).
SemVer? semverCoerceLoose(String input) {
  var s = input.trim();
  if (s.isEmpty) return null;
  final m = RegExp(
    r'(0|[1-9]\d*)'
    r'(?:\.(0|[1-9]\d*))?'
    r'(?:\.(0|[1-9]\d*))?',
  ).firstMatch(s);
  if (m == null) return null;
  var majorStr = m.group(1)!;
  if (majorStr.length > 15) {
    return semverCoerceLoose(s.substring(m.start + majorStr.length));
  }
  return SemVer(
    int.parse(majorStr),
    int.tryParse(m.group(2) ?? '') ?? 0,
    int.tryParse(m.group(3) ?? '') ?? 0,
  );
}
