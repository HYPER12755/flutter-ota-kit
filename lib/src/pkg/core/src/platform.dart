/// Platform enum — hot-updater keeps `ios | android`; we implement Android
/// first but keep the full union for wire compatibility.
library;

/// Target platform for bundle deployment and update checks.
enum Platform {
  /// Apple iOS platform.
  ios('ios'),

  /// Google Android platform.
  android('android');

  /// String value used in database rows and API payloads.
  final String value;

  const Platform(this.value);

  /// Parse a platform string. Throws [ArgumentError] if [v] is not a
  /// recognized platform value.
  static Platform fromValue(String v) => Platform.values.firstWhere(
    (p) => p.value == v,
    orElse: () => throw ArgumentError('unknown platform: $v'),
  );
}
