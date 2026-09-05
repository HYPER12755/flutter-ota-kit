/// UUID helpers matching hot-updater semantics.
///
/// Bundle ids are UUIDv7 (time-sortable); hot-updater relies on lexicographic
/// ordering of the string form matching chronological order.
library;

import 'dart:math';

const String nilUuid = '00000000-0000-0000-0000-000000000000';

final RegExp _uuidV7Pattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

final Random _random = Random.secure();

String _hex(int value, int width) =>
    value.toRadixString(16).padLeft(width, '0');

/// Generates a lowercase RFC 9562 UUIDv7 string (unix-ms timestamp based).
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

bool isUuidV7(String value) => _uuidV7Pattern.hasMatch(value);

/// Lexicographic comparison used by hot-updater for bundle ordering.
int compareBundleIds(String a, String b) => a.compareTo(b);
