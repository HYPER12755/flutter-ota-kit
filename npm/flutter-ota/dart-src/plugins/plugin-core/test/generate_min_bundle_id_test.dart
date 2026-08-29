import 'package:flutter_ota_kit_plugin_core/src/generate_min_bundle_id.dart';
import 'package:flutter_ota_kit_plugin_core/src/uuidv7.dart';
import 'package:test/test.dart';

void main() {
  group('generateMinBundleId', () {
    test('produces valid UUID v7 format', () {
      final id = generateMinBundleId();
      expect(id, matches(RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      )));
    });

    test('has zeroed random bits', () {
      final id = generateMinBundleId();
      final parts = id.split('-');
      // version+rand_a should be 7000 (version 7, rand_a=0)
      expect(parts[2], '7000');
      // variant+rand_b starts with 8, rest is 0
      expect(parts[3], '8000');
      // node is all zeros
      expect(parts[4], '000000000000');
    });

    test('timestamp is close to current time', () {
      final before = DateTime.now().millisecondsSinceEpoch;
      final id = generateMinBundleId();
      final after = DateTime.now().millisecondsSinceEpoch;
      final ts = extractTimestampFromUUIDv7(id);
      expect(ts, greaterThanOrEqualTo(before));
      expect(ts, lessThanOrEqualTo(after));
    });

    test('sorts before a normal UUIDv7 at the same millisecond', () {
      // Create a min bundle ID
      final minId = generateMinBundleId();
      // Create a normal UUIDv7 (with random bits)
      final normalId = createUUIDv7();
      // Both are at approximately the same time, but min should be <= normal
      // when timestamps are close
      final minTs = extractTimestampFromUUIDv7(minId);
      final normalTs = extractTimestampFromUUIDv7(normalId);
      // If timestamps are the same, min should sort first
      if (minTs == normalTs) {
        expect(minId.compareTo(normalId), lessThan(0));
      }
      // Otherwise just verify the format is valid
      expect(minId.length, 36);
    });
  });
}
