import 'dart:io' show Directory, File;

import 'package:flutter_ota_kit_aws/flutter_ota_kit_aws.dart' show s3Storage;
import 'package:flutter_ota_kit_plugin_core/flutter_ota_kit_plugin_core.dart'
    show StoragePlugin;
import 'package:path/path.dart' show basename;
import 'package:test/test.dart';

import 'mock_aws_s3_client.dart' show Store, mockConfig;

void main() {
  group('aws s3Storage', () {
    late Store store;
    late StoragePlugin plugin;
    late String tmpFile;
    late String outFile;

    setUp(() {
      store = Store();
      plugin = s3Storage(mockConfig(store));
      final dir = Directory.systemTemp.createTempSync('fp_s3_').path;
      tmpFile = '$dir/bundle.zip';
      File(tmpFile).writeAsBytesSync([1, 2, 3, 4]);
      outFile = '$dir/out.zip';
    });

    test('plugin metadata', () {
      expect(plugin.name, 's3Storage');
      expect(plugin.supportedProtocol, 's3');
      expect(plugin.profiles.hasNode, isTrue);
      expect(plugin.profiles.hasRuntime, isTrue);
    });

    test('node upload + exists + downloadFile + delete', () async {
      final node = plugin.profiles.node!;
      final res = await node.upload('v1', tmpFile);
      expect(res['storageUri'], 's3://test-bucket/v1/${basename(tmpFile)}');
      expect(await node.exists(res['storageUri']!), isTrue);

      await node.downloadFile(res['storageUri']!, outFile);
      expect(File(outFile).readAsBytesSync(), [1, 2, 3, 4]);

      await node.delete(res['storageUri']!);
      expect(await node.exists(res['storageUri']!), isFalse);
    });

    test('runtime getDownloadUrl + readText (and missing → null)', () async {
      final node = plugin.profiles.node!;
      final runtime = plugin.profiles.runtime!;

      final manifest = '${Directory.systemTemp.path}/fp_manifest.json';
      File(manifest).writeAsStringSync('{"hello":1}');
      final uploaded = await node.upload('manifests', manifest);

      final url = await runtime.getDownloadUrl(uploaded['storageUri']!);
      expect(url['fileUrl'], contains('manifests/'));

      final text = await runtime.readText(uploaded['storageUri']!);
      expect(text, '{"hello":1}');

      expect(await runtime.readText('s3://test-bucket/missing'), isNull);
    });

    test('listObjects filters by prefix', () async {
      final node = plugin.profiles.node!;
      await node.upload('a', tmpFile);
      await node.upload('b', tmpFile);

      expect(await node.listObjects(), hasLength(2));
      expect(await node.listObjects('a/'), hasLength(1));
    });
  });
}
