import 'package:flutter_ota_kit_pocketbase/flutter_ota_kit_pocketbase.dart';
import 'package:test/test.dart';

void main() {
  test('buildPocketBaseStorageUri with no bucket parses back', () {
    final uri = buildPocketBaseStorageUri('abc', 'file.zip');
    final parsed = parsePocketBaseStorageUri(uri);
    expect(parsed, isNotNull);
    expect(parsed!.recordId, 'abc');
    expect(parsed.filename, 'file.zip');
  });
}
