/// Update targeting strategy — hot-updater `UpdateStrategy`.
library;

enum UpdateStrategy {
  fingerprint('fingerprint'),
  appVersion('appVersion');

  final String value;
  const UpdateStrategy(this.value);
}
