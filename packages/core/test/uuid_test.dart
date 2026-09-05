import 'package:flutter_ota_kit_core/flutter_ota_kit_core.dart';
import 'package:test/test.dart';

void main() {
  group('uuidV7', () {
    test('generates RFC-compliant v7 strings', () {
      final id = uuidV7();
      expect(id.length, 36);
      expect(isUuidV7(id), isTrue, reason: id);
    });

    test('encodes provided timestamp', () {
      final ts = DateTime.utc(2026, 1, 1);
      final id = uuidV7(now: ts);
      final tsHex = ts.millisecondsSinceEpoch
          .toRadixString(16)
          .padLeft(12, '0');
      expect(id.substring(0, 8), tsHex.substring(0, 8));
      expect(id.substring(9, 13), tsHex.substring(8, 12));
      expect(id[14], '7');
    });

    test('lexicographic order matches chronological order', () {
      final base = DateTime.utc(2026, 5, 5, 12);
      final earlier = uuidV7(now: base);
      final later = uuidV7(now: base.add(const Duration(seconds: 10)));
      expect(compareBundleIds(earlier, later), -1);
      expect(compareBundleIds(later, earlier), 1);
    });

    test('uniqueness over bulk generation', () {
      final ids = List.generate(5000, (_) => uuidV7()).toSet();
      expect(ids.length, 5000);
    });
  });

  test('nilUuid matches hot-updater sentinel', () {
    expect(nilUuid, '00000000-0000-0000-0000-000000000000');
  });
}
