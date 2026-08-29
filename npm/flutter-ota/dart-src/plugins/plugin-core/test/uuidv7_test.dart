import 'package:flutter_ota_kit_plugin_core/src/uuidv7.dart';
import 'package:test/test.dart';

void main() {
  group('extractTimestampFromUUIDv7', () {
    test('extracts timestamp from known UUID', () {
      // Timestamp hex = 01894f2e3a00 = 1737105248768
      final uuid = '01894f2e-3a00-7000-8000-000000000000';
      final ts = extractTimestampFromUUIDv7(uuid);
      expect(ts, 0x01894f2e3a00);
    });

    test('round-trips createUUIDv7 timestamp', () {
      final uuid = createUUIDv7();
      final ts = extractTimestampFromUUIDv7(uuid);
      final now = DateTime.now().millisecondsSinceEpoch;
      // Should be within 50ms of now
      expect((now - ts).abs(), lessThan(50));
    });
  });

  group('createUUIDv7', () {
    test('produces valid UUID v7 format', () {
      final uuid = createUUIDv7();
      // 8-4-4-4-12 format
      expect(uuid, matches(RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      )));
    });

    test('generates unique UUIDs', () {
      final ids = <String>{};
      for (var i = 0; i < 100; i++) {
        ids.add(createUUIDv7());
      }
      expect(ids.length, 100);
    });

    test('UUIDs with different timestamps are ordered correctly', () {
      // Create two UUIDs with known timestamps
      final uuid1 = createUUIDv7WithSameTimestamp(
        '01900000-0001-7000-8000-000000000000',
      );
      final uuid2 = createUUIDv7WithSameTimestamp(
        '01900000-0002-7000-8000-000000000000',
      );
      expect(uuid2.compareTo(uuid1), greaterThan(0));
    });
  });

  group('createUUIDv7WithSameTimestamp', () {
    test('preserves timestamp from original UUID', () {
      final original = createUUIDv7();
      final originalTs = extractTimestampFromUUIDv7(original);
      final derived = createUUIDv7WithSameTimestamp(original);
      final derivedTs = extractTimestampFromUUIDv7(derived);
      expect(derivedTs, originalTs);
    });

    test('produces different random bits', () {
      final original = createUUIDv7();
      // Generate a few — at least one should differ in random part
      final differentFound = List.generate(10, (_) =>
          createUUIDv7WithSameTimestamp(original))
          .any((u) => u != original);
      expect(differentFound, isTrue);
    });

    test('derived UUID still has version 7 and correct variant', () {
      final original = createUUIDv7();
      final derived = createUUIDv7WithSameTimestamp(original);
      expect(derived, matches(RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      )));
    });
  });
}
