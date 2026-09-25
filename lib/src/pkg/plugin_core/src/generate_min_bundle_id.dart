/// Generate a minimum-priority bundle ID: UUIDv7 with zeroed random bits.
///
/// Used by the DB plugin to create bundle IDs that sort before any
/// random-bit bundle created at the same millisecond.
///
/// Faithful port of hot-updater `generateMinBundleId.ts`.
String generateMinBundleId() {
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final tsHex = timestamp.toRadixString(16).padLeft(12, '0');

  // UUIDv7 layout: 48-bit ts | ver(0111)+12 rand_a(0) | var(10)+62 rand_b(0)
  final timeHigh = tsHex.substring(0, 8);
  final timeLow = tsHex.substring(8, 12);
  const versionAndRandom = '7000'; // version 7, rand_a = 0
  const variantAndRandom = '8000'; // variant 10, rand_b = 0
  const node = '000000000000';

  return '$timeHigh-$timeLow-$versionAndRandom-$variantAndRandom-$node';
}
