import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_ota_kit_cli/flutter_ota_kit_cli.dart';
import 'package:test/test.dart';

// Builds an in-memory APK containing libapp.so for every supported ABI, then
// verifies `packPatch` emits a single device-ready patch.zip that includes all
// ABIs (so one bundle installs on any device).
Future<Uint8List> _buildFakeApk() async {
  final apk = Archive();
  for (final abi in const ['arm64-v8a', 'armeabi-v7a', 'x86_64']) {
    final content = utf8.encode('LIBAPP_$abi');
    apk.addFile(ArchiveFile('lib/$abi/libapp.so', content.length, content));
  }
  final bytes = ZipEncoder().encode(apk);
  return Uint8List.fromList(bytes);
}

void main() {
  test('packPatch includes every ABI found in the APK', () async {
    final apkBytes = await _buildFakeApk();
    final dir = Directory.systemTemp.createTempSync('fp-pack-');
    final apkFile = File('${dir.path}/app.apk')..writeAsBytesSync(apkBytes);
    final outDir = '${dir.path}/dist';
    try {
      final result = await packPatch(
        apkPath: apkFile.path,
        version: '1.2.3',
        targetVersionCode: 7,
        out: outDir,
      );

      expect(result.abis, hasLength(3));
      expect(result.abis, containsAll(['arm64-v8a', 'armeabi-v7a', 'x86_64']));

      final patchBytes = File(result.payloadPath).readAsBytesSync();
      final patch = ZipDecoder().decodeBytes(patchBytes);

      final names = patch.files.map((f) => f.name).toList();
      expect(names, contains('manifest.json'));
      expect(names, contains('lib/arm64-v8a/libapp.so'));
      expect(names, contains('lib/armeabi-v7a/libapp.so'));
      expect(names, contains('lib/x86_64/libapp.so'));

      final manifestFile =
          patch.files.firstWhere((f) => f.name == 'manifest.json');
      final manifest = Map<String, dynamic>.from(
        jsonDecode(utf8.decode(manifestFile.content as List<int>))
            as Map,
      );
      expect(manifest['schemaVersion'], 2);
      expect(manifest['version'], '1.2.3');
      expect(manifest['targetVersionCode'], 7);

      final lib = Map<String, dynamic>.from(manifest['lib'] as Map);
      expect(lib.keys, hasLength(3));
      for (final abi in ['arm64-v8a', 'armeabi-v7a', 'x86_64']) {
        final entry = Map<String, dynamic>.from(lib[abi] as Map);
        expect(entry['path'], 'lib/$abi/libapp.so');
        final expectedMd5 = md5.convert(utf8.encode('LIBAPP_$abi')).toString();
        expect(entry['md5'], expectedMd5);
      }

      // outer manifest records all abis too
      final outer = Map<String, dynamic>.from(
        jsonDecode(File(result.manifestPath).readAsStringSync()) as Map,
      );
      expect(outer['payload'], 'patch.zip');
      expect(
        (outer['abis'] as List).cast<String>(),
        containsAll(['arm64-v8a', 'armeabi-v7a', 'x86_64']),
      );
    } finally {
      dir.deleteSync(recursive: true);
    }
  });

  test('packPatch throws PackException when libapp.so is missing', () async {
    final apk = Archive()..addFile(ArchiveFile('classes.dex', 0, <int>[]));
    final dir = Directory.systemTemp.createTempSync('fp-pack-bad-');
    final apkFile = File('${dir.path}/bad.apk')
      ..writeAsBytesSync(Uint8List.fromList(ZipEncoder().encode(apk)));
    try {
      expect(
        () => packPatch(
          apkPath: apkFile.path,
          version: '1.0.0',
          targetVersionCode: 1,
          out: '${dir.path}/dist',
        ),
        throwsA(isA<PackException>()),
      );
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
