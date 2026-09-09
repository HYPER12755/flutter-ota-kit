/// UUID helpers matching hot-updater semantics.
///
/// Bundle ids are UUIDv7 (time-sortable); hot-updater relies on lexicographic
/// ordering of the string form matching chronological order.
library;

import 'dart:math';

/// The zero UUID, used as a sentinel for "no bundle" or "latest".
const String nilUuid = '00000000-0000-0000-0000-000000000000';

/// Regex pattern for validating UUIDv7 strings.
final RegExp _uuidV7Pattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

/// Secure random number generator for UUIDv7 variant bits.
final Random _random = Random.secure();

/// Format an integer as a zero-padded hex string.
String _hex(int value, int width) =>
    value.toRadixString(16).padLeft(width, '0');

/// Generates a lowercase RFC 9562 UUIDv7 string (unix-ms timestamp based).
///
/// The UUIDv7 format encodes a 48-bit millisecond timestamp in the first
/// 48 bits, making strings lexicographically sortable by creation time.
///
/// Throws [ArgumentError] if the current timestamp is outside the valid
/// UUIDv7 range (0 to 2^48 - 1 milliseconds).
String uuidV7({DateTime? now}) {
  final ts = (now ?? DateTime.now()).millisecondsSinceEpoch;
  if (ts < 0 || ts > 0xFFFFFFFFFFFF) {
    throw ArgumentError('timestamp out of UUIDv7 range');
  }
  // Layout: 48-bit ts | ver(0101)+12 rand bits | var(10)+62 rand bits.
  // Groups: 8 - 4 - "7"+3 - 2(var)+2 - 12.
  final rand = List.generate(10, (_) => _random.nextInt(256));
  final tsHex = _hex(ts, 12);
  final g3 = '${_hex(rand[0] & 0x0F, 1)}${_hex(rand[1], 2)}';
  final g4 = '${_hex((rand[2] & 0x3F) | 0x80, 2)}${_hex(rand[3], 2)}';
  final g5 = StringBuffer();
  for (var i = 4; i < 10; i++) {
    g5.write(_hex(rand[i], 2));
  }
  return '${tsHex.substring(0, 8)}-'
      '${tsHex.substring(8, 12)}-'
      '7$g3-$g4-$g5';
}

/// Returns true if [value] is a valid UUIDv7 string.
bool isUuidV7(String value) => _uuidV7Pattern.hasMatch(value);

/// Lexicographic comparison used by hot-updater for bundle ordering.
int compareBundleIds(String a, String b) => a.compareTo(b);
