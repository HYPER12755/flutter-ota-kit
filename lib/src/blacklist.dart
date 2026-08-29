import 'package:flutter/foundation.dart';

/// A local patch blacklist entry. Mirrors the native `BlacklistStore` JSON shape.
///
/// Typical usage on the app side:
/// ```dart
/// final entries = await FlutterPatcher.blacklist;
/// for (final e in entries) {
///   debugPrint('blacklisted ${e.version} reason=${e.reason}');
/// }
/// ```
@immutable
class BlacklistEntry {
  /// The blacklisted patch version (matches [PatchInfo.version]).
  final String version;

  /// The blacklisted patch md5 (lowercase hex).
  final String md5;

  /// The reason the patch was blacklisted (a native constant; passed as a string
  /// across the platform boundary instead of an enum for forward compatibility).
  /// Possible values:
  /// - `BOOT_CRASH`: circuit breaker tripped after repeated boot failures
  /// - `MD5_MISMATCH`: local file md5 verification failed
  /// - `SIGNATURE_INVALID`: Ed25519 signature verification failed
  final String reason;

  /// When the entry was blacklisted.
  final DateTime blacklistedAt;

  const BlacklistEntry({
    required this.version,
    required this.md5,
    required this.reason,
    required this.blacklistedAt,
  });

  factory BlacklistEntry.fromNative(Map<dynamic, dynamic> raw) {
    final map = Map<String, dynamic>.from(raw);
    return BlacklistEntry(
      version: (map['version'] as String?) ?? '',
      md5: (map['md5'] as String?) ?? '',
      reason: (map['reason'] as String?) ?? '',
      blacklistedAt: DateTime.fromMillisecondsSinceEpoch(
        ((map['blacklistedAt'] as num?) ?? 0).toInt(),
      ),
    );
  }

  @override
  String toString() =>
      'BlacklistEntry(version=$version, md5=$md5, reason=$reason, at=$blacklistedAt)';
}
