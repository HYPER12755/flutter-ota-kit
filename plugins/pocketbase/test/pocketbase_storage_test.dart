import 'dart:io';

import 'package:flutter_ota_kit_plugin_core/flutter_ota_kit_plugin_core.dart'
    show StoragePlugin;
import 'package:flutter_ota_kit_pocketbase/flutter_ota_kit_pocketbase.dart';
import 'package:test/test.dart';

import 'fake_pocketbase_client.dart';

void main() {
  group('pocketbaseStorage', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('pb_storage_test'));
    tearDown(() => tmp.deleteSync(recursive: true));

    ({StoragePlugin storage, PbStore store}) newStorage() {
      final store = PbStore();
      final config = PocketBaseStorageConfig(
        url: 'http://fake',
        adminEmail: 'admin@test.dev',
        adminPassword: 'password123',
        bundlesCollection: 'bundles',
        clientFactory: (_, __, ___) => FakePocketBaseClient(store),
      );
      return (storage: pocketbaseStorage(config), store: store);
    }

    test('metadata', () {
      final (:storage, :store) = newStorage();
      expect(storage.name, 'pocketbaseStorage');
      expect(storage.supportedProtocol, 'pb:');
    });

    test('node upload → exists → downloadFile round-trips', () async {
      final (:storage, :store) = newStorage();
      final node = storage.profiles.node!;

      final artifact = File('${tmp.path}/patch.zip')
        ..writeAsBytesSync([1, 2, 3, 4, 5]);

      final res = await node.upload('bundle-1', artifact.path);
      final uri = res['storageUri']!;
      expect(uri, startsWith('pb://'));

      expect(await node.exists(uri), isTrue);

      final out = '${tmp.path}/downloaded.zip';
      await node.downloadFile(uri, out);
      expect(File(out).readAsBytesSync(), [1, 2, 3, 4, 5]);
    });

    test('runtime getDownloadUrl resolves a fileUrl for a pb:// uri', () async {
      final (:storage, :store) = newStorage();
      final node = storage.profiles.node!;
      final runtime = storage.profiles.runtime!;

      final artifact = File('${tmp.path}/patch.zip')..writeAsBytesSync([9, 9]);
      final res = await node.upload('bundle-x', artifact.path);
      final uri = res['storageUri']!;

      final dl = await runtime.getDownloadUrl(uri);
      expect(dl['fileUrl'], isNotNull);
      expect(dl['fileUrl'], isNotEmpty);
      expect(dl['storageUri'], uri);
    });

    test('runtime readText returns null for a missing object', () async {
      final (:storage, :store) = newStorage();
      final runtime = storage.profiles.runtime!;
      final text = await runtime.readText('pb://bundles/nope/missing.zip');
      expect(text, isNull);
    });

    test('delete removes the backing record', () async {
      final (:storage, :store) = newStorage();
      final node = storage.profiles.node!;
      final artifact = File('${tmp.path}/patch.zip')..writeAsBytesSync([7]);
      final res = await node.upload('bundle-del', artifact.path);
      final uri = res['storageUri']!;
      expect(await node.exists(uri), isTrue);
      await node.delete(uri);
      expect(await node.exists(uri), isFalse);
    });

    test('listObjects filters by prefix', () async {
      final (:storage, :store) = newStorage();
      final node = storage.profiles.node!;
      await node.upload(
        'a1',
        (File('${tmp.path}/a.zip')..writeAsBytesSync([1])).path,
      );
      await node.upload(
        'b1',
        (File('${tmp.path}/b.zip')..writeAsBytesSync([2])).path,
      );
      final all = await node.listObjects();
      expect(all.length, 2);
      final filtered = await node.listObjects('a1');
      expect(filtered.length, 1);
      expect(filtered.single.key, startsWith('a1'));
    });
  });
}
