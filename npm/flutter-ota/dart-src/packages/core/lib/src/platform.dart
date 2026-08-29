/// Platform enum — hot-updater keeps `ios | android`; we implement Android
/// first but keep the full union for wire compatibility.
library;

enum Platform {
  ios('ios'),
  android('android');

  final String value;
  const Platform(this.value);

  static Platform fromValue(String v) =>
      Platform.values.firstWhere((p) => p.value == v,
          orElse: () => throw ArgumentError('unknown platform: $v'));
}
