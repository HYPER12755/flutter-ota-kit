import 'package:flutter_ota_kit_pocketbase/flutter_ota_kit_pocketbase.dart';
import 'package:test/test.dart';

import 'mocks/mock_pocketbase_client.dart' as pb;

void main() {
  test('parsePocketBaseStorageUri handles empty bucket', () {
    final result = parsePocketBaseStorageUri('pb:///abc/file.zip');
    expect(result, isNotNull);
    expect(result!.recordId, 'abc');
    expect(result.filename, 'file.zip');
  });

  test('parsePocketBaseStorageUri handles non-empty bucket', () {
    final result = parsePocketBaseStorageUri('pb://bundles/abc/file.zip');
    expect(result, isNotNull);
    expect(result!.recordId, 'abc');
    expect(result.filename, 'file.zip');
    expect(result.bucket, 'bundles');
  });

  test('MockPocketBaseClient upload + exists round-trips', () async {
    final store = pb.PocketBaseStore();
    final client = pb.MockPocketBaseClient(store);
    client.adminCredentials('admin@x.com', 'pw');

    // Create a record.
    await client.createRecord<dynamic>(
      'bundles',
      {
        'id': 'abc',
        'channel': 'pending',
        'platform': 'android',
        'enabled': false,
      },
      (j) => j,
    );

    // Upload a file to it.
    await client.uploadFile<dynamic>(
      'bundles',
      'abc',
      'artifact',
      'test.zip',
      [1, 2, 3],
      fromJson: (j) => j,
    );

    // Check exists.
    expect(await client.recordExists('bundles', 'abc'), isTrue);
    expect(await client.recordExists('bundles', 'nope'), isFalse);

    // Duplicate create should fail (real PB would return 409).
    expect(
      () => client.createRecord<dynamic>(
        'bundles',
        {'id': 'abc', 'channel': 'production'},
        (j) => j,
      ),
      throwsA(isA<PocketBaseException>()),
    );

    // Download the file.
    final bytes = await client.downloadFile('pb://mock/bundles/abc/test.zip');
    expect(bytes, [1, 2, 3]);
  });
}
