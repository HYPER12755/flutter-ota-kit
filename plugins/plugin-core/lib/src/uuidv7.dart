import 'dart:math';

final Random _random = Random.secure();

String _hex(int value, int width) =>
    value.toRadixString(16).padLeft(width, '0');

/// Extract the millisecond timestamp from a UUIDv7 string.
int extractTimestampFromUUIDv7(String uuid) {
  final hex = uuid.replaceAll('-', '');
  final tsHex = hex.substring(0, 12);
  return int.parse(tsHex, radix: 16);
}

/// Create a UUIDv7 from a timestamp hex string (12 chars).
String _createUUIDv7FromTimestampHex(String tsHex) {
  // 12 bits rand_a (version 7, bits 48-59)
  final randA = _random.nextInt(0x1000);
  // 62 bits rand_b (variant 10, bits 64-125)
  // Combine two 32-bit random values to get 62 usable bits
  final randBHi = _random.nextInt(0x100000000); // 32 bits
  final randBLo = _random.nextInt(0x100000000); // 32 bits
  final randB = (randBHi.toUnsigned(32) << 30) | (randBLo.toUnsigned(30));

  final g3 = _hex((0x7 << 12) | randA, 4);
  final g4 = _hex(0x8000 | ((randB >> 48) & 0x3FFF), 4);
  final g5 = _hex(randB & 0xFFFFFFFFFFFF, 12);
  return '${tsHex.substring(0, 8)}-${tsHex.substring(8, 12)}-$g3-$g4-$g5';
}

/// Create a new UUIDv7 with the current time.
String createUUIDv7() {
  final ts = DateTime.now().millisecondsSinceEpoch;
  return _createUUIDv7FromTimestampHex(ts.toRadixString(16).padLeft(12, '0'));
}

/// Create a new UUIDv7 preserving the timestamp from an existing UUIDv7.
String createUUIDv7WithSameTimestamp(String existingUuid) {
  final tsHex = existingUuid.replaceAll('-', '').substring(0, 12);
  return _createUUIDv7FromTimestampHex(tsHex);
}
